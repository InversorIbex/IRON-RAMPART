class_name WaveManager
extends RefCounted
## Runs the mission's waves from data. Pure logic driven by update(delta),
## which GameSession only calls while a wave is active (never in preparation,
## pause, or after the mission ends), so no unit can appear at those times.
##
## A wave is finished when its whole schedule has spawned AND no enemy is
## left alive (killed or arrived at the HQ). GameSession decides what that
## means (bonus, next state).

signal wave_started(index: int, wave: WaveData)
## First appearance of an enemy type in the current wave (e.g. tank warning).
signal enemy_type_arrived(index: int, enemy_id: StringName)
signal wave_spawning_finished(index: int)

var _waves: Array[WaveData] = []
var _roster: EnemyRoster
var _spawn_cells: Array[Vector2i] = []
var _current: int = -1
var _schedule: Array[Dictionary] = []
var _next_event: int = 0
var _elapsed: float = 0.0
var _seen_types: Dictionary = {}
var _spawned_in_wave: int = 0


func _init(waves: Array[WaveData], roster: EnemyRoster, spawn_cells: Array[Vector2i]) -> void:
	_waves = waves
	_roster = roster
	_spawn_cells.assign(spawn_cells)


func wave_count() -> int:
	return _waves.size()


## Index of the current (or last started) wave; -1 before the first one.
func current_index() -> int:
	return _current


func current_wave() -> WaveData:
	return _waves[_current] if _current >= 0 and _current < _waves.size() else null


func next_wave() -> WaveData:
	var i := _current + 1
	return _waves[i] if i < _waves.size() else null


func has_next_wave() -> bool:
	return _current + 1 < _waves.size()


func is_last_wave() -> bool:
	return _current == _waves.size() - 1


func spawned_in_wave() -> int:
	return _spawned_in_wave


## Units of the current wave that have not appeared yet.
func remaining_to_spawn() -> int:
	return _schedule.size() - _next_event


func is_spawning_done() -> bool:
	return _next_event >= _schedule.size()


## True when the current wave satisfied its completion condition.
func is_wave_cleared() -> bool:
	return _current >= 0 and is_spawning_done() and _roster.count() == 0


## Starts the next wave. Returns false if there is none.
func start_next_wave() -> bool:
	if not has_next_wave():
		return false
	_current += 1
	_schedule = _waves[_current].schedule(_spawn_cells.size())
	_next_event = 0
	_elapsed = 0.0
	_seen_types = {}
	_spawned_in_wave = 0
	wave_started.emit(_current, _waves[_current])
	return true


func update(delta: float) -> void:
	if _current < 0 or is_spawning_done() or delta <= 0.0:
		return
	_elapsed += delta
	var wave := _waves[_current]
	while _next_event < _schedule.size() and _schedule[_next_event]["time"] <= _elapsed:
		var ev: Dictionary = _schedule[_next_event]
		_next_event += 1
		var data := EnemyCatalog.get_data(ev["enemy"])
		if data == null:
			continue # validated at load; defensive
		_roster.spawn(data, _spawn_cells[ev["spawn"]], wave.hp_multiplier, wave.speed_multiplier)
		_spawned_in_wave += 1
		if not _seen_types.has(data.id):
			_seen_types[data.id] = true
			enemy_type_arrived.emit(_current, data.id)
	if is_spawning_done():
		wave_spawning_finished.emit(_current)
