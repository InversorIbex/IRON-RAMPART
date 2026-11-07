extends "res://tests/framework/test_case.gd"
## Mandatory case 14: invalid data must be rejected loudly, never silently.

const H := preload("res://tests/unit/test_helpers.gd")
const MISSION_01 := "res://data/levels/mission_01.json"


func before_each() -> void:
	LevelLoader.report_errors = false # expected errors; keep the log readable


func after_each() -> void:
	LevelLoader.report_errors = true


func _expect_invalid(result: LevelLoader.Result, hint: String) -> void:
	assert_false(result.is_ok(), hint)
	assert_null(result.level, hint)
	assert_false(result.errors.is_empty(), "an explanatory error is required: " + hint)


func _with(key: String, value: Variant) -> Dictionary:
	var d := H.level_dict(H.OPEN_LAYOUT)
	d[key] = value
	return d


func test_mission_01_loads() -> void:
	var r := LevelLoader.load_file(MISSION_01)
	assert_true(r.is_ok(), "errors: %s" % [r.errors])
	if not r.is_ok():
		return
	var level := r.level
	assert_eq(level.width, 24)
	assert_eq(level.height, 16)
	assert_eq(level.spawn_cells.size(), 2)
	assert_eq(level.base_cells.size(), 4)
	assert_true(level.base_cells.has(level.goal_cell))
	assert_eq(level.movement_mask, MovementClass.ALL_GROUND)
	assert_eq(level.available_structures.size(), 6, "3 barriers + 3 turrets")


func test_goal_is_base_cell_closest_to_centroid() -> void:
	var r := LevelLoader.parse_dict(H.level_dict(H.OPEN_LAYOUT))
	assert_true(r.is_ok())
	assert_eq(r.level.goal_cell, Vector2i(7, 2))


func test_missing_file() -> void:
	_expect_invalid(LevelLoader.load_file("res://data/levels/does_not_exist.json"), "missing file")


func test_malformed_json() -> void:
	_expect_invalid(LevelLoader.parse_json_text("{ \"id\": \"x\", "), "truncated json")
	_expect_invalid(LevelLoader.parse_json_text("[1, 2, 3]"), "root not an object")


func test_unsupported_format_version() -> void:
	_expect_invalid(LevelLoader.parse_dict(_with("format_version", 99)), "version 99")
	var d := H.level_dict(H.OPEN_LAYOUT)
	d.erase("format_version")
	_expect_invalid(LevelLoader.parse_dict(d), "missing version")


func test_bad_layouts() -> void:
	_expect_invalid(LevelLoader.parse_dict(_with("layout", [])), "empty layout")
	_expect_invalid(LevelLoader.parse_dict(_with("layout", "S..B")), "layout not an array")
	_expect_invalid(LevelLoader.parse_dict(_with("layout", ["S...", "..B"])), "ragged rows")
	_expect_invalid(LevelLoader.parse_dict(_with("layout", ["S..X", "...B"])), "unknown char")
	_expect_invalid(LevelLoader.parse_dict(_with("layout", ["....", "...B"])), "no spawn")
	_expect_invalid(LevelLoader.parse_dict(_with("layout", ["S...", "...."])), "no base")
	_expect_invalid(LevelLoader.parse_dict(_with("layout", ["S#..", "##.B"])), "spawn sealed by rock")
	var d := H.level_dict(H.OPEN_LAYOUT)
	d.erase("layout")
	_expect_invalid(LevelLoader.parse_dict(d), "missing layout")


func test_bad_fields() -> void:
	_expect_invalid(LevelLoader.parse_dict(_with("cell_size", 63.5)), "non-integer cell size")
	_expect_invalid(LevelLoader.parse_dict(_with("cell_size", "64")), "string cell size")
	_expect_invalid(LevelLoader.parse_dict(_with("starting_credits", -1)), "negative credits")
	_expect_invalid(LevelLoader.parse_dict(_with("movement_classes", ["hover"])), "unknown class")
	_expect_invalid(LevelLoader.parse_dict(_with("movement_classes", [])), "no classes")
	_expect_invalid(LevelLoader.parse_dict(_with("available_structures", ["laser_wall"])), "unknown structure")
	_expect_invalid(LevelLoader.parse_dict(_with("id", "")), "empty id")
	_expect_invalid(LevelLoader.parse_dict(_with("rules", 5)), "rules not an object")


func test_errors_are_collected_not_just_first() -> void:
	var d := _with("starting_credits", -1)
	d["movement_classes"] = ["hover"]
	var r := LevelLoader.parse_dict(d)
	assert_true(r.errors.size() >= 2, "got %s" % [r.errors])
