extends "res://tests/framework/test_case.gd"
## Mandatory cases 1-7 (docs/TESTING.md) plus per-movement-class rules.

const H := preload("res://tests/unit/test_helpers.gd")

## Two gaps in the rock column: (3,1) and (3,3).
const TWO_GAPS := [
	"...#...",
	".......",
	"S..#...",
	".......",
	"...#..B",
]

const SPAWN_OPEN := Vector2i(0, 2)
const GOAL_OPEN := Vector2i(7, 2)


func _path(session: GameSession, bit: int) -> Array[Vector2i]:
	return session.nav.path_to_goal(bit, session.level.spawn_cells[0])


# 1
func test_build_on_free_cell() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100)
	var check := s.construction.build(H.wall(25), Vector2i(4, 0))
	assert_true(check.is_ok(), ConstructionService.reason_text(check))
	assert_true(s.grid.is_occupied(Vector2i(4, 0)))
	assert_eq(s.wallet.get_credits(), 75)
	assert_eq(s.grid.placement_count(), 1)
	assert_not_null(check.placement)


# 2
func test_reject_occupied_cell() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100)
	s.construction.build(H.wall(25), Vector2i(4, 0))
	var check := s.construction.build(H.wall(25), Vector2i(4, 0))
	assert_eq(check.reason, ConstructionService.Reason.OCCUPIED)
	assert_eq(s.wallet.get_credits(), 75, "second attempt must not charge")
	assert_eq(s.grid.placement_count(), 1)


# 3
func test_reject_insufficient_credits() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 10)
	var check := s.construction.build(H.wall(25), Vector2i(4, 0))
	assert_eq(check.reason, ConstructionService.Reason.INSUFFICIENT_CREDITS)
	assert_eq(s.wallet.get_credits(), 10)
	assert_false(s.grid.is_occupied(Vector2i(4, 0)))


# 4
func test_reject_build_that_blocks_every_route() -> void:
	var s := H.make_session(H.CHOKE_LAYOUT, 100)
	var check := s.construction.build(H.wall(25), Vector2i(3, 2))
	assert_eq(check.reason, ConstructionService.Reason.BLOCKS_ROUTE)
	assert_eq(check.broken_routes.size(), 3, "one broken route per movement class")


# 5
func test_rejected_build_preserves_resources_and_map() -> void:
	var s := H.make_session(H.CHOKE_LAYOUT, 100)
	var version_before := s.nav.version
	var path_before := _path(s, MovementClass.INFANTRY)
	s.construction.build(H.wall(25), Vector2i(3, 2))
	assert_eq(s.wallet.get_credits(), 100)
	assert_eq(s.grid.placement_count(), 0)
	assert_false(s.grid.is_occupied(Vector2i(3, 2)))
	assert_eq(s.nav.version, version_before, "navigation untouched")
	assert_true(s.construction.all_routes_open())
	for bit in MovementClass.ALL:
		assert_true(s.nav.is_walkable(bit, Vector2i(3, 2)), "simulation restored for class %d" % bit)
	assert_eq(_path(s, MovementClass.INFANTRY), path_before)


# 6
func test_routes_update_after_build() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var before := _path(s, MovementClass.INFANTRY)
	assert_eq(before.size(), 8, "straight line spawn->base")
	assert_true(before.has(Vector2i(4, 2)))
	var check := s.construction.build(H.wall(), Vector2i(4, 2))
	assert_true(check.is_ok())
	var after := _path(s, MovementClass.INFANTRY)
	assert_false(after.has(Vector2i(4, 2)), "route avoids the new wall")
	assert_eq(after.size(), 10, "orthogonal detour adds two cells")


# 7
func test_routes_update_after_removal_with_refund() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100)
	s.construction.build(H.wall(25), Vector2i(4, 2))
	var check := s.construction.remove_at(Vector2i(4, 2))
	assert_true(check.is_ok())
	assert_eq(check.refund, 12, "floor(25 * 0.5)")
	assert_eq(s.wallet.get_credits(), 87)
	assert_false(s.grid.is_occupied(Vector2i(4, 2)))
	var after := _path(s, MovementClass.INFANTRY)
	assert_eq(after.size(), 8)
	assert_true(after.has(Vector2i(4, 2)))


func test_remove_empty_cell_is_rejected() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100)
	assert_eq(s.construction.remove_at(Vector2i(1, 1)).reason, ConstructionService.Reason.NOTHING_TO_REMOVE)
	assert_eq(s.construction.remove_at(Vector2i(-5, 1)).reason, ConstructionService.Reason.NOTHING_TO_REMOVE)
	assert_eq(s.wallet.get_credits(), 100)


func test_reject_out_of_bounds_and_unbuildable_terrain() -> void:
	var s := H.make_session(H.CHOKE_LAYOUT, 100)
	assert_eq(s.construction.evaluate(H.wall(), Vector2i(-1, 0)).reason, ConstructionService.Reason.OUT_OF_BOUNDS)
	assert_eq(s.construction.evaluate(H.wall(), Vector2i(3, 0)).reason, ConstructionService.Reason.TERRAIN_NOT_BUILDABLE, "rock")
	assert_eq(s.construction.evaluate(H.wall(), Vector2i(0, 2)).reason, ConstructionService.Reason.TERRAIN_NOT_BUILDABLE, "spawn")
	assert_eq(s.construction.evaluate(H.wall(), Vector2i(6, 3)).reason, ConstructionService.Reason.TERRAIN_NOT_BUILDABLE, "base")


func test_multi_cell_partially_out_of_bounds_is_rejected() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100)
	var big := H.structure("bunker", 10, MovementClass.ALL_GROUND, Vector2i(2, 2))
	assert_eq(s.construction.evaluate(big, Vector2i(7, 0)).reason, ConstructionService.Reason.OUT_OF_BOUNDS)
	assert_true(s.construction.build(big, Vector2i(2, 0)).is_ok())
	assert_eq(s.construction.evaluate(H.wall(), Vector2i(3, 1)).reason, ConstructionService.Reason.OCCUPIED)


func test_antitank_barrier_splits_infantry_from_vehicles() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var at := H.structure("at", 35, MovementClass.WHEELED | MovementClass.TRACKED)
	assert_true(s.construction.build(at, Vector2i(4, 2)).is_ok())
	assert_true(_path(s, MovementClass.INFANTRY).has(Vector2i(4, 2)), "infantry walks through")
	assert_false(_path(s, MovementClass.WHEELED).has(Vector2i(4, 2)))
	assert_false(_path(s, MovementClass.TRACKED).has(Vector2i(4, 2)))


func test_sandbags_are_crossed_by_tracked_only() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var bags := H.structure("bags", 10, MovementClass.INFANTRY | MovementClass.WHEELED)
	assert_true(s.construction.build(bags, Vector2i(4, 2)).is_ok())
	assert_false(_path(s, MovementClass.INFANTRY).has(Vector2i(4, 2)))
	assert_false(_path(s, MovementClass.WHEELED).has(Vector2i(4, 2)))
	assert_true(_path(s, MovementClass.TRACKED).has(Vector2i(4, 2)), "tanks roll over sandbags")


func test_validation_is_per_movement_class() -> void:
	var s := H.make_session(TWO_GAPS)
	var at := H.structure("at", 35, MovementClass.WHEELED | MovementClass.TRACKED)
	var bags := H.structure("bags", 10, MovementClass.INFANTRY | MovementClass.WHEELED)
	assert_true(s.construction.build(at, Vector2i(3, 1)).is_ok(), "vehicles still have gap (3,3)")
	var check := s.construction.build(bags, Vector2i(3, 3))
	assert_eq(check.reason, ConstructionService.Reason.BLOCKS_ROUTE, "wheeled would have no gap left")
	assert_eq(check.broken_routes.size(), 1)
	assert_eq(check.broken_routes[0]["movement"], MovementClass.WHEELED)
	assert_true(s.construction.all_routes_open())


func test_non_blocking_structure_skips_route_check() -> void:
	var s := H.make_session(H.CHOKE_LAYOUT)
	var decor := H.structure("decor", 5, MovementClass.NONE)
	assert_true(s.construction.build(decor, Vector2i(3, 2)).is_ok(), "walkable structure may sit in the choke")
	assert_true(s.construction.all_routes_open())


func test_build_and_remove_locked_outside_build_phase() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100, {"allow_build_during_combat": false})
	s.construction.build(H.wall(25), Vector2i(4, 0))
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	assert_eq(s.construction.build(H.wall(25), Vector2i(5, 0)).reason, ConstructionService.Reason.PHASE_LOCKED)
	assert_eq(s.construction.remove_at(Vector2i(4, 0)).reason, ConstructionService.Reason.PHASE_LOCKED)
	assert_eq(s.wallet.get_credits(), 75)
	s.set_phase(GameSession.Phase.WAVE_COMPLETED) # back to a build phase
	assert_true(s.construction.remove_at(Vector2i(4, 0)).is_ok())


func test_footprint_is_centred_under_touch() -> void:
	assert_eq(ConstructionService.origin_for_cell(H.wall(), Vector2i(5, 5)), Vector2i(5, 5))
	var big := H.structure("big", 1, 7, Vector2i(3, 3))
	assert_eq(ConstructionService.origin_for_cell(big, Vector2i(5, 5)), Vector2i(4, 4))


# 13 (construction part): a new session from the same LevelData starts clean.
func test_new_session_has_no_residual_state() -> void:
	var s1 := H.make_session(H.OPEN_LAYOUT, 100)
	s1.construction.build(H.wall(25), Vector2i(4, 2))
	var s2 := GameSession.new(s1.level)
	assert_eq(s2.grid.placement_count(), 0)
	assert_eq(s2.wallet.get_credits(), 100)
	assert_false(s2.grid.is_occupied(Vector2i(4, 2)))
	assert_eq(_path(s2, MovementClass.INFANTRY).size(), 8)
	assert_eq(s2.phase, GameSession.Phase.PREPARATION)
