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
	var session: GameSession = battle.get("session")
	assert_not_null(session, "battle loaded mission_01 and created a session")
	assert_not_null(battle.get("hud"))
	assert_not_null(battle.get("grid_view"))
	if session != null:
		assert_true(session.construction.all_routes_open())
	battle.free()
