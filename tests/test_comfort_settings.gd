extends TestCase
## Large text, Vibration and the real italic font (Christopher, 2026-11-08).


func test_large_text_makes_every_size_bigger() -> void:
	var was := GameText.is_large()
	GameText.set_large(false)
	check_eq(SeriesTheme.fs(18), 20, "normal: the designed size plus two")
	var normal_theme := SeriesTheme.theme()
	GameText.set_large(true)
	check(GameText.is_large(), "on")
	check_eq(SeriesTheme.fs(18), 25, "large: a quarter bigger again")
	check_eq(SeriesTheme.fs(56), 73, "titles too")
	check(SeriesTheme.theme() != normal_theme, "the theme is built afresh")
	check_eq(SeriesTheme.theme().default_font_size, 25, "at the new size")
	check_eq(SeriesTheme.label("x", "body", 19).get_theme_font_size("font_size"), 26, "labels made after it")
	check(bool(L10n.load_setting(GameText.SETTING, false)), "saved")
	GameText.set_large(false)
	check_eq(SeriesTheme.theme().default_font_size, 20, "and back")
	GameText.set_large(was)


func test_vibration_follows_the_switch() -> void:
	var was := GameHaptics.is_on()
	var old_recorder: Variant = GameHaptics.recorder
	GameHaptics.recorder = []
	check(GameHaptics.available(), "shown when recording")
	GameHaptics.set_on(true)
	GameHaptics.pulse(GameHaptics.MOVE)
	GameHaptics.pulse(GameHaptics.CAPTURE)
	GameHaptics.pulse(GameHaptics.END)
	GameHaptics.pulse("nonsense")
	check_eq(GameHaptics.recorder, [GameHaptics.MOVE, GameHaptics.CAPTURE, GameHaptics.END], "a move, a capture, the end")
	GameHaptics.set_on(false)
	GameHaptics.pulse(GameHaptics.MOVE)
	check_eq((GameHaptics.recorder as Array).size(), 3, "nothing when switched off")
	check(not bool(L10n.load_setting(GameHaptics.SETTING, true)), "saved")
	for kind in GameHaptics.PULSES:
		var p: Array = GameHaptics.PULSES[kind]
		check(p[0] >= 25 and p[0] <= 100 and p[1] > 0.0 and p[1] <= 1.0, "%s: short, but long enough to feel, and within strength" % kind)
	check(GameHaptics.PULSES[GameHaptics.MOVE][0] < GameHaptics.PULSES[GameHaptics.CAPTURE][0], "a move lighter than a capture")
	GameHaptics.recorder = null
	check(not GameHaptics.available(), "no vibration on a desktop")
	GameHaptics.set_on(was)
	GameHaptics.recorder = old_recorder


func test_italics_are_alegreyas_own() -> void:
	var f := SeriesTheme.font("book_italic")
	check(f is FontFile, "a font file, not a slanted variation")
	check(f.resource_path.ends_with("Alegreya-MediumItalic.ttf"), "Alegreya Medium Italic")
	check_eq(f.get_font_style() & TextServer.FONT_ITALIC, TextServer.FONT_ITALIC, "an italic face")
	check(f.has_char("ж".unicode_at(0)) and f.has_char("ğ".unicode_at(0)), "Cyrillic and Turkish letters")
