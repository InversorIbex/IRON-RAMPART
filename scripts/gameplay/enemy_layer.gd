class_name EnemyLayer
extends Node2D
## Creates/frees EnemyView instances from EnemyRoster signals and syncs them
## in one loop per frame (instead of one _process per enemy).
## Child of GridView, so it shares its offset/scale.

const VIEW_SCENE := preload("res://scenes/enemies/enemy_view.tscn")

var _views: Dictionary = {} # enemy id -> EnemyView
var _cell_size: float = 64.0


func bind(roster: EnemyRoster, cell_size: float) -> void:
	_cell_size = cell_size
	roster.enemy_spawned.connect(_on_spawned)
	roster.enemy_killed.connect(_on_exit.bind(true))
	roster.enemy_reached_base.connect(_on_exit.bind(false))
	for enemy in roster.get_enemies():
		_on_spawned(enemy)


func sync(delta: float) -> void:
	for view in _views.values():
		(view as EnemyView).sync(delta)


func view_count() -> int:
	return _views.size()


func _on_spawned(enemy: Enemy) -> void:
	var view: EnemyView = VIEW_SCENE.instantiate()
	view.setup(enemy, _cell_size)
	add_child(view)
	_views[enemy.id] = view


func _on_exit(enemy: Enemy, killed: bool) -> void:
	var view: EnemyView = _views.get(enemy.id)
	if view == null:
		return
	_views.erase(enemy.id)
	view.play_exit(killed)
