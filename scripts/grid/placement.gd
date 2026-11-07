class_name Placement
extends RefCounted
## One structure instance placed on the grid (pure data, no visuals).

var id: int
var data: StructureData
var origin: Vector2i
var cells: Array[Vector2i] = []
var hp: int
## Credits actually paid (base cost + combat surcharge, if any).
var paid: int = 0


func _init(p_id: int, p_data: StructureData, p_origin: Vector2i, p_cells: Array[Vector2i]) -> void:
	id = p_id
	data = p_data
	origin = p_origin
	cells = p_cells
	hp = p_data.max_hp
