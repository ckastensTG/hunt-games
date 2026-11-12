extends TestCase
## Other Timeless Games as this build ships it (titles/common/catalog/, a copy
## of the site's games/v1/): the list reads, this game is in it with its own
## IDs, every game has its English card (mipmapped, as the pop-up shrinks
## it), and the export presets carry the list.

const DIR := TitleConfig.CATALOG_DIR


func _entries() -> Array:
	return GameList.parse(FileAccess.get_file_as_string(DIR.path_join("games.json")))


func test_the_shipped_list_reads() -> void:
	var games := _entries()
	check(games.size() >= 2, "Bagh Chal and Jogo da Onça at least (%d)" % games.size())
	check(GameList.updated(FileAccess.get_file_as_string(DIR.path_join("games.json"))) != "", "it has a date")
	check_eq(TitleConfig.active().catalog_setup().get("bundled_dir"), DIR, "TitleConfig points GameCatalog at it")


func test_this_game_is_listed_with_its_own_ids() -> void:
	var title := TitleConfig.for_id(TitleConfig.BAGH_CHAL)
	var mine := _entries().filter(func(e: Dictionary) -> bool: return e.id == TitleConfig.BAGH_CHAL)
	check_eq(mine.size(), 1, "Bagh Chal is in the list (the game itself is included)")
	if mine.is_empty():
		return
	var e: Dictionary = mine[0]
	check_eq(e.line, "timeless", "a Timeless Games title")
	check_eq(e.stores.get("google_play", {}).get("package", ""), title.package, "its package on Google Play")
	# Christopher, 2026-11-11 (bible §13 #25): App Store Connect's Apple ID.
	check_eq(e.stores.get("app_store", {}).get("apple_id", ""), "6830657856", "its Apple ID")


func test_every_game_has_its_english_card() -> void:
	for e in _entries():
		var path: String = DIR.path_join("cards").path_join(e.id).path_join("en.webp")
		check(ResourceLoader.exists(path), "%s: English card shipped" % e.id)
		var cfg := ConfigFile.new()
		if cfg.load(path + ".import") == OK:
			check(bool(cfg.get_value("params", "mipmaps/generate", false)), "%s: mipmapped" % e.id)
		var tex := load(path) as Texture2D
		# A band of the Google Play feature graphic, its name and line at full
		# size (Christopher: half the height, 2026-11-11).
		check(tex != null and tex.get_size() == Vector2(1024, 250), "%s: 1024 x 250" % e.id)
		check(e.card.locales.has("en"), "%s: the list knows its English card" % e.id)


func test_the_presets_carry_the_list() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://export_presets.cfg"), OK, "presets read")
	var i := 0
	while cfg.has_section("preset.%d" % i):
		var section := "preset.%d" % i
		var include := str(cfg.get_value(section, "include_filter", ""))
		check(include.contains("titles/common/catalog/*.json"), "%s: games.json in the build" % cfg.get_value(section, "name"))
		var exclude := str(cfg.get_value(section, "exclude_filter", ""))
		check(not exclude.contains("catalog"), "%s: nothing of the catalog left out" % cfg.get_value(section, "name"))
		i += 1
	check(i >= 3, "three presets")
