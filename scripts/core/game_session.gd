class_name GameSession
extends RefCounted
## All mutable state of one mission attempt. Restarting = creating a new
## GameSession, so no state can leak between attempts.
## Scenes own a session and render it; they never hold gameplay state.

signal phase_changed(phase: int)

enum Phase { BUILD, COMBAT, VICTORY, DEFEAT }

var level: LevelData
var grid: GridModel
var nav: NavGrid
var wallet: Wallet
var construction: ConstructionService
var phase: int = Phase.BUILD
var base_hp: int


func _init(p_level: LevelData) -> void:
	level = p_level
	grid = GridModel.new(level)
	nav = NavGrid.new(grid)
	wallet = Wallet.new(level.starting_credits)
	construction = ConstructionService.new(
			grid, nav, wallet, level.spawn_cells, level.goal_cell, level.movement_mask)
	base_hp = level.base_max_hp
	_apply_phase_rules()


func set_phase(new_phase: int) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	_apply_phase_rules()
	phase_changed.emit(phase)


func _apply_phase_rules() -> void:
	construction.build_enabled = phase == Phase.BUILD
	construction.removal_enabled = phase == Phase.BUILD \
			or (phase == Phase.COMBAT and level.allow_remove_during_combat)
