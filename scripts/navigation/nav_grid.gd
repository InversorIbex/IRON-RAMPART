class_name NavGrid
extends RefCounted
## Grid navigation. One AStarGrid2D per movement class, kept in sync with
## GridModel. Paths are recomputed only on demand; `topology_changed` tells
## consumers (route preview, enemies in Milestone 2) when to re-query.
## See docs/DECISIONS.md (D-004) for why AStarGrid2D.

signal topology_changed(version: int)

## Incremented on every topology change. Cheap staleness check for caches.
var version: int = 0

var _grid: GridModel
var _layers: Dictionary = {} # int (MovementClass bit) -> AStarGrid2D


func _init(grid: GridModel) -> void:
	_grid = grid
	for bit in MovementClass.ALL:
		var astar := AStarGrid2D.new()
		astar.region = Rect2i(0, 0, grid.width, grid.height)
		astar.cell_size = Vector2(grid.cell_size, grid.cell_size)
		# Orthogonal only: classic maze TD, no corner-cutting through walls.
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.update()
		_layers[bit] = astar
	rebuild()


## Full resync from the grid. O(cells). Use on load; prefer `refresh_cells`.
func rebuild() -> void:
	for y in _grid.height:
		for x in _grid.width:
			_sync_cell(Vector2i(x, y))
	_bump()


## Resync only the given cells (after a build or removal).
func refresh_cells(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_sync_cell(cell)
	_bump()


func is_walkable(bit: int, cell: Vector2i) -> bool:
	var astar: AStarGrid2D = _layers.get(bit)
	return astar != null and astar.is_in_boundsv(cell) and not astar.is_point_solid(cell)


## Cell path from `from` to `to` (both included). Empty if unreachable.
func find_path(bit: int, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_walkable(bit, from) or not is_walkable(bit, to):
		return empty
	var astar: AStarGrid2D = _layers[bit]
	return astar.get_id_path(from, to)


func has_path(bit: int, from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return is_walkable(bit, from)
	return not find_path(bit, from, to).is_empty()


## Returns every (spawn, movement class) pair that has no route to `goal`.
## If `extra_blocked_cells` is given, they are treated as blocked for the
## classes in `extra_blocked_mask` — a "what if I build here" simulation.
## The navigation state is always restored before returning.
## Each entry: { "spawn": Vector2i, "movement": int }.
func find_broken_routes(
		spawns: Array[Vector2i],
		goal: Vector2i,
		required_mask: int,
		extra_blocked_cells: Array[Vector2i] = [],
		extra_blocked_mask: int = 0) -> Array[Dictionary]:
	var saved := {} # Vector3i(x, y, bit) -> previous solid state
	for bit in MovementClass.ALL:
		if (extra_blocked_mask & bit) == 0:
			continue
		var astar: AStarGrid2D = _layers[bit]
		for cell in extra_blocked_cells:
			if not astar.is_in_boundsv(cell):
				continue
			saved[Vector3i(cell.x, cell.y, bit)] = astar.is_point_solid(cell)
			astar.set_point_solid(cell, true)

	var broken: Array[Dictionary] = []
	for bit in MovementClass.ALL:
		if (required_mask & bit) == 0:
			continue
		for spawn in spawns:
			if not has_path(bit, spawn, goal):
				broken.append({"spawn": spawn, "movement": bit})

	for key in saved:
		var astar: AStarGrid2D = _layers[key.z]
		astar.set_point_solid(Vector2i(key.x, key.y), saved[key])
	return broken


func _sync_cell(cell: Vector2i) -> void:
	var mask := _grid.blocking_mask_at(cell)
	for bit in MovementClass.ALL:
		var astar: AStarGrid2D = _layers[bit]
		astar.set_point_solid(cell, (mask & bit) != 0)


func _bump() -> void:
	version += 1
	topology_changed.emit(version)
