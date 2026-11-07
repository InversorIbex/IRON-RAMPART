class_name EnemyView
extends Node2D
## Placeholder visual for one Enemy (scene: scenes/enemies/enemy_view.tscn).
## Reads the model, never changes it. Drawn facing +X; the node rotates.
## Shapes come from EnemyData.silhouette/visual_size, so new enemy types need
## no new view code unless they need a new silhouette.

const TURN_SPEED := 10.0 # radians/s cap for heading smoothing
const EXIT_TIME := 0.3
const HIT_FLASH_TIME := 0.08

var enemy: Enemy
var _cell: float = 64.0
var _lane: Vector2 = Vector2.ZERO
var _last_hp: float = -1.0
var _last_state: int = -1
var _bob_phase: float = 0.0
var _exiting: bool = false
var _last_hits: int = 0
var _hit_flash: float = 0.0


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
	if enemy.hits_taken != _last_hits:
		_last_hits = enemy.hits_taken
		_hit_flash = HIT_FLASH_TIME
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		queue_redraw()
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
	var half := size * 0.5
	var hull := Palette.ENEMY_HULL.lerp(d.placeholder_color, 0.25)
	var line := Palette.ENEMY_OUTLINE
	var mark := Palette.ALERT_RED
	match d.silhouette:
		EnemyData.Silhouette.SOLDIER:
			var r := half.x
			draw_circle(Vector2(2, 3), r, Palette.SHADOW)
			draw_circle(Vector2.ZERO, r + 2.0, line)
			draw_circle(Vector2.ZERO, r, hull)
			draw_line(Vector2(0, r * 0.45), Vector2(r * 1.7, r * 0.45), line, 3.0) # rifle
			draw_circle(Vector2.ZERO, r * 0.5, mark) # helmet band
		EnemyData.Silhouette.WHEELED_VEHICLE:
			var rect := Rect2(-half, size)
			draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Palette.SHADOW)
			for wx in [-0.3, 0.3]:
				for wy in [-1.0, 1.0]:
					draw_rect(Rect2(Vector2(wx * size.x - 7, wy * half.y - 5), Vector2(14, 10)), Palette.TRACK)
			draw_rect(rect.grow(2.0), line)
			draw_rect(rect, hull)
			draw_rect(Rect2(Vector2(half.x * 0.2, -half.y * 0.65), Vector2(half.x * 0.6, size.y * 0.65)), Palette.METAL) # cab
			_draw_chevron(Vector2(-half.x * 0.35, 0), half.y * 0.5, mark)
		EnemyData.Silhouette.TRACKED_VEHICLE:
			var rect := Rect2(-half, size)
			draw_rect(Rect2(rect.position + Vector2(3, 5), rect.size), Palette.SHADOW)
			draw_rect(rect.grow(2.0), line)
			draw_rect(Rect2(Vector2(-half.x, -half.y), Vector2(size.x, size.y * 0.24)), Palette.TRACK)
			draw_rect(Rect2(Vector2(-half.x, half.y * 0.52), Vector2(size.x, size.y * 0.24)), Palette.TRACK)
			draw_rect(Rect2(Vector2(-half.x * 0.92, -half.y * 0.55), Vector2(size.x * 0.92, size.y * 0.55)), hull)
			draw_line(Vector2(0, 0), Vector2(half.x * 1.35, 0), line, 7.0) # barrel outline
			draw_line(Vector2(0, 0), Vector2(half.x * 1.3, 0), Palette.METAL_DARK, 4.0)
			draw_circle(Vector2(-half.x * 0.05, 0), half.y * 0.5, Palette.METAL)
			_draw_chevron(Vector2(-half.x * 0.55, 0), half.y * 0.35, mark)
	# Hit flash: brief light overlay when the unit takes damage.
	if _hit_flash > 0.0:
		draw_circle(Vector2.ZERO, maxf(half.x, half.y) * 0.9, Color(Palette.FX_FLASH, 0.55 * _hit_flash / HIT_FLASH_TIME))
	# HP bar and blocked marker stay horizontal: counter-rotate.
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var top_y := -maxf(half.x, half.y) - 14.0
	if enemy.hp < enemy.max_hp:
		var w := maxf(size.x, 30.0)
		var frac := clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
		var top := Vector2(-w * 0.5, top_y)
		draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 8)), Palette.OLIVE_BLACK)
		draw_rect(Rect2(top, Vector2(w * frac, 6)), Palette.ALERT_RED if frac < 0.35 else Palette.TACTICAL_GOLD)
	if enemy.state == Enemy.State.BLOCKED:
		draw_string(ThemeDB.fallback_font, Vector2(-6, top_y - 4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.ALERT_RED)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_chevron(at: Vector2, size: float, color: Color) -> void:
	draw_polyline(PackedVector2Array([at + Vector2(-size, -size), at + Vector2(0, 0), at + Vector2(-size, size)]), color, 3.0)
