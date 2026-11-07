class_name ConstructionService
extends RefCounted
## Single authority for building and removing structures.
## Every placement goes through `evaluate` first; a rejected build never
## touches credits, the grid or navigation. Navigation follows the grid by
## itself (NavGrid listens to GridModel), so this class never syncs it.
##
## Route rule: after a placement, every spawn must still reach the goal for
## every movement class of the mission, and every live enemy must still reach
## it from the cell it is walking to. Cells under enemies cannot be built on.

signal structure_built(placement: Placement)
signal structure_removed(placement: Placement, refund: int)

enum Reason {
	OK,
	NO_STRUCTURE,
	PHASE_LOCKED,
	OUT_OF_BOUNDS,
	TERRAIN_NOT_BUILDABLE,
	OCCUPIED,
	OCCUPIED_BY_UNIT,
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
	## Routes this placement would cut:
	## [{ "cell": Vector2i, "movement": int, "kind": "spawn" | "unit" }].
	var broken_routes: Array[Dictionary] = []
	var placement: Placement = null
	var refund: int = 0
	## Price for this placement right now (base cost + surcharge). Shown in
	## the preview and charged by build(): one number, no divergence.
	var cost: int = 0
	var surcharge: int = 0

	func is_ok() -> bool:
		return reason == 0


var build_enabled: bool = true
var removal_enabled: bool = true
## Extra fraction charged on new construction (set by GameSession: the level's
## combat surcharge during COMBAT, 0 otherwise).
var surcharge_ratio: float = 0.0

var _grid: GridModel
var _nav: NavGrid
var _wallet: Wallet
var _spawn_requirements: Array[Dictionary] = []
## Optional live units (EnemyRoster). Null = no units on the map.
var _units: EnemyRoster = null


func _init(
		grid: GridModel,
		nav: NavGrid,
		wallet: Wallet,
		spawns: Array[Vector2i],
		required_mask: int) -> void:
	_grid = grid
	_nav = nav
	_wallet = wallet
	for bit in MovementClass.ALL:
		if required_mask & bit:
			for spawn in spawns:
				_spawn_requirements.append({"cell": spawn, "movement": bit, "kind": "spawn"})


func set_units(units: EnemyRoster) -> void:
	_units = units


## Footprint origin for a structure centred under `cell` (useful for touch).
static func origin_for_cell(data: StructureData, cell: Vector2i) -> Vector2i:
	if data == null:
		return cell
	return cell - (data.footprint - Vector2i.ONE) / 2


## Current price of a structure, including any surcharge. Single source of truth
## for the HUD, the preview and the charge.
func price_of(data: StructureData) -> int:
	if data == null:
		return 0
	# Small epsilon so 100 x 1.25 = 125 never becomes 126 through float error.
	return ceili(data.cost * (1.0 + surcharge_ratio) - 0.0001)


## Read-only check. Safe to call every time the preview moves.
func evaluate(data: StructureData, origin: Vector2i) -> Check:
	var check := Check.new()
	check.data = data
	check.origin = origin
	if data == null:
		check.reason = Reason.NO_STRUCTURE
		return check
	check.cells = GridModel.footprint_cells(origin, data.footprint)
	check.cost = price_of(data)
	check.surcharge = check.cost - data.cost
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
	if _units != null and data.blocks_mask != MovementClass.NONE:
		var under_units := _units.occupied_cells()
		for cell in check.cells:
			if under_units.has(cell):
				check.reason = Reason.OCCUPIED_BY_UNIT
				return check
	if not _wallet.can_afford(check.cost):
		check.reason = Reason.INSUFFICIENT_CREDITS
		return check
	if data.blocks_mask != MovementClass.NONE:
		check.broken_routes = _nav.find_broken_routes(_route_requirements(), check.cells, data.blocks_mask)
		if not check.broken_routes.is_empty():
			check.reason = Reason.BLOCKS_ROUTE
			return check
	check.reason = Reason.OK
	return check


func build(data: StructureData, origin: Vector2i) -> Check:
	var check := evaluate(data, origin)
	if not check.is_ok():
		return check
	# Validation and payment happen in the same call with the same price; any
	# failure returns before the grid is touched, so a rejection costs nothing.
	if not _wallet.spend(check.cost):
		check.reason = Reason.INSUFFICIENT_CREDITS
		return check
	check.placement = _grid.add_placement(data, origin)
	check.placement.paid = check.cost
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
	_wallet.earn(check.refund)
	structure_removed.emit(placement, check.refund)
	check.reason = Reason.OK
	return check


## Current routes still valid? (Invariant check, used by tests and debug.)
func all_routes_open() -> bool:
	return _nav.find_broken_routes(_route_requirements()).is_empty()


func _route_requirements() -> Array[Dictionary]:
	if _units == null:
		return _spawn_requirements
	var reqs: Array[Dictionary] = []
	reqs.assign(_spawn_requirements)
	reqs.append_array(_units.route_requirements())
	return reqs


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
		Reason.OCCUPIED_BY_UNIT:
			return "Enemy units in the way."
		Reason.INSUFFICIENT_CREDITS:
			return "Insufficient credits."
		Reason.BLOCKS_ROUTE:
			var names := PackedStringArray()
			for route in check.broken_routes:
				var label := MovementClass.to_name(route["movement"]).to_upper()
				if not names.has(label):
					names.append(label)
			var trapped := false
			for route in check.broken_routes:
				trapped = trapped or route.get("kind", "") == "unit"
			if trapped:
				return "Would trap enemies on the field (%s)." % ", ".join(names)
			return "Blocks every route to the base for: %s." % ", ".join(names)
		Reason.NOTHING_TO_REMOVE:
			return "Nothing to remove here."
	return "Unknown construction error."
