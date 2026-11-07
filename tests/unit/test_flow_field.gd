extends "res://tests/framework/test_case.gd"
## NavGrid flow fields: shared navigation, sync with the grid, simulations.

const H := preload("res://tests/unit/test_helpers.gd")
const INF := MovementClass.INFANTRY


func test_nav_follows_direct_grid_mutations() -> void:
	# Audit H1 regression: mutating GridModel directly must update navigation.
	var s := H.make_session(H.OPEN_LAYOUT)
	var p := s.grid.add_placement(H.wall(), Vector2i(4, 2))
	assert_false(s.nav.is_walkable(INF, Vector2i(4, 2)), "nav sees the new wall")
	assert_false(s.nav.path_to_goal(INF, Vector2i(0, 2)).has(Vector2i(4, 2)))
	s.grid.remove_placement(p)
	assert_true(s.nav.is_walkable(INF, Vector2i(4, 2)), "nav sees the removal")


func test_distances_are_shortest_steps() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	assert_eq(s.nav.distance(INF, Vector2i(7, 2)), 0, "goal")
	assert_eq(s.nav.distance(INF, Vector2i(0, 2)), 7)
	assert_eq(s.nav.distance(INF, Vector2i(0, 0)), 9)


func test_next_step_descends_and_is_deterministic() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	assert_eq(s.nav.next_step(INF, Vector2i(0, 0)), Vector2i(1, 0), "horizontal first")
	assert_eq(s.nav.next_step(INF, Vector2i(7, 0)), Vector2i(7, 1))
	assert_eq(s.nav.next_step(INF, Vector2i(7, 2)), Vector2i(7, 2), "goal returns itself")
	var a := s.nav.path_to_goal(INF, Vector2i(0, 4))
	var b := s.nav.path_to_goal(INF, Vector2i(0, 4))
	assert_eq(a, b)
	assert_eq(a.size(), 7 + 2 + 1)


func test_unreachable_cells_have_no_step() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	# Box in (1,0) by direct mutation (bypassing construction rules on purpose).
	for c in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1)]:
		s.grid.add_placement(H.wall(), c)
	assert_eq(s.nav.distance(INF, Vector2i(1, 0)), NavGrid.UNREACHABLE)
	assert_eq(s.nav.next_step(INF, Vector2i(1, 0)), NavGrid.NO_CELL)
	assert_eq(s.nav.path_to_goal(INF, Vector2i(1, 0)).size(), 0)


func test_simulation_never_touches_live_fields() -> void:
	var s := H.make_session(H.CHOKE_LAYOUT)
	var v := s.nav.version
	var d := s.nav.distance(INF, Vector2i(0, 2))
	var reqs := [{"cell": Vector2i(0, 2), "movement": INF}]
	var blocked: Array[Vector2i] = [Vector2i(3, 2)]
	assert_eq(s.nav.find_broken_routes(reqs, blocked, MovementClass.ALL_GROUND).size(), 1)
	assert_eq(s.nav.version, v)
	assert_eq(s.nav.distance(INF, Vector2i(0, 2)), d)
	assert_true(s.nav.is_walkable(INF, Vector2i(3, 2)))


func test_fields_rebuild_only_on_topology_change() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var before := s.nav.rebuild_count
	for i in 50:
		s.nav.next_step(INF, Vector2i(0, 2))
		s.nav.path_to_goal(INF, Vector2i(0, 4))
	s.construction.evaluate(H.wall(), Vector2i(4, 2)) # preview: simulation only
	assert_eq(s.nav.rebuild_count, before, "queries and previews never rebuild")
	s.construction.build(H.wall(), Vector2i(4, 2))
	assert_eq(s.nav.rebuild_count, before + 1, "one rebuild per real change")
