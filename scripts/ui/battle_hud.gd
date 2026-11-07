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
const BUILD_BUTTON_HEIGHT := 92.0
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
## Parallel to _build_buttons (buttons are grouped, so order differs from _structures).
var _button_data: Array[StructureData] = []
var _structures: Array[StructureData] = []
var _surcharge_label: Label
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
	col.add_theme_constant_override("separation", 8)
	_side_panel.add_child(col)
	# Two-column build grid, grouped by category, so 6+ items fit 1080p.
	for category in [StructureData.Category.BARRIER, StructureData.Category.TURRET]:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for data in _structures:
			if data.category != category:
				continue
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = _button_group
			b.custom_minimum_size = Vector2(0, BUILD_BUTTON_HEIGHT)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.clip_text = true
			b.add_theme_font_size_override("font_size", 24)
			b.toggled.connect(_on_build_toggled.bind(data))
			grid.add_child(b)
			_build_buttons.append(b)
			_button_data.append(data)
		if grid.get_child_count() > 0:
			var header := "BARRIERS" if category == StructureData.Category.BARRIER else "TURRETS"
			col.add_child(UiTheme.label(header, 18, Palette.MILITARY_GREEN.lightened(0.3)))
			col.add_child(grid)
	_surcharge_label = UiTheme.label("", 18, Palette.TACTICAL_GOLD)
	col.add_child(_surcharge_label)

	_remove_button = Button.new()
	_remove_button.toggle_mode = true
	_remove_button.button_group = _button_group
	_remove_button.text = "REMOVE"
	_remove_button.custom_minimum_size = Vector2(0, 72)
	_remove_button.toggled.connect(_on_remove_toggled)
	col.add_child(_remove_button)

	_info_label = UiTheme.label("", 20)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_info_label)

	_feedback_label = UiTheme.label("", 20, Palette.TACTICAL_GOLD)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.custom_minimum_size.y = 56
	col.add_child(_feedback_label)

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
	_refresh_affordability()
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
		_info_label.text = ("REMOVE MODE\nTap a structure to select it, tap it again to confirm. "
				+ "The refund is shown before confirming.")
	elif data == null:
		_info_label.text = ("Select a structure, then tap or drag on the map and release to build.\n"
				+ "Tap a placed turret to inspect it.")
	else:
		var price := _session.construction.price_of(data)
		var price_text := "%d CR" % price if price == data.cost else "%d CR (%d +%d combat)" % [price, data.cost, price - data.cost]
		var text := "%s  -  %s  -  %d HP\n%s\n" % [data.display_name.to_upper(), price_text, data.max_hp, data.description]
		if data.turret != null:
			text += _weapon_text(data.turret)
		else:
			var passes := MovementClass.mask_to_names(MovementClass.ALL_GROUND & ~data.blocks_mask)
			text += "PASSABLE FOR: %s" % (", ".join(passes).to_upper() if not passes.is_empty() else "NONE")
		_info_label.text = text
	_feedback_label.text = ""


## Info for a turret already on the field (tap with no tool selected).
func show_turret_info(t: TurretState) -> void:
	_info_label.text = "%s  -  %d HP\n%s\nKILLS %d  -  SHOTS %d  -  DAMAGE %d" % [
		t.placement.data.display_name.to_upper(), t.placement.hp, _weapon_text(t.data),
		t.kills, t.shots_fired, roundi(t.damage_dealt)]
	_feedback_label.text = ""


func _weapon_text(w: TurretData) -> String:
	var layers := PackedStringArray()
	if w.target_layers & Targeting.GROUND:
		layers.append("GROUND")
	if w.target_layers & Targeting.AIR:
		layers.append("AIR")
	var splash := "  SPLASH %.1f" % w.splash_radius_cells if w.splash_radius_cells > 0.0 else ""
	return "RANGE %.1f  -  %.1f SHOTS/S  -  DMG %d %s%s\nTARGETS %s  -  PRIORITY %s" % [
		w.range_cells, w.shots_per_second(), roundi(w.damage), Damage.type_name(w.damage_type), splash,
		"/".join(layers), Targeting.Priority.keys()[w.priority]]


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


## Button labels show the price right now (with combat surcharge) and dim
## what the player cannot afford. Called on credit and phase changes.
func _refresh_affordability() -> void:
	var credits := _session.wallet.get_credits()
	var service := _session.construction
	var surcharged := false
	for i in _build_buttons.size():
		var data := _button_data[i]
		var price := service.price_of(data)
		surcharged = surcharged or price > data.cost
		var b := _build_buttons[i]
		b.text = "%s\n%d CR%s" % [data.label().to_upper(), price, "*" if price > data.cost else ""]
		b.modulate = Color.WHITE if price <= credits else Color(1, 0.55, 0.5, 0.8)
	_surcharge_label.text = ("* COMBAT SURCHARGE +%d%%" % roundi(service.surcharge_ratio * 100.0)) if surcharged else ""


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
