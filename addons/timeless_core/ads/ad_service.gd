class_name AdService
extends Node
## Every ad goes through here (bible §3.1): one per app, made by instance()
## and kept under the scene tree's root as "Ads", like an autoload, so it
## lasts across scenes. The title starts it once with its ad units
## (TitleConfig.ad_setup()).
##
## What the title calls:
##   game_finished()       a game played by a person ended (counts for the cap)
##   after_game(then)      a break after a finished game (Play again on this
##                         device, Main menu, New opponent): shows an
##                         interstitial when AdPolicy says one is due and one
##                         is loaded, then calls `then`. Never called for a
##                         rematch against another player, nor while an
##                         online search runs in the background.
##   show_rewarded(then)   an optional video for an extra; `then` gets a
##                         Reward. The title grants the extra
##                         (unlock_extras_for_session for Bagh Chal's looks).
##   extras_unlocked()     the extras are open: the player removed ads, or
##                         watched a video this session, or there are no ads
##                         on this platform.
##
## "Remove ads" (remove_ads, US$1.99; bible §3.1) sets ads_removed through
## set_ads_removed(), saved in user://ads.cfg. The store purchase and
## restore come with IAPService (next round); until then nothing sets it.
##
## While an ad is on screen the game's sound is muted.

enum Reward { EARNED, SKIPPED, UNAVAILABLE }

signal changed

const NODE_NAME := "Ads"
const SAVE_PATH := "user://ads.cfg"
## Our own phones and tablets, registered as test devices: hashed device IDs
## as the device log prints them when the app asks for consent (Android:
## "Use new ConsentDebugSettings.Builder().addTestDeviceHashedId(...)", in
## logcat; iOS: "<UMP SDK> To enable debug mode for this device, set:
## UMPDebugSettings.testDeviceIdentifiers = ...", in the Mac's Console app
## with the device selected). Debug builds only; they let the EEA consent
## form show on these devices. The moto g(20) got the form without being
## listed (2026-11-06).
const TEST_DEVICES: Array[String] = [
	"29607432-B2E1-4062-8822-CE5030555326",  # Christopher's iPad Air 3 (2026-11-06)
]

## Tests and tools: "none" or "sim" instead of the platform's choice.
static var backend_override := ""
static var _instance: AdService

var backend: AdBackend
var policy := AdPolicy.new(Time.get_ticks_msec())
## The player bought "Remove ads".
var ads_removed := false
## A rewarded video was watched this session (until the app closes).
var extras_unlocked_for_session := false
## An ad is on screen.
var showing := false
var save_path := SAVE_PATH

var _then := Callable()
var _reward_then := Callable()
var _muted_before := false


## The app's AdService, made on first use.
static func instance() -> AdService:
	if is_instance_valid(_instance):
		return _instance
	_instance = AdService.new()
	_instance.name = NODE_NAME
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		# Deferred: the main scene may still be setting up under the root.
		tree.root.add_child.call_deferred(_instance)
	return _instance


## Picks the backend and starts it (consent, then loading ads). Once.
func start(setup: Dictionary) -> void:
	if backend:
		return
	_load_entitlements()
	match pick_backend(setup):
		"admob":
			backend = AdmobAdBackend.new()
		"sim":
			backend = SimAdBackend.new()
		_:
			backend = AdBackend.new()
	backend.name = "Backend"
	backend.changed.connect(func() -> void: changed.emit())
	backend.interstitial_closed.connect(_on_interstitial_closed)
	backend.rewarded_closed.connect(_on_rewarded_closed)
	add_child(backend)
	var s := setup.duplicate()
	if not s.has("test_devices"):
		s["test_devices"] = TEST_DEVICES
	backend.start(s)


## AdMob where its plugin runs and the title has ad units; the labelled
## stand-in in other test builds with a screen; otherwise none.
static func pick_backend(setup: Dictionary) -> String:
	if backend_override != "":
		return backend_override
	if AdmobAdBackend.available() and str(setup.get("interstitial", "")) != "":
		return "admob"
	if OS.is_debug_build() and DisplayServer.get_name() != "headless":
		return "sim"
	return "none"


## Ads can show: there's a backend with ads and the player hasn't removed them.
func ads_enabled() -> bool:
	return backend != null and backend.kind() != "none" and not ads_removed


func extras_unlocked() -> bool:
	return ads_removed or extras_unlocked_for_session or not ads_enabled()


func unlock_extras_for_session() -> void:
	if not extras_unlocked_for_session:
		extras_unlocked_for_session = true
		changed.emit()


func game_finished() -> void:
	policy.game_finished()


## A break after a finished game: an interstitial if one is due and ready,
## then `then` (called at once when there's no ad).
func after_game(then := Callable()) -> void:
	if showing or not ads_enabled() or not policy.interstitial_due(Time.get_ticks_msec()) \
			or not backend.interstitial_ready():
		if then.is_valid():
			then.call()
		return
	showing = true
	_then = then
	_mute(true)
	backend.show_interstitial()


func rewarded_ready() -> bool:
	return ads_enabled() and not showing and backend.rewarded_ready()


## Shows a rewarded video; `then` gets a Reward: EARNED (watched to the end),
## SKIPPED (closed early) or UNAVAILABLE (none loaded, or it couldn't show).
func show_rewarded(then: Callable) -> void:
	if not rewarded_ready():
		then.call(Reward.UNAVAILABLE)
		return
	showing = true
	_reward_then = then
	_mute(true)
	backend.show_rewarded()


func privacy_options_available() -> bool:
	return backend != null and backend.privacy_options_available()


func show_privacy_options() -> void:
	if backend:
		backend.show_privacy_options()


## "Remove ads" bought or restored (IAPService), or refunded (false).
func set_ads_removed(on: bool) -> void:
	ads_removed = on
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value("entitlements", "remove_ads", on)
	cfg.save(save_path)
	changed.emit()


func _load_entitlements() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		ads_removed = bool(cfg.get_value("entitlements", "remove_ads", false))


func _on_interstitial_closed(shown: bool) -> void:
	showing = false
	_mute(false)
	if shown:
		policy.interstitial_shown(Time.get_ticks_msec())
	var then := _then
	_then = Callable()
	if then.is_valid():
		then.call()


func _on_rewarded_closed(earned: bool, shown: bool) -> void:
	showing = false
	_mute(false)
	if shown:
		policy.rewarded_shown(Time.get_ticks_msec())
	var then := _reward_then
	_reward_then = Callable()
	if then.is_valid():
		then.call(Reward.EARNED if earned else (Reward.SKIPPED if shown else Reward.UNAVAILABLE))


## The master bus is muted while an ad plays (the ad has its own sound).
func _mute(on: bool) -> void:
	if on:
		_muted_before = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
	else:
		AudioServer.set_bus_mute(0, _muted_before)
