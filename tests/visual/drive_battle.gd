extends SceneTree
## End-to-end gameplay check: drives the real menu + battle through the real
## input pipeline (Viewport.push_input), asserts state and saves screenshots.
## Needs a renderer (not --headless). On Linux without a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##       --rendering-driver opengl3 --script res://tests/visual/drive_battle.gd
## Screenshots go to $IR_SHOTS_DIR or user://shots/. Exit code 0 = all checks OK.

const WATCHDOG_SECONDS := 600.0

var out_dir: String
var battle: Node
var log_lines: Array[String] = []
var ok := true


func _initialize() -> void:
	out_dir = OS.get_environment("IR_SHOTS_DIR")
	if out_dir.is_empty():
		out_dir = ProjectSettings.globalize_path("user://shots")
	out_dir = out_dir.trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Watchdog: if the driver coroutine dies on a script error it never reaches
	# quit(); fail loudly instead of hanging (real-time, ignores time_scale).
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(func() -> void:
		print("DRIVER RESULT: WATCHDOG TIMEOUT (script error or hang)")
		quit(2))
	_main.call_deferred()


func _main() -> void:
	change_scene_to_file("res://scenes/menus/main_menu.tscn")
	await _frames(10)
	await _shot("01_main_menu")
	# Press PLAY with a real click.
	var play := _find_button(current_scene, "PLAY")
	_click(play.get_global_rect().get_center())
	await _frames(15)
	battle = current_scene
	_check(battle != null and battle.get("session") != null, "PLAY opened the battle with a session")
	await _shot("02_battle_empty")

	var session: GameSession = battle.session
	var hud: BattleHud = battle.hud
	var credits0 := session.wallet.get_credits()

	# Select sandbags via click on its HUD button.
	_click(_find_button(hud, "SANDBAGS").get_global_rect().get_center())
	await _frames(2)
	# Ring around the west spawn (0,8) whose mouth is road (1,8),(2,8).
	var ring := [Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(0, 9), Vector2i(1, 9), Vector2i(2, 9)]
	for c in ring:
		_tap_cell(c)
		await _frames(2)
	_check(session.grid.placement_count() == 6, "6 sandbags built (got %d)" % session.grid.placement_count())
	_check(session.wallet.get_credits() == credits0 - 60,
			"credits %d -> %d (got %d)" % [credits0, credits0 - 60, session.wallet.get_credits()])

	# 7th sandbag closes the spawn for infantry + wheeled -> must be rejected.
	var before := session.wallet.get_credits()
	_tap_cell(Vector2i(3, 8))
	await _frames(2)
	_check(not session.grid.is_occupied(Vector2i(3, 8)), "sealing sandbag rejected")
	_check(session.wallet.get_credits() == before, "credits untouched after rejection")
	var fb: String = hud._feedback_label.text
	log_lines.append("feedback after rejected build: " + fb)
	_check(fb.contains("INFANTRY") and fb.contains("WHEELED") and not fb.contains("TRACKED"), "reason names INFANTRY, WHEELED only")
	_hover_cell(Vector2i(3, 8))
	await _frames(3)
	await _shot("03_rejected_seal_sandbags")

	# Concrete wall elsewhere forces a detour: route must change.
	_click(_find_button(hud, "WALL").get_global_rect().get_center())
	await _frames(2)
	var path_before := session.nav.path_to_goal(MovementClass.INFANTRY, Vector2i(0, 8))
	for c in [Vector2i(14, 4), Vector2i(14, 5), Vector2i(14, 6), Vector2i(14, 7), Vector2i(14, 8)]:
		_tap_cell(c)
		await _frames(2)
	var path_after := session.nav.path_to_goal(MovementClass.INFANTRY, Vector2i(0, 8))
	log_lines.append("west infantry route: %d -> %d cells" % [path_before.size(), path_after.size()])
	_check(path_after != path_before, "route changed after walls")

	# Anti-tank barrier: infantry route may cross it.
	_click(_find_button(hud, "AT BARRIER").get_global_rect().get_center())
	await _frames(2)
	_tap_cell(Vector2i(18, 8))
	await _frames(2)
	_check(session.grid.is_occupied(Vector2i(18, 8)), "AT barrier built")
	_hover_cell(Vector2i(16, 3))
	await _frames(3)
	await _shot("04_maze_with_routes")

	# Remove mode: two taps on a sandbag.
	_click(_find_button(hud, "REMOVE").get_global_rect().get_center())
	await _frames(2)
	var c_before := session.wallet.get_credits()
	_tap_cell(Vector2i(0, 7))
	await _frames(2)
	_check(session.grid.is_occupied(Vector2i(0, 7)), "first tap only arms removal")
	await _shot("05_remove_armed")
	_tap_cell(Vector2i(0, 7))
	await _frames(2)
	_check(not session.grid.is_occupied(Vector2i(0, 7)), "second tap removes")
	_check(session.wallet.get_credits() == c_before + 7, "refund floor(10*0.75)=7")

	# Pause overlay and restart -> clean session.
	_click(_find_button(hud, "II  PAUSE").get_global_rect().get_center())
	await _frames(3)
	_check(paused, "game paused")
	await _shot("06_paused")
	_click(_find_button(hud, "RESTART").get_global_rect().get_center())
	await _frames(15)
	var s2: GameSession = current_scene.session
	_check(not paused, "unpaused after restart")
	_check(s2 != session and s2.grid.placement_count() == 0 and s2.wallet.get_credits() == s2.level.starting_credits,
			"restart = clean session")

	for l in log_lines:
		print(l)
	# Leave the battle before quitting (audio playbacks at shutdown, see CLAUDE.md).
	change_scene_to_file("res://scenes/menus/main_menu.tscn")
	await _frames(10)
	await create_timer(2.0, true, false, true).timeout # let the last sound finish
	print("DRIVER RESULT: ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)


func _check(cond: bool, what: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + what)
	ok = ok and cond


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name + ".png")


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text.begins_with(text):
		return node
	for child in node.get_children():
		var b := _find_button(child, text)
		if b != null:
			return b
	return null


func _cell_pos(cell: Vector2i) -> Vector2:
	var gv: GridView = battle.grid_view
	return gv.get_global_transform_with_canvas() * battle.session.grid.cell_to_local(cell)


func _tap_cell(cell: Vector2i) -> void:
	_click(_cell_pos(cell))


func _hover_cell(cell: Vector2i) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _cell_pos(cell)
	m.global_position = m.position
	root.push_input(m, true)


func _click(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	root.push_input(m, true)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e, true)
