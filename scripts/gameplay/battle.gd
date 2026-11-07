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

const LEVEL_PATH := "res://data/levels/mission_01.json"
const MENU_SCENE := "res://scenes/menus/main_menu.tscn"

var session: GameSession
var grid_view: GridView
var hud: BattleHud

var _selected: StructureData = null
var _remove_mode: bool = false
var _aiming: bool = false
var _hover_cell: Vector2i = Vector2i(-9999, -9999)
var _armed_remove_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	var result := LevelLoader.load_file(LEVEL_PATH)
	if not result.is_ok():
		_show_fatal("Could not load mission:\n" + "\n".join(PackedStringArray(result.errors)))
		return
	session = GameSession.new(result.level)

	grid_view = GridView.new()
	add_child(grid_view)
	grid_view.bind(session)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = BattleHud.new()
	layer.add_child(hud)
	hud.setup(session, StructureCatalog.load_many(session.level.available_structures))
	hud.tool_changed.connect(_on_tool_changed)
	hud.restart_requested.connect(_restart)
	hud.menu_requested.connect(_go_to_menu)

	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


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


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventMouseMotion:
		_update_cursor(_event_cell((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var cell := _event_cell(mb.position)
			if mb.pressed:
				_aiming = session.grid.is_in_bounds(cell)
				_update_cursor(cell)
			elif _aiming:
				_aiming = false
				_commit(cell)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			hud.clear_selection()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			hud.clear_selection()
			get_viewport().set_input_as_handled()


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
			hud.show_feedback("%s built  (-%d CR)" % [_selected.display_name, _selected.cost], false)
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


func _evaluate_at(cell: Vector2i) -> ConstructionService.Check:
	return session.construction.evaluate(_selected, ConstructionService.origin_for_cell(_selected, cell))


# --- Tools / navigation ------------------------------------------------------

func _on_tool_changed(data: StructureData, remove_mode: bool) -> void:
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
