class_name UiTheme
extends RefCounted
## Builds the shared UI Theme from the official palette.
## Built in code for now; can be saved as a .tres Theme once the art pass starts.

const FONT_SIZE := 28
const FONT_SIZE_SMALL := 22
const FONT_SIZE_LARGE := 40
## Minimum touch target height in logical pixels (1080p reference).
const TOUCH_MIN_HEIGHT := 104.0


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	var normal := _box(Palette.OLIVE_BLACK.lightened(0.06), Palette.MILITARY_GREEN, 2)
	var hover := _box(Palette.MILITARY_GREEN.darkened(0.25), Palette.SANDSTONE, 2)
	var pressed := _box(Palette.TACTICAL_GOLD, Palette.TACTICAL_GOLD.lightened(0.3), 3)
	var disabled := _box(Palette.OLIVE_BLACK, Palette.OLIVE_BLACK.lightened(0.12), 2)
	var focus := _box(Color(0, 0, 0, 0), Palette.TACTICAL_GOLD, 2)

	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Palette.SANDSTONE)
	t.set_color("font_hover_color", "Button", Palette.SANDSTONE.lightened(0.2))
	t.set_color("font_pressed_color", "Button", Palette.OLIVE_BLACK)
	t.set_color("font_hover_pressed_color", "Button", Palette.OLIVE_BLACK)
	t.set_color("font_disabled_color", "Button", Palette.SANDSTONE.darkened(0.5))
	t.set_color("font_focus_color", "Button", Palette.SANDSTONE)

	t.set_color("font_color", "Label", Palette.SANDSTONE)
	t.set_stylebox("panel", "PanelContainer",
			_box(Color(Palette.OLIVE_BLACK, 0.94), Palette.MILITARY_GREEN.darkened(0.2), 2, 0))
	return t


static func _box(bg: Color, border: Color, border_width: int, radius: int = 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


## Label helper with consistent sizing.
static func label(text: String, size: int = FONT_SIZE, color: Color = Palette.SANDSTONE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
