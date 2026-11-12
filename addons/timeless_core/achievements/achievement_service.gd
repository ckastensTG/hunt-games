class_name AchievementService
extends Node
## Every achievement goes through here: one per app, made by instance() and
## kept under the scene tree's root as "Achievements", like AdService and
## IAPService. The title starts it once with its achievements
## (TitleConfig.achievements_setup()) and calls unlock(key) when the player
## earns one; the title decides what earns it.
##
## What the title calls:
##   unlock(key)        earned: kept on the device at once
##                      (user://achievements.cfg) and sent to Game Center or
##                      Google Play Games. An unlock that can't be sent now
##                      (offline, not signed in yet) is sent at the next
##                      sign-in, at the next start or when the app comes back.
##   has(key)           earned on this device
##   can_show()         the service is there (the Achievements button)
##   show(then)         the service's achievements screen; `then(ok)`, false
##                      when it couldn't open (signs in again first)
##
## No service (desktop, the Epic store build, tools): unlocks are still kept,
## so they go out if the same install later gets one.

## An achievement was earned, or the service changed (signed in or out).
signal changed

const NODE_NAME := "Achievements"
const SAVE_PATH := "user://achievements.cfg"

## Tests and tools: "none", "game_center" or "play_games" instead of the
## platform's choice.
static var backend_override := ""
static var _instance: AchievementService

var backend: AchievementBackend
## key -> true: earned on this device.
var earned := {}
## key -> true: the service has it.
var sent := {}
var save_path := SAVE_PATH
var debug := false

var _setup := {}
var _sending := {}


static func instance() -> AchievementService:
	if is_instance_valid(_instance):
		return _instance
	_instance = AchievementService.new()
	_instance.name = NODE_NAME
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.add_child.call_deferred(_instance)
	return _instance


## `setup`: {achievements: {key: {"game_center": id, "play_games": id}},
## debug: bool}. Once.
func start(setup: Dictionary) -> void:
	if backend:
		return
	_setup = setup
	debug = bool(setup.get("debug", false))
	_load()
	_use(pick_backend(setup))


## The service where its plugin runs and the title has IDs for it; otherwise
## none. Until a title's store records exist (no Game Center or Google Play
## Games IDs yet), it doesn't sign in at all: Google Play Games can't without
## the game ID in the Android presets, and an empty achievements screen helps
## nobody. Unlocks are still kept, and go out from the first build with IDs.
static func pick_backend(setup: Dictionary) -> String:
	if backend_override != "":
		return backend_override
	if (setup.get("achievements", {}) as Dictionary).is_empty():
		return "none"
	if GameCenterBackend.available() and has_ids(setup, "game_center"):
		return "game_center"
	if PlayGamesBackend.available() and has_ids(setup, "play_games"):
		return "play_games"
	return "none"


## Whether the title gave any of its achievements an ID on this service
## ("game_center" or "play_games").
static func has_ids(setup: Dictionary, kind: String) -> bool:
	var all: Dictionary = setup.get("achievements", {})
	for key in all:
		if str((all[key] as Dictionary).get(kind, "")) != "":
			return true
	return false


func _use(kind: String) -> void:
	if backend:
		backend.queue_free()
	match kind:
		"game_center":
			backend = GameCenterBackend.new()
		"play_games":
			backend = PlayGamesBackend.new()
		_:
			backend = AchievementBackend.new()
	backend.name = "Backend"
	backend.signed_in.connect(_on_signed_in)
	backend.reported.connect(_on_reported)
	add_child(backend)
	backend.start(ids_for(kind), debug)
	changed.emit()


## key -> this service's ID, for the achievements the title gave one.
func ids_for(kind: String) -> Dictionary:
	var out := {}
	var all: Dictionary = _setup.get("achievements", {})
	for key in all:
		var id := str((all[key] as Dictionary).get(kind, ""))
		if id != "":
			out[key] = id
	return out


func has(key: String) -> bool:
	return earned.has(key)


func keys() -> Array:
	return (_setup.get("achievements", {}) as Dictionary).keys()


## Earned: kept, then sent. Earning it again does nothing.
func unlock(key: String) -> void:
	if not (_setup.get("achievements", {}) as Dictionary).has(key):
		push_warning("unknown achievement: %s" % key)
		return
	if not earned.has(key):
		earned[key] = true
		_save()
		_log("earned %s" % key)
		changed.emit()
	_send(key)


## The Achievements button: only where a service runs.
func can_show() -> bool:
	return backend != null and backend.kind() != "none"


## The service's screen. Signs in first when the player isn't (Game Center
## and Google Play Games both ask on the first start; a player who said no
## then can still say yes here).
func show(then := Callable()) -> void:
	if not can_show():
		if then.is_valid():
			then.call(false)
		return
	if backend.is_signed_in:
		var ok := backend.show_achievements()
		if then.is_valid():
			then.call(ok)
		return
	backend.signed_in.connect(func(ok: bool) -> void:
		var shown := ok and backend.show_achievements()
		if then.is_valid():
			then.call(shown), CONNECT_ONE_SHOT)
	backend.sign_in()


## Sends what was earned and isn't with the service yet.
func flush() -> void:
	for key in earned:
		_send(key)


func _send(key: String) -> void:
	if sent.has(key) or _sending.has(key) or backend == null or not backend.is_signed_in:
		return
	if not backend.ids.has(key):
		return  # no ID on this service (yet): kept until there is one
	_sending[key] = true
	backend.report(key)


func _on_signed_in(ok: bool) -> void:
	_log("signed in: %s" % ok)
	if ok:
		flush()
	changed.emit()


func _on_reported(key: String, ok: bool) -> void:
	_sending.erase(key)
	if ok and not sent.has(key):
		sent[key] = true
		_save()
	_log("%s %s" % [key, "sent" if ok else "not sent (kept for later)"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		flush()


## Test builds: forget every achievement on this device (the services keep
## theirs: Game Center's are reset in the sandbox, Google Play's in Play
## Console's testing tools).
func forget() -> void:
	earned.clear()
	sent.clear()
	_save()
	changed.emit()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	for section in [["earned", earned], ["sent", sent]]:
		if cfg.has_section(section[0]):
			for k in cfg.get_section_keys(section[0]):
				if bool(cfg.get_value(section[0], k, false)):
					section[1][k] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in earned:
		cfg.set_value("earned", k, true)
	for k in sent:
		cfg.set_value("sent", k, true)
	cfg.save(save_path)


func _log(text: String) -> void:
	if debug:
		print("[achievements] " + text)
