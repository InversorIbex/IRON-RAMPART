extends "res://tests/framework/test_case.gd"
## Smoke tests: the real scenes instantiate and build their runtime nodes.
## Script errors inside _ready are printed by Godot but don't throw, so CI
## must also scan the output for "SCRIPT ERROR" (see docs/TESTING.md).

var tree: SceneTree


func set_tree(p_tree: SceneTree) -> void:
	tree = p_tree


func test_main_menu_instantiates() -> void:
	var scene: PackedScene = load("res://scenes/menus/main_menu.tscn")
	assert_not_null(scene)
	if scene == null:
		return
	var menu := scene.instantiate()
	tree.root.add_child(menu)
	assert_true(menu.get_child_count() > 0, "menu built its UI in _ready")
	menu.free()


func test_battle_instantiates_with_session() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/battle.tscn")
	assert_not_null(scene)
	if scene == null:
		return
	var battle := scene.instantiate()
	tree.root.add_child(battle)
	await tree.process_frame # let containers/labels lay out
	await tree.process_frame
	var session: GameSession = battle.get("session")
	assert_not_null(session, "battle loaded mission_01 and created a session")
	assert_not_null(battle.get("hud"))
	assert_not_null(battle.get("grid_view"))
	if session != null:
		assert_true(session.construction.all_routes_open())
	# Regression: HUD built in code must cover the viewport and keep the build
	# panel on screen (set_anchors_preset alone left it 0x0 and the panel at x<0).
	var hud: BattleHud = battle.get("hud")
	if hud != null:
		var vp := tree.root.get_visible_rect()
		assert_eq(hud.get_global_rect().size, vp.size, "HUD covers the viewport")
		var panel: Control = hud._side_panel
		assert_true(vp.encloses(panel.get_global_rect()), "build panel on screen: %s" % panel.get_global_rect())
		# Regression: with the longest info text the panel overflowed 1080p.
		# Measure the worst case over every tool selection.
		var available := BattleHud.REFERENCE_HEIGHT - BattleHud.TOP_BAR_HEIGHT
		var worst := 0.0
		var widest := 0.0
		for b in hud._build_buttons + [hud._remove_button]:
			b.button_pressed = true
			await tree.process_frame
			await tree.process_frame
			worst = maxf(worst, panel.get_combined_minimum_size().y)
			widest = maxf(widest, panel.get_combined_minimum_size().x)
		hud.clear_selection()
		assert_true(worst <= available, "side panel fits 1080p: needs %.0f of %.0f px" % [worst, available])
		assert_true(widest <= BattleHud.PANEL_WIDTH, "side panel content fits its width: %.0f px" % widest)
	battle.free()
