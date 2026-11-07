extends Control
## Main menu. Placeholder typography until the logo is produced
## (docs/ART_DIRECTION.md). Settings arrive in Milestone 5.

const BATTLE_SCENE := "res://scenes/gameplay/battle.tscn"


func _ready() -> void:
	theme = UiTheme.build()

	var bg := ColorRect.new()
	bg.color = Palette.OLIVE_BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var stripe := ColorRect.new()
	stripe.color = Palette.MILITARY_GREEN.darkened(0.3)
	stripe.anchor_right = 1.0
	stripe.anchor_top = 0.5
	stripe.anchor_bottom = 0.5
	stripe.offset_top = -230
	stripe.offset_bottom = -60
	add_child(stripe)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)

	var title := UiTheme.label("IRON RAMPART", 128, Palette.SANDSTONE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var slogan := UiTheme.label("BUILD YOUR DEFENSE. SURVIVE THE ASSAULT.", 30, Palette.TACTICAL_GOLD)
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(slogan)
	col.add_child(Control.new()) # spacer

	var play := _menu_button("PLAY", col)
	play.pressed.connect(func() -> void: get_tree().change_scene_to_file(BATTLE_SCENE))
	play.grab_focus.call_deferred()

	var settings := _menu_button("SETTINGS", col)
	settings.disabled = true
	settings.tooltip_text = "Not implemented yet (Milestone 5)."

	# Mobile apps don't show a quit button; Android exits via the back button.
	if not OS.has_feature("mobile"):
		var quit := _menu_button("QUIT", col)
		quit.pressed.connect(func() -> void: get_tree().quit())

	var version := UiTheme.label("v%s  -  prototype" % ProjectSettings.get_setting("application/config/version", "0.0.0"),
			18, Palette.SANDSTONE.darkened(0.3))
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 24
	version.offset_top = -56
	version.offset_bottom = -16
	add_child(version)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _menu_button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(460, UiTheme.TOUCH_MIN_HEIGHT)
	parent.add_child(b)
	return b
