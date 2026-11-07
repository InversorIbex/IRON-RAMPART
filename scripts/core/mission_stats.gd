class_name MissionStats
extends RefCounted
## Counters for one mission attempt (results screen, score, balancing sims).

var kills: int = 0
var kills_by_type: Dictionary = {} # StringName -> int
var credits_from_kills: int = 0
var credits_from_waves: int = 0
var credits_spent: int = 0
var credits_refunded: int = 0
var hq_damage_taken: int = 0
var leaks: int = 0
var waves_completed: int = 0
var structures_built: int = 0
## Seconds spent in WAVE_ACTIVE (pause and preparation excluded).
var combat_time: float = 0.0


func record_kill(enemy: Enemy) -> void:
	kills += 1
	kills_by_type[enemy.data.id] = kills_by_type.get(enemy.data.id, 0) + 1
	credits_from_kills += enemy.data.reward
