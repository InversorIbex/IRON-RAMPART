class_name EnemyRoster
extends RefCounted
## Owns and moves every enemy of a session. Pure logic: no nodes, fixed by
## `update(delta)`, so it is fully testable headless.
##
## Navigation cost: an enemy only queries NavGrid.next_step (an O(1) lookup in
## the shared flow field) when it reaches a cell centre. Nothing is searched
## per frame and nothing per enemy. Blocked units are re-checked only when the
## topology changes.

signal enemy_spawned(enemy: Enemy)
## Destroyed by damage. Reward is applied by GameSession.
signal enemy_killed(enemy: Enemy)
## Reached a base cell. HQ damage is applied by GameSession.
signal enemy_reached_base(enemy: Enemy)
## Emitted after either of the above, once the enemy left the roster.
signal enemy_removed(enemy: Enemy)

var _grid: GridModel
var _nav: NavGrid
var _enemies: Array[Enemy] = []
var _next_id: int = 1
var _has_blocked: bool = false


func _init(grid: GridModel, nav: NavGrid) -> void:
	_grid = grid
	_nav = nav
	_nav.topology_changed.connect(_on_topology_changed)


func get_enemies() -> Array[Enemy]:
	return _enemies


func count() -> int:
	return _enemies.size()


func spawn(data: EnemyData, spawn_cell: Vector2i) -> Enemy:
	assert(data != null, "spawn() needs EnemyData")
	var enemy := Enemy.new(_next_id, data, spawn_cell)
	_next_id += 1
	enemy.position = _grid.cell_to_local(spawn_cell)
	_choose_next(enemy)
	_enemies.append(enemy)
	enemy_spawned.emit(enemy)
	return enemy


## The single damage entry point: applies armour (Damage table), kills and
## removes the enemy at hp <= 0 and emits enemy_killed exactly once.
func damage(enemy: Enemy, amount: float, type: int = Damage.Type.GENERIC) -> float:
	var dealt := enemy.apply_damage(amount, type)
	if enemy.is_alive() and enemy.hp <= 0.0:
		enemy.state = Enemy.State.DEAD
		_remove(enemy)
		enemy_killed.emit(enemy)
		enemy_removed.emit(enemy)
	return dealt


func update(delta: float) -> void:
	if delta <= 0.0 or _enemies.is_empty():
		return
	var arrived: Array[Enemy] = []
	for enemy in _enemies:
		enemy.age += delta
		if enemy.state != Enemy.State.MOVING:
			continue
		enemy.progress += enemy.data.speed * delta
		while enemy.progress >= 1.0 and enemy.state == Enemy.State.MOVING:
			enemy.progress -= 1.0
			enemy.cell = enemy.next_cell
			enemy.cells_walked += 1
			if _grid.terrain_at(enemy.cell) == Terrain.BASE:
				enemy.state = Enemy.State.ARRIVED
				enemy.progress = 0.0
				arrived.append(enemy)
			else:
				_choose_next(enemy)
		_place(enemy)
	for enemy in arrived:
		_remove(enemy)
		enemy_reached_base.emit(enemy)
		enemy_removed.emit(enemy)


## Cells that must stay free: the cell each unit is leaving and the one it is entering.
func occupied_cells() -> Dictionary:
	var cells := {}
	for enemy in _enemies:
		cells[enemy.cell] = true
		cells[enemy.next_cell] = true
	return cells


## For construction validation: each live unit must keep a route from the
## cell it is walking to (its committed segment end).
func route_requirements() -> Array[Dictionary]:
	var seen := {}
	var reqs: Array[Dictionary] = []
	for enemy in _enemies:
		var key := Vector3i(enemy.next_cell.x, enemy.next_cell.y, enemy.movement)
		if seen.has(key):
			continue
		seen[key] = true
		reqs.append({"cell": enemy.next_cell, "movement": enemy.movement, "kind": "unit"})
	return reqs


## Removes every enemy without rewards or damage (used on teardown).
func clear() -> void:
	for enemy in _enemies.duplicate():
		enemy.state = Enemy.State.DEAD
		_remove(enemy)
		enemy_removed.emit(enemy)


func _choose_next(enemy: Enemy) -> void:
	var nxt := _nav.next_step(enemy.movement, enemy.cell)
	if nxt == NavGrid.NO_CELL:
		# No route (should be prevented by construction rules): hold position
		# and wait for the next topology change.
		enemy.state = Enemy.State.BLOCKED
		enemy.next_cell = enemy.cell
		enemy.progress = 0.0
		_has_blocked = true
		return
	enemy.state = Enemy.State.MOVING
	enemy.next_cell = nxt
	if nxt != enemy.cell:
		enemy.heading = Vector2(nxt - enemy.cell)


func _place(enemy: Enemy) -> void:
	var a := _grid.cell_to_local(enemy.cell)
	var b := _grid.cell_to_local(enemy.next_cell)
	enemy.position = a.lerp(b, enemy.progress)


func _on_topology_changed(_version: int) -> void:
	if not _has_blocked:
		return
	_has_blocked = false
	for enemy in _enemies:
		if enemy.state == Enemy.State.BLOCKED:
			_choose_next(enemy)


func _remove(enemy: Enemy) -> void:
	var i := _enemies.find(enemy)
	if i >= 0:
		_enemies.remove_at(i)
