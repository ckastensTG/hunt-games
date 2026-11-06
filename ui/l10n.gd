class_name L10n
extends RefCounted
## Localization helpers (framework §11). The English strings in the code are
## the source text; translations live in locale/<code>.po and are loaded by
## project.godot (internationalization/locale/translations).
##
## - N_("…") marks a string for translation without translating it yet: for
##   tables of text that are translated where they are shown.
## - t("…") / tn("…", "…", n) translate now, from anywhere (static code too).
## - tools/l10n/extract_pot.py collects every string passed to tr(), tr_n(),
##   N_(), t() and tn() into locale/messages.pot.
##
## Write whole sentences. Never build one from translated parts ("The %s won"
## with a side name): word order, case and gender differ by language. A %d
## inside a sentence is fine; use tn() for anything that counts.

## The launch languages (bible §7: 15 since 2026-11-06, when Christopher added
## Traditional Chinese, Indonesian and Thai), each named in its own language.
## Use languages() for what a build offers: it adds the title's own.
const LANGUAGES := [
	["en", "English"],
	["pt_BR", "Português (Brasil)"],
	["es", "Español"],
	["fr", "Français"],
	["de", "Deutsch"],
	["it", "Italiano"],
	["ru", "Русский"],
	["pl", "Polski"],
	["tr", "Türkçe"],
	["zh_CN", "简体中文"],
	["zh_TW", "繁體中文"],
	["ja", "日本語"],
	["ko", "한국어"],
	["id", "Bahasa Indonesia"],
	["th", "ไทย"],
]

## Languages only some titles offer (TitleConfig "languages"), each named in
## its own language. They go right after English in the Language menu.
## Nepali: Bagh Chal only (Christopher, 2026-11-06).
const TITLE_LANGUAGES := [
	["ne", "नेपाली"],
]

const SETTINGS_PATH := "user://settings.cfg"


static func N_(text: String) -> String:
	return text


static func t(text: String, context := "") -> String:
	return TranslationServer.translate(text, context)


static func tn(singular: String, plural: String, n: int, context := "") -> String:
	return TranslationServer.translate_plural(singular, plural, n, context)


## The languages this build offers, as [code, name in its own language]:
## the launch languages plus the title's own (TitleConfig.languages).
static func languages(config: TitleConfig = null) -> Array:
	if config == null:
		config = TitleConfig.active()
	var out := LANGUAGES.duplicate()
	var at := 1
	for entry in TITLE_LANGUAGES:
		if entry[0] in config.languages:
			out.insert(at, entry)
			at += 1
	return out


## The offered language closest to the system's, or English.
## Chinese goes by script: Traditional (zh_TW) for Taiwan, Hong Kong and Macau
## or the Hant script, Simplified (zh_CN) otherwise. Android may still report
## Indonesian with its old code "in".
static func best_locale(system_locale: String, config: TitleConfig = null) -> String:
	var parts := system_locale.replace("-", "_").split("_")
	var lang := parts[0]
	if lang == "in":
		lang = "id"
	if lang == "zh":
		for p in parts.slice(1):
			if p in ["Hant", "TW", "HK", "MO"]:
				return "zh_TW"
		return "zh_CN"
	var code := lang + ("_" + parts[-1] if parts.size() > 1 else "")
	var offered := languages(config)
	for entry in offered:
		if entry[0] == code:
			return entry[0]
	for entry in offered:
		if entry[0].split("_")[0] == lang:
			return entry[0]
	return "en"


## Applies the saved language, or the system's on first run.
static func apply_saved_locale() -> void:
	var saved := str(load_setting("language", ""))
	TranslationServer.set_locale(best_locale(saved) if saved != "" else best_locale(OS.get_locale()))
	SeriesTheme.apply_locale()


static func set_language(code: String) -> void:
	TranslationServer.set_locale(code)
	SeriesTheme.apply_locale()
	save_setting("language", code)


static func current_language() -> String:
	return best_locale(TranslationServer.get_locale())


# --- Player settings (a small file in user://) -------------------------------

static func load_setting(key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default
	return cfg.get_value("player", key, default)


static func save_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # missing on first run: starts empty
	cfg.set_value("player", key, value)
	cfg.save(SETTINGS_PATH)
