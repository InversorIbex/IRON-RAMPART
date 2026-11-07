class_name TestAssault
extends RefCounted
## DEBUG scaffolding for Milestone 2: spawns a fixed mixed column so enemy
## movement can be seen and measured in the real scene. It is NOT the wave
## system (Milestone 4 replaces it with data-driven WaveData/WaveManager).

## 6 infantry + 3 light vehicles + 1 tank = 17 HQ damage (< 20): survivable
## without turrets, so the full BUILD -> COMBAT -> BUILD cycle can be observed.
const SEQUENCE := [
	&"infantry", &"infantry", &"light_vehicle", &"infantry", &"infantry",
	&"heavy_tank", &"light_vehicle", &"infantry", &"infantry", &"light_vehicle",
]
const INTERVAL := 0.8

var _session: GameSession
var _queue: Array = []
var _timer: float = 0.0
var _spawn_index: int = 0


func _init(session: GameSession, sequence: Array = SEQUENCE) -> void:
	_session = session
	_queue = sequence.duplicate()


func is_finished() -> bool:
	return _queue.is_empty()


func remaining() -> int:
	return _queue.size()


func update(delta: float) -> void:
	if _queue.is_empty():
		return
	_timer -= delta
	while _timer <= 0.0 and not _queue.is_empty():
		_timer += INTERVAL
		var data := EnemyCatalog.get_data(_queue.pop_front())
		var spawns := _session.level.spawn_cells
		if data != null:
			_session.enemies.spawn(data, spawns[_spawn_index % spawns.size()])
		_spawn_index += 1
