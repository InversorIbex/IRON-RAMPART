class_name Enemy
extends RefCounted
## One enemy on the field (pure state, no node). Moved by EnemyRoster.
##
## Movement model: the unit always travels from the centre of `cell` to the
## centre of `next_cell`; `progress` in [0, 1) is how far along that segment
## it is. That segment is committed (construction refuses both cells), so
## route changes take effect at the next cell centre: smooth, no teleports,
## no walking through walls.

enum State { MOVING, BLOCKED, ARRIVED, DEAD }

var id: int
var data: EnemyData
var movement: int
var hp: float
## Per-unit stats after wave modifiers (EnemyData stays shared and untouched).
var max_hp: float
var speed: float
var state: int = State.MOVING
var cell: Vector2i
var next_cell: Vector2i
var progress: float = 0.0
## Local-space position (GridView space), updated by the roster.
var position: Vector2 = Vector2.ZERO
## Unit vector of the current segment (for rendering/turret aiming later).
var heading: Vector2 = Vector2.RIGHT
## Seconds alive; cells walked (stats, tests, "most advanced" targeting).
var age: float = 0.0
var cells_walked: int = 0
## Incremented on every damaging hit (views use it for hit flashes).
var hits_taken: int = 0


func _init(p_id: int, p_data: EnemyData, spawn_cell: Vector2i,
		hp_multiplier: float = 1.0, speed_multiplier: float = 1.0) -> void:
	id = p_id
	data = p_data
	movement = p_data.movement
	max_hp = p_data.max_hp * hp_multiplier
	speed = p_data.speed * speed_multiplier
	hp = max_hp
	cell = spawn_cell
	next_cell = spawn_cell


func is_alive() -> bool:
	return state == State.MOVING or state == State.BLOCKED


## Damage after armour (see Damage). Returns the damage actually applied.
## Only EnemyRoster.damage() should call this, so death/rewards stay consistent.
func apply_damage(amount: float, type: int = Damage.Type.GENERIC) -> float:
	if not is_alive() or amount <= 0.0:
		return 0.0
	var dealt := Damage.compute(amount, type, data.armor_class)
	hp -= dealt
	hits_taken += 1
	return dealt
