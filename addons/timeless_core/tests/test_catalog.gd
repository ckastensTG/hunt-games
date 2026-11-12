extends TestCase
## Other Timeless Games: the game list's checks (GameList), the store links
## (StoreLinks) and GameCatalog with a stand-in for the network: the shipped
## and the kept list, reading the list once a day, an hour after a failure,
## the cards in the player's language with their checks, and what's shown
## when a card is missing.

const DIR := "user://test_catalog"
const SHIPPED := "user://test_catalog_shipped"

const LIST := {
	"version": 1, "updated": "2026-11-11",
	"games": [
		{"id": "bagh_chal", "line": "timeless", "name": "Bagh Chal",
			"google_play": {"status": "available", "package": "com.timegalleon.baghchal"},
			"app_store": {"status": "available", "apple_id": "6830657856"},
			"card": {"rev": 1, "locales": ["en", "pt_BR", "ja", "ne"]}},
		{"id": "jogo_da_onca", "line": "timeless", "name": "Jogo da Onça",
			"google_play": {"status": "coming_soon", "package": "com.timegalleon.jogodaonca"},
			"app_store": {"status": "coming_soon", "apple_id": "6832707061"},
			"card": {"rev": 2, "locales": ["en", "pt_BR"]}},
		{"id": "some_board_game", "line": "boards",
			"google_play": {"status": "available", "package": "com.timegalleon.someboardgame"},
			"card": {"rev": 1, "locales": ["en"]}},
	],
}


func _rm(dir: String) -> void:
	var full := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(full):
		return
	for sub in DirAccess.get_directories_at(full):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(full):
		DirAccess.remove_absolute(full.path_join(f))
	DirAccess.remove_absolute(full)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _webp(w := 1024, h := 500, color := Color(0.2, 0.4, 0.3)) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(color)
	return img.save_webp_to_buffer(true, 0.8)


## A GameCatalog on the stand-in network: `site` maps addresses to bodies
## (a missing one fails); `asked` collects every address asked for.
func _catalog(site: Dictionary, asked: Array, now: Array, store := "google_play") -> GameCatalog:
	var c := GameCatalog.new()
	c.clock = func() -> int: return now[0]
	c.fetcher = func(url: String, max_bytes: int, done: Callable) -> void:
		asked.append(url)
		var body: PackedByteArray = site.get(url, PackedByteArray())
		done.call(site.has(url) and body.size() <= max_bytes, body)
	c.start({"bundled_dir": SHIPPED, "cache_dir": DIR, "store": store, "base_url": "https://example.test/games/v1/"})
	return c


func _clean() -> void:
	_rm(DIR)
	_rm(SHIPPED)


func test_the_list_is_checked() -> void:
	var games := GameList.parse(JSON.stringify(LIST))
	check_eq(games.size(), 3, "three games")
	check_eq(games[0].id, "bagh_chal", "in the file's order")
	check_eq(games[0].stores.google_play.package, "com.timegalleon.baghchal", "the package")
	check_eq(games[0].stores.app_store.apple_id, "6830657856", "the Apple ID")
	check_eq(games[1].name, "Jogo da Onça", "a Latin name with ç")
	check_eq(games[0].card.locales, PackedStringArray(["en", "pt_BR", "ja", "ne"]), "card locales")
	check_eq(GameList.updated(JSON.stringify(LIST)), "2026-11-11", "the date")
	check_eq(GameList.parse("not json"), [], "not a list")
	var v2 := LIST.duplicate(true)
	v2.version = 2
	check_eq(GameList.parse(JSON.stringify(v2)), [], "another version isn't read")


func test_bad_entries_are_left_out() -> void:
	var bad := {"version": 1, "games": [
		{"id": "Bad Id", "line": "timeless", "google_play": {"status": "available", "package": "com.a.b"}},
		{"id": "no_line", "line": "other", "google_play": {"status": "available", "package": "com.a.b"}},
		{"id": "evil_link", "line": "timeless", "google_play": {"status": "available", "package": "https://evil.example/x"}},
		{"id": "evil_apple", "line": "timeless", "app_store": {"status": "available", "apple_id": "123abc"}},
		{"id": "number_id", "line": "timeless", "app_store": {"status": "available", "apple_id": 6830657856}},
		{"id": "odd_status", "line": "timeless", "google_play": {"status": "maybe", "package": "com.a.b"}},
		{"id": "soon_no_ids", "line": "timeless", "name": "日本語", "google_play": {"status": "coming_soon"},
			"card": {"rev": 1, "locales": ["en", "../../x", "pt-BR", "en\n"]}},
		{"id": "soon_no_ids", "line": "timeless", "google_play": {"status": "coming_soon"}},
	]}
	var games := GameList.parse(JSON.stringify(bad))
	check_eq(games.size(), 1, "only the coming-soon game without IDs is kept")
	check_eq(games[0].id, "soon_no_ids", "that one, once")
	check_eq(games[0].name, "", "a name that isn't Latin is dropped")
	check_eq(games[0].card.locales, PackedStringArray(["en"]), "bad locales are dropped")
	check(not GameList.valid_package("com.timegalleon.baghchal\n"), "no trailing newline")
	check(not GameList.valid_apple_id("0123456"), "no leading zero")
	check(GameList.valid_package("com.timegalleon.jogodaonca"), "a real package")


func test_games_per_store_and_card_locales() -> void:
	var games := GameList.parse(JSON.stringify(LIST))
	check_eq(GameList.on_store(games, "google_play", "available").map(func(e): return e.id), ["bagh_chal"], "available on Play, this line only")
	check_eq(GameList.on_store(games, "app_store", "coming_soon").map(func(e): return e.id), ["jogo_da_onca"], "coming soon on the App Store")
	check_eq(GameList.on_store(games, "google_play", "available", "boards").map(func(e): return e.id), ["some_board_game"], "the other line")
	check_eq(GameList.card_locale(games[0], "pt_BR"), "pt_BR", "the same locale")
	check_eq(GameList.card_locale(games[0], "pt_PT"), "pt_BR", "the same language")
	check_eq(GameList.card_locale(games[0], "th"), "en", "else English")


func test_store_links_are_built_from_ids() -> void:
	var games := GameList.parse(JSON.stringify(LIST))
	var bagh: Dictionary = games[0]
	check_eq(StoreLinks.urls(bagh, "google_play", "Android"),
		PackedStringArray(["market://details?id=com.timegalleon.baghchal", "https://play.google.com/store/apps/details?id=com.timegalleon.baghchal"]),
		"the Play Store app, then the web")
	check_eq(StoreLinks.urls(bagh, "google_play", "macOS"),
		PackedStringArray(["https://play.google.com/store/apps/details?id=com.timegalleon.baghchal"]), "the web elsewhere")
	check_eq(StoreLinks.urls(bagh, "app_store", "iOS"),
		PackedStringArray(["timelessstore:?id=6830657856", "https://apps.apple.com/app/id6830657856"]), "Apple's sheet, then the page")
	check_eq(StoreLinks.urls(games[1], "google_play", "Android"), PackedStringArray(), "coming soon opens nothing")
	var tampered := bagh.duplicate(true)
	tampered.stores.google_play.package = "x; rm -rf"
	check_eq(StoreLinks.urls(tampered, "google_play", "Android"), PackedStringArray(), "a changed ID is checked again")


func test_the_store_sheet_file_is_shipped() -> void:
	var path := "res://addons/timeless_core/platform/ios/TimelessStoreSheet.m"
	var sources: PackedStringArray = load("res://addons/timeless_core/editor/ios_native_sources.gd").sources()
	check(sources.has(path), "the export step finds it")
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("@\"%s\"" % StoreLinks.IOS_SCHEME), "it answers StoreLinks' scheme")
	check(text.contains("tgstore_canOpenURL:") and text.contains("tgstore_openURL:options:completionHandler:"), "both of Godot's calls, under its own names")
	check(text.contains("SKStoreProductViewController"), "Apple's sheet")


func test_shipped_list_until_the_site_answers() -> void:
	_clean()
	_write(SHIPPED.path_join("games.json"), JSON.stringify(LIST))
	var asked := []
	var now := [1_800_000_000]
	var c := _catalog({}, asked, now)
	check_eq(c.games("available").map(func(e): return e.id), ["bagh_chal"], "the shipped list")
	check_eq(c.games("coming_soon").map(func(e): return e.id), ["jogo_da_onca"], "coming soon")
	c.refresh_if_due()
	check_eq(asked, ["https://example.test/games/v1/games.json"], "asked once")
	c.refresh_if_due()
	check_eq(asked.size(), 1, "not again right after a failure")
	now[0] += 3601
	c.refresh_if_due()
	check_eq(asked.size(), 2, "again an hour after a failure")
	check_eq(c.games("available").size(), 1, "still the shipped list")
	c.free()
	_clean()


func test_the_site_list_is_kept_and_read_once_a_day() -> void:
	_clean()
	_write(SHIPPED.path_join("games.json"), JSON.stringify(LIST))
	var newer := LIST.duplicate(true)
	newer.updated = "2026-12-01"
	newer.games[1].google_play.status = "available"
	var site := {"https://example.test/games/v1/games.json": JSON.stringify(newer).to_utf8_buffer()}
	var asked := []
	var now := [1_800_000_000]
	var c := _catalog(site, asked, now)
	var heard := [0]
	c.changed.connect(func() -> void: heard[0] += 1)
	c.refresh_if_due()
	check_eq(c.games("available").map(func(e): return e.id), ["bagh_chal", "jogo_da_onca"], "the site's list")
	check(heard[0] >= 1, "changed")
	now[0] += 3600 * 23
	c.refresh_if_due()
	check_eq(asked.filter(func(u): return u.ends_with("games.json")).size(), 1, "once a day")
	now[0] += 3600 * 2
	c.refresh_if_due()
	check_eq(asked.filter(func(u): return u.ends_with("games.json")).size(), 2, "the next day")
	c.free()
	# A restart, offline: the kept list, newer than the shipped one.
	var again := _catalog({}, [], now)
	check_eq(again.games("available").size(), 2, "the kept list after a restart")
	again.free()
	# A build shipping a newer list than the kept one uses its own.
	var newest := LIST.duplicate(true)
	newest.updated = "2027-01-01"
	_write(SHIPPED.path_join("games.json"), JSON.stringify(newest))
	var updated := _catalog({}, [], now)
	check_eq(updated.games("available").size(), 1, "the newer shipped list")
	updated.free()
	_clean()


func test_a_bad_list_from_the_site_changes_nothing() -> void:
	_clean()
	_write(SHIPPED.path_join("games.json"), JSON.stringify(LIST))
	var site := {"https://example.test/games/v1/games.json": "{\"version\": 1, \"games\": \"nope\"}".to_utf8_buffer()}
	var c := _catalog(site, [], [1_800_000_000])
	c.refresh_if_due()
	check_eq(c.games("available").size(), 1, "the shipped list stays")
	check(not FileAccess.file_exists(DIR.path_join("games.json")), "nothing kept")
	c.free()
	_clean()


func test_cards_in_the_players_language() -> void:
	_clean()
	_write(SHIPPED.path_join("games.json"), JSON.stringify(LIST))
	var en := _webp()
	var site := {
		"https://example.test/games/v1/games.json": JSON.stringify(LIST).to_utf8_buffer(),
		"https://example.test/games/v1/cards/bagh_chal/pt_BR.webp": _webp(1024, 500, Color(0.6, 0.3, 0.1)),
		"https://example.test/games/v1/cards/jogo_da_onca/pt_BR.webp": _webp(4096, 500),
	}
	var asked := []
	var c := _catalog(site, asked, [1_800_000_000])
	check(c.card(c.entries[0], "pt_BR") == null, "no card yet (none shipped here)")
	c.refresh_if_due()
	c.fetch_cards("pt_BR")
	check(asked.has("https://example.test/games/v1/cards/bagh_chal/pt_BR.webp"), "Bagh Chal's card in Portuguese asked for")
	check(asked.has("https://example.test/games/v1/cards/jogo_da_onca/pt_BR.webp"), "coming-soon games' cards too")
	check(not asked.has("https://example.test/games/v1/cards/some_board_game/en.webp"), "not the other line's")
	var tex := c.card(c.entries[0], "pt_BR")
	check(tex != null and tex.get_size() == Vector2(1024, 500), "Bagh Chal's card")
	check(c.card(c.entries[1], "pt_BR") == null, "a card too big is refused")
	check(not FileAccess.file_exists(c.card_path("jogo_da_onca", 2, "pt_BR")), "and not kept")
	# English falls back to the shipped card.
	var shipped_card := SHIPPED.path_join("cards/jogo_da_onca/en.webp")
	DirAccess.make_dir_recursive_absolute(shipped_card.get_base_dir())
	var f := FileAccess.open(shipped_card, FileAccess.WRITE)
	f.store_buffer(en)
	f.close()
	check(c.card(c.entries[1], "pt_BR") != null, "the shipped English card when the language's is missing")
	var count := asked.size()
	c.fetch_cards("pt_BR")
	check_eq(asked.size(), count + 1, "a kept card isn't asked for again (only the refused one)")
	c.free()
	_clean()


func test_shipped_english_cards_are_not_downloaded() -> void:
	_clean()
	_write(SHIPPED.path_join("games.json"), JSON.stringify(LIST))
	var card_file := SHIPPED.path_join("cards/bagh_chal/en.webp")
	DirAccess.make_dir_recursive_absolute(card_file.get_base_dir())
	var f := FileAccess.open(card_file, FileAccess.WRITE)
	f.store_buffer(_webp())
	f.close()
	var asked := []
	var c := _catalog({}, asked, [1_800_000_000])
	c.fetch_cards("en")
	check(not asked.has("https://example.test/games/v1/cards/bagh_chal/en.webp"), "the shipped one isn't asked for")
	check(asked.has("https://example.test/games/v1/cards/jogo_da_onca/en.webp"), "one not shipped is")
	check(c.card(c.entries[0], "en") != null, "the shipped card is shown")
	c.free()
	_clean()


func test_a_new_rev_replaces_the_kept_card() -> void:
	_clean()
	var site := {
		"https://example.test/games/v1/games.json": JSON.stringify(LIST).to_utf8_buffer(),
		"https://example.test/games/v1/cards/bagh_chal/en.webp": _webp(),
	}
	var now := [1_800_000_000]
	var c := _catalog(site, [], now)
	c.refresh_if_due()
	c.fetch_cards("en")
	check(FileAccess.file_exists(c.card_path("bagh_chal", 1, "en")), "rev 1 kept")
	var next := LIST.duplicate(true)
	next.games[0].card.rev = 2
	site["https://example.test/games/v1/games.json"] = JSON.stringify(next).to_utf8_buffer()
	now[0] += GameCatalog.REFRESH_SECONDS + 1
	c.refresh_if_due()
	c.fetch_cards("en")
	check(FileAccess.file_exists(c.card_path("bagh_chal", 2, "en")), "rev 2 kept")
	check(not FileAccess.file_exists(c.card_path("bagh_chal", 1, "en")), "rev 1 gone")
	c.free()
	_clean()


func test_no_network_in_tools_and_tests() -> void:
	check(not GameCatalog.network_allowed(), "headless: never")
	var c := GameCatalog.new()
	c.start({"bundled_dir": SHIPPED, "cache_dir": DIR})
	c.refresh_if_due()
	check_eq(c.last_attempt, 0, "no attempt without a network")
	c.free()
	_clean()
