class_name PlayGamesBackend
extends AchievementBackend
## Google Play Games, from the Google Play Games Services for Godot plugin
## (Jacob Ibáñez Sánchez, MIT, v3.4.0; addons/GodotPlayGameServices, Play
## Games Services v2). Android only. The plugin's Android half is the
## "GodotPlayGameServices" engine singleton; its autoload of the same name
## wraps it and has to be initialized before anything else. This talks to
## the singleton directly (no plugin class names), so the core still loads
## without the plugin.
##
##   start:  connect, initialize, then ask whether the player is signed in.
##           Play Games v2 signs players in by itself when the game starts
##           (the "Welcome back" bar); no sign-in button is needed.
##   report: unlockAchievement. Play Games keeps unlocks made offline and
##           sends them when it can.
##   show:   Play Games' achievements screen.
##
## The Play Games Services project ID goes in the Android presets' export
## option godot_play_game_services/game_id (Project → Export, set in the
## editor); the plugin writes it into the app's manifest.

const SINGLETON := "GodotPlayGameServices"
const AUTOLOAD := "/root/GodotPlayGameServices"

## Tests set a stand-in (testing/fake_play_games.gd); otherwise the plugin's
## singleton.
var plugin: Object = null
var _reporting := {}  # achievement ID -> key


static func available() -> bool:
	return OS.has_feature("android") and Engine.has_singleton(SINGLETON)


func kind() -> String:
	return "play_games"


func start(achievement_ids: Dictionary, debug_build: bool) -> void:
	super(achievement_ids, debug_build)
	var autoload: Node = null
	if plugin == null:
		plugin = Engine.get_singleton(SINGLETON)
		var tree := Engine.get_main_loop() as SceneTree
		autoload = tree.root.get_node_or_null(AUTOLOAD) if tree else null
	plugin.userAuthenticated.connect(_on_authenticated)
	plugin.achievementUnlocked.connect(_on_unlocked)
	if autoload and autoload.has_method("initialize"):
		autoload.initialize()  # also initializes the singleton
	else:
		plugin.initialize()
	plugin.isAuthenticated()


func sign_in() -> void:
	_log("signing in to Google Play Games")
	plugin.signIn()


func _on_authenticated(ok: bool) -> void:
	is_signed_in = ok
	_log("Google Play Games: %s" % ("signed in" if ok else "not signed in"))
	signed_in.emit(ok)


func report(key: String) -> void:
	var id := str(ids[key])
	_reporting[id] = key
	plugin.unlockAchievement(id)


func _on_unlocked(ok: bool, id: String) -> void:
	var key: String = _reporting.get(id, key_for(id))
	_reporting.erase(id)
	if key == "":
		return
	if not ok:
		_log("Google Play Games didn't take %s" % key)
	reported.emit(key, ok)


func show_achievements() -> bool:
	if not is_signed_in:
		return false
	plugin.showAchievements()
	return true


func key_for(id: String) -> String:
	for k in ids:
		if str(ids[k]) == id:
			return k
	return ""
