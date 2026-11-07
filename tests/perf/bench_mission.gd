extends SceneTree
## Full-mission benchmark: OPERATION FIRST ASSAULT played by the C_balanced
## scripted player. Splits the per-tick cost into waves (spawning), enemy
## movement (+ flow-field lookups), turrets (targeting/aiming/firing) and
## projectiles; reports navigation rebuilds, peaks and memory.
##   godot --headless --path . --script res://tests/perf/bench_mission.gd
##   xvfb-run ... godot --path . --resolution 1920x1080 --script res://tests/perf/bench_mission.gd -- --render

const StrategyBot := preload("res://tests/sim/strategy_bot.gd")
const Sim := preload("res://tests/sim/sim_mission.gd")
const DT := 1.0 / 60.0


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var render := OS.get_cmdline_user_args().has("--render")
	print("BENCH mission mode=%s godot=%s cpu=%s" % ["render" if render else "logic",
			Engine.get_version_info()["string"], OS.get_processor_name()])
	if render:
		await _render()
		# Leave the battle before quitting: killing the process while a sound
		# plays leaves AudioServer playbacks alive at shutdown (exit-only warning,
		# verified not to leak across restarts; see docs/TESTING.md).
		change_scene_to_file("res://scenes/menus/main_menu.tscn")
		for i in 10:
			await process_frame
	else:
		_logic()
	quit()


func _logic() -> void:
	var mem0 := OS.get_static_memory_usage()
	var level := LevelLoader.load_file("res://data/levels/mission_01.json").level
	var s := GameSession.new(level)
	var bot := StrategyBot.new(Sim.STRATEGIES["C_balanced"])
	var acc := {"waves": 0, "move": 0, "turrets": 0, "projectiles": 0, "total": 0}
	var worst := 0
	var ticks := 0
	var peak := {"enemies": 0, "projectiles": 0, "turrets": 0}
	while not s.is_over() and s.waves.has_next_wave():
		bot.prepare(s)
		s.start_wave()
		while s.phase == GameSession.Phase.WAVE_ACTIVE:
			# Same order as GameSession.tick(), timed piece by piece.
			var t0 := Time.get_ticks_usec()
			s.waves.update(DT)
			var t1 := Time.get_ticks_usec()
			s.enemies.update(DT)
			var t2 := Time.get_ticks_usec()
			if not s.is_over():
				s.combat.update(DT)
				if s.waves.is_wave_cleared():
					s._complete_wave()
			var t3 := Time.get_ticks_usec()
			acc["waves"] += t1 - t0
			acc["move"] += t2 - t1
			acc["turrets"] += s.combat.last_turrets_usec
			acc["projectiles"] += s.combat.last_projectiles_usec
			acc["total"] += t3 - t0
			worst = maxi(worst, t3 - t0)
			ticks += 1
			peak["enemies"] = maxi(peak["enemies"], s.enemies.count())
			peak["projectiles"] = maxi(peak["projectiles"], s.combat.get_projectiles().size())
		peak["turrets"] = s.combat.get_turrets().size()
		if s.phase == GameSession.Phase.WAVE_COMPLETED:
			s.set_phase(GameSession.Phase.PREPARATION)
	print("LOGIC result=%s HQ %d | %d ticks (%.0f s of combat)" % [GameSession.Phase.keys()[s.phase], s.base_hp, ticks, ticks * DT])
	var fmt := "  per tick avg: waves %.2f us | enemy move %.1f us | turrets %.1f us | projectiles %.1f us"
	fmt += " | TOTAL %.1f us (worst %d us)"
	print(fmt % [
		float(acc["waves"]) / ticks, float(acc["move"]) / ticks, float(acc["turrets"]) / ticks,
		float(acc["projectiles"]) / ticks, float(acc["total"]) / ticks, worst])
	print("  navigation: %d field rebuilds, avg %.1f us each (only on build/remove)" % [s.nav.rebuild_count,
		float(s.nav.rebuild_usec_total) / maxi(1, s.nav.rebuild_count)])
	print("  peaks: enemies %d | projectiles %d | turrets %d | static memory +%d KiB" % [peak["enemies"], peak["projectiles"],
		peak["turrets"], (OS.get_static_memory_usage() - mem0) / 1024])


func _render() -> void:
	Engine.max_fps = 0
	change_scene_to_file("res://scenes/gameplay/battle.tscn")
	for i in 5:
		await process_frame
	var battle := current_scene
	var s: GameSession = battle.session
	var bot := StrategyBot.new(Sim.STRATEGIES["C_balanced"])
	var frames := 0
	var worst := 0
	var sim := 0
	var views := 0
	var fx := 0
	var peak_nodes := 0
	var peak_enemies := 0
	var mem0 := OS.get_static_memory_usage()
	var t_start := Time.get_ticks_usec()
	var last := t_start
	while not s.is_over() and s.waves.has_next_wave():
		bot.prepare(s)
		s.start_wave()
		while s.phase == GameSession.Phase.WAVE_ACTIVE:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxi(worst, now - last)
			last = now
			frames += 1
			sim += battle.last_sim_usec
			views += battle.last_view_usec
			fx += battle.combat_layer.last_draw_usec
			peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			peak_enemies = maxi(peak_enemies, s.enemies.count())
		if s.phase == GameSession.Phase.WAVE_COMPLETED:
			s.set_phase(GameSession.Phase.PREPARATION)
	var elapsed := float(Time.get_ticks_usec() - t_start) / 1e6
	print("RENDER result=%s HQ %d | %d frames in %.0f s real | %.1f FPS | frame avg %.2f ms worst %.2f ms" % [
		GameSession.Phase.keys()[s.phase], s.base_hp, frames, elapsed, frames / elapsed, 1000.0 * elapsed / frames, worst / 1000.0])
	var fmt := "  our CPU per frame: sim %.3f ms + views %.3f ms + fx draw %.3f ms | peak nodes %d, enemies %d"
	fmt += " | static mem %.1f MiB (+%d KiB)"
	print(fmt % [
		sim / 1000.0 / frames, views / 1000.0 / frames, fx / 1000.0 / frames, peak_nodes, peak_enemies,
		OS.get_static_memory_usage() / 1048576.0, (OS.get_static_memory_usage() - mem0) / 1024])
