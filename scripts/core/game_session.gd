class_name GameSession
extends RefCounted
## All mutable state of one mission attempt. Restarting = creating a new
## GameSession, so no state can leak between attempts.
## Scenes own a session and render it; they never hold gameplay state.
##
## Mission state machine (see docs/ARCHITECTURE.md):
##   PREPARATION --start_wave--> WAVE_ACTIVE --cleared--> WAVE_COMPLETED --debrief--> PREPARATION
##   WAVE_COMPLETED --start_wave--> WAVE_ACTIVE      (skip the debrief)
##   WAVE_ACTIVE --last wave cleared--> VICTORY        WAVE_ACTIVE --HQ 0--> DEFEAT
##   any non-final state <--pause/resume--> PAUSED (resumes the exact previous state)
## Every change goes through _transition(), which rejects anything not in TRANSITIONS.

signal phase_changed(phase: int)
signal base_hp_changed(hp: int, max_hp: int)
## HQ hit: damage taken this hit (for feedback).
signal hq_damaged(amount: int, enemy: Enemy)
signal wave_started(index: int, wave: WaveData)
signal wave_completed(index: int, wave: WaveData, bonus: int)
## First appearance of a type in a wave (HUD warnings, e.g. tanks).
signal enemy_type_arrived(index: int, enemy_id: StringName)
signal mission_ended(victory: bool)

enum Phase { PREPARATION, WAVE_ACTIVE, WAVE_COMPLETED, VICTORY, DEFEAT, PAUSED }

const TRANSITIONS := {
	# DEFEAT is reachable from every non-final, non-paused state: if the HQ falls,
	# the mission is lost whatever the phase (normal play only loses in WAVE_ACTIVE).
	Phase.PREPARATION: [Phase.WAVE_ACTIVE, Phase.PAUSED, Phase.DEFEAT],
	Phase.WAVE_ACTIVE: [Phase.WAVE_COMPLETED, Phase.VICTORY, Phase.DEFEAT, Phase.PAUSED],
	Phase.WAVE_COMPLETED: [Phase.PREPARATION, Phase.WAVE_ACTIVE, Phase.PAUSED, Phase.DEFEAT],
	Phase.PAUSED: [Phase.PREPARATION, Phase.WAVE_ACTIVE, Phase.WAVE_COMPLETED],
	Phase.VICTORY: [],
	Phase.DEFEAT: [],
}

var level: LevelData
var grid: GridModel
var nav: NavGrid
var wallet: Wallet
var construction: ConstructionService
var enemies: EnemyRoster
var combat: CombatSystem
var waves: WaveManager
var stats: MissionStats
var phase: int = Phase.PREPARATION
var base_hp: int

var _resume_phase: int = -1
var _debrief_timer: float = 0.0


func _init(p_level: LevelData) -> void:
	level = p_level
	grid = GridModel.new(level)
	nav = NavGrid.new(grid, level.goal_cell)
	wallet = Wallet.new(level.starting_credits)
	enemies = EnemyRoster.new(grid, nav)
	construction = ConstructionService.new(grid, nav, wallet, level.spawn_cells, level.movement_mask)
	construction.set_units(enemies)
	combat = CombatSystem.new(grid, enemies, nav)
	waves = WaveManager.new(level.waves, enemies, level.spawn_cells)
	stats = MissionStats.new()
	enemies.enemy_killed.connect(_on_enemy_killed)
	enemies.enemy_reached_base.connect(_on_enemy_reached_base)
	waves.wave_started.connect(_on_wave_started)
	waves.enemy_type_arrived.connect(_on_enemy_type_arrived)
	construction.structure_built.connect(_on_structure_built)
	construction.structure_removed.connect(_on_structure_removed)
	base_hp = level.base_max_hp
	_apply_phase_rules()


# --- Commands -------------------------------------------------------------------

## Starts the next wave from PREPARATION or WAVE_COMPLETED. Returns false otherwise.
func start_wave() -> bool:
	if phase != Phase.PREPARATION and phase != Phase.WAVE_COMPLETED:
		return false
	if not waves.has_next_wave():
		return false
	if not _transition(Phase.WAVE_ACTIVE):
		return false
	waves.start_next_wave()
	return true


func pause() -> bool:
	if phase == Phase.PAUSED or is_over():
		return false
	var previous := phase
	if not _transition(Phase.PAUSED):
		return false
	_resume_phase = previous
	return true


func resume() -> bool:
	if phase != Phase.PAUSED:
		return false
	var target := _resume_phase
	_resume_phase = -1
	return _transition(target)


## Generic validated transition (also used by tests to drive edge cases).
## Returns false and changes nothing if the transition is not allowed.
func set_phase(new_phase: int) -> bool:
	return _transition(new_phase)


# --- Simulation -------------------------------------------------------------------

## Advances the simulation. Waves only spawn in WAVE_ACTIVE; nothing runs in
## PAUSED, VICTORY or DEFEAT. In the build phases units/projectiles already on
## the field still resolve (in normal play there are none: waves end cleared).
func tick(delta: float) -> void:
	match phase:
		Phase.WAVE_ACTIVE:
			stats.combat_time += delta
			waves.update(delta)
			enemies.update(delta)
			if is_over():
				return # the HQ fell this tick: no shot or wave logic afterwards
			combat.update(delta)
			if waves.is_wave_cleared():
				_complete_wave()
		Phase.WAVE_COMPLETED, Phase.PREPARATION:
			enemies.update(delta)
			if is_over():
				return
			combat.update(delta)
			if phase == Phase.WAVE_COMPLETED:
				_debrief_timer -= delta
				if _debrief_timer <= 0.0:
					_transition(Phase.PREPARATION)


func is_over() -> bool:
	return phase == Phase.VICTORY or phase == Phase.DEFEAT


func is_build_phase() -> bool:
	return phase == Phase.PREPARATION or phase == Phase.WAVE_COMPLETED


## Wave number for display: 1-based current wave (0 before the first one).
func wave_number() -> int:
	return waves.current_index() + 1


func score() -> int:
	return MissionScore.compute(self)


# --- Internals -------------------------------------------------------------------

func _transition(new_phase: int) -> bool:
	if new_phase == phase or not TRANSITIONS[phase].has(new_phase):
		return false
	phase = new_phase
	_apply_phase_rules()
	phase_changed.emit(phase)
	return true


func _apply_phase_rules() -> void:
	var active := phase == Phase.WAVE_ACTIVE
	construction.build_enabled = is_build_phase() or (active and level.allow_build_during_combat)
	construction.removal_enabled = is_build_phase() or (active and level.allow_remove_during_combat)
	construction.surcharge_ratio = level.combat_build_surcharge if active else 0.0


func _complete_wave() -> void:
	var index := waves.current_index()
	var wave := waves.current_wave()
	stats.waves_completed += 1
	if wave.reward > 0:
		wallet.earn(wave.reward)
		stats.credits_from_waves += wave.reward
	# Order matters for listeners: "wave complete" first, then the new state.
	wave_completed.emit(index, wave, wave.reward)
	if waves.is_last_wave():
		_end(true)
	else:
		_debrief_timer = level.debrief_seconds
		_transition(Phase.WAVE_COMPLETED)


func _end(victory: bool) -> void:
	_transition(Phase.VICTORY if victory else Phase.DEFEAT)
	combat.clear_projectiles()
	mission_ended.emit(victory)


func _on_wave_started(index: int, wave: WaveData) -> void:
	wave_started.emit(index, wave)


func _on_enemy_type_arrived(index: int, enemy_id: StringName) -> void:
	enemy_type_arrived.emit(index, enemy_id)


func _on_enemy_killed(enemy: Enemy) -> void:
	if is_over():
		return
	wallet.earn(enemy.data.reward)
	stats.record_kill(enemy)


func _on_enemy_reached_base(enemy: Enemy) -> void:
	if is_over():
		return
	var dmg := mini(enemy.data.base_damage, base_hp)
	base_hp -= dmg
	stats.hq_damage_taken += dmg
	stats.leaks += 1
	base_hp_changed.emit(base_hp, level.base_max_hp)
	hq_damaged.emit(dmg, enemy)
	if base_hp == 0:
		_end(false)


func _on_structure_built(placement: Placement) -> void:
	stats.credits_spent += placement.paid
	stats.structures_built += 1


func _on_structure_removed(_placement: Placement, refund: int) -> void:
	stats.credits_refunded += refund
