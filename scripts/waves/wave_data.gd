class_name WaveData
extends RefCounted
## One wave of a mission (parsed and validated by LevelLoader from the
## mission JSON). Immutable at runtime: WaveManager only reads it, so the same
## LevelData can be replayed any number of times.

## Spawn selector: a spawn index, or ALTERNATE to cycle through all spawns.
const ALTERNATE := -1

## Completion conditions. Only one today; the field exists so missions can
## declare others later without changing the format.
const COMPLETE_ALL_CLEARED := "all_spawned_and_cleared"


class Group:
	extends RefCounted
	var enemy_id: StringName
	var count: int
	## Seconds after the wave starts when this group's first unit appears.
	var start: float
	## Seconds between consecutive units of the group.
	var interval: float
	## Spawn index into LevelData.spawn_cells, or WaveData.ALTERNATE.
	var spawn: int


var id: String = ""
var display_name: String = ""
## Credits paid once when the wave is completed.
var reward: int = 0
## Difficulty modifiers applied to every unit of the wave.
var hp_multiplier: float = 1.0
var speed_multiplier: float = 1.0
var completion: String = COMPLETE_ALL_CLEARED
var groups: Array[Group] = []


func enemy_count() -> int:
	var n := 0
	for g in groups:
		n += g.count
	return n


## {enemy_id: count} for briefings/intel.
func composition() -> Dictionary:
	var c := {}
	for g in groups:
		c[g.enemy_id] = c.get(g.enemy_id, 0) + g.count
	return c


## Spawn indices used by the wave (ALTERNATE expands to all of them).
func spawn_indices(spawn_count: int) -> Array[int]:
	var used: Array[int] = []
	for g in groups:
		if g.spawn == ALTERNATE:
			for i in spawn_count:
				if not used.has(i):
					used.append(i)
		elif not used.has(g.spawn):
			used.append(g.spawn)
	used.sort()
	return used


## Deterministic spawn schedule: [{ "time": float, "enemy": StringName, "spawn": int }]
## sorted by time, then by group order, then by unit order.
func schedule(spawn_count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var alternate_next := 0
	for gi in groups.size():
		var g := groups[gi]
		for k in g.count:
			var spawn := g.spawn
			if spawn == ALTERNATE:
				spawn = alternate_next % spawn_count
				alternate_next += 1
			events.append({"time": g.start + k * g.interval, "enemy": g.enemy_id, "spawn": spawn,
					"order": gi * 100000 + k})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["time"] < b["time"] or (a["time"] == b["time"] and a["order"] < b["order"]))
	return events
