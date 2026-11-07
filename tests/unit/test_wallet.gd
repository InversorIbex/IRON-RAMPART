extends "res://tests/framework/test_case.gd"

var _events: Array = []


func before_each() -> void:
	_events = []


func _record(credits: int, delta: int) -> void:
	_events.append([credits, delta])


func test_starting_credits_never_negative() -> void:
	assert_eq(Wallet.new(-50).get_credits(), 0)
	assert_eq(Wallet.new(300).get_credits(), 300)


func test_spend_and_earn_emit_signals() -> void:
	var w := Wallet.new(100)
	w.credits_changed.connect(_record)
	assert_true(w.spend(30))
	w.earn(5)
	assert_eq(w.get_credits(), 75)
	assert_eq(_events, [[70, -30], [75, 5]])


func test_cannot_overspend_or_spend_negative() -> void:
	var w := Wallet.new(20)
	w.credits_changed.connect(_record)
	assert_false(w.spend(21))
	assert_false(w.spend(-5))
	w.earn(-10)
	assert_eq(w.get_credits(), 20)
	assert_eq(_events.size(), 0, "no signal on rejected operations")
