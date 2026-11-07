extends SceneTree
## Combat benchmark: enemies x turrets, population kept constant (deaths and
## arrivals respawn). Separates enemy movement, combat simulation, view sync
## and (with --render) the frame time, which includes drawing.
##   godot --headless --path . --script res://tests/perf/bench_combat.gd
##   xvfb-run ... godot --path . --resolution 1920x1080 --script res://tests/perf/bench_combat.gd -- --render

const ENEMY_COUNTS := [25, 50, 100]
const TURRET_COUNTS := [0, 10, 20]
const TICKS := 600
const DT := 1.0 / 60.0
const IDS := [&"infantry", &"light_vehicle", &"heavy_tank"]
const WEAPONS := [&"turret_hmg", &"turret_missile", &"turret_aa"]

var _s: GameSession


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var render := OS.get_cmdline_user_args().has("--render")
	print("BENCH combat mode=%s godot=%s cpu=%s threads=%d" % ["render" if render else "logic",
			Engine.get_version_info()["string"], OS.get_processor_name(), OS.get_processor_count()])
	for t in TURRET_COUNTS:
		for n in ENEMY_COUNTS:
			if render:
				await _bench_render(n, t)
			else:
				_bench_logic(n, t)
	quit()


## Maze + up to `turrets` turrets beside the two long walls (cells the route
## validation rejects are skipped; the real count is reported).
func _setup(s: GameSession, turrets: int) -> int:
	s.level.base_max_hp = 1000000
	s.wallet.earn(1000000)
	var wall := StructureCatalog.load_structure(&"concrete_wall")
	for y in range(0, 13):
		s.construction.build(wall, Vector2i(7, y))
	for y in range(3, 16):
		s.construction.build(wall, Vector2i(14, y))
	var placed := 0
	var candidates: Array[Vector2i] = []
	for y in range(0, 13):
		candidates.append(Vector2i(6, y))
	for y in range(3, 16):
		candidates.append(Vector2i(15, y))
	for c in candidates:
		if placed >= turrets:
			break
		if s.construction.build(StructureCatalog.load_structure(WEAPONS[placed % 3]), c).is_ok():
			placed += 1
	s.set_phase(GameSession.Phase.WAVE_ACTIVE)
	_s = s
	s.enemies.enemy_reached_base.connect(_respawn)
	s.enemies.enemy_killed.connect(_respawn)
	return placed


func _respawn(e: Enemy) -> void:
	_s.base_hp = _s.level.base_max_hp
	_s.enemies.spawn(e.data, _s.level.spawn_cells[e.id % _s.level.spawn_cells.size()])


func _populate(s: GameSession, n: int) -> void:
	for i in n:
		var e := s.enemies.spawn(EnemyCatalog.get_data(IDS[i % 3]), s.level.spawn_cells[i % 2])
		e.progress = randf() * 0.9


func _bench_logic(n: int, turrets: int) -> void:
	seed(99)
	var level := LevelLoader.load_file("res://data/levels/mission_01.json").level
	var s := GameSession.new(level)
	var placed := _setup(s, turrets)
	_populate(s, n)
	var kills := [0]
	s.enemies.enemy_killed.connect(func(_e: Enemy) -> void: kills[0] += 1)
	var move_total := 0
	var combat_total := 0
	var combat_max := 0
	var proj_peak := 0
	for i in TICKS:
		var t0 := Time.get_ticks_usec()
		s.enemies.update(DT)
		var t1 := Time.get_ticks_usec()
		s.combat.update(DT)
		var t2 := Time.get_ticks_usec()
		move_total += t1 - t0
		combat_total += t2 - t1
		combat_max = maxi(combat_max, t2 - t1)
		proj_peak = maxi(proj_peak, s.combat.get_projectiles().size())
	var fmt := "LOGIC enemies=%3d turrets=%2d | enemy move avg %6.1f us | combat avg %6.1f us max %5d us"
	fmt += " | sim total %5.3f ms/tick | projectiles peak %3d | kills %d in 10 s"
	print(fmt % [n, placed, float(move_total) / TICKS, float(combat_total) / TICKS, combat_max,
			(move_total + combat_total) / 1000.0 / TICKS, proj_peak, kills[0]])
	_s = null


func _bench_render(n: int, turrets: int) -> void:
	seed(99)
	Engine.max_fps = 0
	change_scene_to_file("res://scenes/gameplay/battle.tscn")
	for i in 5:
		await process_frame
	var battle := current_scene
	var s: GameSession = battle.session
	var placed := _setup(s, turrets)
	_populate(s, n)
	for i in 30:
		await process_frame
	var frames := 0
	var worst := 0
	var sim_total := 0
	var view_total := 0
	var fx_peak := 0
	var draw_total := 0
	var t_start := Time.get_ticks_usec()
	var last := t_start
	while Time.get_ticks_usec() - t_start < 4_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
		sim_total += battle.last_sim_usec
		view_total += battle.last_view_usec
		fx_peak = maxi(fx_peak, battle.combat_layer.effect_count())
		draw_total += battle.combat_layer.last_draw_usec
	var elapsed := float(Time.get_ticks_usec() - t_start) / 1e6
	var fmt := "RENDER enemies=%3d turrets=%2d | %5.1f FPS | frame avg %6.2f ms worst %6.2f ms"
	fmt += " | our CPU: sim %5.3f + views %5.3f + fx draw %5.3f ms | effects peak %3d | nodes %d"
	print(fmt % [n, placed, frames / elapsed, 1000.0 * elapsed / frames, worst / 1000.0,
			sim_total / 1000.0 / frames, view_total / 1000.0 / frames, draw_total / 1000.0 / frames, fx_peak,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	_s = null
