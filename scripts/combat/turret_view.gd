class_name TurretView
extends Node2D
## Rotating weapon of one turret (scene: scenes/turrets/turret_view.tscn).
## The static base is drawn by GridView with the other structures; this node
## draws the gun, recoil and muzzle flash. Reads TurretState, never writes it.

const FLASH_TIME := 0.06
const RECOIL_TIME := 0.12

var turret: TurretState
var _cell: float = 64.0
var _flash: float = 0.0
var _recoil: float = 0.0
var _barrel_toggle: bool = false


func setup(p_turret: TurretState, cell_size: float) -> void:
	turret = p_turret
	_cell = cell_size
	position = turret.position
	rotation = turret.aim_angle


func on_fired() -> void:
	_flash = FLASH_TIME
	_recoil = RECOIL_TIME
	_barrel_toggle = not _barrel_toggle


## Muzzle position in GridView space (for effects).
func muzzle_position() -> Vector2:
	return position + Vector2.from_angle(rotation) * _cell * 0.42


func sync(delta: float) -> void:
	rotation = turret.aim_angle
	var active := _flash > 0.0 or _recoil > 0.0
	_flash = maxf(0.0, _flash - delta)
	_recoil = maxf(0.0, _recoil - delta)
	if active:
		queue_redraw()


func _draw() -> void:
	var c := _cell
	var dark := Palette.METAL_DARK
	var metal := Palette.METAL
	var kick := -c * 0.08 * (_recoil / RECOIL_TIME)
	match turret.data.silhouette:
		TurretData.Silhouette.TWIN_MG:
			draw_circle(Vector2.ZERO, c * 0.2, metal)
			for side in [-1.0, 1.0]:
				var k := kick if (side > 0.0) == _barrel_toggle else kick * 0.3
				draw_rect(Rect2(Vector2(c * 0.05 + k, side * c * 0.07 - c * 0.03), Vector2(c * 0.38, c * 0.06)), dark)
			draw_circle(Vector2.ZERO, c * 0.1, dark)
			if _flash > 0.0:
				var tip := Vector2(c * 0.46 + kick, (1.0 if _barrel_toggle else -1.0) * c * 0.07)
				_draw_flash(tip, c * 0.24, Palette.TACTICAL_GOLD)
		TurretData.Silhouette.MISSILE_POD:
			draw_rect(Rect2(Vector2(-c * 0.22 + kick, -c * 0.2), Vector2(c * 0.5, c * 0.4)), metal)
			for row in [-1.0, 1.0]:
				draw_circle(Vector2(c * 0.24 + kick, row * c * 0.1), c * 0.07, dark)
				draw_circle(Vector2(c * 0.24 + kick, row * c * 0.1), c * 0.035, Palette.ALERT_RED.darkened(0.3))
			if _flash > 0.0:
				_draw_flash(Vector2(-c * 0.3, 0), c * 0.2, Color(Palette.FX_DUST, 0.8)) # back-blast
		TurretData.Silhouette.AA_TWIN_CANNON:
			draw_circle(Vector2.ZERO, c * 0.22, metal)
			for side in [-1.0, 1.0]:
				draw_rect(Rect2(Vector2(kick, side * c * 0.09 - c * 0.025), Vector2(c * 0.5, c * 0.05)), dark)
			draw_rect(Rect2(Vector2(-c * 0.12, -c * 0.12), Vector2(c * 0.2, c * 0.24)), dark)
			if _flash > 0.0:
				_draw_flash(Vector2(c * 0.52, 0), c * 0.14, Palette.TACTICAL_GOLD)


func _draw_flash(at: Vector2, size: float, color: Color) -> void:
	var a := _flash / FLASH_TIME
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(size, 0), at + Vector2(0, size * 0.45), at + Vector2(-size * 0.2, 0), at + Vector2(0, -size * 0.45),
	]), Color(color, a))
	draw_circle(at, size * 0.3, Color(Palette.FX_FLASH, a))
