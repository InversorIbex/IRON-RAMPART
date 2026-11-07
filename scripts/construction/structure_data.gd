class_name StructureData
extends Resource
## Data definition of anything the player can place on the grid
## (barriers now; turrets and support buildings reuse it later).
## Instances live in data/structures/*.tres and are registered in StructureCatalog.

enum Category { BARRIER, TURRET, SUPPORT }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.BARRIER
@export_range(0, 100000) var cost: int = 0
@export_range(1, 100000) var max_hp: int = 100
## Size in cells. The anchor (origin) is the top-left cell.
@export var footprint: Vector2i = Vector2i.ONE
## Movement classes this structure stops (see MovementClass). 0 = walkable.
@export_flags("Infantry", "Wheeled", "Tracked") var blocks_mask: int = 7
## Fraction of `cost` returned when the player removes it.
@export_range(0.0, 1.0) var refund_ratio: float = 0.75
## Colour used by the placeholder renderer until real sprites exist.
@export var placeholder_color: Color = Color.WHITE
## Optional final sprite. When null, the placeholder renderer is used.
@export var sprite: Texture2D


## Returns a list of human-readable problems. Empty list = valid.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("structure has an empty id")
	if display_name.is_empty():
		errors.append("structure '%s' has no display_name" % id)
	if cost < 0:
		errors.append("structure '%s' has negative cost" % id)
	if max_hp <= 0:
		errors.append("structure '%s' has max_hp <= 0" % id)
	if footprint.x < 1 or footprint.y < 1:
		errors.append("structure '%s' has invalid footprint %s" % [id, footprint])
	if blocks_mask < 0 or blocks_mask > MovementClass.ALL_GROUND:
		errors.append("structure '%s' has invalid blocks_mask %d" % [id, blocks_mask])
	if refund_ratio < 0.0 or refund_ratio > 1.0:
		errors.append("structure '%s' has refund_ratio outside [0, 1]" % id)
	return errors


func refund_amount() -> int:
	return int(floor(cost * refund_ratio))
