class_name EnemyView
extends Node2D
## Placeholder visual for one Enemy (scene: scenes/enemies/enemy_view.tscn).
## Reads the model, never changes it. Drawn facing +X; the node rotates.
## Shapes come from EnemyData.silhouette/visual_size, so new enemy types need
## no new view code unless they need a new silhouette.

const TURN_SPEED := 10.0 # radians/s cap for heading smoothing
const EXIT_TIME := 0.3

var enemy: Enemy
var _cell: float = 64.0
var _lane: Vector2 = Vector2.ZERO
var _last_hp: float = -1.0
var _last_state: int = -1
var _bob_phase: float = 0.0
var _exiting: bool = false


func setup(p_enemy: Enemy, cell_size: float) -> void:
	enemy = p_enemy
	_cell = cell_size
	# Deterministic small lateral offset so units sharing a route stay readable.
	_lane = Vector2(0, ((enemy.id * 7) % 5 - 2) * cell_size * 0.06)
	_bob_phase = float(enemy.id) * 1.7
	rotation = enemy.heading.angle()
	position = enemy.position
	z_index = 1 if enemy.data.silhouette == EnemyData.Silhouette.SOLDIER else 0


func sync(delta: float) -> void:
	if _exiting or enemy == null:
		return
	var target := enemy.heading.angle()
	var diff := wrapf(target - rotation, -PI, PI)
	rotation += clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)
	position = enemy.position + _lane.rotated(rotation)
	if enemy.data.silhouette == EnemyData.Silhouette.SOLDIER and enemy.state == Enemy.State.MOVING:
		_bob_phase += delta * 14.0
		scale = Vector2.ONE * (1.0 + 0.06 * sin(_bob_phase))
	if enemy.hp != _last_hp or enemy.state != _last_state:
		_last_hp = enemy.hp
		_last_state = enemy.state
		queue_redraw()


## Death or arrival: short fade, then free. The model is already gone.
func play_exit(killed: bool) -> void:
	_exiting = true
	modulate = Palette.ALERT_RED if killed else Palette.TACTICAL_GOLD
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, EXIT_TIME)
	tween.tween_property(self, "scale", Vector2.ONE * (1.6 if killed else 0.4), EXIT_TIME)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	if enemy == null:
		return
	var d := enemy.data
	var size := d.visual_size * _cell
	var body := d.placeholder_color
	var dark := body.darkened(0.45)
	var shadow := Color(0, 0, 0, 0.3)
	var half := size * 0.5
	match d.silhouette:
		EnemyData.Silhouette.SOLDIER:
			var r := half.x
			draw_circle(Vector2(2, 3), r, shadow)
			draw_circle(Vector2.ZERO, r, body)
			draw_circle(Vector2.ZERO, r * 0.55, dark) # helmet
			draw_line(Vector2(0, r * 0.5), Vector2(r * 1.5, r * 0.5), dark, 3.0) # rifle
		EnemyData.Silhouette.WHEELED_VEHICLE:
			var rect := Rect2(-half, size)
			draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), shadow)
			for wx in [-0.32, 0.32]:
				for wy in [-1.0, 1.0]:
					draw_rect(Rect2(Vector2(wx * size.x - 6, wy * half.y - 4), Vector2(12, 8)), Color(0.12, 0.12, 0.1))
			draw_rect(rect, body)
			draw_rect(Rect2(Vector2(half.x * 0.25, -half.y * 0.7), Vector2(half.x * 0.6, size.y * 0.7)), dark) # cab
		EnemyData.Silhouette.TRACKED_VEHICLE:
			var rect := Rect2(-half, size)
			draw_rect(Rect2(rect.position + Vector2(3, 5), rect.size), shadow)
			draw_rect(Rect2(Vector2(-half.x, -half.y), Vector2(size.x, size.y * 0.22)), Color(0.12, 0.12, 0.1))
			draw_rect(Rect2(Vector2(-half.x, half.y * 0.56), Vector2(size.x, size.y * 0.22)), Color(0.12, 0.12, 0.1))
			draw_rect(Rect2(Vector2(-half.x * 0.9, -half.y * 0.6), Vector2(size.x * 0.9, size.y * 0.6)), body)
			draw_circle(Vector2(-half.x * 0.05, 0), half.y * 0.5, dark) # turret
			draw_line(Vector2(0, 0), Vector2(half.x * 1.25, 0), dark, 5.0) # barrel
	# Enemy marker so units never blend with friendly structures.
	draw_arc(Vector2.ZERO, maxf(half.x, half.y) + 3.0, 0.0, TAU, 20, Color(Palette.ALERT_RED, 0.8), 2.0)
	if enemy.hp < d.max_hp:
		var w := maxf(size.x, 24.0)
		var frac := clampf(enemy.hp / d.max_hp, 0.0, 1.0)
		var top := Vector2(-w * 0.5, -maxf(half.x, half.y) - 12.0)
		# HP bar is drawn in local space; counter-rotate so it stays horizontal.
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_rect(Rect2(top, Vector2(w, 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top, Vector2(w * frac, 5)), Palette.ALERT_RED if frac < 0.35 else Palette.TACTICAL_GOLD)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if enemy.state == Enemy.State.BLOCKED:
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_string(ThemeDB.fallback_font, Vector2(-6, -half.y - 16), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.ALERT_RED)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
