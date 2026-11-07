extends "res://tests/unit/combat_test_base.gd"
## Turret data, damage/armour model, targeting, range, layers, cadence, aiming.


# --- Data & damage model ---------------------------------------------------------

func test_turret_catalog_data_matches_roles() -> void:
	var hmg := StructureCatalog.load_structure(&"turret_hmg")
	var mis := StructureCatalog.load_structure(&"turret_missile")
	var aa := StructureCatalog.load_structure(&"turret_aa")
	for d in [hmg, mis, aa]:
		assert_not_null(d)
		if d == null:
			return
		assert_eq(d.category, StructureData.Category.TURRET)
		assert_eq(d.validate().size(), 0)
	assert_eq(hmg.turret.damage_type, Damage.Type.BULLET)
	assert_true(hmg.turret.shots_per_second() > 5.0, "HMG: high cadence")
	assert_eq(mis.turret.damage_type, Damage.Type.EXPLOSIVE)
	assert_true(mis.turret.splash_radius_cells > 0.0 and mis.turret.fire_interval > 1.0, "missiles: slow, splash")
	assert_eq(aa.turret.target_layers, Targeting.AIR, "AA engages air only")
	assert_eq([hmg.cost, aa.cost, mis.cost], [100, 150, 180], "costs from the design brief")


func test_damage_table_specialisation() -> void:
	assert_eq(Damage.compute(100, Damage.Type.BULLET, Damage.ArmorClass.NONE), 100.0)
	assert_eq(Damage.compute(100, Damage.Type.BULLET, Damage.ArmorClass.HEAVY), 10.0)
	assert_eq(Damage.compute(100, Damage.Type.EXPLOSIVE, Damage.ArmorClass.HEAVY), 100.0)
	assert_eq(Damage.compute(100, Damage.Type.EXPLOSIVE, Damage.ArmorClass.NONE), 60.0)
	assert_eq(Damage.compute(100, Damage.Type.GENERIC, Damage.ArmorClass.HEAVY), 40.0)
	assert_eq(Damage.compute(-5, Damage.Type.BULLET, Damage.ArmorClass.NONE), 0.0)


func test_roster_damage_uses_type_and_armor() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var tank := s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 2))
	assert_eq(s.enemies.damage(tank, 100.0, Damage.Type.BULLET), 10.0)
	assert_eq(s.enemies.damage(tank, 100.0, Damage.Type.EXPLOSIVE), 100.0)
	assert_eq(tank.hp, 490.0)


# --- Targeting ---------------------------------------------------------------------

func test_first_priority_uses_real_route_progress() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var behind := s.enemies.spawn(_enemy("infantry"), Vector2i(0, 2))
	var ahead := s.enemies.spawn(_enemy("infantry"), Vector2i(5, 2))
	var origin := s.grid.cell_to_local(Vector2i(1, 1))
	var big := 20 * 64.0
	var first := Targeting.select(origin, big, Targeting.GROUND, Targeting.Priority.FIRST, s.enemies.get_enemies(), s.nav)
	var closest := Targeting.select(origin, big, Targeting.GROUND, Targeting.Priority.CLOSEST, s.enemies.get_enemies(), s.nav)
	assert_eq(first, ahead, "FIRST = closest to the base along the route")
	assert_eq(closest, behind, "CLOSEST = nearest to the turret")


func test_first_priority_follows_the_maze_not_straight_distance() -> void:
	# A wall makes the geometrically closer unit the one with the longer route.
	var layout := [
		"..........",
		".#########",
		"S........B",
	]
	var s := H.make_session(layout)
	var top := s.enemies.spawn(_enemy("infantry"), Vector2i(8, 0)) # near B in a straight line, long way round
	var bottom := s.enemies.spawn(_enemy("infantry"), Vector2i(4, 2)) # farther, but on the open lane
	assert_true(Targeting.remaining_cells(bottom, s.nav) < Targeting.remaining_cells(top, s.nav))
	var pick := Targeting.select(Vector2.ZERO, 9999.0, Targeting.GROUND, Targeting.Priority.FIRST, s.enemies.get_enemies(), s.nav)
	assert_eq(pick, bottom)


func test_strongest_priority_and_deterministic_ties() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var a := s.enemies.spawn(_enemy("infantry"), Vector2i(2, 2))
	var b := s.enemies.spawn(_enemy("infantry"), Vector2i(2, 2))
	var tank := s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 0))
	var all := s.enemies.get_enemies()
	assert_eq(Targeting.select(Vector2.ZERO, 9999.0, Targeting.GROUND, Targeting.Priority.STRONGEST, all, s.nav), tank)
	s.enemies.damage(tank, 10000.0)
	for i in 5:
		assert_eq(Targeting.select(Vector2.ZERO, 9999.0, Targeting.GROUND, Targeting.Priority.CLOSEST, all, s.nav), a,
				"tie broken by lowest id (a=%d, b=%d)" % [a.id, b.id])


func test_out_of_range_enemies_are_never_engaged() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	_watch(s)
	var t := _place(s, _turret_structure(_weapon(10.0, 0.2, 1.2)), Vector2i(7, 4)) # far corner
	var e := s.enemies.spawn(_enemy("infantry"), Vector2i(0, 0))
	s.enemies.get_enemies()[0].state = Enemy.State.BLOCKED # hold far away
	_run(s, 2.0)
	assert_eq(t.shots_fired, 0)
	assert_eq(e.hp, 60.0)


func test_aa_ignores_ground_units_unless_configured() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var aa := _place(s, StructureCatalog.load_structure(&"turret_aa"), Vector2i(3, 1))
	var both := _weapon(1.0, 0.3, 5.0, 50.0, 0.0, Targeting.GROUND | Targeting.AIR)
	var air_and_ground := _place(s, _turret_structure(both), Vector2i(3, 3))
	s.enemies.spawn(_enemy("infantry"), Vector2i(0, 2))
	_run(s, 2.0)
	assert_eq(aa.shots_fired, 0, "AIR-only weapon never fires at ground units")
	assert_true(air_and_ground.shots_fired > 0, "a GROUND|AIR weapon does")


func test_air_target_layer_is_selectable() -> void:
	# No aircraft exist yet; a ground unit re-tagged as AIR proves the AA path works.
	var s := H.make_session(H.OPEN_LAYOUT)
	var plane := _enemy("light_vehicle").duplicate() as EnemyData
	plane.target_layer = Targeting.AIR
	var aa := _place(s, StructureCatalog.load_structure(&"turret_aa"), Vector2i(3, 1))
	var e := s.enemies.spawn(plane, Vector2i(0, 2))
	_run(s, 2.0)
	assert_true(aa.shots_fired > 0, "AA engages AIR targets")
	assert_true(e.hp < plane.max_hp)


# --- Cadence, aiming ---------------------------------------------------------------

func test_cadence_matches_fire_interval() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var t := _place(s, _turret_structure(_weapon(0.01, 0.5, 20.0)), Vector2i(3, 1))
	s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 2))
	_run(s, 5.0)
	assert_true(t.shots_fired >= 9 and t.shots_fired <= 11, "~10 shots in 5 s at 0.5 s (got %d)" % t.shots_fired)


func test_turret_turns_before_firing() -> void:
	var s := H.make_session(H.OPEN_LAYOUT)
	var w := _weapon(1.0, 0.1, 20.0)
	w.turn_speed_deg = 90.0
	w.aim_tolerance_deg = 5.0
	var t := _place(s, _turret_structure(w), Vector2i(3, 1))
	s.enemies.spawn(_enemy("heavy_tank"), Vector2i(0, 2)) # starts pointing north, target south-west
	_run(s, 0.5)
	assert_eq(t.shots_fired, 0, "still traversing (90 deg/s)")
	_run(s, 2.0)
	assert_true(t.shots_fired > 0, "fires once aligned")
