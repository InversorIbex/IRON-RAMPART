extends SceneTree
## Milestone 3 end-to-end match through the real input pipeline (needs a renderer):
## maze + turrets in BUILD, inspect a turret, assault, combat build with the
## +25 % surcharge (HUD + ghost), kills, rewards, effects cleanup.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##       --rendering-driver opengl3 --script res://tests/visual/drive_combat.gd

const WATCHDOG_SECONDS := 600.0

## Demo budget on top of the mission's 300 CR so all three turret types fit in
## one run (balancing is Milestone 6). Reported in the output.
const DEMO_BUDGET := 600

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
	change_scene_to_file("res://scenes/menus/main_menu.tscn")
	await _frames(5)
	_click(_find_button(current_scene, "PLAY").get_global_rect().get_center())
	await _frames(10)
	battle = current_scene
	var s: GameSession = battle.session
	var hud: BattleHud = battle.hud
	s.wallet.earn(DEMO_BUDGET)
	print("  demo budget: %d + %d CR" % [s.level.starting_credits, DEMO_BUDGET])

	# --- BUILD phase: maze + turrets at base price ---------------------------------
	_select(hud, "WALL")
	var walls := 0
	for y in range(5, 12):
		walls += await _build_at(s, Vector2i(5, y))
	_check(walls == 7, "7 walls built (maze west of the spawn)")
	var credits := s.wallet.get_credits()
	_select(hud, "HMG")
	await _build_at(s, Vector2i(8, 7))
	_check(s.wallet.get_credits() == credits - 100, "HMG at base price in BUILD (100)")
	await _build_at(s, Vector2i(18, 1))
	_select(hud, "MISSILES")
	await _build_at(s, Vector2i(19, 6))
	_select(hud, "AA GUN")
	await _build_at(s, Vector2i(14, 9))
	_check(s.combat.get_turrets().size() == 4, "4 turrets registered (%d)" % s.combat.get_turrets().size())
	_check(battle.combat_layer.view_count() == 4, "one TurretView per turret")
	_check(s.construction.all_routes_open(), "every route still open")

	# Inspect a turret: no tool + tap.
	hud.clear_selection()
	await _frames(2)
	_tap_cell(Vector2i(19, 6))
	await _frames(2)
	_check(battle._selected_turret != null and hud._info_label.text.contains("MISSILE"), "tap shows turret info")
	await _shot("20_defences_ready")

	# --- COMBAT ----------------------------------------------------------------------
	var hp0 := s.base_hp
	var kills := [0]
	var rewards := [0]
	s.enemies.enemy_killed.connect(func(e: Enemy) -> void:
		kills[0] += 1
		rewards[0] += e.data.reward)
	var by_type := {}
	s.combat.shot_fired.connect(func(t: TurretState, _p: Projectile) -> void:
		by_type[t.data.id] = by_type.get(t.data.id, 0) + 1)
	_click(_find_button(hud, "START WAVE").get_global_rect().get_center())
	await _frames(2)
	_check(s.phase == GameSession.Phase.WAVE_ACTIVE, "wave 1 started")
	# Capture the fight while projectiles are in the air.
	var shot_taken := false
	# HMG rounds fly ~0.1 s, so "in the air" means >= 1 projectile; prefer a frame
	# with a missile up (bigger visual) if one appears within the window.
	for i in 1500:
		await process_frame
		var projectiles := s.combat.get_projectiles()
		var missile_up := projectiles.any(func(p: Projectile) -> bool: return p.kind == TurretData.ProjectileKind.MISSILE)
		if not shot_taken and projectiles.size() >= 1 and battle.combat_layer.effect_count() >= 3 \
				and (missile_up or i > 1200):
			await _shot("21_firefight")
			# Close-up of the same fight to judge effects at a playable zoom.
			var cam: BattleCamera = battle.camera
			var focus: Vector2 = battle.grid_view.get_global_transform_with_canvas() * projectiles[0].position
			cam.zoom_at(focus, 2.4)
			await _frames(2)
			await _shot("21b_firefight_zoomed")
			cam.zoom_at(focus, 0.01)
			shot_taken = true
			break
	_check(shot_taken, "captured a firefight (projectiles + effects on screen)")

	# Combat build: +25 % surcharge visible in the HUD and in the ghost, then charged.
	_select(hud, "HMG")
	await _frames(2)
	var btn := _find_button(hud, "HMG")
	_check(btn.text.contains("125 CR*"), "HUD shows combat price: '%s'" % btn.text.replace("\n", " "))
	_check(hud._surcharge_label.text.contains("+25%"), "HUD explains the surcharge")
	var cell := Vector2i(12, 5)
	_hover(_cell_pos(cell))
	await _frames(2)
	await _shot("22_combat_build_preview")
	var check := s.construction.evaluate(StructureCatalog.load_structure(&"turret_hmg"), cell)
	_check(check.is_ok() and check.cost == 125 and check.surcharge == 25, "preview price 125 (+25)")
	_tap_cell(cell)
	await _frames(2)
	# Read what was actually paid (kills may add rewards to the balance meanwhile).
	var placed := s.grid.get_placement_at(cell)
	_check(placed != null and placed.paid == 125, "charged 125 in combat (paid %s)" % [placed.paid if placed else "-"])
	print("  feedback: ", hud._feedback_label.text)
	hud.clear_selection()

	# Let it play out.
	Engine.time_scale = 4.0
	var waited := 0.0
	while s.phase == GameSession.Phase.WAVE_ACTIVE and waited < 120.0:
		await _seconds(1.0)
		waited += 1.0
	Engine.time_scale = 1.0
	await _seconds(3.0) # let effects fade
	print("  shots by weapon: %s | kills %d | rewards %d CR | HQ %d -> %d" % [by_type, kills[0], rewards[0], hp0, s.base_hp])
	_check(kills[0] >= 5, "turrets destroyed enemies (%d kills)" % kills[0])
	_check(by_type.get(&"hmg", 0) > 0 and by_type.get(&"missile", 0) > 0, "HMG and missiles both fired")
	_check(by_type.get(&"aa", 0) == 0, "AA held fire: no air targets")
	_check(hp0 - s.base_hp < 8, "HQ took less than the undefended 8 damage of wave 1 (%d)" % (hp0 - s.base_hp))
	_check(s.is_build_phase(), "back to a build phase")
	_check(s.combat.get_projectiles().is_empty() and battle.enemy_layer.view_count() == 0, "no leftover projectiles/views")
	_check(battle.combat_layer.effect_count() < 10, "effects expire (%d left: scorch marks)" % battle.combat_layer.effect_count())
	_check(_find_button(hud, "HMG").text.contains("100 CR") and not _find_button(hud, "HMG").text.contains("*"),
			"price back to base after combat")
	await _shot("23_after_battle")

	# Leave the battle before quitting (audio playbacks at shutdown, see CLAUDE.md).
	change_scene_to_file("res://scenes/menus/main_menu.tscn")
	await _frames(10)
	print("DRIVER RESULT: ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)


func _build_at(s: GameSession, cell: Vector2i) -> int:
	var count := s.grid.placement_count()
	_tap_cell(cell)
	await _frames(1)
	return 1 if s.grid.placement_count() == count + 1 else 0


func _select(hud: BattleHud, label: String) -> void:
	_click(_find_button(hud, label).get_global_rect().get_center())


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


func _hover(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	root.push_input(m, true)


func _click(pos: Vector2) -> void:
	_hover(pos)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e, true)
