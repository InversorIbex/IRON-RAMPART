class_name Damage
extends RefCounted
## Damage model: final damage = amount x MULTIPLIER[damage type][armor class].
## One table, one formula, used by every damage source through
## EnemyRoster.damage() (single entry point for HP, death and rewards).
##
##              NONE   LIGHT  HEAVY      (armor class)
##   GENERIC    1.00   0.75   0.40       untyped damage (debug, tests, hazards)
##   BULLET     1.00   0.50   0.10       HMG: shreds infantry, useless vs tanks
##   EXPLOSIVE  0.60   1.00   1.00       missiles: built for armour
##   FLAK       0.60   0.40   0.15       anti-air bursts (vs ground, if allowed)

enum Type { GENERIC, BULLET, EXPLOSIVE, FLAK }
enum ArmorClass { NONE, LIGHT, HEAVY }

const MULTIPLIER := [
	[1.00, 0.75, 0.40],
	[1.00, 0.50, 0.10],
	[0.60, 1.00, 1.00],
	[0.60, 0.40, 0.15],
]


static func multiplier(type: int, armor_class: int) -> float:
	return MULTIPLIER[type][armor_class]


static func compute(amount: float, type: int, armor_class: int) -> float:
	if amount <= 0.0:
		return 0.0
	return amount * multiplier(type, armor_class)


static func type_name(type: int) -> String:
	return Type.keys()[type]
