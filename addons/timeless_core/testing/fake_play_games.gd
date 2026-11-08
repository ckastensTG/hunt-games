extends RefCounted
## A stand-in for the Google Play Games Services for Godot plugin's Android
## singleton in tests (PlayGamesBackend.plugin): initialize, isAuthenticated,
## signIn, unlockAchievement and showAchievements, with the plugin's signal
## names.

signal userAuthenticated(is_authenticated: bool)
signal achievementUnlocked(is_unlocked: bool, achievement_id: String)

## What isAuthenticated() and signIn() answer: true, false, or "" to wait
## until the test calls answer().
var signed_in_answer: Variant = true
## What unlockAchievement answers.
var unlock_ok := true
var initialized := false
var unlocked_ids: Array[String] = []
var shows := 0
var sign_in_calls := 0


func initialize() -> void:
	initialized = true


func isAuthenticated() -> void:
	if signed_in_answer is bool:
		answer(signed_in_answer)


func signIn() -> void:
	sign_in_calls += 1
	if signed_in_answer is bool:
		answer(signed_in_answer)


func answer(ok: bool) -> void:
	userAuthenticated.emit(ok)


func unlockAchievement(id: String) -> void:
	if unlock_ok:
		unlocked_ids.append(id)
	achievementUnlocked.emit(unlock_ok, id)


func showAchievements() -> void:
	shows += 1
