extends RefCounted
## Scripted "competent player" used by the balance simulator and by the
## mission balance regression test. See sim_mission.gd for the strategies.
## Limitations: builds only between waves, never removes/rebuilds, never
## reacts mid-wave, fixed preferred cells. A human adapts; this is a baseline.

var strategy: Dictionary
var verbose := false
var _maze: Array = []


func _init(p_strategy: Dictionary) -> void:
	strategy = p_strategy
	_maze = p_strategy["maze"].duplicate()


## Called in each preparation phase. Returns the number of invalid placements.
func prepare(s: GameSession) -> int:
	return _prepare(s, strategy, _maze)


## Plays the whole mission with fixed steps; returns per-wave lines.
func play(s: GameSession, dt: float = 1.0 / 60.0, max_wave_seconds: float = 240.0) -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	while not s.is_over() and s.waves.has_next_wave():
		prepare(s)
		var entry := {"credits_before": s.wallet.get_credits(), "hp_before": s.base_hp, "kills_before": s.stats.kills}
		s.start_wave()
		var t := 0.0
		while s.phase == GameSession.Phase.WAVE_ACTIVE and t < max_wave_seconds:
			s.tick(dt)
			t += dt
		entry["seconds"] = t
		entry["wave"] = s.waves.current_index()
		entry["hp_after"] = s.base_hp
		entry["credits_after"] = s.wallet.get_credits()
		entry["kills"] = s.stats.kills - int(entry["kills_before"])
		log.append(entry)
		if s.phase == GameSession.Phase.WAVE_COMPLETED:
			s.set_phase(GameSession.Phase.PREPARATION) # no time pressure: skip the debrief
	return log


## One preparation phase of the scripted player (see STRATEGIES).
func _prepare(s: GameSession, strategy: Dictionary, maze: Array) -> int:
	var rejected := 0
	# The very first purchase may be a turret so wave 1 isn't faced unarmed.
	if strategy.get("turret_first", false) and s.combat.get_turrets().is_empty():
		rejected += _buy_turrets(s, strategy, 1)
	while not maze.is_empty():
		var item: Array = maze[0]
		var r := _try(s, item[0], Vector2i(item[1], item[2]))
		if r == 0:
			break # can't afford: keep for later
		maze.pop_front()
		rejected += 1 if r < 0 else 0
	return rejected + _buy_turrets(s, strategy, 999)


func _buy_turrets(s: GameSession, strategy: Dictionary, limit: int) -> int:
	var rejected := 0
	var bought := 0
	var cap: int = strategy.get("max_turrets", 999)
	while bought < limit and s.combat.get_turrets().size() < cap:
		var missiles := 0
		for t in s.combat.get_turrets():
			missiles += 1 if t.data.id == &"missile" else 0
		# Planning player: reads the intel of the next two waves for armour.
		var tanks := 0
		for k in [1, 2]:
			var i: int = s.waves.current_index() + k
			if i < s.level.waves.size():
				tanks = maxi(tanks, s.level.waves[i].composition().get(&"heavy_tank", 0))
		var want_missile: bool = tanks > 0 and missiles < 1 + tanks / 2 and not strategy["missile_cells"].is_empty()
		var kind := "turret_missile" if want_missile else "turret_hmg"
		var cells: Array = strategy["missile_cells"] if want_missile else strategy["hmg_cells"]
		var placed := false
		var cant_afford := false
		for c in cells:
			var r := _try(s, kind, Vector2i(c[0], c[1]))
			if r == 1:
				placed = true
				break
			if r == 0:
				cant_afford = true
				break
		if not placed:
			break # saving up, or no free spot left
		bought += 1
	return rejected


## 1 = built, 0 = unaffordable, -1 = invalid/occupied (skipped).
func _try(s: GameSession, id: String, cell: Vector2i) -> int:
	var data := StructureCatalog.load_structure(StringName(id))
	var check := s.construction.evaluate(data, cell)
	if check.reason == ConstructionService.Reason.INSUFFICIENT_CREDITS:
		return 0
	if not check.is_ok():
		if verbose and check.reason != ConstructionService.Reason.OCCUPIED:
			print("    rejected %s at %s: %s" % [id, cell, ConstructionService.reason_text(check)])
		return -1
	s.construction.build(data, cell)
	return 1
