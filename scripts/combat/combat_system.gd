class_name CombatSystem
extends RefCounted
## Turrets, projectiles and damage. Pure logic driven by `update(delta)`.
##
## Integration without coupling:
## - Turrets appear/disappear by listening to GridModel placement signals
##   (same pattern as NavGrid); construction knows nothing about combat.
## - All damage goes through EnemyRoster.damage(), the single place that
##   applies armour, kills, and emits enemy_killed (rewards stay in GameSession).
## - Targets are re-selected only when a turret has none valid or is ready to
##   fire; selection is O(enemies) and deterministic (Targeting).

signal turret_added(turret: TurretState)
signal turret_removed(turret: TurretState)
signal shot_fired(turret: TurretState, projectile: Projectile)
## hit = true when damage was applied; false for a bullet that lost its target.
signal projectile_impact(projectile: Projectile, hit: bool)
signal explosion(position: Vector2, radius_px: float, kind: int)

## Safety net: any projectile older than this is discarded.
const MAX_PROJECTILE_AGE := 6.0
## Target scans (O(enemies)) happen at most this often per turret: a 0.1 s
## reaction time. Measured: idle/aligning turrets rescanning every frame made
## combat cost O(turrets x enemies) per frame (docs/TESTING.md, session 4).
const RETARGET_INTERVAL := 0.1
## Scan phases are staggered across turrets to avoid spikes on one frame.
const RETARGET_PHASES := 6

var _grid: GridModel
var _roster: EnemyRoster
var _nav: NavGrid
var _turrets: Array[TurretState] = []
var _by_placement: Dictionary = {} # placement id -> TurretState
var _projectiles: Array[Projectile] = []


func _init(grid: GridModel, roster: EnemyRoster, nav: NavGrid) -> void:
	_grid = grid
	_roster = roster
	_nav = nav
	grid.placement_added.connect(_on_placement_added)
	grid.placement_removed.connect(_on_placement_removed)
	for placement in grid.get_placements():
		_on_placement_added(placement)


func get_turrets() -> Array[TurretState]:
	return _turrets


func get_projectiles() -> Array[Projectile]:
	return _projectiles


func turret_at(placement: Placement) -> TurretState:
	return _by_placement.get(placement.id, null) if placement != null else null


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	var enemies := _roster.get_enemies()
	for turret in _turrets:
		_update_turret(turret, delta, enemies)
	_update_projectiles(delta)


## Clears projectiles (e.g. mission over). Turrets stay with the grid.
func clear_projectiles() -> void:
	_projectiles.clear()


# --- Turrets -----------------------------------------------------------------

func _update_turret(t: TurretState, delta: float, enemies: Array[Enemy]) -> void:
	t.cooldown -= delta
	if t.cooldown < -t.data.fire_interval:
		t.cooldown = 0.0 # idle: don't bank shots
	t.retarget_timer -= delta
	if t.target != null and not Targeting.can_target(t.target, t.data.target_layers, t.position, t.range_px):
		t.target = null
	# Scan when there is no valid target, and re-evaluate priority when ready
	# to fire (a faster unit may now lead) — both throttled.
	if (t.target == null or t.cooldown <= 0.0) and t.retarget_timer <= 0.0:
		t.target = Targeting.select(t.position, t.range_px, t.data.target_layers, t.data.priority, enemies, _nav)
		t.retarget_timer = RETARGET_INTERVAL
	if t.target == null:
		return
	var desired := (t.target.position - t.position).angle()
	var diff := wrapf(desired - t.aim_angle, -PI, PI)
	var step := deg_to_rad(t.data.turn_speed_deg) * delta
	t.aim_angle = wrapf(t.aim_angle + clampf(diff, -step, step), -PI, PI)
	if t.cooldown <= 0.0 and absf(wrapf(desired - t.aim_angle, -PI, PI)) <= deg_to_rad(t.data.aim_tolerance_deg):
		_fire(t)
		t.cooldown += t.data.fire_interval


func _fire(t: TurretState) -> void:
	var p := Projectile.new()
	var cs := float(_grid.cell_size)
	p.kind = t.data.projectile
	p.source = t
	p.target = t.target
	p.target_pos = t.target.position
	p.origin = t.position + Vector2.from_angle(t.aim_angle) * cs * 0.42 # muzzle
	p.position = p.origin
	p.speed_px = t.data.projectile_speed * cs
	p.damage = t.data.damage
	p.damage_type = t.data.damage_type
	p.splash_px = t.data.splash_radius_cells * cs
	p.splash_falloff = t.data.splash_falloff
	t.shots_fired += 1
	_projectiles.append(p)
	shot_fired.emit(t, p)


# --- Projectiles -------------------------------------------------------------

func _update_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	var finished: Array[Projectile] = []
	for p in _projectiles:
		p.age += delta
		if p.target != null and p.target.is_alive():
			p.target_pos = p.target.position
		var to_target := p.target_pos - p.position
		var step := p.speed_px * delta
		if to_target.length() <= step:
			p.position = p.target_pos
			_impact(p)
		elif p.age > MAX_PROJECTILE_AGE:
			p.done = true
		else:
			p.position += to_target.normalized() * step
		if p.done:
			finished.append(p)
	for p in finished:
		_projectiles.erase(p)


func _impact(p: Projectile) -> void:
	if p.done:
		return # never damage twice
	p.done = true
	var target_alive := p.target != null and p.target.is_alive()
	if p.splash_px > 0.0:
		_explode(p, target_alive)
		projectile_impact.emit(p, true)
	elif target_alive:
		_deal(p, p.target, p.damage)
		projectile_impact.emit(p, true)
	else:
		projectile_impact.emit(p, false)


## Area damage: direct target full damage, others in radius x falloff.
## Victims are collected first because kills mutate the roster's list.
func _explode(p: Projectile, target_alive: bool) -> void:
	var victims: Array[Enemy] = []
	var r2 := p.splash_px * p.splash_px
	for e in _roster.get_enemies():
		if e.is_alive() and e.position.distance_squared_to(p.position) <= r2:
			victims.append(e)
	if target_alive and not victims.has(p.target):
		victims.append(p.target)
	for e in victims:
		var amount := p.damage if (target_alive and e == p.target) else p.damage * p.splash_falloff
		_deal(p, e, amount)
	explosion.emit(p.position, p.splash_px, p.kind)


func _deal(p: Projectile, enemy: Enemy, amount: float) -> void:
	var was_alive := enemy.is_alive()
	var dealt := _roster.damage(enemy, amount, p.damage_type)
	if p.source != null:
		p.source.damage_dealt += dealt
		if was_alive and not enemy.is_alive():
			p.source.kills += 1


# --- Grid sync -----------------------------------------------------------------

func _on_placement_added(placement: Placement) -> void:
	if placement.data.turret == null:
		return
	var center := Vector2.ZERO
	for c in placement.cells:
		center += _grid.cell_to_local(c)
	center /= placement.cells.size()
	var t := TurretState.new(placement, placement.data.turret, center, _grid.cell_size)
	t.retarget_timer = RETARGET_INTERVAL * float(placement.id % RETARGET_PHASES) / RETARGET_PHASES
	_turrets.append(t)
	_by_placement[placement.id] = t
	turret_added.emit(t)


func _on_placement_removed(placement: Placement) -> void:
	var t: TurretState = _by_placement.get(placement.id, null)
	if t == null:
		return
	_by_placement.erase(placement.id)
	_turrets.erase(t)
	turret_removed.emit(t)
