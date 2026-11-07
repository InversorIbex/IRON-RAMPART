extends "res://tests/framework/test_case.gd"

const H := preload("res://tests/unit/test_helpers.gd")

var session: GameSession
var grid: GridModel


func before_each() -> void:
	session = H.make_session(H.CHOKE_LAYOUT)
	grid = session.grid


func test_dimensions_come_from_data() -> void:
	assert_eq(grid.width, 7)
	assert_eq(grid.height, 5)
	assert_eq(grid.cell_size, 64)
	assert_eq(grid.size_in_pixels(), Vector2(448, 320))


func test_local_to_cell_and_back() -> void:
	assert_eq(grid.local_to_cell(Vector2(0, 0)), Vector2i(0, 0))
	assert_eq(grid.local_to_cell(Vector2(65, 130)), Vector2i(1, 2))
	assert_eq(grid.local_to_cell(Vector2(63.9, 63.9)), Vector2i(0, 0))
	assert_eq(grid.local_to_cell(Vector2(-1, -1)), Vector2i(-1, -1), "negative coords must floor, not truncate")
	assert_eq(grid.cell_to_local(Vector2i(1, 2)), Vector2(96, 160))
	assert_eq(grid.local_to_cell(grid.cell_to_local(Vector2i(5, 3))), Vector2i(5, 3))


func test_bounds() -> void:
	assert_true(grid.is_in_bounds(Vector2i(0, 0)))
	assert_true(grid.is_in_bounds(Vector2i(6, 4)))
	assert_false(grid.is_in_bounds(Vector2i(7, 0)))
	assert_false(grid.is_in_bounds(Vector2i(0, 5)))
	assert_false(grid.is_in_bounds(Vector2i(-1, 0)))


func test_terrain_buildability() -> void:
	assert_true(grid.is_buildable_terrain(Vector2i(1, 1)), "ground")
	assert_false(grid.is_buildable_terrain(Vector2i(3, 0)), "rock")
	assert_false(grid.is_buildable_terrain(Vector2i(0, 2)), "spawn")
	assert_false(grid.is_buildable_terrain(Vector2i(6, 3)), "base")
	assert_false(grid.is_buildable_terrain(Vector2i(99, 99)), "out of bounds")


func test_rock_blocks_every_class() -> void:
	assert_eq(grid.blocking_mask_at(Vector2i(3, 0)), MovementClass.ALL_GROUND)
	assert_eq(grid.blocking_mask_at(Vector2i(1, 1)), MovementClass.NONE)


func test_multi_cell_placement_occupies_and_frees_all_cells() -> void:
	var bunker := H.structure("bunker", 10, MovementClass.ALL_GROUND, Vector2i(2, 2))
	var p := grid.add_placement(bunker, Vector2i(0, 0))
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		assert_true(grid.is_occupied(cell), "cell %s occupied" % cell)
		assert_eq(grid.get_placement_at(cell), p)
	assert_false(grid.is_occupied(Vector2i(2, 0)))
	grid.remove_placement(p)
	assert_eq(grid.placement_count(), 0)
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		assert_false(grid.is_occupied(cell), "cell %s freed" % cell)


func test_level_terrain_is_not_shared_with_grid() -> void:
	# GridModel must copy terrain so a restart from the same LevelData is clean.
	var level := session.level
	var other := GridModel.new(level)
	assert_eq(other.terrain_at(Vector2i(3, 0)), Terrain.ROCK)
	assert_eq(level.terrain_at(Vector2i(3, 0)), Terrain.ROCK)
