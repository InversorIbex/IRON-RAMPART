extends "res://tests/framework/test_case.gd"
## Shared fixtures for the combat suites (synthetic weapons, placement, event capture).

const H := preload("res://tests/unit/test_helpers.gd")
const DT := 1.0 / 60.0

var _impacts: Array = [] # [hit: bool]
var _explosions: int = 0
var _kills: int = 0


func before_each() -> void:
	_impacts = []
	_explosions = 0
	_kills = 0


func _enemy(id: String) -> EnemyData:
	return EnemyCatalog.get_data(StringName(id))


## Synthetic weapon: fast turning, configurable everything else.
func _weapon(dmg: float, interval: float, range_cells: float, speed: float = 50.0,
		splash: float = 0.0, layers: int = Targeting.GROUND, type: int = Damage.Type.GENERIC) -> TurretData:
	var w := TurretData.new()
	w.id = &"test_weapon"
	w.damage = dmg
	w.damage_type = type
	w.fire_interval = interval
	w.range_cells = range_cells
	w.projectile_speed = speed
	w.splash_radius_cells = splash
	w.projectile = TurretData.ProjectileKind.MISSILE if splash > 0.0 else TurretData.ProjectileKind.BULLET
	w.target_layers = layers
	w.turn_speed_deg = 3600.0
	w.aim_tolerance_deg = 180.0
	return w


func _turret_structure(w: TurretData) -> StructureData:
	var d := H.structure("test_turret", 0, MovementClass.ALL_GROUND)
	d.category = StructureData.Category.TURRET
	d.turret = w
	return d


func _place(s: GameSession, data: StructureData, cell: Vector2i) -> TurretState:
	var check := s.construction.build(data, cell)
	assert_true(check.is_ok(), "turret placed at %s: %s" % [cell, ConstructionService.reason_text(check)])
	return s.combat.turret_at(check.placement)


func _watch(s: GameSession) -> void:
	s.combat.projectile_impact.connect(func(_p: Projectile, hit: bool) -> void: _impacts.append(hit))
	s.combat.explosion.connect(func(_pos: Vector2, _r: float, _k: int) -> void: _explosions += 1)
	s.enemies.enemy_killed.connect(func(_e: Enemy) -> void: _kills += 1)


func _run(s: GameSession, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		s.tick(DT)
