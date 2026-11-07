extends "res://tests/framework/test_case.gd"
## Full mission flow with the real mission data: balance regression with the
## scripted strategies, restart after victory/defeat, no duplicated rewards
## (Hito 4 cases 6, 11, 12, 13, 14, 16, 17, 18).

const StrategyBot := preload("res://tests/sim/strategy_bot.gd")
const Sim := preload("res://tests/sim/sim_mission.gd")
const MISSION := "res://data/levels/mission_01.json"

var _killed_ids: Dictionary = {}
var _double_rewards: int = 0


func before_each() -> void:
	_killed_ids = {}
	_double_rewards = 0


func _play(strategy: String) -> GameSession:
	var level := LevelLoader.load_file(MISSION).level
	var s := GameSession.new(level)
	s.enemies.enemy_killed.connect(_on_killed)
	StrategyBot.new(Sim.STRATEGIES[strategy]).play(s)
	return s


func _on_killed(e: Enemy) -> void:
	if _killed_ids.has(e.id):
		_double_rewards += 1
	_killed_ids[e.id] = true


func test_balanced_defence_wins_the_mission() -> void:
	var s := _play("C_balanced")
	assert_eq(s.phase, GameSession.Phase.VICTORY, "C_balanced wins (HQ %d)" % s.base_hp)
	assert_eq(s.stats.waves_completed, 5)
	assert_true(s.base_hp > 0 and s.base_hp < s.level.base_max_hp, "a win that still costs HQ (%d)" % s.base_hp)
	assert_eq(s.enemies.count(), 0, "no enemies left")
	assert_eq(_double_rewards, 0, "no enemy rewarded twice")
	assert_eq(s.stats.kills, _killed_ids.size())
	var expected := s.level.starting_credits + s.stats.credits_from_kills + s.stats.credits_from_waves \
			- s.stats.credits_spent + s.stats.credits_refunded
	assert_eq(s.wallet.get_credits(), expected, "credits ledger balances")


func test_insufficient_defence_loses() -> void:
	var s := _play("D_insufficient")
	assert_eq(s.phase, GameSession.Phase.DEFEAT)
	assert_true(s.wave_number() <= 3, "falls early (wave %d)" % s.wave_number())
	assert_eq(s.base_hp, 0)


func test_firepower_also_wins() -> void:
	# Several tactical approaches must be viable (not only one).
	var s := _play("B_firepower")
	assert_eq(s.phase, GameSession.Phase.VICTORY, "B_firepower wins (HQ %d)" % s.base_hp)


func test_restart_after_victory_is_clean() -> void:
	var s := _play("C_balanced")
	var level := s.level
	var waves_before := level.waves.map(func(w: WaveData) -> int: return w.enemy_count())
	var fresh := GameSession.new(level)
	_assert_fresh(fresh, level)
	assert_eq(level.waves.map(func(w: WaveData) -> int: return w.enemy_count()), waves_before, "wave data untouched")


func test_restart_after_defeat_is_clean() -> void:
	var s := _play("D_insufficient")
	var fresh := GameSession.new(s.level)
	_assert_fresh(fresh, s.level)
	# The old session can't affect the new one.
	s.tick(1.0)
	assert_eq(fresh.base_hp, s.level.base_max_hp)


func _assert_fresh(s: GameSession, level: LevelData) -> void:
	assert_eq(s.phase, GameSession.Phase.PREPARATION)
	assert_eq(s.wallet.get_credits(), level.starting_credits)
	assert_eq(s.base_hp, level.base_max_hp)
	assert_eq(s.wave_number(), 0)
	assert_eq(s.enemies.count(), 0)
	assert_eq(s.combat.get_projectiles().size(), 0)
	assert_eq(s.combat.get_turrets().size(), 0)
	assert_eq(s.grid.placement_count(), 0)
	assert_eq(s.stats.kills, 0)
	assert_eq(s.waves.remaining_to_spawn(), 0)
	for spawn in level.spawn_cells:
		assert_true(s.nav.can_reach_goal(MovementClass.TRACKED, spawn), "navigation reset")
