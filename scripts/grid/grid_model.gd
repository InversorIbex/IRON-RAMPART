class_name GridModel
extends RefCounted
## Logical map: static terrain + player structure occupancy.
## Pure data — knows nothing about rendering or pathfinding.
## Coordinates: cell (x, y) covers local rect [x*cell_size, (x+1)*cell_size).
## "Local" means the GridView's local space; the view applies offset/scale.

signal placement_added(placement: Placement)
signal placement_removed(placement: Placement)

var width: int
var height: int
var cell_size: int

var _terrain: PackedByteArray
var _occupancy: Dictionary = {} # Vector2i -> Placement
var _placements: Dictionary = {} # int -> Placement
var _next_id: int = 1


func _init(level: LevelData) -> void:
	width = level.width
	height = level.height
	cell_size = level.cell_size
	_terrain = level.terrain.duplicate()


# --- Coordinates -------------------------------------------------------------

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func local_to_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(floori(local_pos.x / cell_size), floori(local_pos.y / cell_size))


## Centre of the cell in local space.
func cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell.x * cell_size, cell.y * cell_size), Vector2(cell_size, cell_size))


func size_in_pixels() -> Vector2:
	return Vector2(width * cell_size, height * cell_size)


static func footprint_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells


# --- Queries -----------------------------------------------------------------

func terrain_at(cell: Vector2i) -> int:
	return _terrain[cell.y * width + cell.x]


func is_buildable_terrain(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and Terrain.is_buildable(terrain_at(cell))


func is_occupied(cell: Vector2i) -> bool:
	return _occupancy.has(cell)


func get_placement_at(cell: Vector2i) -> Placement:
	return _occupancy.get(cell, null)


func get_placements() -> Array:
	return _placements.values()


func placement_count() -> int:
	return _placements.size()


## Movement classes that cannot enter `cell` (terrain + structure).
func blocking_mask_at(cell: Vector2i) -> int:
	var mask := Terrain.blocks_mask(terrain_at(cell))
	var placement: Placement = _occupancy.get(cell, null)
	if placement != null:
		mask |= placement.data.blocks_mask
	return mask


# --- Mutation (callers must validate first: see ConstructionService) ---------

func add_placement(data: StructureData, origin: Vector2i) -> Placement:
	var cells := footprint_cells(origin, data.footprint)
	for cell in cells:
		assert(is_in_bounds(cell) and not is_occupied(cell), "add_placement on invalid cell %s" % cell)
	var placement := Placement.new(_next_id, data, origin, cells)
	_next_id += 1
	_placements[placement.id] = placement
	for cell in cells:
		_occupancy[cell] = placement
	placement_added.emit(placement)
	return placement


func remove_placement(placement: Placement) -> void:
	if not _placements.has(placement.id):
		return
	_placements.erase(placement.id)
	for cell in placement.cells:
		_occupancy.erase(cell)
	placement_removed.emit(placement)
