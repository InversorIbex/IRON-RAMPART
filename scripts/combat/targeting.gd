class_name Targeting
extends RefCounted
## Deterministic target selection (pure function, O(enemies) per call).
## Ties are broken by lowest enemy id, so results never depend on timing.

enum Priority {
	FIRST, ## most advanced towards the base (real route distance, flow field)
	CLOSEST, ## nearest to the turret
	STRONGEST, ## highest current HP (armour hunters)
}

## Target layers (bit flags). Ground units today; AIR is ready for aircraft.
const GROUND := 1
const AIR := 2


## Remaining route length to the base in cells (lower = more advanced).
static func remaining_cells(enemy: Enemy, nav: NavGrid) -> float:
	var d := nav.distance(enemy.movement, enemy.next_cell)
	if d == NavGrid.UNREACHABLE:
		return INF
	return d + (1.0 - enemy.progress) if enemy.next_cell != enemy.cell else float(d)


static func can_target(enemy: Enemy, layers: int, origin: Vector2, range_px: float) -> bool:
	return enemy.is_alive() \
			and (enemy.data.target_layer & layers) != 0 \
			and origin.distance_squared_to(enemy.position) <= range_px * range_px


static func select(
		origin: Vector2,
		range_px: float,
		layers: int,
		priority: int,
		enemies: Array[Enemy],
		nav: NavGrid) -> Enemy:
	var best: Enemy = null
	var best_key := INF
	for enemy in enemies:
		if not can_target(enemy, layers, origin, range_px):
			continue
		var key: float
		match priority:
			Priority.CLOSEST:
				key = origin.distance_squared_to(enemy.position)
			Priority.STRONGEST:
				key = -enemy.hp
			_:
				key = remaining_cells(enemy, nav)
		if best == null or key < best_key or (key == best_key and enemy.id < best.id):
			best = enemy
			best_key = key
	return best
