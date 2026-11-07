class_name BattleHud
extends Control
## Battle HUD: top status bar (credits, HQ, wave x/5, mission state, START
## WAVE, PAUSE), right build panel, intel strip, event banners, HQ-hit flash,
## pause overlay and the mission results screen.
## Emits intent signals; Battle decides what they mean. Built in code until
## the UI art pass (then it becomes a .tscn with the same API).

signal tool_changed(data: StructureData, remove_mode: bool)
signal restart_requested
signal menu_requested
signal start_wave_requested
signal pause_requested(paused: bool)

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
var _wave_label: Label
var _start_button: Button
var _results_overlay: Control
var _results_box: VBoxContainer
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _intel: PanelContainer
var _intel_label: Label
var _hit_flash: ColorRect
var _top_style_calm: StyleBox
var _top_style_alert: StyleBoxFlat
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
	_build_feedback_layers()
	_build_pause_overlay()
	_session.wallet.credits_changed.connect(_on_credits_changed)
	_session.phase_changed.connect(_on_phase_changed)
	_session.base_hp_changed.connect(func(_hp: int, _max: int) -> void: _refresh_status())
	_session.hq_damaged.connect(_on_hq_damaged)
	_session.wave_started.connect(_on_wave_started)
	_session.wave_completed.connect(_on_wave_completed)
	_session.enemy_type_arrived.connect(_on_enemy_type_arrived)
	_session.mission_ended.connect(_show_results)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh_status()
	_refresh_affordability()
	_refresh_intel()
	_show_info(null, false)
	show_banner(_session.level.display_name.to_upper(),
			"%s  -  BUILD YOUR DEFENSES, THEN START WAVE 1" % _session.level.region.to_upper(), Palette.TACTICAL_GOLD, 4.0)


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
	_top_style_calm = _top_bar.get_theme_stylebox("panel")
	_top_style_alert = (_top_style_calm as StyleBoxFlat).duplicate() as StyleBoxFlat
	_top_style_alert.border_color = Palette.ALERT_RED
	_top_style_alert.border_width_bottom = 4
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	_top_bar.add_child(row)

	_credits_label = UiTheme.label("", UiTheme.FONT_SIZE, Palette.TACTICAL_GOLD)
	row.add_child(_credits_label)
	_base_label = UiTheme.label("")
	row.add_child(_base_label)
	_wave_label = UiTheme.label("", UiTheme.FONT_SIZE, Palette.SANDSTONE)
	row.add_child(_wave_label)
	_phase_label = UiTheme.label("")
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_phase_label)
	_enemy_label = UiTheme.label("", UiTheme.FONT_SIZE, Palette.ALERT_RED.lightened(0.15))
	row.add_child(_enemy_label)

	_start_button = Button.new()
	_start_button.custom_minimum_size = Vector2(250, 0)
	_start_button.pressed.connect(func() -> void: start_wave_requested.emit())
	row.add_child(_start_button)

	var pause := Button.new()
	pause.text = "II  PAUSE"
	pause.custom_minimum_size = Vector2(170, 0)
	pause.pressed.connect(func() -> void: pause_requested.emit(true))
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
			["RESUME", func() -> void: pause_requested.emit(false)],
			["RESTART", func() -> void: restart_requested.emit()],
			["MAIN MENU", func() -> void: menu_requested.emit()]])
	# Results screen: content is filled in _show_results().
	_results_overlay = ColorRect.new()
	(_results_overlay as ColorRect).color = Color(Palette.OLIVE_BLACK, 0.9)
	_results_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_overlay.visible = false
	add_child(_results_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_overlay.add_child(center)
	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 14)
	center.add_child(_results_box)


## Banner strip under the top bar, intel strip at the bottom of the map and a
## full-screen red flash for HQ hits. None of them take input.
func _build_feedback_layers() -> void:
	_hit_flash = ColorRect.new()
	_hit_flash.color = Color(Palette.ALERT_RED, 0.0)
	_hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_flash)
	move_child(_hit_flash, 0)

	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.0
	_banner.anchor_right = 0.0
	_banner.offset_top = TOP_BAR_HEIGHT + 14
	_banner.modulate.a = 0.0
	add_child(_banner)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(col)
	_banner_title = UiTheme.label("", 40, Palette.TACTICAL_GOLD)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_title)
	_banner_sub = UiTheme.label("", 22, Palette.SANDSTONE)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_sub)

	_intel = PanelContainer.new()
	_intel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intel.anchor_top = 1.0
	_intel.anchor_bottom = 1.0
	_intel.modulate.a = 0.92
	add_child(_intel)
	_intel_label = UiTheme.label("", 20, Palette.SANDSTONE)
	_intel.add_child(_intel_label)


## Transient centred banner (wave start/complete, tank warning...).
func show_banner(title: String, subtitle: String, color: Color, seconds: float = 2.5) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = subtitle
	_banner_sub.visible = not subtitle.is_empty()
	_banner.reset_size()
	var area := map_area()
	_banner.position.x = area.position.x + (area.size.x - _banner.get_combined_minimum_size().x) * 0.5
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(seconds)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


func banner_text() -> String:
	return _banner_title.text if _banner.modulate.a > 0.01 else ""


## Insufficient credits: brief red pulse on the credits counter.
func flash_credits() -> void:
	_credits_label.add_theme_color_override("font_color", Palette.ALERT_RED)
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_callback(func() -> void: _credits_label.add_theme_color_override("font_color", Palette.TACTICAL_GOLD))


func _on_hq_damaged(amount: int, _enemy: Enemy) -> void:
	_hit_flash.color.a = minf(0.35, 0.12 + 0.05 * amount)
	var t := create_tween()
	t.tween_property(_hit_flash, "color:a", 0.0, 0.45)
	_base_label.add_theme_color_override("font_color", Palette.ALERT_RED)
	var t2 := create_tween()
	t2.tween_interval(0.6)
	t2.tween_callback(func() -> void: _base_label.add_theme_color_override("font_color", Palette.SANDSTONE))


func _on_wave_started(index: int, wave: WaveData) -> void:
	show_banner("WAVE %d  -  %s" % [index + 1, wave.display_name.to_upper()],
			"%d HOSTILES INBOUND" % wave.enemy_count(), Palette.ALERT_RED, 2.5)


func _on_wave_completed(index: int, _wave: WaveData, bonus: int) -> void:
	if _session.waves.is_last_wave():
		return # the results screen takes over
	show_banner("WAVE %d CLEARED" % (index + 1), "+%d CR BONUS  -  REBUILD AND PREPARE" % bonus, Palette.TACTICAL_GOLD, 3.0)


func _on_enemy_type_arrived(_index: int, enemy_id: StringName) -> void:
	if enemy_id == &"heavy_tank":
		show_banner("ARMOR INBOUND", "HEAVY TANKS: BULLETS BARELY SCRATCH THEM - USE MISSILES", Palette.ALERT_RED, 3.0)


## Composition of the next wave, shown while the player prepares.
func _refresh_intel() -> void:
	var wave := _session.waves.next_wave()
	_intel.visible = wave != null and _session.is_build_phase()
	if not _intel.visible:
		return
	var parts := PackedStringArray()
	var comp := wave.composition()
	for id in comp:
		var data := EnemyCatalog.get_data(id)
		parts.append("%d %s" % [comp[id], (data.display_name if data else String(id)).to_upper()])
	var spawns := PackedStringArray()
	for i in wave.spawn_indices(_session.level.spawn_cells.size()):
		spawns.append(_session.level.spawn_name(i).to_upper())
	var mods := ""
	if wave.hp_multiplier != 1.0 or wave.speed_multiplier != 1.0:
		mods = "   HP x%.2f  SPEED x%.2f" % [wave.hp_multiplier, wave.speed_multiplier]
	_intel_label.text = "INTEL  WAVE %d - %s:  %s   FROM %s%s" % [_session.wave_number() + 1,
			wave.display_name.to_upper(), ", ".join(parts), " + ".join(spawns), mods]
	var area := map_area()
	_intel.reset_size()
	_intel.offset_left = area.position.x + 16
	_intel.offset_right = _intel.offset_left + _intel.get_combined_minimum_size().x
	_intel.offset_top = -_intel.get_combined_minimum_size().y - 16
	_intel.offset_bottom = -16


func _show_results(victory: bool) -> void:
	for c in _results_box.get_children():
		c.queue_free()
	var s := _session
	var title := UiTheme.label("MISSION COMPLETE" if victory else "MISSION FAILED", 72,
			Palette.TACTICAL_GOLD if victory else Palette.ALERT_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_box.add_child(title)
	var sub := UiTheme.label(s.level.display_name.to_upper(), 26, Palette.SANDSTONE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_box.add_child(sub)
	var rows: Array = [
		["WAVES SURVIVED" if victory else "WAVE REACHED",
				"%d / %d" % [s.stats.waves_completed if victory else s.wave_number(), s.waves.wave_count()]],
		["ENEMIES DESTROYED", str(s.stats.kills)],
		["HQ INTEGRITY", "%d / %d" % [s.base_hp, s.level.base_max_hp]],
		["CREDITS REMAINING", str(s.wallet.get_credits())],
		["MISSION SCORE", str(s.score())],
	]
	if victory:
		rows.append(["RATING", "%d / 3 STARS" % MissionScore.stars(s)])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	for r in rows:
		grid.add_child(UiTheme.label(r[0], 28, Palette.SANDSTONE.darkened(0.15)))
		var v := UiTheme.label(r[1], 28, Palette.TACTICAL_GOLD)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
	_results_box.add_child(grid)
	for entry in [["RESTART MISSION", func() -> void: restart_requested.emit()],
			["MAIN MENU", func() -> void: menu_requested.emit()]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(460, UiTheme.TOUCH_MIN_HEIGHT)
		b.pressed.connect(entry[1])
		_results_box.add_child(b)
	_results_overlay.visible = true


func results_visible() -> bool:
	return _results_overlay.visible


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
	_refresh_intel()
	_pause_overlay.visible = phase == GameSession.Phase.PAUSED


# --- Behaviour ---------------------------------------------------------------

## Android back / Esc while no tool is active.
func toggle_pause() -> void:
	pause_requested.emit(_session.phase != GameSession.Phase.PAUSED)


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
	var s := _session
	_credits_label.text = "CREDITS  %d" % s.wallet.get_credits()
	_base_label.text = "HQ  %d / %d" % [s.base_hp, s.level.base_max_hp]
	_wave_label.text = "WAVE  %d / %d" % [s.wave_number(), s.waves.wave_count()]
	var text := ""
	var color := Palette.SANDSTONE
	match s.phase:
		GameSession.Phase.PREPARATION:
			text = "PREPARE DEFENSES"
			color = Palette.VALID
		GameSession.Phase.WAVE_ACTIVE:
			var wave := s.waves.current_wave()
			text = "UNDER ATTACK" + (" - %s" % wave.display_name.to_upper() if wave else "")
			color = Palette.ALERT_RED
		GameSession.Phase.WAVE_COMPLETED:
			text = "WAVE CLEARED"
			color = Palette.TACTICAL_GOLD
		GameSession.Phase.PAUSED:
			text = "PAUSED"
		GameSession.Phase.VICTORY:
			text = "MISSION COMPLETE"
			color = Palette.TACTICAL_GOLD
		GameSession.Phase.DEFEAT:
			text = "MISSION FAILED"
			color = Palette.ALERT_RED
	_phase_label.text = text
	_phase_label.add_theme_color_override("font_color", color)
	_top_bar.add_theme_stylebox_override("panel",
			_top_style_alert if s.phase == GameSession.Phase.WAVE_ACTIVE else _top_style_calm)
	var next := s.wave_number() + 1
	_start_button.text = "START WAVE %d" % next if s.waves.has_next_wave() else "FINAL WAVE"
	_start_button.disabled = not s.is_build_phase() or not s.waves.has_next_wave()


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
