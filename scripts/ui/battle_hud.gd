class_name BattleHud
extends Control
## Battle HUD: top status bar + right build panel + pause overlay.
## Emits intent signals; Battle decides what they mean. Built in code until
## the UI art pass (then it becomes a .tscn with the same API).

signal tool_changed(data: StructureData, remove_mode: bool)
signal restart_requested
signal menu_requested
## DEBUG (Milestone 2): start TestAssault. Replaced by the wave button in Milestone 4.
signal assault_requested

const PANEL_WIDTH := 400.0
const TOP_BAR_HEIGHT := 76.0
## Reference logical height (project viewport). The side panel must fit in it.
const REFERENCE_HEIGHT := 1080.0
const LEGEND_SHORT := {
	MovementClass.INFANTRY: "INFANTRY",
	MovementClass.WHEELED: "WHEELED",
	MovementClass.TRACKED: "TRACKED",
}

var _session: GameSession
var _credits_label: Label
var _base_label: Label
var _phase_label: Label
var _enemy_label: Label
var _assault_button: Button
var _defeat_overlay: Control
var _info_label: Label
var _feedback_label: Label
var _build_buttons: Array[Button] = []
var _structures: Array[StructureData] = []
var _remove_button: Button
var _button_group := ButtonGroup.new()
var _pause_overlay: Control
var _top_bar: PanelContainer
var _side_panel: PanelContainer


func setup(session: GameSession, structures: Array[StructureData]) -> void:
	_session = session
	_structures = structures
	theme = UiTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_button_group.allow_unpress = true
	_build_top_bar()
	_build_side_panel()
	_build_pause_overlay()
	_session.wallet.credits_changed.connect(_on_credits_changed)
	_session.phase_changed.connect(_on_phase_changed)
	_session.base_hp_changed.connect(func(_hp: int, _max: int) -> void: _refresh_status())
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh_status()
	_refresh_affordability()
	_show_info(null, false)


func clear_selection() -> void:
	var pressed := _button_group.get_pressed_button()
	if pressed != null:
		pressed.button_pressed = false # emits toggled -> tool_changed(null, false)
	_show_info(null, false)


func show_feedback(text: String, is_error: bool) -> void:
	_feedback_label.text = text
	_feedback_label.add_theme_color_override("font_color",
			Palette.ALERT_RED if is_error else Palette.TACTICAL_GOLD)


# --- Construction ------------------------------------------------------------

func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_bar.custom_minimum_size.y = TOP_BAR_HEIGHT
	add_child(_top_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	_top_bar.add_child(row)

	_credits_label = UiTheme.label("", UiTheme.FONT_SIZE, Palette.TACTICAL_GOLD)
	row.add_child(_credits_label)
	_base_label = UiTheme.label("")
	row.add_child(_base_label)
	_phase_label = UiTheme.label("")
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_phase_label)
	_enemy_label = UiTheme.label("", UiTheme.FONT_SIZE, Palette.ALERT_RED.lightened(0.15))
	row.add_child(_enemy_label)

	_assault_button = Button.new()
	_assault_button.text = "TEST ASSAULT"
	_assault_button.tooltip_text = "Debug: spawns a fixed enemy column (waves arrive in Milestone 4)."
	_assault_button.custom_minimum_size = Vector2(230, 0)
	_assault_button.pressed.connect(func() -> void: assault_requested.emit())
	row.add_child(_assault_button)

	var pause := Button.new()
	pause.text = "II  PAUSE"
	pause.custom_minimum_size = Vector2(170, 0)
	pause.pressed.connect(_set_paused.bind(true))
	row.add_child(pause)


func _build_side_panel() -> void:
	_side_panel = PanelContainer.new()
	_side_panel.anchor_left = 1.0
	_side_panel.anchor_right = 1.0
	_side_panel.anchor_top = 0.0
	_side_panel.anchor_bottom = 1.0
	_side_panel.offset_left = -PANEL_WIDTH
	_side_panel.offset_top = TOP_BAR_HEIGHT
	# If content ever exceeds PANEL_WIDTH, grow towards the map, never off-screen.
	_side_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_side_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_side_panel.add_child(col)
	col.add_child(UiTheme.label("BUILD", UiTheme.FONT_SIZE_SMALL, Palette.MILITARY_GREEN.lightened(0.3)))

	for data in _structures:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _button_group
		b.text = "%s\n%d CR" % [data.display_name.to_upper(), data.cost]
		b.custom_minimum_size = Vector2(0, UiTheme.TOUCH_MIN_HEIGHT)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggled.connect(_on_build_toggled.bind(data))
		col.add_child(b)
		_build_buttons.append(b)

	_remove_button = Button.new()
	_remove_button.toggle_mode = true
	_remove_button.button_group = _button_group
	_remove_button.text = "REMOVE"
	_remove_button.custom_minimum_size = Vector2(0, UiTheme.TOUCH_MIN_HEIGHT * 0.8)
	_remove_button.toggled.connect(_on_remove_toggled)
	col.add_child(_remove_button)

	_info_label = UiTheme.label("", UiTheme.FONT_SIZE_SMALL)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_info_label)

	_feedback_label = UiTheme.label("", UiTheme.FONT_SIZE_SMALL, Palette.TACTICAL_GOLD)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.custom_minimum_size.y = 90
	col.add_child(_feedback_label)

	col.add_child(UiTheme.label("ENEMY ROUTES", 18, Palette.MILITARY_GREEN.lightened(0.3)))
	var legend_row := HBoxContainer.new()
	legend_row.add_theme_constant_override("separation", 7)
	for bit in MovementClass.ALL:
		var color: Color = GridView.ROUTE_STYLE[bit]["color"]
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(26, 6)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend_row.add_child(swatch)
		legend_row.add_child(UiTheme.label(LEGEND_SHORT[bit], 17, color))
	col.add_child(legend_row)


func _build_pause_overlay() -> void:
	_pause_overlay = _make_overlay("PAUSED", Palette.SANDSTONE, [
			["RESUME", _set_paused.bind(false)],
			["RESTART", func() -> void: restart_requested.emit()],
			["MAIN MENU", func() -> void: menu_requested.emit()]])
	_defeat_overlay = _make_overlay("HQ DESTROYED", Palette.ALERT_RED, [
			["RESTART", func() -> void: restart_requested.emit()],
			["MAIN MENU", func() -> void: menu_requested.emit()]])


func _make_overlay(title_text: String, title_color: Color, entries: Array) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(Palette.OLIVE_BLACK, 0.85)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	center.add_child(col)
	var title := UiTheme.label(title_text, 64, title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for entry in entries:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(420, UiTheme.TOUCH_MIN_HEIGHT)
		b.pressed.connect(entry[1])
		col.add_child(b)
	return overlay


## Called every frame by Battle; only touches the label when the text changes.
func set_enemy_status(alive: int, queued: int) -> void:
	var text := "" if alive + queued == 0 else "ENEMIES  %d" % (alive + queued)
	if _enemy_label.text != text:
		_enemy_label.text = text


func _on_phase_changed(phase: int) -> void:
	_refresh_status()
	_assault_button.disabled = phase != GameSession.Phase.BUILD
	if phase == GameSession.Phase.DEFEAT:
		_defeat_overlay.visible = true


# --- Behaviour ---------------------------------------------------------------

func toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_overlay.visible = paused


func _on_build_toggled(pressed: bool, data: StructureData) -> void:
	if pressed:
		_show_info(data, false)
		tool_changed.emit(data, false)
	elif _button_group.get_pressed_button() == null:
		_show_info(null, false)
		tool_changed.emit(null, false)


func _on_remove_toggled(pressed: bool) -> void:
	if pressed:
		_show_info(null, true)
		tool_changed.emit(null, true)
	elif _button_group.get_pressed_button() == null:
		_show_info(null, false)
		tool_changed.emit(null, false)


func _show_info(data: StructureData, remove_mode: bool) -> void:
	if remove_mode:
		_info_label.text = "REMOVE MODE\nTap a structure to select it, tap it again to confirm. The refund is shown before confirming."
	elif data == null:
		_info_label.text = ("Select a structure, then tap or drag on the map and release to build.\n"
				+ "Enemies always need an open route to the HQ.")
	else:
		var blocks := MovementClass.mask_to_names(data.blocks_mask)
		var passes := MovementClass.mask_to_names(MovementClass.ALL_GROUND & ~data.blocks_mask)
		_info_label.text = "%s  -  %d CR  -  %d HP\n%s\nBLOCKS: %s\nPASSABLE: %s" % [
			data.display_name.to_upper(), data.cost, data.max_hp, data.description,
			", ".join(blocks).to_upper() if not blocks.is_empty() else "NONE",
			", ".join(passes).to_upper() if not passes.is_empty() else "NONE"]
	_feedback_label.text = ""


func _on_credits_changed(_credits: int, _delta: int) -> void:
	_refresh_status()
	_refresh_affordability()


func _refresh_status() -> void:
	_credits_label.text = "CREDITS  %d" % _session.wallet.get_credits()
	_base_label.text = "HQ  %d / %d" % [_session.base_hp, _session.level.base_max_hp]
	match _session.phase:
		GameSession.Phase.DEFEAT:
			_phase_label.text = "MISSION FAILED"
		GameSession.Phase.VICTORY:
			_phase_label.text = "MISSION COMPLETE"
		_:
			_phase_label.text = "%s PHASE" % GameSession.Phase.keys()[_session.phase]


func _refresh_affordability() -> void:
	var credits := _session.wallet.get_credits()
	for i in _build_buttons.size():
		var affordable := _structures[i].cost <= credits
		_build_buttons[i].modulate = Color.WHITE if affordable else Color(1, 0.55, 0.5, 0.8)


func _apply_safe_area() -> void:
	# Keep HUD out of notches/rounded corners on phones. Desktop: no margins.
	var left := 0.0
	var right := 0.0
	var top := 0.0
	if OS.has_feature("mobile"):
		var screen := DisplayServer.screen_get_size()
		var safe := DisplayServer.get_display_safe_area()
		var vp := get_viewport_rect().size
		if screen.x > 0 and screen.y > 0:
			var sx := vp.x / screen.x
			var sy := vp.y / screen.y
			left = safe.position.x * sx
			right = (screen.x - safe.end.x) * sx
			top = safe.position.y * sy
	_top_bar.offset_left = left
	_top_bar.offset_right = -right
	_top_bar.offset_top = top
	_side_panel.offset_right = -right
	_side_panel.offset_left = -PANEL_WIDTH - right
	_side_panel.offset_top = TOP_BAR_HEIGHT + top


## Area of the screen (viewport coords) left free for the map.
func map_area() -> Rect2:
	var vp := get_viewport_rect().size
	var top := _side_panel.offset_top
	var right := -_side_panel.offset_left
	var left := _top_bar.offset_left
	return Rect2(Vector2(left, top), Vector2(vp.x - right - left, vp.y - top))
