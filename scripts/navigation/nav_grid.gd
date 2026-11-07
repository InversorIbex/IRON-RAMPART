class_name NavGrid
extends RefCounted
## Shared grid navigation towards the mission goal.
##
## One flow field per movement class: a BFS distance map from the goal over
## the cells that class can walk. Every enemy of a class reads the same field
## (`next_step`), so there are no per-enemy searches; fields are recomputed
## only when the topology changes. Route previews use the same fields, so the
## drawn route is exactly the route enemies follow. See docs/DECISIONS.md D-011.
##
## NavGrid listens to GridModel's placement signals, so it can never be out of
## sync with the grid, whoever mutates it.

signal topology_changed(version: int)

const UNREACHABLE := -1
const NO_CELL := Vector2i(-1, -1)
## Neighbour order is also the deterministic tie-break when several
## neighbours are equally close to the goal: horizontal moves first, which
## produces clean L-shaped routes instead of staircases.
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Incremented on every topology change. Cheap staleness check for caches.
var version: int = 0
var goal: Vector2i
## Total time spent rebuilding fields (microseconds), for profiling.
var rebuild_usec_total: int = 0
var rebuild_count: int = 0

var _grid: GridModel
var _w: int
var _h: int
var _walkable: Dictionary = {} # bit -> PackedByteArray (1 = walkable)
var _dist: Dictionary = {} # bit -> PackedInt32Array (steps to goal, UNREACHABLE)


func _init(grid: GridModel, p_goal: Vector2i) -> void:
	_grid = grid
	goal = p_goal
	_w = grid.width
	_h = grid.height
	for bit in MovementClass.ALL:
		var walk := PackedByteArray()
		walk.resize(_w * _h)
		_walkable[bit] = walk
	grid.placement_added.connect(_on_placement_changed)
	grid.placement_removed.connect(_on_placement_changed)
	rebuild()


## Full resync from the grid + all fields. O(cells x classes).
func rebuild() -> void:
	var cells: Array[Vector2i] = []
	for y in _h:
		for x in _w:
			cells.append(Vector2i(x, y))
	_sync_cells(cells)
	_recompute_fields()


# --- Queries -----------------------------------------------------------------

func is_walkable(bit: int, cell: Vector2i) -> bool:
	if not _in_bounds(cell) or not _walkable.has(bit):
		return false
	return (_walkable[bit] as PackedByteArray)[_idx(cell)] == 1


## Steps from `cell` to the goal for this class, or UNREACHABLE.
func distance(bit: int, cell: Vector2i) -> int:
	if not _in_bounds(cell) or not _dist.has(bit):
		return UNREACHABLE
	return (_dist[bit] as PackedInt32Array)[_idx(cell)]


func can_reach_goal(bit: int, cell: Vector2i) -> bool:
	return distance(bit, cell) != UNREACHABLE


## Next cell towards the goal. Returns `cell` itself at the goal and NO_CELL
## if the goal is unreachable from `cell`.
func next_step(bit: int, cell: Vector2i) -> Vector2i:
	var d := distance(bit, cell)
	if d == UNREACHABLE:
		return NO_CELL
	if d == 0:
		return cell
	var field: PackedInt32Array = _dist[bit]
	for dir in DIRS:
		var n: Vector2i = cell + dir
		if _in_bounds(n) and field[_idx(n)] == d - 1:
			return n
	return NO_CELL # unreachable in a consistent field


## Full route from `from` to the goal (both included). Empty if unreachable.
func path_to_goal(bit: int, from: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not can_reach_goal(bit, from):
		return path
	var cell := from
	path.append(cell)
	while cell != goal:
		cell = next_step(bit, cell)
		if cell == NO_CELL:
			path.clear()
			return path
		path.append(cell)
	return path


## Which of `requirements` would lose their route to the goal?
## requirements: [{ "cell": Vector2i, "movement": int, ... }] — extra keys are kept.
## `extra_blocked_cells` are treated as blocked for the classes in
## `extra_blocked_mask` (a "what if I build here" simulation). The live fields
## are never modified: affected classes get a temporary field.
func find_broken_routes(
		requirements: Array,
		extra_blocked_cells: Array[Vector2i] = [],
		extra_blocked_mask: int = 0) -> Array[Dictionary]:
	var fields := {}
	for bit in MovementClass.ALL:
		if (extra_blocked_mask & bit) != 0 and not extra_blocked_cells.is_empty():
			var walk: PackedByteArray = (_walkable[bit] as PackedByteArray).duplicate()
			for cell in extra_blocked_cells:
				if _in_bounds(cell):
					walk[_idx(cell)] = 0
			fields[bit] = _bfs(walk)
		else:
			fields[bit] = _dist[bit]
	var broken: Array[Dictionary] = []
	for req in requirements:
		var cell: Vector2i = req["cell"]
		var field: PackedInt32Array = fields[req["movement"]]
		if not _in_bounds(cell) or field[_idx(cell)] == UNREACHABLE:
			broken.append(req)
	return broken


# --- Internals ---------------------------------------------------------------

func _on_placement_changed(placement: Placement) -> void:
	_sync_cells(placement.cells)
	_recompute_fields()


func _sync_cells(cells: Array[Vector2i]) -> void:
	# Packed arrays are copy-on-write values: read, modify, store back.
	for bit in MovementClass.ALL:
		var walk: PackedByteArray = _walkable[bit]
		for cell in cells:
			walk[_idx(cell)] = 0 if (_grid.blocking_mask_at(cell) & bit) != 0 else 1
		_walkable[bit] = walk


func _recompute_fields() -> void:
	var t0 := Time.get_ticks_usec()
	for bit in MovementClass.ALL:
		_dist[bit] = _bfs(_walkable[bit])
	rebuild_usec_total += Time.get_ticks_usec() - t0
	rebuild_count += 1
	version += 1
	topology_changed.emit(version)


## Breadth-first distances from the goal over walkable cells.
func _bfs(walk: PackedByteArray) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(_w * _h)
	dist.fill(UNREACHABLE)
	var g := _idx(goal)
	if walk[g] == 0:
		return dist
	var queue := PackedInt32Array()
	queue.resize(_w * _h)
	var head := 0
	var tail := 0
	queue[tail] = g
	tail += 1
	dist[g] = 0
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % _w
		var y := i / _w
		var nd := dist[i] + 1
		# Inlined neighbours (hot loop): E, W, S, N.
		if x + 1 < _w and walk[i + 1] == 1 and dist[i + 1] == UNREACHABLE:
			dist[i + 1] = nd
			queue[tail] = i + 1
			tail += 1
		if x > 0 and walk[i - 1] == 1 and dist[i - 1] == UNREACHABLE:
			dist[i - 1] = nd
			queue[tail] = i - 1
			tail += 1
		if y + 1 < _h and walk[i + _w] == 1 and dist[i + _w] == UNREACHABLE:
			dist[i + _w] = nd
			queue[tail] = i + _w
			tail += 1
		if y > 0 and walk[i - _w] == 1 and dist[i - _w] == UNREACHABLE:
			dist[i - _w] = nd
			queue[tail] = i - _w
			tail += 1
	return dist


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _w and cell.y < _h


func _idx(cell: Vector2i) -> int:
	return cell.y * _w + cell.x
