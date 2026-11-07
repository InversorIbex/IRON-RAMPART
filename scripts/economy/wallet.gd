class_name Wallet
extends RefCounted
## Military credits. Never negative; every change emits `credits_changed`.

signal credits_changed(credits: int, delta: int)

var _credits: int = 0


func _init(starting_credits: int = 0) -> void:
	_credits = maxi(0, starting_credits)


func get_credits() -> int:
	return _credits


func can_afford(amount: int) -> bool:
	return amount >= 0 and amount <= _credits


## Returns false (and changes nothing) if the amount is invalid or unaffordable.
func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	if amount == 0:
		return true
	_credits -= amount
	credits_changed.emit(_credits, -amount)
	return true


func earn(amount: int) -> void:
	if amount <= 0:
		return
	_credits += amount
	credits_changed.emit(_credits, amount)
