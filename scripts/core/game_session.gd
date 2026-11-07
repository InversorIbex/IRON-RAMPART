class_name GameSession
extends RefCounted
## All mutable state of one mission attempt. Restarting = creating a new
## GameSession, so no state can leak between attempts.
## Scenes own a session and render it; they never hold gameplay state.

signal phase_changed(phase: int)
signal base_hp_changed(hp: int, max_hp: int)

enum Phase { BUILD, COMBAT, VICTORY, DEFEAT }

var level: LevelData
var grid: GridModel
var nav: NavGrid
var wallet: Wallet
var construction: ConstructionService
var enemies: EnemyRoster
var combat: CombatSystem
var phase: int = Phase.BUILD
var base_hp: int


func _init(p_level: LevelData) -> void:
	level = p_level
	grid = GridModel.new(level)
	nav = NavGrid.new(grid, level.goal_cell)
	wallet = Wallet.new(level.starting_credits)
	enemies = EnemyRoster.new(grid, nav)
	construction = ConstructionService.new(grid, nav, wallet, level.spawn_cells, level.movement_mask)
	construction.set_units(enemies)
	combat = CombatSystem.new(grid, enemies, nav)
	enemies.enemy_killed.connect(_on_enemy_killed)
	enemies.enemy_reached_base.connect(_on_enemy_reached_base)
	base_hp = level.base_max_hp
	_apply_phase_rules()


## Advances the simulation. Frozen once the mission is over.
func tick(delta: float) -> void:
	if phase == Phase.BUILD or phase == Phase.COMBAT:
		enemies.update(delta)
		# The HQ may fall during enemies.update(): no shot is fired after defeat.
		if not is_over():
			combat.update(delta)


func set_phase(new_phase: int) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	_apply_phase_rules()
	phase_changed.emit(phase)


func is_over() -> bool:
	return phase == Phase.VICTORY or phase == Phase.DEFEAT


func _apply_phase_rules() -> void:
	construction.build_enabled = phase == Phase.BUILD \
			or (phase == Phase.COMBAT and level.allow_build_during_combat)
	construction.removal_enabled = phase == Phase.BUILD \
			or (phase == Phase.COMBAT and level.allow_remove_during_combat)
	construction.surcharge_ratio = level.combat_build_surcharge if phase == Phase.COMBAT else 0.0


func _on_enemy_killed(enemy: Enemy) -> void:
	wallet.earn(enemy.data.reward)


func _on_enemy_reached_base(enemy: Enemy) -> void:
	if is_over():
		return
	base_hp = maxi(0, base_hp - enemy.data.base_damage)
	base_hp_changed.emit(base_hp, level.base_max_hp)
	if base_hp == 0:
		set_phase(Phase.DEFEAT)
		combat.clear_projectiles()
