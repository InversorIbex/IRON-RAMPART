class_name ConstructionService
extends RefCounted
## Single authority for building and removing structures.
## Every placement goes through `evaluate` first; a rejected build never
## touches credits, the grid or navigation.

signal structure_built(placement: Placement)
signal structure_removed(placement: Placement, refund: int)

enum Reason {
	OK,
	NO_STRUCTURE,
	PHASE_LOCKED,
	OUT_OF_BOUNDS,
	TERRAIN_NOT_BUILDABLE,
	OCCUPIED,
	INSUFFICIENT_CREDITS,
	BLOCKS_ROUTE,
	NOTHING_TO_REMOVE,
}


## Outcome of an evaluate/build/remove call.
class Check:
	extends RefCounted
	var reason: int = 0 # ConstructionService.Reason
	var data: StructureData = null
	var origin: Vector2i = Vector2i.ZERO
	var cells: Array[Vector2i] = []
	## Routes that this placement would cut: [{ "spawn": Vector2i, "movement": int }].
	var broken_routes: Array[Dictionary] = []
	var placement: Placement = null
	var refund: int = 0

	func is_ok() -> bool:
		return reason == 0


var build_enabled: bool = true
var removal_enabled: bool = true

var _grid: GridModel
var _nav: NavGrid
var _wallet: Wallet
var _spawns: Array[Vector2i] = []
var _goal: Vector2i
var _required_mask: int


func _init(
		grid: GridModel,
		nav: NavGrid,
		wallet: Wallet,
		spawns: Array[Vector2i],
		goal: Vector2i,
		required_mask: int) -> void:
	_grid = grid
	_nav = nav
	_wallet = wallet
	_spawns.assign(spawns)
	_goal = goal
	_required_mask = required_mask


## Footprint origin for a structure centred under `cell` (useful for touch).
static func origin_for_cell(data: StructureData, cell: Vector2i) -> Vector2i:
	if data == null:
		return cell
	return cell - (data.footprint - Vector2i.ONE) / 2


## Read-only check. Safe to call every time the preview moves.
func evaluate(data: StructureData, origin: Vector2i) -> Check:
	var check := Check.new()
	check.data = data
	check.origin = origin
	if data == null:
		check.reason = Reason.NO_STRUCTURE
		return check
	check.cells = GridModel.footprint_cells(origin, data.footprint)
	if not build_enabled:
		check.reason = Reason.PHASE_LOCKED
		return check
	for cell in check.cells:
		if not _grid.is_in_bounds(cell):
			check.reason = Reason.OUT_OF_BOUNDS
			return check
	for cell in check.cells:
		if not _grid.is_buildable_terrain(cell):
			check.reason = Reason.TERRAIN_NOT_BUILDABLE
			return check
	for cell in check.cells:
		if _grid.is_occupied(cell):
			check.reason = Reason.OCCUPIED
			return check
	if not _wallet.can_afford(data.cost):
		check.reason = Reason.INSUFFICIENT_CREDITS
		return check
	if data.blocks_mask != MovementClass.NONE:
		check.broken_routes = _nav.find_broken_routes(
				_spawns, _goal, _required_mask, check.cells, data.blocks_mask)
		if not check.broken_routes.is_empty():
			check.reason = Reason.BLOCKS_ROUTE
			return check
	check.reason = Reason.OK
	return check


func build(data: StructureData, origin: Vector2i) -> Check:
	var check := evaluate(data, origin)
	if not check.is_ok():
		return check
	if not _wallet.spend(data.cost):
		check.reason = Reason.INSUFFICIENT_CREDITS
		return check
	check.placement = _grid.add_placement(data, origin)
	_nav.refresh_cells(check.cells)
	structure_built.emit(check.placement)
	return check


func remove_at(cell: Vector2i) -> Check:
	var check := Check.new()
	check.origin = cell
	if not removal_enabled:
		check.reason = Reason.PHASE_LOCKED
		return check
	var placement: Placement = null
	if _grid.is_in_bounds(cell):
		placement = _grid.get_placement_at(cell)
	if placement == null:
		check.reason = Reason.NOTHING_TO_REMOVE
		return check
	check.data = placement.data
	check.cells = placement.cells
	check.placement = placement
	check.refund = placement.data.refund_amount()
	_grid.remove_placement(placement)
	_nav.refresh_cells(placement.cells)
	_wallet.earn(check.refund)
	structure_removed.emit(placement, check.refund)
	check.reason = Reason.OK
	return check


## Current routes still valid? (Invariant check, used by tests and debug.)
func all_routes_open() -> bool:
	return _nav.find_broken_routes(_spawns, _goal, _required_mask).is_empty()


static func reason_text(check: Check) -> String:
	match check.reason:
		Reason.OK:
			return "Ready to build."
		Reason.NO_STRUCTURE:
			return "Select a structure first."
		Reason.PHASE_LOCKED:
			return "Not allowed during this phase."
		Reason.OUT_OF_BOUNDS:
			return "Outside the battlefield."
		Reason.TERRAIN_NOT_BUILDABLE:
			return "Cannot build on this terrain."
		Reason.OCCUPIED:
			return "Cell already occupied."
		Reason.INSUFFICIENT_CREDITS:
			return "Insufficient credits."
		Reason.BLOCKS_ROUTE:
			var names := PackedStringArray()
			for route in check.broken_routes:
				var label := MovementClass.to_name(route["movement"]).to_upper()
				if not names.has(label):
					names.append(label)
			return "Blocks every route to the base for: %s." % ", ".join(names)
		Reason.NOTHING_TO_REMOVE:
			return "Nothing to remove here."
	return "Unknown construction error."
