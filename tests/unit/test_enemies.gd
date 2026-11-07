extends "res://tests/framework/test_case.gd"
## Enemy movement, routing, base damage, death and multi-unit behaviour.
## Mandatory cases 8 (reach base), 9/10 (destruction, damage), 12 (defeat), 13.

const H := preload("res://tests/unit/test_helpers.gd")
const DT := 1.0 / 60.0

## Pocket: row 2 west of (4,2) only connects to the rest through row 2.
const POCKET := [
	"S.......",
	"####.###",
	".......B",
]

var _events: Array[String] = []


func before_each() -> void:
	_events = []


func _data(id: String) -> EnemyData:
	return EnemyCatalog.get_data(StringName(id))


## Runs the session; returns every cell each enemy entered, keyed by enemy id.
func _run(s: GameSession, seconds: float) -> Dictionary:
	var visited := {}
	var steps := int(round(seconds / DT))
	for i in steps:
		for e in s.enemies.get_enemies():
			if not visited.has(e.id):
				visited[e.id] = [e.cell]
			if visited[e.id].back() != e.cell:
				visited[e.id].append(e.cell)
		s.tick(DT)
	return visited


func _assert_never_blocked(s: GameSession, cells: Array, movement: int, label: String) -> void:
	for c in cells:
		assert_true(s.nav.is_walkable(movement, c), "%s entered blocked cell %s" % [label, c])


func test_catalog_has_three_valid_types_with_distinct_mobility() -> void:
	var seen := {}
	for id in EnemyCatalog.PATHS:
		var d := EnemyCatalog.get_data(id)
		assert_not_null(d, "enemy '%s' loads" % id)
		if d != null:
			assert_eq(d.validate().size(), 0)
			seen[d.movement] = id
	assert_eq(seen.size(), 3, "infantry, wheeled and tracked are all represented")


func test_each_class_moves_towards_base_at_its_speed() -> void:
	for id in ["infantry", "light_vehicle", "heavy_tank"]:
		var s := H.make_session(H.OPEN_LAYOUT)
		var d := _data(id)
		var e := s.enemies.spawn(d, Vector2i(0, 2))
		var x0 := e.position.x
		_run(s, 1.0)
		var expected := d.speed * 64.0
		assert_true(absf((e.position.x - x0) - expected) < 64.0 * d.speed * DT * 2.0,
				"%s moved %.1f px, expected ~%.1f" % [id, e.position.x - x0, expected])
		assert_eq(e.state, Enemy.State.MOVING)


func test_movement_is_smooth_no_teleports() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var e := s.enemies.spawn(_data("light_vehicle"), Vector2i(0, 0))
	var prev := e.position
	var max_step := e.data.speed * 64.0 * DT + 0.001
	for i in 120:
		s.tick(DT)
		if not e.is_alive():
			break
		assert_true(prev.distance_to(e.position) <= max_step, "jump of %.2f px" % prev.distance_to(e.position))
		prev = e.position


func test_reaches_base_and_damages_hq_once() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	s.enemies.enemy_reached_base.connect(func(_e: Enemy) -> void: _events.append("arrived"))
	var hp0 := s.base_hp
	var e := s.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	_run(s, 7.0 / e.data.speed + 0.5)
	assert_eq(e.state, Enemy.State.ARRIVED)
	assert_eq(s.base_hp, hp0 - e.data.base_damage)
	assert_eq(s.enemies.count(), 0, "removed from the roster")
	assert_eq(_events, ["arrived"] as Array[String])


func test_differentiated_routes_per_mobility() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var at := StructureCatalog.load_structure(&"antitank_barrier")
	assert_true(s.construction.build(at, Vector2i(4, 2)).is_ok())
	var inf := s.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	var lv := s.enemies.spawn(_data("light_vehicle"), Vector2i(0, 2))
	var tank := s.enemies.spawn(_data("heavy_tank"), Vector2i(0, 2))
	var visited := _run(s, 12.0)
	assert_true(visited[inf.id].has(Vector2i(4, 2)), "infantry walks through the AT barrier")
	assert_false(visited[lv.id].has(Vector2i(4, 2)), "light vehicle goes around")
	assert_false(visited[tank.id].has(Vector2i(4, 2)), "tank goes around")
	for e in [inf, lv, tank]:
		assert_eq(e.state, Enemy.State.ARRIVED, "%s arrived" % e.data.id)
		_assert_never_blocked(s, visited[e.id], e.movement, e.data.id)


func test_tanks_cross_sandbags_others_do_not() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	assert_true(s.construction.build(StructureCatalog.load_structure(&"sandbags"), Vector2i(4, 2)).is_ok())
	var inf := s.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	var tank := s.enemies.spawn(_data("heavy_tank"), Vector2i(0, 2))
	var visited := _run(s, 12.0)
	assert_false(visited[inf.id].has(Vector2i(4, 2)))
	assert_true(visited[tank.id].has(Vector2i(4, 2)))


func test_enemy_reroutes_when_maze_changes_mid_run() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	var e := s.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	var visited := _run(s, 1.0) # now between (1,2) and (2,2)
	assert_eq(e.cell, Vector2i(1, 2))
	var check := s.construction.build(H.wall(), Vector2i(4, 2))
	assert_true(check.is_ok(), ConstructionService.reason_text(check))
	var rest := _run(s, 10.0)
	var path: Array = visited[e.id] + rest[e.id]
	assert_false(path.has(Vector2i(4, 2)), "never entered the new wall")
	assert_eq(e.state, Enemy.State.ARRIVED)
	_assert_never_blocked(s, path, e.movement, "infantry")


func test_cannot_build_on_cells_under_enemies() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var e := s.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	_run(s, 1.0)
	for c in [e.cell, e.next_cell]:
		assert_eq(s.construction.evaluate(H.wall(), c).reason,
				ConstructionService.Reason.OCCUPIED_BY_UNIT, "cell %s" % c)
	var walkable := H.structure("decor", 1, MovementClass.NONE)
	assert_true(s.construction.evaluate(walkable, e.next_cell).is_ok(), "non-blocking pieces allowed")


func test_cannot_trap_an_enemy_even_if_spawns_stay_open() -> void:
	var s := H.make_session(POCKET)
	s.enemies.spawn(_data("infantry"), Vector2i(1, 2)) # inside the pocket
	var check := s.construction.evaluate(H.wall(), Vector2i(3, 2))
	assert_eq(check.reason, ConstructionService.Reason.BLOCKS_ROUTE)
	assert_eq(check.broken_routes[0]["kind"], "unit")
	assert_true(ConstructionService.reason_text(check).contains("trap"))
	var no_units := H.make_session(POCKET)
	assert_true(no_units.construction.evaluate(H.wall(), Vector2i(3, 2)).is_ok(), "fine without the unit")


func test_lost_route_holds_position_then_resumes() -> void:
	# Construction prevents this; force it through GridModel to test robustness.
	var s := H.make_session(H.OPEN_LAYOUT)
	var e := s.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	_run(s, 1.0)
	var blockers: Array[Placement] = []
	for c in [Vector2i(2, 1), Vector2i(3, 2), Vector2i(2, 3), Vector2i(1, 2)]:
		blockers.append(s.grid.add_placement(H.wall(), c))
	_run(s, 2.0)
	assert_eq(e.state, Enemy.State.BLOCKED)
	assert_eq(e.cell, Vector2i(2, 2), "finished its committed segment, then held")
	var held := e.position
	_run(s, 1.0)
	assert_eq(e.position, held, "no movement while blocked")
	s.grid.remove_placement(blockers[1])
	_run(s, 8.0)
	assert_eq(e.state, Enemy.State.ARRIVED, "resumed after the route reopened")


func test_damage_armor_death_and_reward() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 0)
	s.enemies.enemy_killed.connect(func(_e: Enemy) -> void: _events.append("killed"))
	var tank := s.enemies.spawn(_data("heavy_tank"), Vector2i(0, 2))
	assert_true(absf(s.enemies.damage(tank, 100.0) - 40.0) < 0.001, "GENERIC vs HEAVY = 0.40")
	assert_true(absf(tank.hp - 560.0) < 0.001)
	var inf := s.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	s.enemies.damage(inf, 1000.0)
	assert_eq(inf.state, Enemy.State.DEAD)
	assert_eq(s.enemies.count(), 1, "dead unit removed")
	assert_eq(s.wallet.get_credits(), inf.data.reward)
	assert_eq(s.enemies.damage(inf, 10.0), 0.0, "dead units ignore damage")
	assert_eq(_events, ["killed"] as Array[String])


func test_defeat_when_hq_destroyed_and_simulation_freezes() -> void:
	var d := H.level_dict(H.OPEN_LAYOUT)
	d["base_max_hp"] = 4
	var s := GameSession.new(LevelLoader.parse_dict(d).level)
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	s.enemies.spawn(_data("heavy_tank"), Vector2i(0, 2)) # 5 damage
	var straggler := s.enemies.spawn(_data("heavy_tank"), Vector2i(0, 0)) # 9 cells: arrives later
	_run(s, 7.0 / 0.8 + 0.5)
	assert_eq(s.base_hp, 0)
	assert_eq(s.phase, GameSession.Phase.DEFEAT)
	var pos := straggler.position
	_run(s, 1.0)
	assert_eq(straggler.position, pos, "frozen after defeat")


func test_new_session_has_no_enemy_residue() -> void:
	var s1 := H.make_session(H.OPEN_LAYOUT)
	for i in 5:
		s1.enemies.spawn(_data("infantry"), Vector2i(0, 2))
	_run(s1, 1.0)
	var s2 := GameSession.new(s1.level)
	assert_eq(s2.enemies.count(), 0)
	assert_eq(s2.base_hp, s2.level.base_max_hp)
	_run(s1, 10.0)
	assert_eq(s2.base_hp, s2.level.base_max_hp, "old session cannot hurt the new HQ")


func test_many_enemies_all_arrive_without_crossing_walls() -> void:
	var level := LevelLoader.load_file("res://data/levels/mission_01.json").level
	level.base_max_hp = 1000 # keep the HQ alive so every unit can be checked
	var s := GameSession.new(level)
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	var wall := StructureCatalog.load_structure(&"concrete_wall")
	for y in range(2, 14):
		s.construction.build(wall, Vector2i(10, y)) # a long wall to route around
	var ids := ["infantry", "light_vehicle", "heavy_tank"]
	var spawned: Array[Enemy] = []
	var expected_damage := 0
	for i in 30:
		var e := s.enemies.spawn(_data(ids[i % 3]), level.spawn_cells[i % level.spawn_cells.size()])
		spawned.append(e)
		expected_damage += e.data.base_damage
	var visited := _run(s, 60.0)
	for e in spawned:
		assert_eq(e.state, Enemy.State.ARRIVED, "enemy %d (%s) arrived" % [e.id, e.data.id])
		_assert_never_blocked(s, visited[e.id], e.movement, e.data.id)
	assert_eq(level.base_max_hp - s.base_hp, expected_damage)
