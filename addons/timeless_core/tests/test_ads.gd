extends TestCase
## AdService and AdPolicy: the interstitial cap (every 2nd finished game, 3+
## minutes apart, never after the first game), rewarded videos and their
## results, Remove ads, muting while an ad shows, and the backend choice.

const SAVE := "user://test_ads.cfg"


func _clean() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


## A service on the test stand-in, with the 3-minute gap already passed.
func _service(instant := true) -> AdService:
	_clean()
	AdService.backend_override = "sim"
	var ads := AdService.new()
	ads.save_path = SAVE
	ads.start({"interstitial": "demo", "rewarded": "demo", "debug": true})
	AdService.backend_override = ""
	(ads.backend as SimAdBackend).instant = instant
	ads.policy.last_ad_ms = Time.get_ticks_msec() - AdPolicy.MIN_GAP_MS - 1
	return ads


func _free(ads: AdService) -> void:
	ads.free()
	_clean()


func test_policy_every_second_game_and_three_minutes_apart() -> void:
	var p := AdPolicy.new(0)
	var gap := AdPolicy.MIN_GAP_MS
	p.game_finished()
	check(not p.interstitial_due(gap * 10), "never after the first game")
	p.game_finished()
	check(not p.interstitial_due(gap - 1), "not in the first 3 minutes of the session")
	check(p.interstitial_due(gap), "after the second game, 3 minutes in")
	p.interstitial_shown(gap)
	check(not p.interstitial_due(gap * 10), "the count starts again")
	p.game_finished()
	p.game_finished()
	check(not p.interstitial_due(gap * 2 - 1), "3 minutes after the last ad")
	check(p.interstitial_due(gap * 2), "two games and 3 minutes later")
	p.rewarded_shown(gap * 2)
	check(not p.interstitial_due(gap * 3 - 1), "a rewarded video counts for the gap")
	check(p.interstitial_due(gap * 3), "but not for the games")


func test_after_game_shows_only_when_due() -> void:
	var ads := _service()
	var sim := ads.backend as SimAdBackend
	var calls := [0]
	var then := func() -> void: calls[0] += 1
	ads.game_finished()
	ads.after_game(then)
	check_eq(sim.interstitials_shown, 0, "no ad after one game")
	check_eq(calls[0], 1, "the break goes on at once")
	ads.game_finished()
	ads.after_game(then)
	check_eq(sim.interstitials_shown, 1, "an ad after the second game")
	check_eq(calls[0], 2, "then the break goes on")
	check_eq(ads.policy.games_since_ad, 0, "the count starts again")
	ads.game_finished()
	ads.game_finished()
	ads.after_game(then)
	check_eq(sim.interstitials_shown, 1, "not again within 3 minutes")
	_free(ads)


func test_no_ad_when_none_is_loaded() -> void:
	var ads := _service()
	var sim := ads.backend as SimAdBackend
	sim.fill = false
	ads.game_finished()
	ads.game_finished()
	var calls := [0]
	ads.after_game(func() -> void: calls[0] += 1)
	check_eq(calls[0], 1, "the break goes on")
	check_eq(ads.policy.games_since_ad, 2, "still due for the next break")
	_free(ads)


func test_sound_is_muted_while_an_ad_shows() -> void:
	var ads := _service(false)
	var sim := ads.backend as SimAdBackend
	AudioServer.set_bus_mute(0, false)
	ads.game_finished()
	ads.game_finished()
	var calls := [0]
	ads.after_game(func() -> void: calls[0] += 1)
	check(ads.showing, "the ad is on screen")
	check(AudioServer.is_bus_mute(0), "the game is muted")
	check_eq(calls[0], 0, "the break waits for the ad")
	sim._close(true)
	check(not ads.showing, "closed")
	check(not AudioServer.is_bus_mute(0), "sound back")
	check_eq(calls[0], 1, "then the break goes on")
	_free(ads)


func test_rewarded_results() -> void:
	var ads := _service()
	var sim := ads.backend as SimAdBackend
	var got := []
	var record := func(r: int) -> void: got.append(r)
	check(not ads.extras_unlocked(), "extras locked with ads on")
	ads.show_rewarded(record)
	check_eq(got, [AdService.Reward.EARNED], "watched to the end")
	check(not ads.extras_unlocked(), "the title grants the extra")
	sim.instant_earn = false
	ads.show_rewarded(record)
	check_eq(got[1], AdService.Reward.SKIPPED, "closed early")
	sim.fill = false
	check(not ads.rewarded_ready(), "nothing loaded")
	ads.show_rewarded(record)
	check_eq(got[2], AdService.Reward.UNAVAILABLE, "no video")
	ads.unlock_extras_for_session()
	check(ads.extras_unlocked(), "unlocked for the session")
	_free(ads)


func test_remove_ads_turns_ads_off_and_opens_extras() -> void:
	var ads := _service()
	var sim := ads.backend as SimAdBackend
	ads.set_ads_removed(true)
	check(not ads.ads_enabled(), "no ads")
	check(ads.extras_unlocked(), "every extra open")
	ads.game_finished()
	ads.game_finished()
	ads.after_game()
	check_eq(sim.interstitials_shown, 0, "no interstitial")
	ads.free()
	# Kept for the next session.
	var again := AdService.new()
	again.save_path = SAVE
	AdService.backend_override = "sim"
	again.start({})
	AdService.backend_override = ""
	check(again.ads_removed, "still removed after a restart")
	_free(again)


func test_no_ads_backend() -> void:
	_clean()
	AdService.backend_override = "none"
	var ads := AdService.new()
	ads.save_path = SAVE
	ads.start({"interstitial": "demo", "rewarded": "demo", "debug": true})
	AdService.backend_override = ""
	check(not ads.ads_enabled(), "no ads")
	check(ads.extras_unlocked(), "nothing to unlock")
	var calls := [0]
	ads.after_game(func() -> void: calls[0] += 1)
	check_eq(calls[0], 1, "breaks go on")
	var got := []
	ads.show_rewarded(func(r: int) -> void: got.append(r))
	check_eq(got, [AdService.Reward.UNAVAILABLE], "no videos")
	check(not ads.privacy_options_available(), "no consent to change")
	_free(ads)


func test_backend_choice() -> void:
	check(not AdmobAdBackend.available(), "no AdMob plugin library here")
	check_eq(AdService.pick_backend({"interstitial": "x"}), "none", "headless tools and tests: no ads")
	AdService.backend_override = "sim"
	check_eq(AdService.pick_backend({}), "sim", "tests can pick the stand-in")
	AdService.backend_override = ""


# --- AdmobAdBackend against a stand-in for the plugin's node -------------------

const FAKE_ADMOB := "res://addons/timeless_core/testing/fake_admob.gd"
enum { UNKNOWN, NOT_REQUIRED, REQUIRED, OBTAINED }


func _admob(consent: int, debug := true) -> AdmobAdBackend:
	var b := AdmobAdBackend.new()
	b.script_path = FAKE_ADMOB
	b.start({"interstitial": "unit/i", "rewarded": "unit/r", "debug": debug, "test_devices": ["ABC"]})
	b._admob.consent = consent
	b._ask_consent()  # in the game: when the node is ready
	return b


func test_admob_setup() -> void:
	var b := _admob(UNKNOWN)
	var f: Node = b._admob
	check_eq(f.is_real, false, "debug build: the plugin's test mode")
	check_eq(f.android_real_interstitial_id, "unit/i", "the title's interstitial unit")
	check_eq(f.android_debug_rewarded_id, "unit/r", "the title's rewarded unit")
	check_eq(f.debug_geography, AdmobAdBackend.DEBUG_GEOGRAPHY_EEA, "consent form as in the EEA")
	check_eq(f.test_device_hashed_ids, ["ABC"] as Array[String], "test devices")
	check(f.remove_interstitial_ads_after_displayed, "a shown interstitial is dropped")
	check_eq(f.calls, ["update_consent_info"] as Array[String], "consent first, nothing else")
	b.free()
	var real := _admob(UNKNOWN, false)
	check_eq(real._admob.is_real, true, "release build")
	check_eq(real._admob.debug_geography, -1, "no debug location in release")
	real.free()


func test_admob_consent_form_then_sdk() -> void:
	var b := _admob(REQUIRED)
	var f: Node = b._admob
	f.consent_info_updated.emit()
	check_eq(f.count("load_consent_form"), 1, "form loaded where consent is required")
	f.consent_form_loaded.emit()
	check_eq(f.count("show_consent_form"), 1, "and shown")
	check_eq(f.count("initialize"), 0, "no SDK before a choice")
	f.consent = OBTAINED
	f.consent_form_dismissed.emit(null)
	check_eq(f.count("initialize"), 1, "SDK started after the choice")
	f.initialization_completed.emit(null)
	check_eq(f.count("load_interstitial_ad"), 1, "an interstitial loaded ahead")
	check_eq(f.count("load_rewarded_ad"), 1, "a rewarded video loaded ahead")
	check(b.privacy_options_available(), "the choice can be changed")
	b.show_privacy_options()
	check_eq(f.count("reset_consent_info"), 1, "privacy choices: cleared")
	check_eq(f.count("update_consent_info"), 2, "and asked again")
	b.free()


func test_admob_consent_not_required_or_unknown() -> void:
	var b := _admob(NOT_REQUIRED)
	b._admob.consent_info_updated.emit()
	check_eq(b._admob.count("load_consent_form"), 0, "no form outside consent regions")
	check_eq(b._admob.count("initialize"), 1, "SDK straight away")
	check(not b.privacy_options_available(), "nothing to change")
	b.free()
	var offline := _admob(UNKNOWN)
	offline._admob.consent_info_update_failed.emit(null)
	check_eq(offline._admob.count("initialize"), 0, "no consent known: no SDK yet")
	offline._consent_retry_at = 0
	offline._process(0.0)
	check_eq(offline._admob.count("update_consent_info"), 2, "asked again later")
	offline.free()


func test_admob_show_reload_retry_and_expiry() -> void:
	var b := _admob(NOT_REQUIRED)
	var f: Node = b._admob
	f.consent_info_updated.emit()
	f.initialization_completed.emit(null)
	var closed: Array = []
	b.interstitial_closed.connect(func(shown: bool) -> void: closed.append(shown))
	check(not b.interstitial_ready(), "nothing loaded yet")
	f.interstitial_loaded = true
	f.interstitial_ad_loaded.emit(null, null)
	check(b.interstitial_ready(), "loaded")
	b.show_interstitial()
	check_eq(f.count("show_interstitial_ad"), 1, "shown")
	f.interstitial_ad_dismissed_full_screen_content.emit(null)
	check_eq(closed, [true], "closed after it showed")
	check_eq(f.count("load_interstitial_ad"), 2, "the next one loads")
	# A failed load waits, then tries again.
	f.interstitial_ad_failed_to_load.emit(null, null)
	check(b._retry_at["interstitial"] > Time.get_ticks_msec(), "waits before trying again")
	b._process(0.0)
	check_eq(f.count("load_interstitial_ad"), 2, "not at once")
	b._retry_at["interstitial"] = 0
	b._process(0.0)
	check_eq(f.count("load_interstitial_ad"), 3, "then again")
	# An ad that couldn't show is dropped and reported as not shown.
	f.interstitial_loaded = true
	f.interstitial_ad_loaded.emit(null, null)
	b.show_interstitial()
	f.interstitial_ad_failed_to_show_full_screen_content.emit(f.FakeAdInfo.new("x"), null)
	check_eq(closed, [true, false], "not shown")
	check_eq(f.count("remove_interstitial_ad"), 1, "dropped")
	# Older than 55 minutes: dropped and reloaded, not shown.
	f.interstitial_loaded = true
	f.interstitial_ad_loaded.emit(null, null)
	b._loaded_at["interstitial"] = Time.get_ticks_msec() - AdmobAdBackend.EXPIRE_MS - 1
	check(not b.interstitial_ready(), "an expired ad isn't shown")
	check_eq(f.count("remove_interstitial_ad"), 2, "it's dropped")
	b.free()


func test_admob_rewarded() -> void:
	var b := _admob(NOT_REQUIRED)
	var f: Node = b._admob
	f.consent_info_updated.emit()
	f.initialization_completed.emit(null)
	var got: Array = []
	b.rewarded_closed.connect(func(earned: bool, shown: bool) -> void: got.append([earned, shown]))
	f.rewarded_loaded = true
	f.rewarded_ad_loaded.emit(null, null)
	b.show_rewarded()
	f.rewarded_ad_user_earned_reward.emit(null, null)
	f.rewarded_ad_dismissed_full_screen_content.emit(null)
	check_eq(got, [[true, true]], "watched to the end")
	f.rewarded_loaded = true
	f.rewarded_ad_loaded.emit(null, null)
	b.show_rewarded()
	f.rewarded_ad_dismissed_full_screen_content.emit(null)
	check_eq(got[1], [false, true], "closed early: no reward")
	b.show_rewarded()
	check_eq(f.count("show_rewarded_ad"), 2, "nothing loaded: not shown")
	b.free()
