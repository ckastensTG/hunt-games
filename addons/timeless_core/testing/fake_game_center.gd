extends RefCounted
## A stand-in for Godot Apple Plugins' Game Center classes in tests:
## GameCenterManager (authenticate and its two signals), GKAchievement's
## static make and report_achievement, and GKGameCenterViewController's
## show_type. One object plays all three (GameCenterBackend.manager,
## .achievements, .view).

signal authentication_result(status: bool)
signal authentication_error(message: String)

## What authenticate() answers: true (signed in), false (closed the sheet),
## or "" to wait until the test calls answer().
var sign_in_answer: Variant = true
## What report_achievement answers: null (it worked) or an error.
var report_error: Variant = null
## Every achievement ID reported, and every screen shown.
var reported_ids: Array[String] = []
var shown: Array[int] = []
var authenticate_calls := 0


class FakeAchievement:
	extends RefCounted
	var identifier := ""
	var percent_complete := 0.0
	var shows_completion_banner := false


func authenticate() -> void:
	authenticate_calls += 1
	if sign_in_answer is bool:
		answer(sign_in_answer)


func answer(ok: bool) -> void:
	authentication_result.emit(ok)


func make(identifier: String) -> Object:
	var a := FakeAchievement.new()
	a.identifier = identifier
	return a


func report_achievement(list: Array, callback: Callable) -> void:
	for a in list:
		if a.percent_complete >= 100.0 and a.shows_completion_banner:
			reported_ids.append(a.identifier)
	callback.call(report_error)


func show_type(state: int) -> void:
	shown.append(state)
