class_name Sfx
extends Node
## Placeholder sound effects synthesised in code (no audio assets yet):
## short military-style cues for mission events. Replace with recorded/designed
## audio in the art pass (docs/ART_DIRECTION.md). Volume is deliberately low.

enum Cue { WAVE_START, TANK_WARNING, HQ_HIT, KILL, WAVE_COMPLETE, VICTORY, DEFEAT, DENIED }

const MIX_RATE := 22050
const POOL_SIZE := 6
## Kill clicks are rate-limited so big fights don't turn into noise.
const KILL_MIN_INTERVAL := 0.08

var _streams: Dictionary = {} # Cue -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _last_kill_ms: int = -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = -10.0
		add_child(p)
		_players.append(p)
	_streams[Cue.WAVE_START] = _tones([[220.0, 0.25], [330.0, 0.45]], 0.35, true)
	_streams[Cue.TANK_WARNING] = _tones([[110.0, 0.18], [0.0, 0.08], [110.0, 0.18], [0.0, 0.08], [110.0, 0.3]], 0.4, true)
	_streams[Cue.HQ_HIT] = _noise(0.25, 0.5, 0.15)
	_streams[Cue.KILL] = _noise(0.05, 0.25, 0.6)
	_streams[Cue.WAVE_COMPLETE] = _tones([[392.0, 0.12], [523.0, 0.12], [659.0, 0.3]], 0.3, false)
	_streams[Cue.VICTORY] = _tones([[392.0, 0.2], [523.0, 0.2], [659.0, 0.2], [784.0, 0.6]], 0.3, false)
	_streams[Cue.DEFEAT] = _tones([[330.0, 0.3], [262.0, 0.3], [196.0, 0.7]], 0.3, true)
	_streams[Cue.DENIED] = _tones([[160.0, 0.12]], 0.25, true)


func play(cue: int) -> void:
	if cue == Cue.KILL:
		var now := Time.get_ticks_msec()
		if now - _last_kill_ms < KILL_MIN_INTERVAL * 1000.0:
			return
		_last_kill_ms = now
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _streams[cue]
	p.play()


func stream_for(cue: int) -> AudioStreamWAV:
	return _streams.get(cue)


## Sequence of [frequency Hz (0 = silence), seconds]. Square-ish wave if harsh.
func _tones(notes: Array, volume: float, harsh: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	for n in notes:
		var freq: float = n[0]
		var samples := int(MIX_RATE * float(n[1]))
		for i in samples:
			var t := float(i) / MIX_RATE
			var env := minf(1.0, i / 200.0) * minf(1.0, (samples - i) / 400.0)
			var v := 0.0
			if freq > 0.0:
				v = sin(TAU * freq * t)
				if harsh:
					v = clampf(v * 3.0, -1.0, 1.0) * 0.7 + sin(TAU * freq * 2.0 * t) * 0.3
			_put(data, v * env * volume)
	return _wav(data)


func _noise(seconds: float, volume: float, brightness: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var samples := int(MIX_RATE * seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last := 0.0
	for i in samples:
		var env := pow(1.0 - float(i) / samples, 2.0)
		last = lerpf(last, rng.randf_range(-1.0, 1.0), brightness) # cheap low-pass
		_put(data, last * env * volume)
	return _wav(data)


func _put(data: PackedByteArray, v: float) -> void:
	var s := int(clampf(v, -1.0, 1.0) * 32767.0)
	data.append(s & 0xFF)
	data.append((s >> 8) & 0xFF)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
