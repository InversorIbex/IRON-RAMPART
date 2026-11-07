extends "res://tests/framework/test_case.gd"
## Confirmed design rules for building during combat (D-012 / D-015):
## +25 % configurable surcharge on NEW construction during combat, shown before
## charging; rejections never consume credits; no building on enemies; never
## trap enemies; never seal the base.

const H := preload("res://tests/unit/test_helpers.gd")
const R := ConstructionService.Reason


func _combat_session(credits: int = 1000, rules: Dictionary = {}) -> GameSession:
	var s := H.make_session(H.OPEN_LAYOUT, credits, rules)
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	return s


func test_no_surcharge_between_waves() -> void:
	var s := H.make_session(H.OPEN_LAYOUT, 100)
	assert_eq(s.construction.price_of(H.wall(25)), 25)
	var check := s.construction.build(H.wall(25), Vector2i(4, 0))
	assert_eq(check.cost, 25)
	assert_eq(check.surcharge, 0)
	assert_eq(s.wallet.get_credits(), 75)


func test_combat_surcharge_is_charged_and_reported() -> void:
	var s := _combat_session(100)
	assert_eq(s.construction.price_of(H.wall(25)), 32, "ceil(25 x 1.25)")
	var preview := s.construction.evaluate(H.wall(25), Vector2i(4, 0))
	assert_eq(preview.cost, 32, "preview shows the surcharged price")
	assert_eq(preview.surcharge, 7)
	var check := s.construction.build(H.wall(25), Vector2i(4, 0))
	assert_true(check.is_ok())
	assert_eq(s.wallet.get_credits(), 68, "charged exactly the previewed price")
	assert_eq(check.placement.paid, 32)


func test_surcharge_rounding_is_exact() -> void:
	var s := _combat_session()
	for pair in [[100, 125], [180, 225], [150, 188], [10, 13], [35, 44], [0, 0]]:
		assert_eq(s.construction.price_of(H.structure("x", pair[0], 7)), pair[1], "cost %d" % pair[0])


func test_surcharge_is_configurable_per_level() -> void:
	var half := _combat_session(1000, {"combat_build_surcharge": 0.5})
	assert_eq(half.construction.price_of(H.wall(25)), 38, "ceil(25 x 1.5)")
	var free := _combat_session(1000, {"combat_build_surcharge": 0})
	assert_eq(free.construction.price_of(H.wall(25)), 25)


func test_invalid_surcharge_rule_is_rejected_by_loader() -> void:
	LevelLoader.report_errors = false
	for bad in [-0.1, 6, "lots"]:
		var d := H.level_dict(H.OPEN_LAYOUT, 100, {"combat_build_surcharge": bad})
		assert_false(LevelLoader.parse_dict(d).is_ok(), "surcharge %s" % [bad])
	LevelLoader.report_errors = true


func test_surcharge_returns_to_zero_after_combat() -> void:
	var s := _combat_session()
	s.set_phase(GameSession.Phase.WAVE_COMPLETED) # back to a build phase
	assert_eq(s.construction.price_of(H.wall(25)), 25)


func test_rejected_for_surcharge_costs_nothing() -> void:
	# 30 credits: enough for the base price (25) but not the combat price (32).
	var s := _combat_session(30)
	var version := s.nav.version
	var check := s.construction.build(H.wall(25), Vector2i(4, 0))
	assert_eq(check.reason, R.INSUFFICIENT_CREDITS)
	assert_eq(s.wallet.get_credits(), 30)
	assert_eq(s.grid.placement_count(), 0)
	assert_eq(s.nav.version, version, "navigation untouched")


func test_rejected_route_block_in_combat_costs_nothing() -> void:
	var s := H.make_session(H.CHOKE_LAYOUT, 100)
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	var check := s.construction.build(H.wall(25), Vector2i(3, 2))
	assert_eq(check.reason, R.BLOCKS_ROUTE, "the base can never be sealed")
	assert_eq(s.wallet.get_credits(), 100)


func test_combat_build_on_enemy_rejected_without_charge() -> void:
	var s := _combat_session(100)
	var e := s.enemies.spawn(EnemyCatalog.get_data(&"infantry"), Vector2i(0, 2))
	for i in 60:
		s.tick(1.0 / 60.0)
	var check := s.construction.build(H.wall(25), e.next_cell)
	assert_eq(check.reason, R.OCCUPIED_BY_UNIT)
	assert_eq(s.wallet.get_credits(), 100)


func test_combat_build_that_traps_enemy_rejected_without_charge() -> void:
	var pocket := ["S.......", "####.###", ".......B"]
	var s := H.make_session(pocket, 100)
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	s.enemies.spawn(EnemyCatalog.get_data(&"infantry"), Vector2i(1, 2))
	var check := s.construction.build(H.wall(25), Vector2i(3, 2))
	assert_eq(check.reason, R.BLOCKS_ROUTE)
	assert_eq(check.broken_routes[0]["kind"], "unit")
	assert_eq(s.wallet.get_credits(), 100)


func test_surcharge_is_never_refunded() -> void:
	var s := _combat_session(100, {"allow_remove_during_combat": true})
	s.construction.build(H.wall(25), Vector2i(4, 0)) # pays 32
	var check := s.construction.remove_at(Vector2i(4, 0))
	assert_eq(check.refund, 12, "refund from the base cost: floor(25 x 0.5)")
	assert_eq(s.wallet.get_credits(), 100 - 32 + 12)
