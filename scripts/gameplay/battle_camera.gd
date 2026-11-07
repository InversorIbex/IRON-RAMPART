class_name BattleCamera
extends Camera2D
## Zoom/pan camera for the battlefield. At zoom 1 it shows exactly the
## fitted layout (identical to having no camera); zooming in makes cells
## large enough for fingers. The HUD lives on a CanvasLayer, unaffected.

const MIN_ZOOM := 1.0
const MAX_ZOOM := 3.0
const SHAKE_MAX_PX := 7.0
const SHAKE_DECAY := 6.0

## World rect the view may travel over. Extended to the right/top by the HUD
## size so every map cell can be brought out from under the panels.
var _bounds: Rect2
var _view: Vector2
## Screen shake (cosmetic, decays; never moves the logical camera position).
var _shake: float = 0.0


func add_shake(strength: float) -> void:
	_shake = minf(1.0, _shake + strength * 0.5)


func _process(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta * _shake - delta)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * SHAKE_MAX_PX * _shake / zoom.x
	if _shake == 0.0:
		offset = Vector2.ZERO


func reset_view(view_size: Vector2, hud_right: float, hud_top: float) -> void:
	_view = view_size
	_bounds = Rect2(Vector2(0, -hud_top), view_size + Vector2(hud_right, hud_top))
	zoom = Vector2.ONE
	position = view_size * 0.5


func get_zoom_level() -> float:
	return zoom.x


## Zooms keeping the world point under `screen_point` fixed.
func zoom_at(screen_point: Vector2, factor: float) -> void:
	var old := zoom.x
	var z := clampf(old * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(z, old):
		return
	var world := position + (screen_point - _view * 0.5) / old
	zoom = Vector2(z, z)
	position = world - (screen_point - _view * 0.5) / z
	_clamp()


func pan_by(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_clamp()


func _clamp() -> void:
	if zoom.x <= MIN_ZOOM + 0.001:
		position = _view * 0.5
		return
	var half := _view * 0.5 / zoom.x
	position.x = clampf(position.x, _bounds.position.x + half.x, _bounds.end.x - half.x)
	position.y = clampf(position.y, _bounds.position.y + half.y, _bounds.end.y - half.y)
