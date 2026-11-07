extends SceneTree
## Milestone 2 end-to-end check on the real battle scene (needs a renderer):
## assault, live re-routing, unit-occupied cells, pinch zoom (real touch
## events through Input, including mouse emulation), precise tap while zoomed,
## HQ damage, cleanup of views, defeat. Screenshots to $IR_SHOTS_DIR or user://shots/.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##       --rendering-driver opengl3 --script res://tests/visual/drive_enemies.gd

const WATCHDOG_SECONDS := 600.0

var out_dir: String
var battle: Node
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
	change_scene_to_file("res://scenes/gameplay/battle.tscn")
	await _frames(10)
	battle = current_scene
	var s: GameSession = battle.session
	var hud: BattleHud = battle.hud
	var layer: EnemyLayer = battle.enemy_layer

	# --- Assault ---------------------------------------------------------------
	_click(_find_button(hud, "START WAVE").get_global_rect().get_center())
	await _frames(2)
	_check(s.phase == GameSession.Phase.WAVE_ACTIVE, "START WAVE -> WAVE_ACTIVE")
	Engine.time_scale = 3.0
	await _seconds(4.0)
	Engine.time_scale = 1.0
	var classes := {}
	for e in s.enemies.get_enemies():
		classes[e.movement] = true
	_check(s.enemies.count() > 0 and layer.view_count() == s.enemies.count(),
			"one view per live enemy (%d / %d)" % [layer.view_count(), s.enemies.count()])
	await _shot("10_assault_moving")

	# --- Build during combat on the live route; units must re-route ------------
	# Test budget: combat builds carry the +25 % surcharge; this check is about
	# routing, not economy (economy is covered by drive_combat and unit tests).
	s.wallet.earn(400)
	_click(_find_button(hud, "WALL").get_global_rect().get_center())
	await _frames(2)
	var built := 0
	for y in range(3, 14):
		var c := Vector2i(16, y)
		if s.construction.evaluate(StructureCatalog.load_structure(&"concrete_wall"), c).is_ok():
			_tap_cell(c)
			await _frames(1)
			built += 1 if s.grid.is_occupied(c) else 0
	_check(built >= 5, "walls built during combat (%d)" % built)
	var occupied_ok := true
	for e in s.enemies.get_enemies():
		occupied_ok = occupied_ok and s.nav.is_walkable(e.movement, e.cell) and s.nav.is_walkable(e.movement, e.next_cell)
	_check(occupied_ok, "no live enemy stands on a blocking cell")
	# Tap the cell an enemy is entering: must be refused (not built).
	var target: Enemy = null
	for e in s.enemies.get_enemies():
		if s.grid.is_buildable_terrain(e.next_cell) and not s.grid.is_occupied(e.next_cell):
			target = e
			break
	_check(target != null, "found an enemy entering a buildable cell")
	if target != null:
		var cell := target.next_cell
		_tap_cell(cell)
		await _frames(1)
		_check(not s.grid.is_occupied(cell), "refused to build on an enemy's cell")
		print("  feedback: ", hud._feedback_label.text)
	await _shot("11_rerouted_during_combat")

	# --- Pinch zoom with real touch events (finger 0 also emulates the mouse) --
	var placements_before := s.grid.placement_count()
	var a := Vector2(600, 500)
	var b := Vector2(800, 500)
	_touch(0, a, true)
	await _frames(1)
	_touch(1, b, true)
	await _frames(1)
	for i in 10:
		_drag(0, a - Vector2(12 * (i + 1), 0))
		_drag(1, b + Vector2(12 * (i + 1), 0))
		await _frames(1)
	_touch(0, a - Vector2(120, 0), false)
	_touch(1, b + Vector2(120, 0), false)
	await _frames(2)
	var cam: BattleCamera = battle.camera
	_check(cam.get_zoom_level() > 1.5, "pinch zoomed in (zoom %.2f)" % cam.get_zoom_level())
	_check(s.grid.placement_count() == placements_before, "pinch with a tool selected built nothing")

	# --- Precise tap while zoomed ------------------------------------------------
	var precise := Vector2i(9, 9)
	var screen := _cell_pos(precise)
	var precise_ok := s.construction.evaluate(StructureCatalog.load_structure(&"concrete_wall"), precise).is_ok()
	_check(precise_ok, "precision target cell %s is buildable" % precise)
	if precise_ok:
		_click(screen)
		await _frames(1)
		_check(s.grid.is_occupied(precise) and not s.grid.is_occupied(precise + Vector2i(1, 0)),
				"zoomed tap built exactly cell %s" % precise)
	var cell_px: float = 64.0 * battle.grid_view.scale.x * cam.get_zoom_level()
	print("  cell size on screen at zoom %.2f: %.0f px" % [cam.get_zoom_level(), cell_px])
	await _shot("12_zoomed_in")
	cam.zoom_at(Vector2(960, 540), 0.01) # back to overview
	await _frames(2)

	# --- Let the assault finish -------------------------------------------------
	var hp0 := s.base_hp
	Engine.time_scale = 4.0
	var waited := 0.0
	while s.phase == GameSession.Phase.WAVE_ACTIVE and waited < 90.0:
		await _seconds(1.0)
		waited += 1.0
	Engine.time_scale = 1.0
	await _frames(30) # exit tweens
	_check(s.enemies.count() == 0, "assault finished (%.0f s scaled)" % waited)
	_check(s.base_hp < hp0 and not s.is_over(), "HQ damaged but alive (%d -> %d)" % [hp0, s.base_hp])
	_check(s.is_build_phase(), "back to a build phase after the wave (%s)" % GameSession.Phase.keys()[s.phase])
	_check(layer.view_count() == 0 and layer.get_child_count() == 0, "no leftover enemy views")
	await _shot("13_after_assault")

	# --- Defeat -------------------------------------------------------------------
	_check(s.start_wave(), "wave 2 started")
	for i in 8:
		s.enemies.spawn(EnemyCatalog.get_data(&"heavy_tank"), s.level.spawn_cells[i % 2])
	Engine.time_scale = 6.0
	waited = 0.0
	while not s.is_over() and waited < 120.0:
		await _seconds(1.0)
		waited += 1.0
	Engine.time_scale = 1.0
	await _frames(5)
	_check(s.phase == GameSession.Phase.DEFEAT and hud.results_visible(), "defeat screen shown")
	await _shot("14_defeat")

	# Leave the battle before quitting (audio playbacks at shutdown, see CLAUDE.md).
	change_scene_to_file("res://scenes/menus/main_menu.tscn")
	await _frames(10)
	print("DRIVER RESULT: ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)


func _check(cond: bool, what: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + what)
	ok = ok and cond


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(t: float) -> void:
	await create_timer(t, true, false, false).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name + ".png")


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text.begins_with(text):
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _cell_pos(cell: Vector2i) -> Vector2:
	var gv: GridView = battle.grid_view
	return gv.get_global_transform_with_canvas() * battle.session.grid.cell_to_local(cell)


func _tap_cell(cell: Vector2i) -> void:
	_click(_cell_pos(cell))


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


## Real touch events through Input, so mouse emulation of finger 0 happens too.
func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)


func _drag(index: int, pos: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = pos
	Input.parse_input_event(d)
