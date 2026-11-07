class_name TurretState
extends RefCounted
## Runtime state of one placed turret (pure data, updated by CombatSystem).

var placement: Placement
var data: TurretData
## Turret centre in GridView local space.
var position: Vector2
var range_px: float
## Current barrel angle (radians, 0 = +X).
var aim_angle: float = 0.0
## Seconds until the next shot is allowed (<= 0 = ready).
var cooldown: float = 0.0
var target: Enemy = null
## Seconds until the next target scan is allowed (see CombatSystem.RETARGET_INTERVAL).
var retarget_timer: float = 0.0
## Stats (HUD info, tests, balancing).
var shots_fired: int = 0
var kills: int = 0
var damage_dealt: float = 0.0


func _init(p_placement: Placement, p_data: TurretData, p_position: Vector2, cell_size: int) -> void:
	placement = p_placement
	data = p_data
	position = p_position
	range_px = p_data.range_cells * cell_size
	aim_angle = -PI * 0.5 # barrels start pointing "north"
