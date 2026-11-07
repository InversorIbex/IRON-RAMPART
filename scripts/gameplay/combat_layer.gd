class_name CombatLayer
extends Node2D
## Combat visuals: owns TurretViews and draws projectiles + short-lived
## effects (tracers, missile smoke, impacts, explosions, wreck fires) in a
## single _draw per frame. Purely cosmetic: it listens to CombatSystem and
## EnemyRoster signals and never changes gameplay state.
## Child of GridView (above EnemyLayer), so it shares its transform.

signal heavy_impact(strength: float) ## for camera shake

enum Fx { SPARK, PUFF, EXPLOSION, SMOKE, SCORCH, DEBRIS }

const TURRET_SCENE := preload("res://scenes/turrets/turret_view.tscn")
## Hard cap on simultaneous effects so heavy fights can't explode the cost.
const MAX_EFFECTS := 400
const TEXT_LIFE := 0.9

## CPU time of the last _draw() (GDScript building draw commands), microseconds.
var last_draw_usec: int = 0

var _combat: CombatSystem
var _cell: float = 64.0
var _views: Dictionary = {} # TurretState -> TurretView
## Each effect: [kind, position, age, life, size, extra]
var _effects: Array = []
var _active_last_frame: bool = false
## Floating reward texts: [position, age, text]
var _texts: Array = []


func bind(combat: CombatSystem, roster: EnemyRoster, cell_size: float) -> void:
	_combat = combat
	_cell = cell_size
	combat.turret_added.connect(_on_turret_added)
	combat.turret_removed.connect(_on_turret_removed)
	combat.shot_fired.connect(_on_shot)
	combat.projectile_impact.connect(_on_impact)
	combat.explosion.connect(_on_explosion)
	roster.enemy_killed.connect(_on_enemy_killed)
	for t in combat.get_turrets():
		_on_turret_added(t)


func effect_count() -> int:
	return _effects.size()


func view_count() -> int:
	return _views.size()


func sync(delta: float) -> void:
	for view in _views.values():
		(view as TurretView).sync(delta)
	var i := 0
	while i < _effects.size():
		var fx: Array = _effects[i]
		fx[2] += delta
		if fx[2] >= fx[3]:
			_effects.remove_at(i)
		else:
			i += 1
	# Missile exhaust: drop a smoke puff behind each missile.
	for p in _combat.get_projectiles():
		if p.kind == TurretData.ProjectileKind.MISSILE:
			_add(Fx.SMOKE, p.position - p.heading() * _cell * 0.12, 0.6, _cell * 0.08)
	var j := 0
	while j < _texts.size():
		_texts[j][1] += delta
		if _texts[j][1] >= TEXT_LIFE:
			_texts.remove_at(j)
		else:
			j += 1
	var active := not _effects.is_empty() or not _combat.get_projectiles().is_empty() or not _texts.is_empty()
	if active or _active_last_frame:
		queue_redraw()
	_active_last_frame = active


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_all()
	last_draw_usec = Time.get_ticks_usec() - t0


func _draw_all() -> void:
	# Ground-level effects first (scorch, smoke), then projectiles, then flashes.
	for fx in _effects:
		var t: float = fx[2] / fx[3]
		match fx[0]:
			Fx.SCORCH:
				draw_circle(fx[1], fx[4], Color(Palette.FX_SCORCH, 0.35 * (1.0 - t)))
			Fx.SMOKE:
				draw_circle(fx[1], fx[4] * (1.0 + t * 1.5), Color(Palette.FX_SMOKE, 0.45 * (1.0 - t)))
	for p in _combat.get_projectiles():
		_draw_projectile(p)
	for fx in _effects:
		var t: float = fx[2] / fx[3]
		match fx[0]:
			Fx.SPARK:
				draw_circle(fx[1], fx[4] * (1.0 - t), Color(Palette.FX_SPARK, 1.0 - t))
				for k in 4:
					var ray: Vector2 = Vector2.from_angle(fx[5] + k * TAU / 4.0) * fx[4] * (0.8 + 1.6 * t)
					draw_line(fx[1] + ray * 0.4, fx[1] + ray, Color(Palette.FX_FLASH, 1.0 - t), 2.0)
			Fx.PUFF:
				draw_circle(fx[1], fx[4] * (0.6 + t), Color(Palette.FX_DUST, 0.5 * (1.0 - t)))
			Fx.EXPLOSION:
				var r: float = fx[4]
				draw_circle(fx[1], r * (0.4 + 0.6 * t), Color(Palette.FX_FIRE, 0.9 * (1.0 - t)))
				draw_circle(fx[1], r * 0.5 * (1.0 - t), Color(Palette.FX_FLASH, 1.0 - t))
				draw_arc(fx[1], r * (0.5 + t), 0.0, TAU, 24, Color(Palette.FX_SPARK, 0.7 * (1.0 - t)), 3.0)
			Fx.DEBRIS:
				for k in 6:
					var dir := Vector2.from_angle(float(k) * TAU / 6.0 + fx[5])
					draw_circle(fx[1] + dir * fx[4] * t, 3.0, Color(Palette.FX_DEBRIS, 1.0 - t))
	# Reward pop-ups: rise and fade (gold = credits).
	for tx in _texts:
		var k: float = tx[1] / TEXT_LIFE
		var pos: Vector2 = tx[0] + Vector2(-14, -18 - 28.0 * k)
		draw_string(ThemeDB.fallback_font, pos + Vector2(1, 1), tx[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
				Color(Palette.OLIVE_BLACK, 1.0 - k))
		draw_string(ThemeDB.fallback_font, pos, tx[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(Palette.TACTICAL_GOLD, 1.0 - k))


func _draw_projectile(p: Projectile) -> void:
	var dir := p.heading()
	match p.kind:
		TurretData.ProjectileKind.BULLET:
			# Tracer: bright streak behind the round.
			var tail := p.position - dir * minf(_cell * 0.6, p.position.distance_to(p.origin))
			draw_line(tail, p.position, Color(Palette.TACTICAL_GOLD, 0.45), 7.0) # glow
			draw_line(p.position - dir * _cell * 0.3, p.position, Palette.FX_FLASH, 3.0) # hot core
		TurretData.ProjectileKind.MISSILE:
			var side := Vector2(-dir.y, dir.x)
			draw_line(p.position - dir * _cell * 0.18, p.position, Palette.FX_MISSILE, 5.0)
			draw_line(p.position - dir * _cell * 0.18 + side * 4, p.position - dir * _cell * 0.18 - side * 4, Palette.METAL_DARK, 3.0)
			draw_circle(p.position - dir * _cell * 0.2, 4.0, Palette.FX_FIRE) # motor
		TurretData.ProjectileKind.FLAK:
			draw_circle(p.position, 3.0, Palette.FX_SPARK)


func _add(kind: int, pos: Vector2, life: float, size: float, extra: float = 0.0) -> void:
	if _effects.size() >= MAX_EFFECTS:
		_effects.pop_front()
	_effects.append([kind, pos, 0.0, life, size, extra])


func _on_turret_added(t: TurretState) -> void:
	var view: TurretView = TURRET_SCENE.instantiate()
	view.setup(t, _cell)
	add_child(view)
	_views[t] = view


func _on_turret_removed(t: TurretState) -> void:
	var view: TurretView = _views.get(t)
	if view != null:
		_views.erase(t)
		view.queue_free()


func _on_shot(t: TurretState, _p: Projectile) -> void:
	var view: TurretView = _views.get(t)
	if view != null:
		view.on_fired()


func _on_impact(p: Projectile, hit: bool) -> void:
	if p.kind == TurretData.ProjectileKind.BULLET:
		_add(Fx.SPARK if hit else Fx.PUFF, p.position, 0.2 if hit else 0.35, _cell * (0.12 if hit else 0.08), p.age * 37.0)


func _on_explosion(pos: Vector2, radius_px: float, kind: int) -> void:
	var big := kind == TurretData.ProjectileKind.MISSILE
	_add(Fx.EXPLOSION, pos, 0.45 if big else 0.25, radius_px)
	_add(Fx.SMOKE, pos, 1.6, radius_px * 0.4)
	if big:
		_add(Fx.SCORCH, pos, 6.0, radius_px * 0.6)
		heavy_impact.emit(0.6)


func _on_enemy_killed(enemy: Enemy) -> void:
	if enemy.data.reward > 0:
		if _texts.size() >= 40:
			_texts.pop_front()
		_texts.append([enemy.position, 0.0, "+%d" % enemy.data.reward])
	var size := maxf(enemy.data.visual_size.x, enemy.data.visual_size.y) * _cell
	if enemy.data.silhouette == EnemyData.Silhouette.SOLDIER:
		_add(Fx.PUFF, enemy.position, 0.5, size * 0.6)
		return
	# Vehicles: fireball, debris, lingering smoke and a scorch mark.
	_add(Fx.EXPLOSION, enemy.position, 0.6, size * 0.9)
	_add(Fx.DEBRIS, enemy.position, 0.6, size * 1.2, float(enemy.id))
	_add(Fx.SMOKE, enemy.position, 2.5, size * 0.35)
	_add(Fx.SCORCH, enemy.position, 8.0, size * 0.55)
	heavy_impact.emit(1.0 if enemy.data.silhouette == EnemyData.Silhouette.TRACKED_VEHICLE else 0.5)
