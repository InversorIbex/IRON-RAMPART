extends SceneTree
## Milestone 4 end-to-end: OPERATION FIRST ASSAULT from the main menu to the
## results screen, twice (needs a renderer):
##  1. PLAY -> first defence built with real taps on HUD + map -> START WAVE x5
##     (HUD button) with pause/resume mid-wave -> VICTORY results -> RESTART,
##     checking the old session was freed and the new one is clean.
##  2. No defence -> START WAVE until DEFEAT -> results -> MAIN MENU.
## Between waves the C_balanced scripted player reinforces through the game
## API (same rules as the HUD) to keep the run short; wave/pause/restart/menu
## actions all go through the real HUD buttons.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##       --rendering-driver opengl3 --script res://tests/visual/drive_mission.gd

const WATCHDOG_SECONDS := 600.0

const StrategyBot := preload("res://tests/sim/strategy_bot.gd")
const Sim := preload("res://tests/sim/sim_mission.gd")
const SPEED := 4.0

var out_dir: String
var ok := true
var _banners: Array[String] = []


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
	await _frames(5)
	await _shot("30_menu")
	_click(_find_button(current_scene, "PLAY").get_global_rect().get_center())
	await _frames(10)
	var battle := current_scene
	var s: GameSession = battle.session
	var hud: BattleHud = battle.hud
	_check(s.phase == GameSession.Phase.PREPARATION and s.wave_number() == 0, "mission starts in PREPARATION, wave 0/5")
	_check(hud._wave_label.text == "WAVE  0 / 5", "HUD wave counter: '%s'" % hud._wave_label.text)
	_check(hud.banner_text().begins_with("OPERATION FIRST ASSAULT"), "mission banner: '%s'" % hud.banner_text())
	_check(hud._intel.visible and hud._intel_label.text.contains("FIRST CONTACT"),
			"intel shows next wave: '%s'" % hud._intel_label.text)
	s.wave_started.connect(func(_i: int, _w: WaveData) -> void: _banners.append(hud.banner_text()))
	s.enemy_type_arrived.connect(func(_i: int, id: StringName) -> void:
		if id == &"heavy_tank":
			_banners.append(hud.banner_text()))

	# First defence with real input (C_balanced's opening): HMG + north wall + HMG.
	var credits0 := s.wallet.get_credits()
	_select(hud, "HMG")
	await _tap(battle, Vector2i(19, 6))
	_select(hud, "WALL")
	for x in [20, 21, 22, 23]:
		await _tap(battle, Vector2i(x, 4))
	_select(hud, "HMG")
	await _tap(battle, Vector2i(18, 9))
	hud.clear_selection()
	_check(s.wallet.get_credits() == credits0 - 300, "opening defence paid at base prices (%d left)" % s.wallet.get_credits())
	await _shot("31_opening_defence")

	var bot := StrategyBot.new(Sim.STRATEGIES["C_balanced"])
	bot.prepare(s) # anything else the plan affords now
	var paused_checked := false
	for wave in 5:
		_click(_find_button(hud, "START WAVE").get_global_rect().get_center())
		await _frames(2)
		_check(s.phase == GameSession.Phase.WAVE_ACTIVE and s.wave_number() == wave + 1, "wave %d started via HUD" % (wave + 1))
		if not paused_checked:
			await _seconds(2.0)
			await _shot("32_wave1_under_attack")
			_click(_find_button(hud, "II  PAUSE").get_global_rect().get_center())
			await _frames(3)
			var frozen := s.enemies.get_enemies().map(func(e: Enemy) -> Vector2: return e.position)
			await _frames(30)
			var still := s.enemies.get_enemies().map(func(e: Enemy) -> Vector2: return e.position)
			_check(s.phase == GameSession.Phase.PAUSED and paused and frozen == still, "PAUSE freezes the battle")
			await _shot("33_paused")
			_click(_find_button(hud, "RESUME").get_global_rect().get_center())
			await _frames(3)
			_check(s.phase == GameSession.Phase.WAVE_ACTIVE and not paused, "RESUME returns to WAVE_ACTIVE")
			paused_checked = true
		Engine.time_scale = SPEED
		var guard := 0.0
		while s.phase == GameSession.Phase.WAVE_ACTIVE and guard < 120.0:
			await _seconds(0.5)
			guard += 0.5
			if wave == 2 and s.waves.spawned_in_wave() > 9 and not FileAccess.file_exists(out_dir + "34_armor_wave.png"):
				Engine.time_scale = 1.0
				await _shot("34_armor_wave")
				Engine.time_scale = SPEED
		Engine.time_scale = 1.0
		if s.is_over():
			break
		await _frames(2)
		_check(s.phase == GameSession.Phase.WAVE_COMPLETED and hud.banner_text().begins_with("WAVE %d CLEARED" % (wave + 1)),
				"wave %d cleared banner: '%s'" % [wave + 1, hud.banner_text()])
		if wave == 0:
			await _shot("35_wave_cleared")
		bot.prepare(s)
	await _frames(10)
	print("  banners seen: %s" % [_banners])
	var armour_banner := _banners.any(func(b: String) -> bool: return b == "ARMOR INBOUND")
	_check(_banners.size() >= 6 and armour_banner, "wave + armour banners shown")
	_check(s.phase == GameSession.Phase.VICTORY, "VICTORY (HQ %d/20)" % s.base_hp)
	_check(hud.results_visible(), "results screen visible")
	print("  results: waves %d, kills %d, HQ %d, credits %d, score %d, stars %d" % [s.stats.waves_completed, s.stats.kills,
			s.base_hp, s.wallet.get_credits(), s.score(), MissionScore.stars(s)])
	await _shot("36_victory")

	# RESTART from the results screen: old session must be freed, new one clean.
	var old_ref: WeakRef = weakref(s)
	s = null
	_click(_find_button(hud, "RESTART MISSION").get_global_rect().get_center())
	await _frames(15)
	battle = current_scene
	var s2: GameSession = battle.session
	_check(old_ref.get_ref() == null, "previous session freed after restart (no leaked references)")
	_check(s2.phase == GameSession.Phase.PREPARATION and s2.wave_number() == 0 and s2.wallet.get_credits() == 350
			and s2.base_hp == 20 and s2.grid.placement_count() == 0 and s2.enemies.count() == 0 and not paused,
			"restart: clean session (credits %d, HQ %d, structures %d)" % [s2.wallet.get_credits(), s2.base_hp, s2.grid.placement_count()])

	# Run 2: no defence -> defeat.
	hud = battle.hud
	for wave in 5:
		if s2.is_over():
			break
		_click(_find_button(hud, "START WAVE").get_global_rect().get_center())
		await _frames(2)
		Engine.time_scale = SPEED
		var guard := 0.0
		while s2.phase == GameSession.Phase.WAVE_ACTIVE and guard < 120.0:
			await _seconds(0.5)
			guard += 0.5
		Engine.time_scale = 1.0
	await _frames(10)
	_check(s2.phase == GameSession.Phase.DEFEAT and hud.results_visible(), "undefended run ends in DEFEAT with results")
	print("  defeat: wave reached %d, kills %d, HQ %d" % [s2.wave_number(), s2.stats.kills, s2.base_hp])
	await _shot("37_defeat")
	_click(_find_button(hud, "MAIN MENU").get_global_rect().get_center())
	await _frames(10)
	_check(current_scene.name == "MainMenu" and not paused, "MAIN MENU from results")
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
	if node is Button and (node as Button).text.begins_with(text) and (node as Button).is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _select(hud: BattleHud, label: String) -> void:
	_click(_find_button(hud, label).get_global_rect().get_center())


func _tap(battle: Node, cell: Vector2i) -> void:
	var gv: GridView = battle.grid_view
	_click(gv.get_global_transform_with_canvas() * battle.session.grid.cell_to_local(cell))
	await _frames(1)


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
