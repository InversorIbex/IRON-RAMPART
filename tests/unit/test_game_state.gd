extends "res://tests/framework/test_case.gd"
## Mission state machine, pause, victory/defeat, stats and score
## (Hito 4 cases 1, 7-9, 13-15, 20).

const H := preload("res://tests/unit/test_helpers.gd")
const DT := 1.0 / 60.0
const P := GameSession.Phase

var _ended: Array = []


func before_each() -> void:
	_ended = []


func _session(waves: Array[WaveData], credits: int = 1000, hp: int = 20) -> GameSession:
	var d := H.level_dict(H.OPEN_LAYOUT, credits)
	d["base_max_hp"] = hp
	var level := LevelLoader.parse_dict(d).level
	level.waves = waves
	level.debrief_seconds = 1.0
	var s := GameSession.new(level)
	s.mission_ended.connect(func(v: bool) -> void: _ended.append(v))
	return s


func _two_waves() -> Array[WaveData]:
	var w: Array[WaveData] = [H.wave("w1", [["infantry", 2, 0.0, 0.5]], 50), H.wave("w2", [["infantry", 2, 0.0, 0.5]], 50)]
	return w


func _tick(s: GameSession, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		s.tick(DT)


func _kill_all(s: GameSession) -> void:
	for e in s.enemies.get_enemies().duplicate():
		s.enemies.damage(e, 99999.0)


func test_mission_starts_in_preparation() -> void:
	var s := _session(_two_waves())
	assert_eq(s.phase, P.PREPARATION)
	assert_eq(s.wave_number(), 0)
	assert_eq(s.waves.wave_count(), 2)
	assert_true(s.construction.build_enabled)
	assert_eq(s.construction.surcharge_ratio, 0.0)


func test_start_wave_transitions_and_counts() -> void:
	var s := _session(_two_waves())
	assert_true(s.start_wave())
	assert_eq(s.phase, P.WAVE_ACTIVE)
	assert_eq(s.wave_number(), 1)
	assert_false(s.start_wave(), "cannot start a wave during a wave")


func test_invalid_transitions_are_rejected() -> void:
	var s := _session(_two_waves())
	for bad in [P.VICTORY, P.WAVE_COMPLETED, P.PREPARATION]:
		assert_false(s.set_phase(bad), "PREPARATION -> %s" % P.keys()[bad])
	assert_eq(s.phase, P.PREPARATION)
	assert_false(s.resume(), "not paused")
	s.start_wave()
	assert_false(s.set_phase(P.PREPARATION), "WAVE_ACTIVE -> PREPARATION skips the wave end")
	s.set_phase(P.DEFEAT)
	for any in [P.PREPARATION, P.WAVE_ACTIVE, P.WAVE_COMPLETED, P.VICTORY, P.PAUSED]:
		assert_false(s.set_phase(any), "DEFEAT is final (-> %s)" % P.keys()[any])
	assert_false(s.pause())
	assert_false(s.start_wave())


func test_pause_resumes_the_exact_previous_state() -> void:
	var s := _session(_two_waves())
	for setup in ["prep", "active", "completed"]:
		s = _session(_two_waves())
		if setup != "prep":
			s.start_wave()
		if setup == "completed":
			_tick(s, 0.6)
			_kill_all(s)
			_tick(s, DT * 2)
		var before := s.phase
		assert_true(s.pause(), setup)
		assert_eq(s.phase, P.PAUSED)
		assert_false(s.pause(), "double pause rejected")
		assert_false(s.construction.build_enabled, "no building while paused")
		assert_true(s.resume())
		assert_eq(s.phase, before, "resumed into %s" % setup)


func test_paused_simulation_is_frozen() -> void:
	var s := _session(_two_waves())
	s.start_wave()
	_tick(s, 0.3)
	var e := s.enemies.get_enemies()[0]
	var pos := e.position
	s.pause()
	_tick(s, 5.0)
	assert_eq(e.position, pos, "units don't move")
	assert_eq(s.enemies.count(), 1, "no new spawns")
	assert_eq(s.base_hp, 20)


func test_debrief_then_preparation_and_skip() -> void:
	var s := _session(_two_waves())
	s.start_wave()
	_tick(s, 0.6)
	_kill_all(s)
	_tick(s, DT * 2)
	assert_eq(s.phase, P.WAVE_COMPLETED)
	assert_eq(s.construction.surcharge_ratio, 0.0, "no surcharge between waves")
	_tick(s, 1.2)
	assert_eq(s.phase, P.PREPARATION, "debrief ends by itself")
	var s2 := _session(_two_waves())
	s2.start_wave()
	_tick(s2, 0.6)
	_kill_all(s2)
	_tick(s2, DT * 2)
	assert_true(s2.start_wave(), "START WAVE during the debrief skips it")
	assert_eq(s2.wave_number(), 2)


func test_build_rules_per_phase() -> void:
	var s := _session(_two_waves(), 1000)
	var wall := H.wall(100)
	assert_eq(s.construction.price_of(wall), 100, "PREPARATION")
	s.start_wave()
	assert_eq(s.construction.price_of(wall), 125, "WAVE_ACTIVE: +25 %")
	assert_true(s.construction.build(wall, Vector2i(4, 0)).is_ok(), "build during combat")
	assert_eq(s.wallet.get_credits(), 875)
	s.pause()
	assert_eq(s.construction.build(wall, Vector2i(5, 0)).reason, ConstructionService.Reason.PHASE_LOCKED)
	assert_eq(s.wallet.get_credits(), 875, "rejected while paused: no charge")


func test_insufficient_credits_in_combat_charges_nothing() -> void:
	var s := _session(_two_waves(), 110)
	s.start_wave()
	var check := s.construction.build(H.wall(100), Vector2i(4, 0))
	assert_eq(check.reason, ConstructionService.Reason.INSUFFICIENT_CREDITS, "needs 125")
	assert_eq(s.wallet.get_credits(), 110)


func test_victory_after_last_wave() -> void:
	var s := _session(_two_waves(), 0)
	for i in 2:
		assert_true(s.start_wave())
		_tick(s, 0.6)
		_kill_all(s)
		_tick(s, DT * 2)
	assert_eq(s.phase, P.VICTORY)
	assert_eq(_ended, [true], "mission_ended emitted once")
	assert_eq(s.stats.waves_completed, 2)
	assert_eq(s.wallet.get_credits(), 4 * 5 + 2 * 50, "4 kills + 2 bonuses")
	assert_false(s.start_wave())
	var credits := s.wallet.get_credits()
	_tick(s, 3.0)
	assert_eq(s.wallet.get_credits(), credits, "nothing changes after victory")


func test_defeat_stops_waves_and_projectiles() -> void:
	var w: Array[WaveData] = [H.wave("w1", [["heavy_tank", 1, 0.0, 1.0], ["infantry", 10, 30.0, 1.0]])]
	var s := _session(w, 1000, 5)
	var t := s.construction.build(StructureCatalog.load_structure(&"turret_hmg"), Vector2i(6, 4))
	assert_true(t.is_ok())
	s.start_wave()
	_tick(s, 12.0) # the tank reaches the HQ: 5 damage
	assert_eq(s.phase, P.DEFEAT)
	assert_eq(_ended, [false])
	_tick(s, 40.0)
	assert_eq(s.enemies.count(), 0, "the infantry group never spawns after defeat")
	assert_eq(s.combat.get_projectiles().size(), 0)
	assert_eq(s.base_hp, 0)


func test_score_formula() -> void:
	var s := _session(_two_waves(), 0)
	for i in 2:
		s.start_wave()
		_tick(s, 0.6)
		_kill_all(s)
		_tick(s, DT * 2)
	# 2 waves, 4 kills, HQ 20, credits 120, victory
	assert_eq(s.score(), 500 * 2 + 10 * 4 + 150 * 20 + 120 + 1000)
	assert_eq(MissionScore.stars(s), 3)
