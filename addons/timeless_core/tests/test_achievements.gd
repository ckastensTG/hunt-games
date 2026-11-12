extends TestCase
## AchievementService and the Game Center backend against a stand-in for
## Godot Apple Plugins: unlocks kept on the device across restarts, sent once
## signed in, kept for later when the service can't take them, never sent
## twice, the Achievements screen (signing in first), and the backend choice.

const SAVE := "user://test_achievements.cfg"
const FakeGameCenter := preload("res://addons/timeless_core/testing/fake_game_center.gd")
const FakePlayGames := preload("res://addons/timeless_core/testing/fake_play_games.gd")
const SETUP := {"achievements": {
	"first_lesson": {"game_center": "baghchal.first_lesson", "play_games": "CgkIplay1"},
	"the_hunt": {"game_center": "baghchal.the_hunt"},
}}


func _clean() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _service(kind: String) -> AchievementService:
	AchievementService.backend_override = kind
	var s := AchievementService.new()
	s.save_path = SAVE
	s.start(SETUP)
	AchievementService.backend_override = ""
	return s


## A service on Game Center with the stand-in, not started yet.
func _game_center(fake: Object) -> AchievementService:
	var s := AchievementService.new()
	s.save_path = SAVE
	s._setup = SETUP
	s._load()
	var gc := GameCenterBackend.new()
	gc.manager = fake
	gc.achievements = fake
	gc.view = fake
	s.backend = gc
	gc.signed_in.connect(s._on_signed_in)
	gc.reported.connect(s._on_reported)
	s.add_child(gc)
	gc.start(s.ids_for("game_center"), false)
	return s


## A service on Google Play Games with the stand-in.
func _play_games(fake: Object) -> AchievementService:
	var s := AchievementService.new()
	s.save_path = SAVE
	s._setup = SETUP
	s._load()
	var pg := PlayGamesBackend.new()
	pg.plugin = fake
	s.backend = pg
	pg.signed_in.connect(s._on_signed_in)
	pg.reported.connect(s._on_reported)
	s.add_child(pg)
	pg.start(s.ids_for("play_games"), false)
	return s


func test_no_service_keeps_unlocks_on_the_device() -> void:
	_clean()
	var s := _service("none")
	check(not s.can_show(), "no Achievements button without a service")
	check(not s.has("first_lesson"), "nothing earned yet")
	s.unlock("first_lesson")
	s.unlock("first_lesson")
	check(s.has("first_lesson"), "earned")
	check(not s.sent.has("first_lesson"), "nowhere to send it")
	s.free()
	var again := _service("none")
	check(again.has("first_lesson"), "kept after a restart")
	check(not again.has("the_hunt"), "only what was earned")
	again.free()
	_clean()


func test_unknown_key_is_ignored() -> void:
	_clean()
	var s := _service("none")
	s.unlock("not_an_achievement")
	check(s.earned.is_empty(), "nothing earned")
	s.free()
	_clean()


func test_ids_for_each_service() -> void:
	_clean()
	var s := _service("none")
	check_eq(s.ids_for("game_center"), {"first_lesson": "baghchal.first_lesson", "the_hunt": "baghchal.the_hunt"})
	check_eq(s.ids_for("play_games"), {"first_lesson": "CgkIplay1"}, "only the ones with an ID")
	check_eq(s.keys().size(), 2)
	s.free()
	_clean()


func test_game_center_sends_once_signed_in() -> void:
	_clean()
	var fake := FakeGameCenter.new()
	fake.sign_in_answer = ""  # the sheet is still up
	var s := _game_center(fake)
	check_eq(fake.authenticate_calls, 1, "signs in at start")
	check(s.can_show(), "Achievements button")
	s.unlock("first_lesson")
	check(s.has("first_lesson"), "earned at once")
	check_eq(fake.reported_ids, [], "not sent before signing in")
	fake.answer(true)
	check_eq(fake.reported_ids, ["baghchal.first_lesson"], "sent at 100% with the banner")
	check(s.sent.has("first_lesson"), "the service has it")
	s.unlock("first_lesson")
	check_eq(fake.reported_ids.size(), 1, "never sent twice")
	s.free()
	_clean()


func test_game_center_failure_is_kept_for_later() -> void:
	_clean()
	var fake := FakeGameCenter.new()
	fake.report_error = "COMMUNICATIONS_FAILURE"
	var s := _game_center(fake)
	s.unlock("the_hunt")
	check(s.has("the_hunt"), "earned")
	check(not s.sent.has("the_hunt"), "not with the service")
	s.free()
	# Next start, online again: sent at sign-in.
	var fake2 := FakeGameCenter.new()
	var again := _game_center(fake2)
	check_eq(fake2.reported_ids, ["baghchal.the_hunt"], "sent at the next sign-in")
	check(again.sent.has("the_hunt"), "and kept as sent")
	again.free()
	_clean()


func test_show_signs_in_first() -> void:
	_clean()
	var fake := FakeGameCenter.new()
	fake.sign_in_answer = false  # closed the sheet at start
	var s := _game_center(fake)
	var got := []
	fake.sign_in_answer = ""
	s.show(func(ok: bool) -> void: got.append(ok))
	check_eq(fake.authenticate_calls, 2, "asks again")
	fake.answer(true)
	check_eq(got, [true], "opened after signing in")
	check_eq(fake.shown, [GameCenterBackend.STATE_ACHIEVEMENTS], "on the Achievements page")
	got.clear()
	s.show(func(ok: bool) -> void: got.append(ok))
	check_eq(got, [true], "signed in: straight there")
	s.free()
	_clean()


func test_play_games_unlocks_and_shows() -> void:
	_clean()
	var fake := FakePlayGames.new()
	fake.signed_in_answer = ""  # still checking
	var s := _play_games(fake)
	check(fake.initialized, "the plugin is initialized first")
	s.unlock("first_lesson")
	s.unlock("the_hunt")  # no Google Play ID yet: kept on the device only
	check_eq(fake.unlocked_ids, [], "nothing sent before signing in")
	fake.answer(true)
	check_eq(fake.unlocked_ids, ["CgkIplay1"], "sent once signed in")
	check(s.sent.has("first_lesson") and not s.sent.has("the_hunt"), "only what has an ID")
	check(s.has("the_hunt"), "but both earned")
	var got := []
	s.show(func(ok: bool) -> void: got.append(ok))
	check_eq(got, [true], "shown")
	check_eq(fake.shows, 1, "Play Games' own screen")
	s.free()
	_clean()


func test_play_games_sign_in_from_the_button() -> void:
	_clean()
	var fake := FakePlayGames.new()
	fake.signed_in_answer = false  # not signed in at start
	var s := _play_games(fake)
	check(not s.backend.is_signed_in, "not signed in")
	fake.signed_in_answer = true
	var got := []
	s.show(func(ok: bool) -> void: got.append(ok))
	check_eq(fake.sign_in_calls, 1, "the button signs in")
	check_eq(got, [true], "then shows")
	s.free()
	_clean()


func test_backend_choice() -> void:
	check_eq(AchievementService.pick_backend({}), "none", "a title without achievements")
	# Headless Linux: neither Game Center nor Google Play Games.
	check_eq(AchievementService.pick_backend(SETUP), "none", "no service on this platform")
	check(not GameCenterBackend.available(), "Game Center only on iPhone and iPad")
	check(not PlayGamesBackend.available(), "Google Play Games only on Android")


## A title whose store records aren't made yet signs in to neither service.
func test_services_need_the_titles_ids() -> void:
	check(AchievementService.has_ids(SETUP, "game_center"), "Game Center IDs given")
	check(AchievementService.has_ids(SETUP, "play_games"), "a Google Play Games ID given")
	var unmade := {"achievements": {
		"first_lesson": {"game_center": "", "play_games": ""},
		"the_hunt": {},
	}}
	check(not AchievementService.has_ids(unmade, "game_center"), "no Game Center IDs yet")
	check(not AchievementService.has_ids(unmade, "play_games"), "no Google Play Games IDs yet")
	check_eq(AchievementService.pick_backend(unmade), "none", "no IDs: no service")
	check(not AchievementService.has_ids({}, "play_games"), "a title without achievements")
