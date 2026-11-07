extends SceneTree
## Enemy/navigation benchmark. Population is kept constant (arrivals respawn).
##
## Logic only (headless):
##   godot --headless --path . --script res://tests/perf/bench_enemies.gd
## Full scene with rendering (needs a display; frame time includes drawing):
##   godot --path . --resolution 1920x1080 --script res://tests/perf/bench_enemies.gd -- --render
##
## Prints one line per population. Numbers depend on the machine: record the
## hardware with the results (docs/TESTING.md).

const COUNTS := [10, 25, 50, 100]
const TICKS := 600 # 10 s of game time at 60 Hz
const DT := 1.0 / 60.0
const TOGGLE_EVERY := 60 # ticks between maze changes (topology churn)
const IDS := [&"infantry", &"light_vehicle", &"heavy_tank"]

## Current session. Signals connect to methods (not lambdas capturing the
## session) so no reference cycle keeps sessions alive after each run.
var _s: GameSession


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var render := OS.get_cmdline_user_args().has("--render")
	print("BENCH mode=%s godot=%s cpu=%s threads=%d" % ["render" if render else "logic",
			Engine.get_version_info()["string"], OS.get_processor_name(), OS.get_processor_count()])
	for n in ([0] + COUNTS if render else COUNTS):
		if render:
			await _bench_render(n)
		else:
			_bench_logic(n)
	quit()


func _make_session() -> GameSession:
	var level := LevelLoader.load_file("res://data/levels/mission_01.json").level
	level.base_max_hp = 1000000
	level.starting_credits = 100000
	level.allow_remove_during_combat = true # the bench toggles an obstacle in combat
	var s := GameSession.new(level)
	# A representative maze: two long walls the routes must snake around.
	var wall := StructureCatalog.load_structure(&"concrete_wall")
	for y in range(0, 13):
		s.construction.build(wall, Vector2i(7, y))
	for y in range(3, 16):
		s.construction.build(wall, Vector2i(14, y))
	s.set_phase(GameSession.Phase.COMBAT)
	_s = s
	s.enemies.enemy_reached_base.connect(_respawn)
	return s


func _respawn(e: Enemy) -> void:
	_s.base_hp = _s.level.base_max_hp
	_s.enemies.spawn(e.data, _s.level.spawn_cells[e.id % _s.level.spawn_cells.size()])


func _populate(s: GameSession, n: int) -> void:
	for i in n:
		var e := s.enemies.spawn(EnemyCatalog.get_data(IDS[i % 3]), s.level.spawn_cells[i % 2])
		e.progress = randf() * 0.9 # desynchronise


## Toggles a wall on a cell no enemy uses; returns true if the grid changed.
func _toggle_obstacle(s: GameSession, on: bool) -> bool:
	var cell := Vector2i(10, 8)
	if on:
		return s.construction.build(StructureCatalog.load_structure(&"concrete_wall"), cell).is_ok()
	return s.construction.remove_at(cell).is_ok()


func _bench_logic(n: int) -> void:
	seed(1234)
	var s := _make_session()
	var mem0 := OS.get_static_memory_usage()
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	_populate(s, n)
	var mem1 := OS.get_static_memory_usage()
	var obj1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var rebuild0 := s.nav.rebuild_usec_total
	var rebuilds0 := s.nav.rebuild_count
	var tick_total := 0
	var tick_max := 0
	var change_total := 0
	var changes := 0
	var eval_total := 0
	var evals := 0
	var wall := StructureCatalog.load_structure(&"concrete_wall")
	for t in TICKS:
		if t % TOGGLE_EVERY == 0:
			var c0 := Time.get_ticks_usec()
			if _toggle_obstacle(s, (t / TOGGLE_EVERY) % 2 == 0):
				change_total += Time.get_ticks_usec() - c0
				changes += 1
		# Build preview while units move (what a dragging finger costs).
		var e0 := Time.get_ticks_usec()
		s.construction.evaluate(wall, Vector2i(3 + t % 3, 5 + t % 7))
		eval_total += Time.get_ticks_usec() - e0
		evals += 1
		var t0 := Time.get_ticks_usec()
		s.tick(DT)
		var dt_us := Time.get_ticks_usec() - t0
		tick_total += dt_us
		tick_max = maxi(tick_max, dt_us)
	var rebuilds := s.nav.rebuild_count - rebuilds0
	var fmt := "LOGIC n=%3d alive=%3d | tick avg %6.1f us max %6d us | field rebuild avg %6.1f us (%d)"
	fmt += " | maze change avg %6.1f us (%d) | preview eval avg %6.1f us | static mem +%d KiB, objects +%d"
	print(fmt % [
		n, s.enemies.count(), float(tick_total) / TICKS, tick_max,
		float(s.nav.rebuild_usec_total - rebuild0) / maxi(1, rebuilds), rebuilds,
		float(change_total) / maxi(1, changes), changes, float(eval_total) / evals,
		(mem1 - mem0) / 1024, int(obj1 - obj0)])
	_s = null


func _bench_render(n: int) -> void:
	seed(1234)
	Engine.max_fps = 0
	change_scene_to_file("res://scenes/gameplay/battle.tscn")
	for i in 5:
		await process_frame
	var battle := current_scene
	var s: GameSession = battle.session
	s.level.allow_remove_during_combat = true
	# Same maze + population as the logic bench, inside the real scene.
	s.wallet.earn(100000)
	var wall := StructureCatalog.load_structure(&"concrete_wall")
	for y in range(0, 13):
		s.construction.build(wall, Vector2i(7, y))
	for y in range(3, 16):
		s.construction.build(wall, Vector2i(14, y))
	s.set_phase(GameSession.Phase.COMBAT)
	_s = s
	s.enemies.enemy_reached_base.connect(_respawn)
	_populate(s, n)
	for i in 30:
		await process_frame # warm-up
	var frames := 0
	var changes := 0
	var worst := 0
	var sim_total := 0
	var view_total := 0
	var t_start := Time.get_ticks_usec()
	var last := t_start
	var mem0 := OS.get_static_memory_usage()
	while Time.get_ticks_usec() - t_start < 5_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
		sim_total += battle.last_sim_usec
		view_total += battle.last_view_usec
		if frames % 30 == 0 and _toggle_obstacle(s, (frames / 30) % 2 == 1):
			changes += 1
	var elapsed := float(Time.get_ticks_usec() - t_start) / 1e6
	var fmt := "RENDER n=%3d alive=%3d views=%3d | %5.1f FPS | frame avg %6.2f ms worst %6.2f ms"
	fmt += " | our CPU: sim %5.3f ms + view sync %5.3f ms | maze changes %d | nodes %d | static mem %.1f MiB (delta %+d KiB)"
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print(fmt % [n, s.enemies.count(), battle.enemy_layer.view_count(), frames / elapsed, 1000.0 * elapsed / frames,
		worst / 1000.0, sim_total / 1000.0 / frames, view_total / 1000.0 / frames, changes, nodes,
		OS.get_static_memory_usage() / 1048576.0, (OS.get_static_memory_usage() - mem0) / 1024])
	_s = null
