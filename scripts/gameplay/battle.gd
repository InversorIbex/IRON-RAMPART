extends Node2D
## Battle scene controller: owns the GameSession, wires view + HUD, and
## translates pointer input into construction commands.
##
## Input model (touch first, mouse equivalent):
##  - Press on the map starts aiming; dragging moves the preview;
##    releasing builds at the previewed cell. Releasing outside the map cancels.
##  - Presses that start on the HUD never reach this node (GUI consumes them),
##    so UI taps can't trigger accidental builds.
##  - Remove mode: first tap arms a structure, second tap on it confirms.
##  - Right click / Esc / Android back: cancel current tool.
##  - Camera: pinch = zoom, two-finger drag = pan; one-finger drag pans only
##    when no tool is selected. A second finger cancels any aim in progress,
##    so pinching can never build. Desktop: wheel = zoom, middle drag = pan.

const LEVEL_PATH := "res://data/levels/mission_01.json"
const MENU_SCENE := "res://scenes/menus/main_menu.tscn"

## Screen distance a press must travel before it counts as a drag (pan).
const DRAG_THRESHOLD := 14.0
## While enemies move, the build preview is re-validated at this period.
const PREVIEW_REFRESH := 0.2

var session: GameSession
var grid_view: GridView
var enemy_layer: EnemyLayer
var combat_layer: CombatLayer
var camera: BattleCamera
var hud: BattleHud
var assault: TestAssault = null
## CPU cost of the last frame's simulation + view sync (microseconds).
## Read by the benchmark and future debug overlays; two clock reads per frame.
var last_sim_usec: int = 0
var last_view_usec: int = 0

var _selected: StructureData = null
var _remove_mode: bool = false
var _aiming: bool = false
var _hover_cell: Vector2i = Vector2i(-9999, -9999)
var _armed_remove_cell: Vector2i = Vector2i(-1, -1)
var _touches: Dictionary = {} # touch index -> screen position
var _gesture: bool = false # multi-touch in progress: ignore emulated mouse
var _press_pos: Vector2 = Vector2.ZERO
var _panning: bool = false
var _mouse_pan: bool = false
var _preview_timer: float = 0.0
var _selected_turret: TurretState = null
var _info_timer: float = 0.0


func _ready() -> void:
	var result := LevelLoader.load_file(LEVEL_PATH)
	if not result.is_ok():
		_show_fatal("Could not load mission:\n" + "\n".join(PackedStringArray(result.errors)))
		return
	session = GameSession.new(result.level)

	grid_view = GridView.new()
	add_child(grid_view)
	grid_view.bind(session)
	enemy_layer = EnemyLayer.new()
	grid_view.add_child(enemy_layer)
	enemy_layer.bind(session.enemies, session.grid.cell_size)
	combat_layer = CombatLayer.new()
	grid_view.add_child(combat_layer) # after EnemyLayer: drawn on top
	combat_layer.bind(session.combat, session.enemies, session.grid.cell_size)
	camera = BattleCamera.new()
	add_child(camera)
	camera.make_current()
	combat_layer.heavy_impact.connect(camera.add_shake)
	session.combat.turret_removed.connect(_on_turret_removed)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = BattleHud.new()
	layer.add_child(hud)
	hud.setup(session, StructureCatalog.load_many(session.level.available_structures))
	hud.tool_changed.connect(_on_tool_changed)
	hud.restart_requested.connect(_restart)
	hud.menu_requested.connect(_go_to_menu)
	hud.assault_requested.connect(start_test_assault)

	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func _process(delta: float) -> void:
	if session == null:
		return
	var t0 := Time.get_ticks_usec()
	if assault != null:
		assault.update(delta)
	session.tick(delta)
	var t1 := Time.get_ticks_usec()
	enemy_layer.sync(delta)
	combat_layer.sync(delta)
	last_sim_usec = t1 - t0
	last_view_usec = Time.get_ticks_usec() - t1
	if _selected_turret != null:
		_info_timer -= delta
		if _info_timer <= 0.0:
			_info_timer = 0.5
			hud.show_turret_info(_selected_turret)
	if assault != null and assault.is_finished() and session.enemies.count() == 0 \
			and session.phase == GameSession.Phase.COMBAT:
		assault = null
		session.set_phase(GameSession.Phase.BUILD)
	hud.set_enemy_status(session.enemies.count(), assault.remaining() if assault != null else 0)
	if _selected != null and session.enemies.count() > 0:
		_preview_timer -= delta
		if _preview_timer <= 0.0:
			_preview_timer = PREVIEW_REFRESH
			_refresh_preview()


## DEBUG (Milestone 2): spawns TestAssault.SEQUENCE. Replaced by waves in Milestone 4.
func start_test_assault() -> void:
	if session == null or session.is_over() or assault != null:
		return
	assault = TestAssault.new(session)
	session.set_phase(GameSession.Phase.COMBAT)


func _notification(what: int) -> void:
	# Android back button (requires application/config/quit_on_go_back=false).
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null:
		if _selected != null or _remove_mode:
			hud.clear_selection()
		else:
			hud.toggle_pause()


# --- Layout ------------------------------------------------------------------

func _layout() -> void:
	if session == null:
		return
	var area := hud.map_area().grow(-12)
	var map_size := session.grid.size_in_pixels()
	var s := minf(area.size.x / map_size.x, area.size.y / map_size.y)
	grid_view.scale = Vector2(s, s)
	grid_view.position = area.position + (area.size - map_size * s) * 0.5
	var vp := get_viewport_rect().size
	camera.reset_view(vp, vp.x - area.end.x, area.position.y)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif _gesture and event is InputEventMouse:
		return # emulated mouse from finger 0 during a pinch: never build/pan
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _mouse_pan:
			camera.pan_by(mm.relative)
		elif _panning or (_pressing_without_tool(mm) and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD):
			_panning = true
			camera.pan_by(mm.relative)
		else:
			_update_cursor(_event_cell(mm.position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var cell := _event_cell(mb.position)
			if mb.pressed:
				_press_pos = mb.position
				_panning = false
				_aiming = session.grid.is_in_bounds(cell) and (_selected != null or _remove_mode)
				_update_cursor(cell)
			else:
				if _aiming:
					_commit(cell)
				elif not _panning and _selected == null and not _remove_mode:
					_select_turret_at(cell)
				_aiming = false
				_panning = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mouse_pan = mb.pressed
		elif mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			camera.zoom_at(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			hud.clear_selection()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			hud.clear_selection()
			get_viewport().set_input_as_handled()


func _pressing_without_tool(mm: InputEventMouseMotion) -> bool:
	return (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _selected == null and not _remove_mode


func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		# Ignore fingers that land on the HUD (buttons handle those).
		if _touches.is_empty() and not hud.map_area().has_point(t.position):
			return
		_touches[t.index] = t.position
		if _touches.size() >= 2 and not _gesture:
			_gesture = true
			_aiming = false # a second finger cancels the pending build
			_hover_cell = Vector2i(-9999, -9999)
			grid_view.clear_cursor()
	else:
		_touches.erase(t.index)
		if _touches.is_empty():
			_gesture = false


func _on_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	if _touches.size() < 2:
		_touches[d.index] = d.position
		return
	var keys := _touches.keys()
	var other: Vector2 = _touches[keys[1] if keys[0] == d.index else keys[0]]
	var old_pos: Vector2 = _touches[d.index]
	var old_mid := (old_pos + other) * 0.5
	var new_mid := (d.position + other) * 0.5
	var old_dist := old_pos.distance_to(other)
	var new_dist := d.position.distance_to(other)
	if old_dist > 1.0:
		camera.zoom_at(new_mid, new_dist / old_dist)
	camera.pan_by(new_mid - old_mid)
	_touches[d.index] = d.position


func _event_cell(viewport_pos: Vector2) -> Vector2i:
	var local := grid_view.get_global_transform_with_canvas().affine_inverse() * viewport_pos
	return session.grid.local_to_cell(local)


func _update_cursor(cell: Vector2i) -> void:
	if cell == _hover_cell:
		return
	_hover_cell = cell
	if _selected != null:
		grid_view.set_ghost(_evaluate_at(cell))
	elif _remove_mode:
		grid_view.set_remove_cursor(cell, _is_armed(cell))


func _commit(cell: Vector2i) -> void:
	if not session.grid.is_in_bounds(cell):
		return # released outside the map: treat as cancel of this gesture
	if _selected != null:
		var origin := ConstructionService.origin_for_cell(_selected, cell)
		var check := session.construction.build(_selected, origin)
		if check.is_ok():
			var extra := "" if check.surcharge == 0 else ", incl. +%d combat surcharge" % check.surcharge
			hud.show_feedback("%s built  (-%d CR%s)" % [_selected.display_name, check.cost, extra], false)
		else:
			hud.show_feedback(ConstructionService.reason_text(check), true)
		grid_view.set_ghost(_evaluate_at(cell))
	elif _remove_mode:
		_commit_remove(cell)


func _commit_remove(cell: Vector2i) -> void:
	var placement := session.grid.get_placement_at(cell)
	if placement == null:
		_armed_remove_cell = Vector2i(-1, -1)
		hud.show_feedback("Nothing to remove here.", true)
	elif not _is_armed(cell):
		_armed_remove_cell = cell
		hud.show_feedback("Tap again to remove %s  (+%d CR)"
				% [placement.data.display_name, placement.data.refund_amount()], false)
	else:
		var check := session.construction.remove_at(cell)
		_armed_remove_cell = Vector2i(-1, -1)
		if check.is_ok():
			hud.show_feedback("%s removed  (+%d CR)" % [check.data.display_name, check.refund], false)
		else:
			hud.show_feedback(ConstructionService.reason_text(check), true)
	grid_view.set_remove_cursor(cell, _is_armed(cell))


## True if `cell` belongs to the structure armed for removal.
func _is_armed(cell: Vector2i) -> bool:
	if not session.grid.is_in_bounds(_armed_remove_cell) or not session.grid.is_in_bounds(cell):
		return false
	var armed := session.grid.get_placement_at(_armed_remove_cell)
	return armed != null and armed == session.grid.get_placement_at(cell)


## Tap with no tool: inspect a turret (range ring + live stats in the HUD).
func _select_turret_at(cell: Vector2i) -> void:
	var placement: Placement = null
	if session.grid.is_in_bounds(cell):
		placement = session.grid.get_placement_at(cell)
	_selected_turret = session.combat.turret_at(placement)
	grid_view.set_selected_turret(_selected_turret)
	if _selected_turret != null:
		_info_timer = 0.0
	else:
		hud.clear_selection()


func _on_turret_removed(t: TurretState) -> void:
	if t == _selected_turret:
		_selected_turret = null
		grid_view.set_selected_turret(null)


func _refresh_preview() -> void:
	if session.grid.is_in_bounds(_hover_cell):
		grid_view.set_ghost(_evaluate_at(_hover_cell))


func _evaluate_at(cell: Vector2i) -> ConstructionService.Check:
	return session.construction.evaluate(_selected, ConstructionService.origin_for_cell(_selected, cell))


# --- Tools / navigation ------------------------------------------------------

func _on_tool_changed(data: StructureData, remove_mode: bool) -> void:
	if data != null or remove_mode:
		_selected_turret = null
		grid_view.set_selected_turret(null)
	_selected = data
	_remove_mode = remove_mode
	_aiming = false
	_armed_remove_cell = Vector2i(-1, -1)
	_hover_cell = Vector2i(-9999, -9999)
	grid_view.clear_cursor()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _show_fatal(message: String) -> void:
	push_error(message)
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := UiTheme.label(message, UiTheme.FONT_SIZE, Palette.ALERT_RED)
	label.position = Vector2(40, 40)
	layer.add_child(label)
