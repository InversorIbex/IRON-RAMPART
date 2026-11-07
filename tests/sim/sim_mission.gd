extends SceneTree

const StrategyBot := preload("res://tests/sim/strategy_bot.gd")
## Balance simulator: plays OPERATION FIRST ASSAULT end to end with scripted
## defensive strategies through the real game API (construction rules,
## prices, waves, combat). Not a pass/fail test: it prints a comparison table.
##   godot --headless --path . --script res://tests/sim/sim_mission.gd [-- --verbose]
##
## The player model lives in strategy_bot.gd (limitations documented there and
## in docs/TESTING.md): builds only between waves, never reacts mid-wave.

const DT := 1.0 / 60.0
const MISSION := "res://data/levels/mission_01.json"
const MAX_WAVE_SECONDS := 240.0

## Strategies for a competent, intel-reading player:
## - "maze": obstacles built first, in order, whenever affordable.
## - "hmg_cells" / "missile_cells": preferred turret spots, in priority order.
## - "max_turrets": cap (strategy D uses it to stay deliberately weak).
## Each preparation: build pending maze items; then buy turrets while
## affordable. The next turret is a missile launcher if either of the next two
## waves has tanks and the player owns fewer launchers than 1 + tanks / 2
## (a planning player saving for armour); otherwise an HMG.
## If the chosen turret is unaffordable the player saves (stops buying).
const STRATEGIES := {
	"A_long_maze": {
		"desc": "long sandbag maze (both routes ~40 cells), turrets on the corridor",
		"maze": [
			["sandbags", 16, 4], ["sandbags", 16, 5], ["sandbags", 16, 6], ["sandbags", 16, 7], ["sandbags", 16, 8],
			["sandbags", 16, 9], ["sandbags", 16, 10], ["sandbags", 16, 11], ["sandbags", 16, 12], ["sandbags", 16, 13],
			["sandbags", 16, 14], ["sandbags", 16, 15],
			["sandbags", 12, 0], ["sandbags", 12, 1], ["sandbags", 12, 2], ["sandbags", 12, 3], ["sandbags", 12, 4],
			["sandbags", 12, 5], ["sandbags", 12, 6], ["sandbags", 12, 7], ["sandbags", 12, 8], ["sandbags", 12, 9],
			["sandbags", 12, 10], ["sandbags", 12, 11], ["sandbags", 12, 12],
		],
		"hmg_cells": [[14, 7], [14, 11], [14, 3], [18, 2], [18, 11]],
		"missile_cells": [[19, 7], [19, 9], [18, 5], [14, 13]],
		"turret_first": true,
	},
	"A2_maze_vs_armor": {
		"desc": "same maze, but the x=16 line is concrete so tanks are routed too",
		"maze": [
			["concrete_wall", 16, 4], ["concrete_wall", 16, 5], ["concrete_wall", 16, 6], ["concrete_wall", 16, 7],
			["concrete_wall", 16, 8], ["concrete_wall", 16, 9], ["concrete_wall", 16, 10], ["concrete_wall", 16, 11],
			["concrete_wall", 16, 12], ["concrete_wall", 16, 13], ["concrete_wall", 16, 14], ["concrete_wall", 16, 15],
			["sandbags", 12, 0], ["sandbags", 12, 1], ["sandbags", 12, 2], ["sandbags", 12, 3], ["sandbags", 12, 4],
			["sandbags", 12, 5], ["sandbags", 12, 6], ["sandbags", 12, 7], ["sandbags", 12, 8], ["sandbags", 12, 9],
			["sandbags", 12, 10], ["sandbags", 12, 11], ["sandbags", 12, 12],
		],
		"hmg_cells": [[14, 7], [14, 11], [14, 3], [18, 2], [18, 11]],
		"missile_cells": [[15, 1], [19, 7], [19, 9], [18, 5]],
		"turret_first": true,
	},
	"B_firepower": {
		"desc": "no maze: turrets around the HQ",
		"maze": [],
		"hmg_cells": [[19, 6], [19, 9], [18, 2], [17, 7], [20, 3], [17, 9], [20, 11]],
		"missile_cells": [[20, 5], [19, 10], [18, 5], [17, 11]],
	},
	"C_balanced": {
		"desc": "seal the HQ's north side so both routes merge; mixed turrets",
		"maze": [
			["concrete_wall", 20, 4], ["concrete_wall", 21, 4], ["concrete_wall", 22, 4], ["concrete_wall", 23, 4],
			["sandbags", 19, 0], ["sandbags", 19, 1], ["sandbags", 19, 2], ["sandbags", 19, 3],
		],
		"hmg_cells": [[19, 6], [18, 9], [16, 3], [15, 8], [17, 4]],
		"missile_cells": [[17, 6], [20, 10], [17, 11], [16, 9]],
		"turret_first": true,
	},
	"D_insufficient": {
		"desc": "deliberately weak: one HMG, then hoard credits",
		"maze": [],
		"hmg_cells": [[19, 6]],
		"missile_cells": [],
		"max_turrets": 1,
	},
}

var _verbose := false
var _maps := false


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	_verbose = OS.get_cmdline_user_args().has("--verbose")
	_maps = OS.get_cmdline_user_args().has("--maps")
	print("SIM %s  godot %s" % [MISSION, Engine.get_version_info()["string"]])
	var level0 := LevelLoader.load_file(MISSION).level
	for w in level0.waves:
		print("  wave %-3s %-16s enemies %2d  hp x%.2f  speed x%.2f  bonus %d" % [w.id, w.display_name,
				w.enemy_count(), w.hp_multiplier, w.speed_multiplier, w.reward])
	for name in STRATEGIES:
		_run(name, STRATEGIES[name])
	quit()


func _run(name: String, strategy: Dictionary) -> void:
	var level := LevelLoader.load_file(MISSION).level
	var s := GameSession.new(level)
	var bot := StrategyBot.new(strategy)
	bot.verbose = _verbose
	var rejected := 0
	var lines: Array[String] = []
	var total_time := 0.0
	while not s.is_over() and s.waves.has_next_wave():
		rejected += bot.prepare(s)
		var credits_before := s.wallet.get_credits()
		var hp_before := s.base_hp
		var kills_before := s.stats.kills
		var west := s.nav.path_to_goal(MovementClass.INFANTRY, level.spawn_cells[1]).size()
		var north := s.nav.path_to_goal(MovementClass.INFANTRY, level.spawn_cells[0]).size()
		var tank_west := s.nav.path_to_goal(MovementClass.TRACKED, level.spawn_cells[1]).size()
		if _maps and (s.waves.current_index() == -1 or not s.waves.has_next_wave() or s.waves.current_index() == 3):
			print("  map before wave %d (%s):" % [s.wave_number() + 1, name])
			_print_map(s)
		s.start_wave()
		var t := 0.0
		while s.phase == GameSession.Phase.WAVE_ACTIVE and t < MAX_WAVE_SECONDS:
			s.tick(DT)
			t += DT
		total_time += t
		lines.append("    w%d %-15s %5.1fs  kills %2d/%2d  HQ %2d->%2d  credits %4d->%4d  turrets %d  route W/N/tankW %d/%d/%d" % [
			s.waves.current_index() + 1, s.waves.current_wave().display_name, t,
			s.stats.kills - kills_before, s.waves.current_wave().enemy_count(), hp_before, s.base_hp,
			credits_before, s.wallet.get_credits(), s.combat.get_turrets().size(), west, north, tank_west])
		# Skip the debrief (no time pressure in preparation; only simulated seconds matter).
		if s.phase == GameSession.Phase.WAVE_COMPLETED:
			s.set_phase(GameSession.Phase.PREPARATION)
	var result := "VICTORY" if s.phase == GameSession.Phase.VICTORY else (
			"DEFEAT at wave %d" % s.wave_number() if s.phase == GameSession.Phase.DEFEAT else "TIMEOUT")
	print("\nSTRATEGY %s (%s)" % [name, strategy["desc"]])
	for l in lines:
		print(l)
	var fmt := "  RESULT %s | HQ %d/%d | kills %d | score %d (%d stars) | earned %d (kills %d + waves %d)"
	fmt += " spent %d | left %d | combat %.0fs | rejected %d"
	print(fmt % [
		result, s.base_hp, level.base_max_hp, s.stats.kills, s.score(), MissionScore.stars(s),
		s.stats.credits_from_kills + s.stats.credits_from_waves, s.stats.credits_from_kills, s.stats.credits_from_waves,
		s.stats.credits_spent, s.wallet.get_credits(), total_time, rejected])


## ASCII map: structures, infantry routes (*), tank-only route cells (o) and
## empty cells inside any turret range (':').
func _print_map(s: GameSession) -> void:
	var g := s.grid
	var marks := {}
	for spawn in s.level.spawn_cells:
		for c in s.nav.path_to_goal(MovementClass.TRACKED, spawn):
			marks[c] = "o"
		for c in s.nav.path_to_goal(MovementClass.INFANTRY, spawn):
			marks[c] = "*"
	var letters := {&"sandbags": "s", &"concrete_wall": "W", &"antitank_barrier": "A",
			&"turret_hmg": "H", &"turret_missile": "M", &"turret_aa": "X"}
	print("     " + "".join(range(g.width).map(func(x: int) -> String: return str(x % 10))))
	for y in g.height:
		var row := ""
		for x in g.width:
			var c := Vector2i(x, y)
			var p := g.get_placement_at(c)
			var ch := "."
			match g.terrain_at(c):
				Terrain.ROCK:
					ch = "#"
				Terrain.SPAWN:
					ch = "S"
				Terrain.BASE:
					ch = "B"
				Terrain.ROAD:
					ch = "~"
			if p != null:
				ch = letters.get(p.data.id, "?")
			elif marks.has(c) and ch == ".":
				ch = marks[c]
			elif ch == ".":
				for t in s.combat.get_turrets():
					if t.position.distance_to(g.cell_to_local(c)) <= t.range_px:
						ch = ":"
						break
			row += ch
		print("  %2d %s" % [y, row])
