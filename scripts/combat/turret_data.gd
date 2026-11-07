class_name TurretData
extends Resource
## Weapon definition of a turret (data/turrets/*.tres). Placement data (cost,
## HP, footprint, blocking) stays in the StructureData that references it,
## so turrets reuse construction, route validation and navigation unchanged.

enum ProjectileKind { BULLET, MISSILE, FLAK }
## Placeholder weapon drawing used by TurretView.
enum Silhouette { TWIN_MG, MISSILE_POD, AA_TWIN_CANNON }

@export var id: StringName = &""
@export var damage: float = 10.0
@export var damage_type: Damage.Type = Damage.Type.BULLET
## Seconds between shots (cadence = 1 / fire_interval).
@export_range(0.02, 30.0) var fire_interval: float = 0.5
## Range in cells, measured from the turret centre to the enemy position.
@export_range(0.5, 20.0) var range_cells: float = 3.0
@export var projectile: ProjectileKind = ProjectileKind.BULLET
## Projectile speed in cells per second (homing; always reaches a live target).
@export_range(0.5, 100.0) var projectile_speed: float = 20.0
## Explosion radius in cells. 0 = direct hit only.
@export_range(0.0, 5.0) var splash_radius_cells: float = 0.0
## Damage fraction for units in the blast that were not the direct target.
@export_range(0.0, 1.0) var splash_falloff: float = 0.5
## Targeting.GROUND / Targeting.AIR bits this weapon may engage.
@export_flags("Ground", "Air") var target_layers: int = Targeting.GROUND
@export var priority: Targeting.Priority = Targeting.Priority.FIRST
## Barrel traverse speed (degrees/s) and max misalignment to open fire.
@export_range(10.0, 3600.0) var turn_speed_deg: float = 360.0
@export_range(0.5, 180.0) var aim_tolerance_deg: float = 10.0
@export var silhouette: Silhouette = Silhouette.TWIN_MG


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("turret has an empty id")
	if damage <= 0.0:
		errors.append("turret '%s' damage must be > 0" % id)
	if fire_interval <= 0.0:
		errors.append("turret '%s' fire_interval must be > 0" % id)
	if range_cells <= 0.0:
		errors.append("turret '%s' range must be > 0" % id)
	if projectile_speed <= 0.0:
		errors.append("turret '%s' projectile_speed must be > 0" % id)
	if target_layers == 0:
		errors.append("turret '%s' cannot target any layer" % id)
	if projectile == ProjectileKind.MISSILE and splash_radius_cells <= 0.0:
		errors.append("turret '%s': missiles need a splash radius" % id)
	return errors


func shots_per_second() -> float:
	return 1.0 / fire_interval
