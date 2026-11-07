extends "res://tests/framework/test_case.gd"
## WaveData / WaveManager / mission wave data (Hito 4 cases 2-6, 11, 12, 18, 19).

const H := preload("res://tests/unit/test_helpers.gd")
const DT := 1.0 / 60.0

var _spawns: Array = [] # [time, enemy_id, cell]
var _clock := 0.0


func before_each() -> void:
	_spawns = []
	_clock = 0.0


func _session(waves: Array[WaveData], credits: int = 1000, layout: Array = H.OPEN_LAYOUT) -> GameSession:
	var level := LevelLoader.parse_dict(H.level_dict(layout, credits)).level
	level.waves = waves
	var s := GameSession.new(level)
	s.enemies.enemy_spawned.connect(func(e: Enemy) -> void: _spawns.append([_clock, e.data.id, e.cell]))
	return s


func _tick(s: GameSession, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		_clock += DT
		s.tick(DT)


func _one(groups: Array, reward: int = 0) -> Array[WaveData]:
	var w: Array[WaveData] = [H.wave("w1", groups, reward)]
	return w


func test_schedule_order_and_intervals_are_deterministic() -> void:
	var w := H.wave("w", [["infantry", 3, 0.0, 1.0, 0], ["light_vehicle", 2, 0.5, 2.0, 0]])
	var sched := w.schedule(1)
	var times := sched.map(func(e: Dictionary) -> float: return e["time"])
	var ids := sched.map(func(e: Dictionary) -> StringName: return e["enemy"])
	assert_eq(times, [0.0, 0.5, 1.0, 2.0, 2.5])
	assert_eq(ids, [&"infantry", &"light_vehicle", &"infantry", &"infantry", &"light_vehicle"])
	assert_eq(w.schedule(1), sched, "same input, same schedule")


func test_alternate_spawn_cycles_through_spawns() -> void:
	var w := H.wave("w", [["infantry", 4, 0.0, 1.0]])
	assert_eq(w.schedule(2).map(func(e: Dictionary) -> int: return e["spawn"]), [0, 1, 0, 1])


func test_units_appear_in_order_at_their_intervals() -> void:
	var s := _session(_one([["infantry", 3, 0.0, 1.5], ["heavy_tank", 1, 1.0, 1.0]]))
	assert_true(s.start_wave())
	_tick(s, 4.0)
	assert_eq(_spawns.map(func(x: Array) -> StringName: return x[1]), [&"infantry", &"heavy_tank", &"infantry", &"infantry"])
	var times: Array = _spawns.map(func(x: Array) -> float: return x[0])
	for i in times.size():
		assert_true(absf(times[i] - [0.0, 1.0, 1.5, 3.0][i]) <= DT * 1.5, "unit %d at %.3f s" % [i, times[i]])


func test_no_spawns_outside_an_active_wave() -> void:
	var s := _session(_one([["infantry", 5, 0.0, 1.0]]))
	_tick(s, 3.0)
	assert_eq(_spawns.size(), 0, "nothing spawns in PREPARATION")
	s.start_wave()
	_tick(s, 0.5)
	assert_true(s.pause())
	var n := _spawns.size()
	_tick(s, 5.0)
	assert_eq(_spawns.size(), n, "nothing spawns while PAUSED")
	assert_true(s.resume())
	_tick(s, 5.0)
	assert_eq(_spawns.size(), 5, "the schedule continues after resuming")


func test_wave_ends_only_when_all_spawned_and_none_alive() -> void:
	var s := _session(_one([["infantry", 2, 0.0, 3.0]]))
	s.start_wave()
	_tick(s, 0.1)
	s.enemies.damage(s.enemies.get_enemies()[0], 9999.0) # field empty, one still to come
	_tick(s, 0.5)
	assert_eq(s.phase, GameSession.Phase.WAVE_ACTIVE, "not done: one unit still scheduled")
	_tick(s, 3.0)
	assert_eq(s.enemies.count(), 1)
	assert_eq(s.phase, GameSession.Phase.WAVE_ACTIVE, "not done: one unit alive")
	s.enemies.damage(s.enemies.get_enemies()[0], 9999.0)
	_tick(s, DT * 2)
	assert_ne(s.phase, GameSession.Phase.WAVE_ACTIVE, "done: all spawned and resolved")


func test_units_reaching_the_hq_also_resolve_the_wave() -> void:
	var two: Array[WaveData] = [H.wave("w1", [["infantry", 2, 0.0, 0.5]]), H.wave("w2", [["infantry", 1, 0.0, 1.0]])]
	var s := _session(two)
	s.start_wave()
	_tick(s, 10.0)
	assert_eq(s.base_hp, s.level.base_max_hp - 2, "both leaked")
	assert_eq(s.phase, GameSession.Phase.PREPARATION, "wave completed by arrivals, debrief over")
	assert_eq(s.stats.leaks, 2)


func test_wave_bonus_paid_once_and_no_reward_for_leaks() -> void:
	var two: Array[WaveData] = [H.wave("w1", [["infantry", 2, 0.0, 0.5]], 70), H.wave("w2", [["infantry", 1, 0.0, 1.0]])]
	var s := _session(two, 0)
	var completions := [0]
	s.wave_completed.connect(func(_i: int, _w: WaveData, _b: int) -> void: completions[0] += 1)
	s.start_wave()
	_tick(s, 0.1)
	s.enemies.damage(s.enemies.get_enemies()[0], 9999.0) # 1 kill = 5 CR
	_tick(s, 15.0) # the other leaks: no reward
	assert_eq(completions[0], 1)
	assert_eq(s.wallet.get_credits(), 5 + 70)
	assert_eq(s.stats.credits_from_waves, 70)
	assert_eq(s.stats.credits_from_kills, 5)


func test_difficulty_modifiers_apply_per_unit_only() -> void:
	var w := H.wave("w", [["heavy_tank", 1, 0.0, 1.0]])
	w.hp_multiplier = 1.5
	w.speed_multiplier = 1.2
	var waves: Array[WaveData] = [w]
	var s := _session(waves)
	s.start_wave()
	_tick(s, 0.05)
	var tank := s.enemies.get_enemies()[0]
	assert_eq(tank.max_hp, 900.0)
	assert_eq(tank.hp, 900.0)
	assert_true(absf(tank.speed - 0.96) < 0.0001)
	assert_eq(EnemyCatalog.get_data(&"heavy_tank").max_hp, 600, "shared EnemyData untouched")


func test_mission_01_waves_escalate() -> void:
	var level := LevelLoader.load_file("res://data/levels/mission_01.json").level
	assert_eq(level.display_name, "Operation First Assault")
	assert_eq(level.waves.size(), 5)
	assert_eq(level.waves.map(func(w: WaveData) -> String: return w.display_name),
			["First Contact", "Fast Approach", "Armored Threat", "Breaking Point", "Iron Assault"])
	for i in range(1, 5):
		assert_true(level.waves[i].enemy_count() > level.waves[i - 1].enemy_count(), "wave %d bigger" % (i + 1))
	assert_eq(level.waves[0].composition().keys(), [&"infantry"], "wave 1 teaches with infantry only")
	assert_false(level.waves[1].composition().has(&"heavy_tank"), "no tanks before wave 3")
	assert_true(level.waves[2].composition().has(&"heavy_tank"), "wave 3 introduces armour")
	var tanks: Array = level.waves.map(func(w: WaveData) -> int: return w.composition().get(&"heavy_tank", 0))
	assert_eq(tanks.max(), tanks[4], "the final wave brings the most armour")
	assert_eq(level.spawn_names, PackedStringArray(["north", "west"]))
