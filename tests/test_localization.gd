extends TestCase
## The translations load in Godot and answer for every launch language
## (the Python tools in tools/l10n/ check the files themselves).


func test_every_language_translates() -> void:
	var before := TranslationServer.get_locale()
	for entry in L10n.LANGUAGES:
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
	check_eq(L10n.best_locale("zh_TW"), "zh_CN", "Chinese")
	check_eq(L10n.best_locale("nl_NL"), "en", "not a launch language")


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
