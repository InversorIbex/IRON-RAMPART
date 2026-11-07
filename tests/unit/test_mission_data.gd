extends "res://tests/framework/test_case.gd"
## Mission data validation (Hito 4 case 19): every bad configuration is
## rejected with an explicit error, and a second mission parses with the same
## code (campaign readiness).

const H := preload("res://tests/unit/test_helpers.gd")


func before_each() -> void:
	LevelLoader.report_errors = false


func after_each() -> void:
	LevelLoader.report_errors = true


func _mission(waves: Variant, extra: Dictionary = {}) -> Dictionary:
	var d := H.level_dict(H.OPEN_LAYOUT)
	d["waves"] = waves
	for k in extra:
		d[k] = extra[k]
	return d


func _good_wave() -> Dictionary:
	return {"id": "w1", "name": "Probe", "reward": 10, "groups": [
		{"enemy": "infantry", "count": 3, "start": 0, "interval": 1.0, "spawn": 0}]}


func _expect_error(d: Dictionary, needle: String) -> void:
	var r := LevelLoader.parse_dict(d)
	assert_false(r.is_ok(), "should fail: " + needle)
	var joined := " | ".join(PackedStringArray(r.errors))
	assert_true(joined.contains(needle), "error mentions '%s': %s" % [needle, joined])


func test_valid_minimal_mission_parses() -> void:
	var r := LevelLoader.parse_dict(_mission([_good_wave()], {"mission": {"region": "Test", "spawn_names": ["gate"]}}))
	assert_true(r.is_ok(), "errors: %s" % [r.errors])
	if r.is_ok():
		assert_eq(r.level.waves.size(), 1)
		assert_eq(r.level.waves[0].groups[0].count, 3)
		assert_eq(r.level.spawn_name(0), "gate")


func test_wave_errors_are_explicit() -> void:
	var bad_enemy := _good_wave()
	bad_enemy["groups"][0]["enemy"] = "dragon"
	_expect_error(_mission([bad_enemy]), "unknown enemy 'dragon'")
	var bad_count := _good_wave()
	bad_count["groups"][0]["count"] = 0
	_expect_error(_mission([bad_count]), "'count'")
	var bad_interval := _good_wave()
	bad_interval["groups"][0]["interval"] = 0
	_expect_error(_mission([bad_interval]), "'interval'")
	var bad_start := _good_wave()
	bad_start["groups"][0]["start"] = -1
	_expect_error(_mission([bad_start]), "'start'")
	var no_groups := _good_wave()
	no_groups["groups"] = []
	_expect_error(_mission([no_groups]), "non-empty 'groups'")
	_expect_error(_mission([_good_wave(), _good_wave()]), "unique 'id'")
	var bad_mod := _good_wave()
	bad_mod["modifiers"] = {"hp": 50}
	_expect_error(_mission([bad_mod]), "'hp'")
	var bad_cond := _good_wave()
	bad_cond["completion"] = "kill_the_boss"
	_expect_error(_mission([bad_cond]), "unknown completion")
	_expect_error(_mission("five waves"), "'waves' must be an array")


func test_spawn_references_are_validated() -> void:
	var by_name := _good_wave()
	by_name["groups"][0]["spawn"] = "east"
	_expect_error(_mission([by_name], {"mission": {"spawn_names": ["gate"]}}), "unknown spawn 'east'")
	var by_index := _good_wave()
	by_index["groups"][0]["spawn"] = 3
	_expect_error(_mission([by_index]), "'spawn'")
	_expect_error(_mission([_good_wave()], {"mission": {"spawn_names": ["a", "b"]}}), "spawn_names")


func test_mission_identity_and_victory_are_validated() -> void:
	_expect_error(_mission([_good_wave()], {"mission": {"theme": "volcano"}}), "unknown mission theme")
	_expect_error(_mission([_good_wave()], {"victory": {"type": "capture_flag"}}), "victory.type")
	_expect_error(_mission([_good_wave()], {"mission": {"debrief_seconds": 999}}), "debrief_seconds")
	_expect_error(_mission([_good_wave()], {"mission": "outpost"}), "'mission' must be an object")


func test_second_mission_uses_the_same_format() -> void:
	# A different map, spawns and waves: no code changes needed (campaign readiness).
	var d := {
		"format_version": 1, "id": "w1_m02", "name": "Second Test",
		"mission": {"region": "Dust Frontier", "spawn_names": ["ridge", "road"], "theme": "desert"},
		"starting_credits": 400, "base_max_hp": 15,
		"available_structures": ["concrete_wall", "turret_hmg"],
		"rules": {"combat_build_surcharge": 0.5},
		"waves": [
			{"id": "a", "name": "A", "groups": [{"enemy": "infantry", "count": 2, "spawn": "ridge"}]},
			{"id": "b", "name": "B", "reward": 40, "modifiers": {"speed": 1.2},
				"groups": [{"enemy": "light_vehicle", "count": 2, "spawn": "road", "interval": 2}]},
		],
		"layout": ["S.......", "........", "........", ".......B", "S......."],
	}
	var r := LevelLoader.parse_dict(d)
	assert_true(r.is_ok(), "errors: %s" % [r.errors])
	if not r.is_ok():
		return
	var s := GameSession.new(r.level)
	assert_eq(s.waves.wave_count(), 2)
	assert_eq(s.construction.surcharge_ratio, 0.0)
	assert_true(s.start_wave())
	assert_eq(s.construction.price_of(StructureCatalog.load_structure(&"concrete_wall")), 38, "this mission's +50 %")
