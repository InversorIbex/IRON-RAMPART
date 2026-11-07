extends RefCounted
## Minimal test base class. Any method starting with `test_` is a test.
## `before_each()` / `after_each()` run around every test. Failures are collected, not thrown.

var failures: Array[String] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("expected true. " + message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("expected false. " + message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected <%s> but got <%s>. %s" % [expected, actual, message])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		_fail("did not expect <%s>. %s" % [actual, message])


func assert_null(value: Variant, message: String = "") -> void:
	if value != null:
		_fail("expected null but got <%s>. %s" % [value, message])


func assert_not_null(value: Variant, message: String = "") -> void:
	if value == null:
		_fail("expected a non-null value. " + message)


func _fail(message: String) -> void:
	failures.append(message)
