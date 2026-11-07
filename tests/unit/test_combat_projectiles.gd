extends "res://tests/unit/combat_test_base.gd"
## Projectiles, impacts, explosions, kills/rewards, integration, restart, perf.


# --- Projectiles, impacts, explosions ------------------------------------------------

func test_each_projectile_damages_exactly_once() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	_watch(s)
	var t := _place(s, _turret_structure(_weapon(10.0, 100.0, 20.0)), Vector2i(3, 1)) # one shot only
	var tank := s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 2))
	_run(s, 3.0)
	assert_eq(t.shots_fired, 1)
	assert_eq(tank.hits_taken, 1)
	assert_eq(tank.hp, 600.0 - 4.0, "10 GENERIC vs HEAVY = 4")
	assert_eq(_impacts, [true])
	assert_eq(s.combat.get_projectiles().size(), 0, "projectile removed after impact")


func test_bullet_fizzles_when_target_dies_before_impact() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 0)
	_watch(s)
	_place(s, _turret_structure(_weapon(10.0, 100.0, 20.0, 1.0)), Vector2i(6, 4)) # slow bullet
	var victim := s.enemies.spawn(_enemy("infantry"), Vector2i(0, 2))
	var bystander := s.enemies.spawn(_enemy("infantry"), Vector2i(0, 2))
	_run(s, 0.2)
	assert_eq(s.combat.get_projectiles().size(), 1, "bullet in flight")
	s.enemies.damage(victim, 1000.0) # dies before the bullet arrives
	var credits := s.wallet.get_credits()
	_run(s, 8.0)
	assert_eq(_impacts, [false], "impact reported as a miss")
	assert_eq(bystander.hits_taken, 0, "a lost bullet never hits someone else")
	assert_eq(s.wallet.get_credits(), credits, "no extra reward")
	assert_eq(s.combat.get_projectiles().size(), 0)


func test_missile_explodes_at_last_position_when_target_lost() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	_watch(s)
	_place(s, _turret_structure(_weapon(100.0, 100.0, 20.0, 1.5, 1.0, Targeting.GROUND, Damage.Type.EXPLOSIVE)), Vector2i(4, 4))
	var victim := s.enemies.spawn(_enemy("light_vehicle"), Vector2i(2, 2))
	victim.state = Enemy.State.BLOCKED # stays put
	var neighbour := s.enemies.spawn(_enemy("light_vehicle"), Vector2i(2, 2))
	neighbour.state = Enemy.State.BLOCKED
	_run(s, 0.1)
	s.enemies.damage(victim, 10000.0)
	_run(s, 5.0)
	assert_eq(_explosions, 1, "missile still detonates")
	assert_eq(neighbour.hp, neighbour.max_hp - 50.0, "splash share: 100 x 0.5 falloff x 1.0 (EXPLOSIVE vs LIGHT)")


func test_splash_hits_each_unit_once_with_falloff() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 0)
	_watch(s)
	_place(s, _turret_structure(_weapon(100.0, 100.0, 20.0, 30.0, 0.8, Targeting.GROUND, Damage.Type.EXPLOSIVE)), Vector2i(3, 0))
	var group: Array[Enemy] = []
	for i in 3:
		var e := s.enemies.spawn(_enemy("heavy_tank"), Vector2i(2, 2))
		e.state = Enemy.State.BLOCKED
		group.append(e)
	var far := s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 0)) # behind the group: never FIRST
	far.state = Enemy.State.BLOCKED
	_run(s, 1.0)
	assert_eq(_explosions, 1)
	var full := 0
	var half := 0
	for e in group:
		assert_eq(e.hits_taken, 1, "unit %d damaged exactly once" % e.id)
		if e.hp == 500.0:
			full += 1
		elif e.hp == 550.0:
			half += 1
	assert_eq([full, half], [1, 2], "direct target full damage, others 50 %")
	assert_eq(far.hits_taken, 0, "outside the blast")


func test_splash_kills_reward_each_victim_once() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 0)
	_watch(s)
	var w := _weapon(500.0, 100.0, 20.0, 30.0, 1.0, Targeting.GROUND, Damage.Type.GENERIC)
	var t := _place(s, _turret_structure(w), Vector2i(3, 0))
	for i in 4:
		s.enemies.spawn(_enemy("infantry"), Vector2i(2, 2)).state = Enemy.State.BLOCKED
	_run(s, 1.0)
	assert_eq(_kills, 4)
	assert_eq(t.kills, 4)
	assert_eq(s.wallet.get_credits(), 4 * 5)
	assert_eq(s.enemies.count(), 0)


# --- Real weapons, kills, rewards ------------------------------------------------------

func test_hmg_destroys_infantry_and_pays_reward() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100)
	_watch(s)
	var t := _place(s, StructureCatalog.load_structure(&"turret_hmg"), Vector2i(3, 1))
	var credits := s.wallet.get_credits()
	var hp0 := s.base_hp
	var e := s.enemies.spawn(_enemy("infantry"), Vector2i(0, 2))
	_run(s, 6.0)
	assert_eq(e.state, Enemy.State.DEAD, "killed before reaching the HQ")
	assert_eq(s.base_hp, hp0)
	assert_eq(s.wallet.get_credits(), credits + e.data.reward)
	assert_eq(t.kills, 1)
	assert_eq(_kills, 1)


func test_specialisation_hmg_vs_missiles_on_tanks() -> void:
	var a := H.make_session(H.OPEN_LAYOUT)
	var hmg := _place(a, StructureCatalog.load_structure(&"turret_hmg"), Vector2i(3, 1))
	var tank_a := a.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 2))
	_run(a, 3.0)
	var b := H.make_session(H.OPEN_LAYOUT)
	var mis := _place(b, StructureCatalog.load_structure(&"turret_missile"), Vector2i(3, 1))
	var tank_b := b.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 2))
	_run(b, 3.0)
	assert_true(hmg.shots_fired > mis.shots_fired * 5, "HMG fires far more often")
	assert_true(tank_b.hp < tank_a.hp, "but missiles hurt tanks much more (%.0f vs %.0f HP left)" % [tank_b.hp, tank_a.hp])
	assert_true(600.0 - tank_a.hp < 60.0, "bullets barely scratch heavy armour")


# --- Integration with construction/navigation --------------------------------------------

func test_turrets_are_part_of_the_maze() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	_place(s, StructureCatalog.load_structure(&"turret_hmg"), Vector2i(4, 2))
	for bit in MovementClass.ALL:
		assert_false(s.nav.path_to_goal(bit, Vector2i(0, 2)).has(Vector2i(4, 2)), "class %d routes around" % bit)
	var choke := H.make_session(H.CHOKE_LAYOUT)
	var check := choke.construction.build(StructureCatalog.load_structure(&"turret_hmg"), Vector2i(3, 2))
	assert_eq(check.reason, ConstructionService.Reason.BLOCKS_ROUTE, "a turret cannot seal the base either")


func test_turrets_follow_grid_signals() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var p := s.grid.add_placement(StructureCatalog.load_structure(&"turret_hmg"), Vector2i(1, 1))
	assert_eq(s.combat.get_turrets().size(), 1)
	s.grid.add_placement(H.wall(), Vector2i(2, 1))
	assert_eq(s.combat.get_turrets().size(), 1, "walls are not turrets")
	s.grid.remove_placement(p)
	assert_eq(s.combat.get_turrets().size(), 0)


func test_turret_removed_while_projectile_in_flight() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	_watch(s)
	_place(s, _turret_structure(_weapon(10.0, 100.0, 20.0, 1.0)), Vector2i(6, 4))
	var e := s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 2))
	e.state = Enemy.State.BLOCKED
	_run(s, 0.2)
	assert_true(s.construction.remove_at(Vector2i(6, 4)).is_ok())
	_run(s, 8.0)
	assert_eq(_impacts, [true], "projectile still resolves")
	assert_eq(s.combat.get_turrets().size(), 0)


func test_restart_has_no_combat_residue() -> void:
	var s1 := H.make_session(H.OPEN_LAYOUT)
	_place(s1, StructureCatalog.load_structure(&"turret_hmg"), Vector2i(3, 1))
	s1.enemies.spawn(_enemy("infantry"), Vector2i(0, 2))
	_run(s1, 0.5)
	var s2 := GameSession.new(s1.level)
	assert_eq(s2.combat.get_turrets().size(), 0)
	assert_eq(s2.combat.get_projectiles().size(), 0)
	assert_eq(s2.wallet.get_credits(), s2.level.starting_credits)


func test_defeat_clears_projectiles_and_stops_turrets() -> void:
	var d := H.level_dict(H.OPEN_LAYOUT)
	d["base_max_hp"] = 1
	var s := GameSession.new(LevelLoader.parse_dict(d).level)
	var t := _place(s, _turret_structure(_weapon(0.001, 0.1, 20.0, 0.5)), Vector2i(6, 4))
	s.enemies.spawn(_enemy("light_vehicle"), Vector2i(0, 2))
	s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 0))
	_run(s, 6.0)
	assert_eq(s.phase, GameSession.Phase.DEFEAT)
	var shots := t.shots_fired
	_run(s, 2.0)
	assert_eq(t.shots_fired, shots, "no firing after defeat")
	assert_eq(s.combat.get_projectiles().size(), 0)


func test_turret_defence_reduces_hq_damage() -> void:
	var damage := []
	for with_turrets in [false, true]:
		var level := LevelLoader.load_file("res://data/levels/mission_01.json").level
		level.starting_credits = 10000
		# One column: 6 infantry + 3 light vehicles + 1 tank = 17 potential HQ damage.
		var column: Array[WaveData] = [H.wave("column", [["infantry", 6, 0.0, 0.8], ["light_vehicle", 3, 2.0, 2.4],
				["heavy_tank", 1, 4.0, 1.0]])]
		level.waves = column
		var s := GameSession.new(level)
		if with_turrets:
			for c in [Vector2i(19, 7), Vector2i(19, 8), Vector2i(18, 2), Vector2i(10, 7)]:
				_place(s, StructureCatalog.load_structure(&"turret_hmg"), c)
			_place(s, StructureCatalog.load_structure(&"turret_missile"), Vector2i(19, 9))
		assert_true(s.start_wave())
		for i in int(60.0 / DT):
			s.tick(DT)
		damage.append(level.base_max_hp - s.base_hp)
	assert_eq(damage[0], 17, "undefended: the whole column reaches the HQ")
	assert_true(damage[1] < damage[0], "defended HQ takes less damage (%d vs %d)" % [damage[1], damage[0]])


# --- Performance sanity (generous bound: ~20x the measured cost) -------------------------

func test_combat_cost_100_enemies_20_turrets() -> void:
	var level := LevelLoader.load_file("res://data/levels/mission_01.json").level
	level.starting_credits = 100000
	level.base_max_hp = 100000
	var s := GameSession.new(level)
	var placed := 0
	for y in range(0, 16):
		for x in [6, 15]:
			var kind: StringName = [&"turret_hmg", &"turret_missile"][placed % 2]
			if placed < 20 and s.construction.build(StructureCatalog.load_structure(kind), Vector2i(x, y)).is_ok():
				placed += 1
	for i in 100:
		s.enemies.spawn(_enemy(["infantry", "light_vehicle", "heavy_tank"][i % 3]), level.spawn_cells[i % 2])
	var total := 0
	for i in 300:
		var t0 := Time.get_ticks_usec()
		s.combat.update(DT)
		total += Time.get_ticks_usec() - t0
		s.enemies.update(DT)
	var avg_ms := total / 300.0 / 1000.0
	print("    combat.update avg %.3f ms (%d turrets, %d enemies alive)" % [avg_ms, placed, s.enemies.count()])
	assert_eq(placed, 20)
	assert_true(avg_ms < 3.0, "combat.update avg %.3f ms" % avg_ms)
