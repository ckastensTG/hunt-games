extends TestCase
## The translations load in Godot and answer for every language a build can
## offer (the Python tools in tools/l10n/ check the files themselves).


func test_every_language_translates() -> void:
	var before := TranslationServer.get_locale()
	for entry in L10n.languages(TitleConfig.for_id(TitleConfig.DEV)):
		var code: String = entry[0]
		if code == "en":
			continue
		TranslationServer.set_locale(code)
		check(L10n.t("Goats to move") != "Goats to move", "%s: a sentence" % code)
		check(L10n.t("How to play") != "How to play", "%s: a button" % code)
		var plural := L10n.tn("%d goat still to place", "%d goats still to place", 3)
		check(plural.contains("%d") and plural != "%d goats still to place", "%s: a plural" % code)
	TranslationServer.set_locale(before)


func test_best_locale() -> void:
	check_eq(L10n.best_locale("pt_BR"), "pt_BR", "exact")
	check_eq(L10n.best_locale("pt_PT"), "pt_BR", "same language")
	check_eq(L10n.best_locale("de_AT"), "de", "region dropped")
	check_eq(L10n.best_locale("zh_CN"), "zh_CN", "Simplified Chinese")
	check_eq(L10n.best_locale("zh_SG"), "zh_CN", "Singapore: Simplified")
	check_eq(L10n.best_locale("zh_Hans_CN"), "zh_CN", "the Hans script")
	check_eq(L10n.best_locale("zh_TW"), "zh_TW", "Taiwan: Traditional")
	check_eq(L10n.best_locale("zh_HK"), "zh_TW", "Hong Kong: Traditional")
	check_eq(L10n.best_locale("zh_Hant_MO"), "zh_TW", "the Hant script")
	check_eq(L10n.best_locale("zh"), "zh_CN", "no region")
	check_eq(L10n.best_locale("in_ID"), "id", "Android's old Indonesian code")
	check_eq(L10n.best_locale("id_ID"), "id", "Indonesian")
	check_eq(L10n.best_locale("th_TH"), "th", "Thai")
	check_eq(L10n.best_locale("nl_NL"), "en", "not a launch language")
	var bagh := TitleConfig.for_id(TitleConfig.BAGH_CHAL)
	var jogo := TitleConfig.for_id(TitleConfig.JOGO_DA_ONCA)
	check_eq(L10n.best_locale("ne_NP", bagh), "ne", "Nepali in Bagh Chal")
	check_eq(L10n.best_locale("ne_IN", bagh), "ne", "Nepali from India")
	check_eq(L10n.best_locale("ne_NP", jogo), "en", "no Nepali in Jogo da Onça")


## The 15 launch languages (bible §7, 2026-11-06), each named in its own language.
func test_launch_languages() -> void:
	var codes := L10n.LANGUAGES.map(func(e: Array) -> String: return e[0])
	check_eq(codes.size(), 15, "15 launch languages")
	for code in ["zh_TW", "id", "th"]:
		check(code in codes, "%s is a launch language" % code)
	check(not "ne" in codes, "Nepali is a title language, not a launch language")


## Nepali is Bagh Chal's alone, right after English (Christopher, 2026-11-06).
func test_title_languages() -> void:
	var codes := func(config: TitleConfig) -> Array:
		return L10n.languages(config).map(func(e: Array) -> String: return e[0])
	var bagh: Array = codes.call(TitleConfig.for_id(TitleConfig.BAGH_CHAL))
	var jogo: Array = codes.call(TitleConfig.for_id(TitleConfig.JOGO_DA_ONCA))
	check_eq(bagh.size(), L10n.LANGUAGES.size() + 1, "Bagh Chal: the launch languages and Nepali")
	check_eq(bagh[1], "ne", "Nepali after English")
	check(not "ne" in jogo, "Jogo da Onça has no Nepali")
	check_eq(jogo.size(), L10n.LANGUAGES.size(), "Jogo da Onça: the launch languages")
	check("ne" in codes.call(TitleConfig.for_id(TitleConfig.DEV)), "dev builds offer every language")


## In Nepali the game's name is written बाघचाल; elsewhere it stays Bagh Chal.
func test_native_title_name() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("ne")
	check_eq(HuntText.title_name("bagh_chal"), "बाघचाल", "Nepali")
	check_eq(HuntText.title_name("adugo"), "Jogo da Onça", "other titles unchanged")
	TranslationServer.set_locale("de")
	check_eq(HuntText.title_name("bagh_chal"), "Bagh Chal", "German")
	TranslationServer.set_locale(before)


func test_every_reason_has_text() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for id in HuntRuleSets.ALL:
		var rules := HuntRuleSets.by_id(id)
		var title := "komikan" if id == HuntRuleSets.KOMIKAN else ("adugo" if id == HuntRuleSets.ADUGO else "bagh_chal")
		for why in HuntState.Reason.values():
			if why == HuntState.Reason.NONE:
				continue
			check(HuntText.reason(title, why, rules) != "", "%s: reason %d" % [id, why])
	TranslationServer.set_locale(before)
