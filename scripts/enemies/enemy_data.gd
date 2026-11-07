class_name EnemyData
extends Resource
## Data definition of an enemy type. Instances: data/enemies/*.tres,
## registered in EnemyCatalog. Behaviour lives in Enemy/EnemyRoster.

## Placeholder silhouette used by EnemyView until real sprites exist.
enum Silhouette { SOLDIER, WHEELED_VEHICLE, TRACKED_VEHICLE }

@export var id: StringName = &""
@export var display_name: String = ""
## Exactly one MovementClass bit: decides which flow field the unit follows.
@export_enum("Infantry:1", "Wheeled:2", "Tracked:4") var movement: int = MovementClass.INFANTRY
@export_range(1, 100000) var max_hp: int = 100
## Cells per second.
@export_range(0.05, 20.0) var speed: float = 1.0
## Fraction of incoming damage absorbed (0 = none, 0.9 = 90 %).
## Milestone 3 will add damage types; this stays the generic resistance.
@export_range(0.0, 0.9) var armor: float = 0.0
## HQ damage when the unit reaches the base.
@export_range(0, 1000) var base_damage: int = 1
## Credits awarded when the unit is destroyed.
@export_range(0, 10000) var reward: int = 5
@export var silhouette: Silhouette = Silhouette.SOLDIER
## Visual footprint in cells (x = length along heading, y = width).
@export var visual_size: Vector2 = Vector2(0.35, 0.35)
@export var placeholder_color: Color = Color.WHITE
@export var sprite: Texture2D


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("enemy has an empty id")
	if display_name.is_empty():
		errors.append("enemy '%s' has no display_name" % id)
	if not MovementClass.ALL.has(movement):
		errors.append("enemy '%s' must have exactly one movement class (got %d)" % [id, movement])
	if max_hp <= 0:
		errors.append("enemy '%s' has max_hp <= 0" % id)
	if speed <= 0.0:
		errors.append("enemy '%s' has speed <= 0" % id)
	if armor < 0.0 or armor > 0.9:
		errors.append("enemy '%s' armor outside [0, 0.9]" % id)
	if base_damage < 0 or reward < 0:
		errors.append("enemy '%s' has negative base_damage or reward" % id)
	return errors
