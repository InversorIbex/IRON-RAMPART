class_name GridView
extends Node2D
## Placeholder renderer for the battlefield: terrain, structures, spawn/base
## markers, live enemy routes per movement class and the build preview.
## Reads GameSession state; never mutates it. All art here is temporary
## procedural drawing, to be replaced by TileMapLayer + sprites (docs/ART_DIRECTION.md).

## Route colours/offsets per movement class, so split routes are readable.
const ROUTE_STYLE := {
	MovementClass.INFANTRY: {"color": Palette.SANDSTONE, "offset": Vector2(-7, -7)},
	MovementClass.WHEELED: {"color": Palette.TACTICAL_GOLD, "offset": Vector2(0, 0)},
	MovementClass.TRACKED: {"color": Palette.ALERT_RED, "offset": Vector2(7, 7)},
}

var session: GameSession
var show_routes: bool = true

var _routes: Array = [] # [{ "movement": int, "points": PackedVector2Array }]
var _ghost: ConstructionService.Check = null
var _remove_cell: Vector2i = Vector2i(-1, -1)
var _remove_armed: bool = false


func bind(p_session: GameSession) -> void:
	session = p_session
	session.nav.topology_changed.connect(_on_topology_changed)
	_recompute_routes()
	queue_redraw()


func set_ghost(check: ConstructionService.Check) -> void:
	_ghost = check
	queue_redraw()


func set_remove_cursor(cell: Vector2i, armed: bool) -> void:
	_remove_cell = cell
	_remove_armed = armed
	queue_redraw()


func clear_cursor() -> void:
	_ghost = null
	_remove_cell = Vector2i(-1, -1)
	_remove_armed = false
	queue_redraw()


func _on_topology_changed(_version: int) -> void:
	_recompute_routes()
	queue_redraw()


func _recompute_routes() -> void:
	_routes.clear()
	var level := session.level
	for bit in MovementClass.ALL:
		if (level.movement_mask & bit) == 0:
			continue
		for spawn in level.spawn_cells:
			var path := session.nav.path_to_goal(bit, spawn)
			var points := PackedVector2Array()
			for cell in path:
				points.append(session.grid.cell_to_local(cell) + ROUTE_STYLE[bit]["offset"])
			_routes.append({"movement": bit, "points": points})


func _draw() -> void:
	if session == null:
		return
	_draw_terrain()
	_draw_grid_lines()
	_draw_markers()
	_draw_structures()
	if show_routes:
		_draw_routes()
	_draw_ghost()
	_draw_remove_cursor()


func _draw_terrain() -> void:
	var grid := session.grid
	draw_rect(Rect2(Vector2.ZERO, grid.size_in_pixels()), Palette.TERRAIN_GROUND)
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x, y)
			var rect := grid.cell_rect(cell)
			match grid.terrain_at(cell):
				Terrain.ROCK:
					draw_rect(rect, Palette.TERRAIN_ROCK)
					draw_rect(rect.grow(-10), Palette.TERRAIN_ROCK.lightened(0.12))
				Terrain.ROAD, Terrain.SPAWN:
					draw_rect(rect, Palette.TERRAIN_ROAD)
				Terrain.BASE:
					draw_rect(rect, Palette.MILITARY_GREEN.darkened(0.2))


func _draw_grid_lines() -> void:
	var grid := session.grid
	var size := grid.size_in_pixels()
	for x in grid.width + 1:
		draw_line(Vector2(x * grid.cell_size, 0), Vector2(x * grid.cell_size, size.y), Palette.GRID_LINE, 1.0)
	for y in grid.height + 1:
		draw_line(Vector2(0, y * grid.cell_size), Vector2(size.x, y * grid.cell_size), Palette.GRID_LINE, 1.0)


func _draw_markers() -> void:
	var grid := session.grid
	var font := ThemeDB.fallback_font
	for spawn in session.level.spawn_cells:
		var rect := grid.cell_rect(spawn)
		draw_rect(rect.grow(-4), Palette.ALERT_RED, false, 4.0)
		draw_string(font, rect.position + Vector2(8, grid.cell_size * 0.62), "IN",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Palette.ALERT_RED)
	# Base: outline around all base cells + HQ label.
	var base_rect := grid.cell_rect(session.level.base_cells[0])
	for c in session.level.base_cells:
		base_rect = base_rect.merge(grid.cell_rect(c))
	draw_rect(base_rect.grow(-4), Palette.TACTICAL_GOLD, false, 5.0)
	draw_string(font, base_rect.position + Vector2(0, base_rect.size.y * 0.5 + 10), "HQ",
			HORIZONTAL_ALIGNMENT_CENTER, base_rect.size.x, 32, Palette.TACTICAL_GOLD)


func _draw_structures() -> void:
	for placement in session.grid.get_placements():
		_draw_structure_shape(placement.data, placement.cells, 1.0)


## Placeholder silhouettes, chosen so each barrier type is distinguishable.
func _draw_structure_shape(data: StructureData, cells: Array[Vector2i], alpha: float) -> void:
	var grid := session.grid
	var col := Color(data.placeholder_color, alpha)
	var shadow := Color(0, 0, 0, 0.3 * alpha)
	for cell in cells:
		var r := grid.cell_rect(cell).grow(-5)
		match data.id:
			&"sandbags":
				for i in 3:
					var bag := Rect2(r.position + Vector2(0, i * r.size.y / 3.0), Vector2(r.size.x, r.size.y / 3.0 - 3))
					draw_rect(Rect2(bag.position + Vector2(2, 3), bag.size), shadow)
					draw_rect(bag, col)
			&"antitank_barrier":
				var c := r.get_center()
				var h := r.size.x * 0.38
				draw_line(c + Vector2(-h, -h) + Vector2(3, 3), c + Vector2(h, h) + Vector2(3, 3), shadow, 9.0)
				draw_line(c + Vector2(-h, -h), c + Vector2(h, h), col, 8.0)
				draw_line(c + Vector2(h, -h), c + Vector2(-h, h), col, 8.0)
				draw_circle(c, 6.0, Color(Palette.SANDSTONE, alpha))
			_:
				draw_rect(Rect2(r.position + Vector2(3, 4), r.size), shadow)
				draw_rect(r, col)
				draw_rect(r.grow(-8), col.darkened(0.15), false, 2.0)


func _draw_routes() -> void:
	for route in _routes:
		var points: PackedVector2Array = route["points"]
		if points.size() < 2:
			continue
		var color: Color = ROUTE_STYLE[route["movement"]]["color"]
		draw_polyline(points, Color(color, 0.75), 3.0)
		# Direction chevrons every few cells.
		for i in range(1, points.size() - 1, 3):
			var dir := (points[i + 1] - points[i]).normalized()
			var side := Vector2(-dir.y, dir.x)
			var tip := points[i] + dir * 8.0
			draw_line(tip, tip - dir * 10.0 + side * 7.0, color, 3.0)
			draw_line(tip, tip - dir * 10.0 - side * 7.0, color, 3.0)


func _draw_ghost() -> void:
	if _ghost == null or _ghost.data == null:
		return
	var ok := _ghost.is_ok()
	var tint := Palette.VALID if ok else Palette.ALERT_RED
	var grid := session.grid
	for cell in _ghost.cells:
		if not grid.is_in_bounds(cell):
			continue
		var rect := grid.cell_rect(cell)
		draw_rect(rect, Color(tint, 0.35))
		draw_rect(rect.grow(-2), tint, false, 3.0)
	if ok or _ghost.reason == ConstructionService.Reason.BLOCKS_ROUTE \
			or _ghost.reason == ConstructionService.Reason.INSUFFICIENT_CREDITS:
		var in_bounds: Array[Vector2i] = []
		for cell in _ghost.cells:
			if grid.is_in_bounds(cell):
				in_bounds.append(cell)
		_draw_structure_shape(_ghost.data, in_bounds, 0.55)
	if not ok:
		for cell in _ghost.cells:
			if grid.is_in_bounds(cell):
				var r := grid.cell_rect(cell).grow(-14)
				draw_line(r.position, r.end, Palette.ALERT_RED, 4.0)
				draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Palette.ALERT_RED, 4.0)
	# Explain route blocks visually: flag every spawn/unit that would be cut off.
	for route in _ghost.broken_routes:
		var rect := grid.cell_rect(route["cell"]).grow(4)
		draw_rect(rect, Color(Palette.ALERT_RED, 0.35))
		draw_rect(rect, Palette.ALERT_RED, false, 5.0)


func _draw_remove_cursor() -> void:
	if not session.grid.is_in_bounds(_remove_cell):
		return
	var placement := session.grid.get_placement_at(_remove_cell)
	var cells: Array[Vector2i] = [_remove_cell]
	if placement != null:
		cells = placement.cells
	var color := Palette.ALERT_RED if _remove_armed else Palette.TACTICAL_GOLD
	for cell in cells:
		var rect := session.grid.cell_rect(cell)
		draw_rect(rect, Color(color, 0.25 if placement != null else 0.1))
		draw_rect(rect.grow(-2), color, false, 4.0 if _remove_armed else 2.0)
