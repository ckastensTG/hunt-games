class_name AdmobAdBackend
extends AdBackend
## Google AdMob through Cengiz's AdMob plugin (addons/AdmobPlugin, v7.0, MIT;
## chosen 2026-11-06). The plugin's Admob node is made here in code, so no
## scene needs one, and the core still loads in a title without the plugin
## (everything goes through the loaded script, never its class names).
##
## Order at start (Google's UMP rules): consent first, then the SDK, then one
## interstitial and one rewarded video loaded ahead.
##   1. Ask Google's consent service where the player is. Where the law asks
##      for consent (EEA, UK, Switzerland, some US states) and no choice is
##      stored yet, load and show Google's consent form.
##   2. Start the SDK once ads may be requested (consent obtained or not
##      required). Offline at first launch: try again every few minutes and
##      when the app comes back to the front.
##   3. Keep one ad of each kind loaded. A failed load waits longer each time
##      (30 s up to 5 min); a loaded ad older than 55 min is dropped (Google
##      lets them expire after an hour).
##
## Debug builds (setup.debug) use Google's demo ad units (TitleConfig.ad_unit)
## and set the consent location to the EEA, so the form shows on test devices
## (setup.test_devices: hashed device IDs, printed in the device log).
## The App ID goes into the Android manifest from
## res://addons/AdmobPlugin/android_export.cfg (the real one in every build).
##
## Google shows the consent form only once a GDPR message is published for
## the app in AdMob (Privacy & messaging); until then the consent request
## fails ("no form(s) configured", seen on the moto 2026-11-06) and release
## builds never start the SDK, so no ads load. Test builds start it anyway
## after a failed request (demo ads only), so ads can be checked meanwhile.
## Debug builds log each step as "[ads]" lines (Godot's Output with remote
## debug, logcat, Xcode's console).
##
## iPhone and iPad: after consent and before the SDK starts, Apple's tracking
## prompt (App Tracking Transparency), so the first ad request can already
## use the advertising identifier where the player allows it. iOS shows the
## prompt once; later asks answer at once with the stored choice. Its text is
## NSUserTrackingUsageDescription in the iOS export preset's
## additional_plist_content. The App ID for iOS comes from
## res://addons/AdmobPlugin/ios_export.cfg.

const SCRIPT_PATH := "res://addons/AdmobPlugin/Admob.gd"
const SINGLETON := "AdmobPlugin"
const EXPIRE_MS := 55 * 60 * 1000
const RETRY_MS: Array[int] = [30_000, 60_000, 120_000, 300_000]
const CONSENT_RETRY_MS := 120_000
## iOS: if the tracking prompt gives no answer in this time (the plugin can't
## ask, or the player leaves it up), the SDK starts anyway.
const ATT_WAIT_MS := 60_000
## The plugin's UserConsent.Status.
enum Consent { UNKNOWN, NOT_REQUIRED, REQUIRED, OBTAINED }
## AdmobConfig.ContentRating: G, PG, T, MA. PG suits a strategy game rated
## for everyone (bible: Google Play target audience 13+).
const CONTENT_RATING_PG := 1
## ConsentRequestParameters.DebugGeography.EEA.
const DEBUG_GEOGRAPHY_EEA := 1

const INTERSTITIAL := "interstitial"
const REWARDED := "rewarded"

## Tests swap in testing/fake_admob.gd.
var script_path := SCRIPT_PATH
var _admob = null  # the plugin's Admob node (untyped: loaded at run time)
var _sdk_started := false
var _consent_retry_at := -1
var _loaded_at := {INTERSTITIAL: -1, REWARDED: -1}
var _loading := {INTERSTITIAL: false, REWARDED: false}
var _retry_at := {INTERSTITIAL: -1, REWARDED: -1}
var _fails := {INTERSTITIAL: 0, REWARDED: 0}
var _earned := false
var _debug := false
## Apple's tracking prompt comes before the SDK (tests set it).
var ios := OS.has_feature("ios")
var _att_asked_at := -1
var _att_answered := false


## True when the plugin runs on this device (its Android or iOS library is
## in the build).
static func available() -> bool:
	return Engine.has_singleton(SINGLETON) and ResourceLoader.exists(SCRIPT_PATH)


func kind() -> String:
	return "admob"


func start(setup: Dictionary) -> void:
	var script: Script = load(script_path)
	_admob = script.new()
	_admob.name = "Admob"
	var debug: bool = setup.get("debug", true)
	_debug = debug
	_admob.is_real = not debug
	# The title already picked the right units for this build (demo units in
	# debug builds), so both of the plugin's sets get the same ones.
	for prefix in ["android_debug_", "android_real_", "ios_debug_", "ios_real_"]:
		_admob.set(prefix + "interstitial_id", str(setup.get(INTERSTITIAL, "")))
		_admob.set(prefix + "rewarded_id", str(setup.get(REWARDED, "")))
	_admob.max_ad_content_rating = CONTENT_RATING_PG
	_admob.remove_interstitial_ads_after_displayed = true
	_admob.remove_rewarded_ads_after_displayed = true
	if debug:
		_admob.debug_geography = DEBUG_GEOGRAPHY_EEA
		var ids: Array[String] = []
		for id in setup.get("test_devices", []):
			ids.append(str(id))
		_admob.test_device_hashed_ids = ids
	_admob.consent_info_updated.connect(_on_consent_info_updated)
	_admob.consent_info_update_failed.connect(func(e: Variant) -> void:
		_log("consent request failed: %s" % _message(e))
		_start_sdk_if_allowed()
		# Test builds only: start anyway, so Google's demo ads can be checked
		# before the consent message exists. Release builds never do this.
		if _debug and not _sdk_started:
			_log("test build: starting the SDK without a consent answer (demo ads only)")
			_start_sdk())
	_admob.consent_form_loaded.connect(func() -> void:
		_log("consent form loaded, showing it")
		_admob.show_consent_form())
	_admob.consent_form_failed_to_load.connect(func(e: Variant) -> void:
		_log("consent form failed to load: %s" % _message(e))
		_start_sdk_if_allowed())
	_admob.consent_form_dismissed.connect(func(_e: Variant) -> void:
		_log("consent form closed, consent %s" % Consent.keys()[_consent()])
		_start_sdk_if_allowed()
		changed.emit())
	_admob.initialization_completed.connect(_on_initialized)
	if _admob.has_signal("tracking_authorization_granted"):
		_admob.tracking_authorization_granted.connect(_on_tracking_answer.bind(true))
		_admob.tracking_authorization_denied.connect(_on_tracking_answer.bind(false))
	_admob.interstitial_ad_loaded.connect(func(_a: Variant, _r: Variant) -> void: _on_loaded(INTERSTITIAL))
	_admob.interstitial_ad_failed_to_load.connect(func(_a: Variant, _e: Variant) -> void: _on_load_failed(INTERSTITIAL))
	_admob.interstitial_ad_dismissed_full_screen_content.connect(func(_a: Variant) -> void:
		_log("interstitial closed")
		interstitial_closed.emit(true)
		_load(INTERSTITIAL))
	_admob.interstitial_ad_failed_to_show_full_screen_content.connect(func(a: Variant, _e: Variant) -> void:
		_log("interstitial failed to show")
		_admob.remove_interstitial_ad(a.get_ad_id())
		interstitial_closed.emit(false)
		_load(INTERSTITIAL))
	_admob.rewarded_ad_loaded.connect(func(_a: Variant, _r: Variant) -> void: _on_loaded(REWARDED))
	_admob.rewarded_ad_failed_to_load.connect(func(_a: Variant, _e: Variant) -> void: _on_load_failed(REWARDED))
	_admob.rewarded_ad_user_earned_reward.connect(func(_a: Variant, _r: Variant) -> void: _earned = true)
	_admob.rewarded_ad_dismissed_full_screen_content.connect(func(_a: Variant) -> void:
		_log("rewarded closed, reward %s" % _earned)
		rewarded_closed.emit(_earned, true)
		_load(REWARDED))
	_admob.rewarded_ad_failed_to_show_full_screen_content.connect(func(a: Variant, _e: Variant) -> void:
		_log("rewarded failed to show")
		_admob.remove_rewarded_ad(a.get_ad_id())
		rewarded_closed.emit(false, false)
		_load(REWARDED))
	# Its _ready picks the ad units and finds the plugin; consent comes next.
	_admob.ready.connect(_ask_consent, CONNECT_ONE_SHOT)
	add_child(_admob)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _admob and not _sdk_started:
		_ask_consent()


func _process(_delta: float) -> void:
	if _admob == null:
		return
	var now := Time.get_ticks_msec()
	if _att_asked_at != -1 and not _att_answered and now - _att_asked_at >= ATT_WAIT_MS:
		_log("no answer to the tracking prompt, starting the SDK")
		_on_tracking_answer(false)
	if not _sdk_started:
		if _consent_retry_at >= 0 and now >= _consent_retry_at:
			_ask_consent()
		return
	for k in [INTERSTITIAL, REWARDED]:
		if not _loading[k] and _loaded_at[k] == -1 and _retry_at[k] >= 0 and now >= _retry_at[k]:
			_load(k)


# --- Consent and start ---------------------------------------------------------

func _ask_consent() -> void:
	_consent_retry_at = Time.get_ticks_msec() + CONSENT_RETRY_MS
	_admob.update_consent_info()


func _consent() -> int:
	var c: Variant = _admob.get_consent_status()
	return int(c.status) if c != null else Consent.UNKNOWN


func _on_consent_info_updated() -> void:
	_log("consent %s, form available: %s" % [Consent.keys()[_consent()], _admob.is_consent_form_available()])
	if _consent() == Consent.REQUIRED and _admob.is_consent_form_available():
		_admob.load_consent_form()
	else:
		_start_sdk_if_allowed()
	changed.emit()


func _start_sdk_if_allowed() -> void:
	if _sdk_started or _consent() not in [Consent.OBTAINED, Consent.NOT_REQUIRED]:
		return
	_start_sdk()


func _start_sdk() -> void:
	if ios and not _att_answered:
		_ask_tracking()
		return
	_sdk_started = true
	_consent_retry_at = -1
	_log("starting the SDK")
	_admob.initialize()


## iOS: Apple's tracking prompt; the SDK starts once it's answered.
func _ask_tracking() -> void:
	if _att_asked_at != -1:
		return
	_att_asked_at = Time.get_ticks_msec()
	_consent_retry_at = -1
	_log("asking for tracking permission")
	_admob.request_tracking_authorization()


func _on_tracking_answer(allowed: bool) -> void:
	if _att_answered:
		return
	_att_answered = true
	_log("tracking %s" % ("allowed" if allowed else "not allowed"))
	if not _sdk_started:
		_start_sdk()


func _on_initialized(_status: Variant) -> void:
	_log("SDK ready, loading ads")
	_load(INTERSTITIAL)
	_load(REWARDED)


# --- Loading -----------------------------------------------------------------

func _load(k: String) -> void:
	if not _sdk_started or _loading[k]:
		return
	_loading[k] = true
	_retry_at[k] = -1
	if k == INTERSTITIAL:
		_admob.load_interstitial_ad()
	else:
		_admob.load_rewarded_ad()


func _on_loaded(k: String) -> void:
	_loading[k] = false
	_loaded_at[k] = Time.get_ticks_msec()
	_fails[k] = 0
	_log("%s loaded" % k)
	changed.emit()


func _on_load_failed(k: String) -> void:
	_loading[k] = false
	_loaded_at[k] = -1
	_fails[k] += 1
	_retry_at[k] = Time.get_ticks_msec() + RETRY_MS[mini(_fails[k], RETRY_MS.size()) - 1]
	_log("%s failed to load (%d in a row), trying again in %d s" % [k, _fails[k], (_retry_at[k] - Time.get_ticks_msec()) / 1000])


## True when an ad of this kind is loaded and fresh; an expired one is
## dropped and a new one loaded.
func _ready_to_show(k: String) -> bool:
	if _admob == null or _loaded_at[k] == -1:
		return false
	var loaded: bool = _admob.is_interstitial_ad_loaded() if k == INTERSTITIAL else _admob.is_rewarded_ad_loaded()
	if loaded and Time.get_ticks_msec() - _loaded_at[k] < EXPIRE_MS:
		return true
	if loaded:
		if k == INTERSTITIAL:
			_admob.remove_interstitial_ad()
		else:
			_admob.remove_rewarded_ad()
	_loaded_at[k] = -1
	_load(k)
	return false


# --- Showing -----------------------------------------------------------------

func interstitial_ready() -> bool:
	return _ready_to_show(INTERSTITIAL)


func show_interstitial() -> void:
	if not _ready_to_show(INTERSTITIAL):
		interstitial_closed.emit.call_deferred(false)
		return
	_loaded_at[INTERSTITIAL] = -1
	_admob.show_interstitial_ad()


func rewarded_ready() -> bool:
	return _ready_to_show(REWARDED)


func show_rewarded() -> void:
	if not _ready_to_show(REWARDED):
		rewarded_closed.emit.call_deferred(false, false)
		return
	_earned = false
	_loaded_at[REWARDED] = -1
	_admob.show_rewarded_ad()


# --- Logging -----------------------------------------------------------------

func _log(text: String) -> void:
	if _debug:
		print("[ads] " + text)


static func _message(error: Variant) -> String:
	if error != null and error is Object and error.has_method("get_message"):
		return "%s (%d)" % [error.get_message(), error.get_code()]
	return str(error)


# --- Privacy -----------------------------------------------------------------

func privacy_options_available() -> bool:
	return _admob != null and _consent() in [Consent.REQUIRED, Consent.OBTAINED]


## Clears the stored choice and asks again: the consent form shows (where it
## applies) through the normal start-up path.
func show_privacy_options() -> void:
	if _admob == null:
		return
	_admob.reset_consent_info()
	_ask_consent()
