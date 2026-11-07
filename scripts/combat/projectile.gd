class_name Projectile
extends RefCounted
## One projectile in flight (pure data, moved by CombatSystem).
## Homing: while its target lives it steers to it, so it always connects.
## If the target dies or reaches the base first, the projectile keeps flying
## to the last known position: bullets then fizzle (no damage), missiles and
## flak still detonate there (area damage only).

var kind: int # TurretData.ProjectileKind
var source: TurretState
var target: Enemy
var target_pos: Vector2
var position: Vector2
var origin: Vector2
var speed_px: float
var damage: float
var damage_type: int
var splash_px: float
var splash_falloff: float
var age: float = 0.0
## Set once on impact: guarantees a single damage application.
var done: bool = false


func heading() -> Vector2:
	var d := target_pos - position
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
