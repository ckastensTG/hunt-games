class_name AchievementBackend
extends Node
## Where achievements go. AchievementService picks one when it starts:
##   GameCenterBackend  Game Center (iPhone and iPad, Godot Apple Plugins'
##                      GameKit);
##   PlayGamesBackend   Google Play Games (Android, the Google Play Games
##                      Services for Godot plugin);
##   AchievementBackend this one: no service (desktop, the Epic store build,
##                      tools). Unlocks are still kept on the device.
## Achievements are known by a key (e.g. "first_lesson") and the service's
## own ID for it (Game Center's achievement ID, Google Play's
## "CgkI…" ID).

## Signed in (or not) to the service: Game Center's local player, Google
## Play Games' player. Unlocks are only sent while signed in.
signal signed_in(ok: bool)
## The service has the unlock (`ok`), or couldn't take it now (no network,
## not signed in): the service keeps it and tries again later.
signal reported(key: String, ok: bool)

## key -> the service's achievement ID.
var ids := {}
var debug := false
var is_signed_in := false


## "none", "game_center" or "play_games".
func kind() -> String:
	return "none"


func start(achievement_ids: Dictionary, debug_build: bool) -> void:
	ids = achievement_ids
	debug = debug_build


## Sends one unlock. Ends with exactly one `reported`.
func report(key: String) -> void:
	reported.emit.call_deferred(key, false)


## The service's own achievements screen. False when it can't show it now.
func show_achievements() -> bool:
	return false


## Signs in again (the player turned it down at start, or it failed).
func sign_in() -> void:
	pass


func _log(text: String) -> void:
	if debug:
		print("[achievements] " + text)
