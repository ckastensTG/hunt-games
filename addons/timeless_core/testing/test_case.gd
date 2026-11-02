class_name TestCase
extends RefCounted
## Minimal test base. Methods named test_* run in file order; any failed
## assertion marks the test as failed (the test keeps running).

var _failures: Array[String] = []


func check(condition: bool, message := "check failed") -> void:
	if not condition:
		_failures.append(message)


func check_eq(actual: Variant, expected: Variant, message := "") -> void:
	if not _equal(actual, expected):
		_failures.append("%sexpected %s, got %s" % [message + ": " if message != "" else "", str(expected), str(actual)])


func fail(message: String) -> void:
	_failures.append(message)


func take_failures() -> Array[String]:
	var f := _failures
	_failures = []
	return f


static func _equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
			return float(a) == float(b)
		return false
	return a == b
