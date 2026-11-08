class_name GameCenterBackend
extends AchievementBackend
## Game Center, from Godot Apple Plugins (Miguel de Icaza / Xogot, MIT;
## addons/GodotApplePluginsGameCenter and its runtime, a GDExtension that
## loads by itself). Its classes are reached through ClassDB, so the core
## still loads without the plugin. iPhone and iPad only (the plugin also runs
## in the macOS editor, where there's no game to sign in to).
##
##   start:  GameCenterManager.authenticate(): the "Welcome back" banner, or
##           Game Center's sign-in sheet the first time. GameKit shows that
##           sheet once per launch; a player who closes it can sign in from
##           the Achievements button (sign_in) or iOS Settings.
##   report: GKAchievement at 100%, with Game Center's completion banner.
##   show:   Game Center's dashboard, on its Achievements page.
##
## Callbacks from the plugin take the error last (null when it worked).

const MANAGER := "GameCenterManager"
const ACHIEVEMENT := "GKAchievement"
const VIEW := "GKGameCenterViewController"
## GKGameCenterViewController.State.ACHIEVEMENTS
const STATE_ACHIEVEMENTS := 2

## Tests set a stand-in (testing/fake_game_center.gd); otherwise made in
## start().
var manager: Object = null
## Tests: the stand-in for GKAchievement's static calls (make, report).
var achievements: Object = null
## Tests: the stand-in for GKGameCenterViewController.show_type.
var view: Object = null


static func available() -> bool:
	return OS.has_feature("ios") and ClassDB.class_exists(MANAGER)


func kind() -> String:
	return "game_center"


func start(achievement_ids: Dictionary, debug_build: bool) -> void:
	super(achievement_ids, debug_build)
	if manager == null:
		manager = ClassDB.instantiate(MANAGER)
	manager.authentication_result.connect(_on_authentication_result)
	manager.authentication_error.connect(_on_authentication_error)
	sign_in()


func sign_in() -> void:
	_log("signing in to Game Center")
	manager.authenticate()


func _on_authentication_result(ok: bool) -> void:
	is_signed_in = ok
	_log("Game Center: %s" % ("signed in" if ok else "not signed in"))
	signed_in.emit(ok)


func _on_authentication_error(message: String) -> void:
	is_signed_in = false
	_log("Game Center sign-in failed: %s" % message)
	signed_in.emit(false)


func report(key: String) -> void:
	var a: Object = _static(ACHIEVEMENT, "make", [str(ids[key])])
	if a == null:
		reported.emit.call_deferred(key, false)
		return
	a.percent_complete = 100.0
	a.shows_completion_banner = true
	_static(ACHIEVEMENT, "report_achievement", [[a], func(error: Variant) -> void:
		if error:
			_log("Game Center didn't take %s: %s" % [key, str(error)])
		reported.emit(key, not error)])


func show_achievements() -> bool:
	if not is_signed_in:
		return false
	_static(VIEW, "show_type", [STATE_ACHIEVEMENTS])
	return true


## A static method of the plugin's class, or of the test stand-in.
func _static(cls: String, method: String, args: Array) -> Variant:
	var stand_in: Object = achievements if cls == ACHIEVEMENT else (view if cls == VIEW else null)
	if stand_in:
		return stand_in.callv(method, args)
	return ClassDB.callv("class_call_static", [cls, method] + args)
