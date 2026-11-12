class_name TitleConfig
extends RefCounted
## Which store title this build is (framework §1). Each export preset carries
## a feature tag, `title_bagh_chal` or `title_jogo_da_onca`; at start the game
## reads it and offers only that title's rule sets, looks and store IDs. With
## no title tag (the editor, tests, desktop dev builds) everything is offered.
##
## EOS: the product, sandbox and deployment IDs below aren't secret (they ship
## in the app). The client ID and secret stay out of the repo: they live in
## res://config/eos_<title>.cfg, which .gitignore leaves out
## (see config/eos_title.example.cfg).
##
## AdMob: the App IDs and ad unit IDs aren't secret either (they ship in the
## app). Debug builds use Google's demo ad units (ad_unit()), so testing never
## shows or clicks a live ad on the account. The Android App ID also sits in
## res://addons/AdmobPlugin/android_export.cfg, which the AdMob plugin writes
## into the manifest (tests/test_ads_setup.gd checks they match).
##
## Purchases: "iap" maps each product key to its product ID, the same in
## Google Play and the App Store (bible §3.1: one "Remove ads", US$1.99).
##
## Achievements: "achievements" maps each key (HuntAchievements decides when
## one is earned) to its ID in Game Center (chosen by us when the achievement
## was created in App Store Connect) and in Google Play Games (made by Play
## Console, "CgkI…"; "" until it exists).
##
## Credits: "author" is the line on the Credits screen ("Bagh Chal is a game
## by …"; Christopher, 2026-11-08).

const DEV := "dev"
## The game list and English cards shipped with the build (GameCatalog).
const CATALOG_DIR := "res://titles/common/catalog"
const BAGH_CHAL := "bagh_chal"
const JOGO_DA_ONCA := "jogo_da_onca"
## Suffix for Komikan with the dogs moving first (see resolve_rule_set).
const DOGS_FIRST := "+dogs_first"

const TITLES := {
	BAGH_CHAL: {
		# The launcher label; the store listing name ("Bagh Chal – Timeless
		# Games", bible §2) is set in the store consoles.
		"short_name": "Bagh Chal",
		"rule_sets": [HuntRuleSets.BAGH_CHAL_STANDARD, HuntRuleSets.BAGH_CHAL_PARLETT],
		# Languages this title offers on top of the launch languages
		# (L10n.TITLE_LANGUAGES): Nepali, the game's home language
		# (Christopher, 2026-11-06).
		"languages": ["ne"],
		# The look every player has. The others open for the session after a
		# rewarded video, or for good with Remove ads (Christopher, 2026-11-06).
		"free_look": "brass",
		# Confirmed by Christopher 2026-11-03; permanent once published.
		"package": "com.timegalleon.baghchal",
		"eos": {
			"product_name": "Timeless Games: Bagh Chal",
			"product_id": "21d401468aa44ca49a79daded636fb6b",
			"sandbox_id": "f9acb9d5eaac4f5f9a48151d1b5dc914",  # Live
			"deployment_id": "62e0d1d7527840f7a52383c2be071b83",  # Live Deployment
		},
		# From Christopher's AdMob account, 2026-11-04 (publisher pub-8333290579862415).
		# Created by Christopher in Play Console and App Store Connect as a
		# one-time (non-consumable) product, US$1.99.
		"iap": {"remove_ads": "remove_ads"},
		"author": "Christopher Kastensmidt",
		# The eight launch achievements (Christopher, 2026-11-08; launch
		# checklist §5.8). Game Center: the IDs set in App Store Connect.
		# Google Play Games: the IDs Play Console gave them (games project
		# 782700281832; the Android presets' godot_play_game_services/game_id).
		"achievements": {
			"first_lesson": {"game_center": "baghchal.first_lesson", "play_games": "CgkI6P_J5OMWEAIQBg"},
			"the_hunt": {"game_center": "baghchal.the_hunt", "play_games": "CgkI6P_J5OMWEAIQBQ"},
			"herd_holds": {"game_center": "baghchal.herd_holds", "play_games": "CgkI6P_J5OMWEAIQAQ"},
			"tiger_tamer": {"game_center": "baghchal.tiger_tamer", "play_games": "CgkI6P_J5OMWEAIQAw"},
			"apex": {"game_center": "baghchal.apex", "play_games": "CgkI6P_J5OMWEAIQBw"},
			"not_one_left": {"game_center": "baghchal.not_one_left", "play_games": "CgkI6P_J5OMWEAIQAg"},
			"neighbors": {"game_center": "baghchal.neighbors", "play_games": "CgkI6P_J5OMWEAIQBA"},
			"across_the_world": {"game_center": "baghchal.across_the_world", "play_games": "CgkI6P_J5OMWEAIQCA"},
		},
		"admob": {
			"android": {
				"app_id": "ca-app-pub-8333290579862415~4379954395",
				"interstitial": "ca-app-pub-8333290579862415/3728830665",
				"rewarded": "ca-app-pub-8333290579862415/6782756456",
			},
			"ios": {
				"app_id": "ca-app-pub-8333290579862415~3756750820",
				"interstitial": "ca-app-pub-8333290579862415/9655944760",
				"rewarded": "ca-app-pub-8333290579862415/5078792545",
			},
		},
	},
	JOGO_DA_ONCA: {
		"short_name": "Jogo da Onça",
		"rule_sets": [HuntRuleSets.ADUGO, HuntRuleSets.KOMIKAN],
		"languages": [],
		"free_look": "",  # one look so far
		"package": "",  # M3
		"eos": {},  # its own EOS product, M3 (bible §5.2)
		"admob": {},  # its own AdMob apps, M3
		"iap": {},  # its own store apps and Remove ads, M3
		"author": "Christopher Kastensmidt",
		"achievements": {},  # its own, M3
	},
}

## Google's demo ad units (developers.google.com/admob/{android,ios}/test-ads).
## They always fill and never pay, so debug builds can show ads safely.
const ADMOB_DEMO_UNITS := {
	"android": {
		"interstitial": "ca-app-pub-3940256099942544/1033173712",
		"rewarded": "ca-app-pub-3940256099942544/5224354917",
	},
	"ios": {
		"interstitial": "ca-app-pub-3940256099942544/4411468910",
		"rewarded": "ca-app-pub-3940256099942544/1712485313",
	},
}

var id: String
var short_name: String
var rule_sets: Array
## Title-only languages offered on top of the launch languages, e.g. ["ne"].
var languages: Array
var package: String
var eos: Dictionary
## {"android": {app_id, interstitial, rewarded}, "ios": {...}}, or {}.
var admob: Dictionary
## Purchases: {key: product ID}, e.g. {"remove_ads": "remove_ads"}.
var iap: Dictionary
## {key: {"game_center": ID, "play_games": ID}}, or {}.
var achievements: Dictionary
## Who made the game, for the Credits screen.
var author: String


static var _active: TitleConfig


## The title this build was exported for, or the dev configuration.
static func active() -> TitleConfig:
	if _active == null:
		_active = for_id(detect())
	return _active


static func detect() -> String:
	for title in TITLES:
		if OS.has_feature("title_" + title):
			return title
	return DEV


static func for_id(title: String) -> TitleConfig:
	var c := TitleConfig.new()
	c.id = title
	if TITLES.has(title):
		var t: Dictionary = TITLES[title]
		c.short_name = t.short_name
		c.rule_sets = t.rule_sets.duplicate()
		c.languages = t.languages.duplicate()
		c.package = t.package
		c.eos = t.eos.duplicate()
		c.admob = t.admob.duplicate(true)
		c.iap = t.iap.duplicate()
		c.achievements = t.achievements.duplicate(true)
		c.author = t.author
	else:
		c.short_name = "Hunt Games (dev)"
		c.rule_sets = HuntRuleSets.ALL.duplicate()
		c.languages = []
		for t in TITLES.values():
			for code in t.languages:
				if not code in c.languages:
					c.languages.append(code)
		c.package = ""
		c.eos = TITLES[BAGH_CHAL].eos.duplicate()
		c.admob = TITLES[BAGH_CHAL].admob.duplicate(true)
		c.iap = TITLES[BAGH_CHAL].iap.duplicate()
		c.achievements = TITLES[BAGH_CHAL].achievements.duplicate(true)
		c.author = TITLES[BAGH_CHAL].author
	return c


## The platform AdMob runs on in this build: "android", "ios" or "" (desktop,
## editor, web: no ads).
static func ad_platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("ios"):
		return "ios"
	return ""


## The AdMob App ID for a platform ("" if this title has none). The ads
## plugin writes it into the Android manifest and the iOS Info.plist
## (GADApplicationIdentifier); debug builds use the real App ID too, with
## demo ad units.
func admob_app_id(platform := ad_platform()) -> String:
	return str(admob.get(platform, {}).get("app_id", ""))


## The ad unit for "interstitial" or "rewarded" on a platform. Debug builds
## (and `demo`) get Google's demo unit, release builds the title's own.
func ad_unit(kind: String, platform := ad_platform(), demo := OS.is_debug_build()) -> String:
	if admob_app_id(platform) == "":
		return ""
	if demo:
		return str(ADMOB_DEMO_UNITS.get(platform, {}).get(kind, ""))
	return str(admob.get(platform, {}).get(kind, ""))


## What AdService.start() needs: this build's ad units (demo units in debug
## builds) and whether it's a test build.
func ad_setup() -> Dictionary:
	return {
		"interstitial": ad_unit("interstitial"),
		"rewarded": ad_unit("rewarded"),
		"debug": OS.is_debug_build(),
	}


## What IAPService.start() needs: the title's products, and whether it's a
## test build.
func iap_setup() -> Dictionary:
	return {"products": iap.duplicate(), "debug": OS.is_debug_build()}


## What GameCatalog.start() needs ("Other Timeless Games", playbook Phase 9):
## the series' game list and English cards as shipped with the build, and
## the line to show. The list is the same for every title; the build's copy
## is refreshed from the site's (website/apps-site/games/v1/) before export.
func catalog_setup() -> Dictionary:
	return {"bundled_dir": CATALOG_DIR, "line": "timeless"}


## What AchievementService.start() needs: the title's achievements with
## their Game Center and Google Play Games IDs, and whether it's a test build.
func achievements_setup() -> Dictionary:
	return {"achievements": achievements.duplicate(true), "debug": OS.is_debug_build()}


## The texts of iOS's permission prompts, in English; the iOS export preset
## carries them in additional_plist_content (tests/test_ads_setup.gd checks
## they match), and timeless_core's export step writes their translations
## into each language's InfoPlist.strings. Marked here so they're translated
## with the rest.
static func ios_usage(title: String) -> Dictionary:
	if title != BAGH_CHAL and title != DEV:
		return {}
	return {
		# TRANSLATORS: iPhone/iPad system prompt, under Apple's question "Allow Bagh Chal to track your activity across other companies' apps and websites?". Says why: more relevant ads, and ads keep the game free.
		"NSUserTrackingUsageDescription": L10n.N_("This lets us show you ads that are more relevant. Bagh Chal is free because of ads."),
		# TRANSLATORS: iPhone/iPad system prompt, under Apple's question "Bagh Chal would like to find and connect to devices on your local network". Says why: to play someone nearby on the same Wi-Fi.
		"NSLocalNetworkUsageDescription": L10n.N_("Bagh Chal looks for games on your Wi-Fi network so you can play someone nearby."),
	}


## The look a title gives every player ("" when it has only one look). The
## others need a rewarded video (for the session) or Remove ads.
static func free_look(title: String) -> String:
	return str(TITLES.get(title, {}).get("free_look", ""))


## The EOS client for this title from res://config/eos_<title>.cfg:
## {client_id, client_secret}, or {} when the file isn't there.
func eos_client() -> Dictionary:
	var title := BAGH_CHAL if id == DEV else id
	var cfg := ConfigFile.new()
	if cfg.load("res://config/eos_%s.cfg" % title) != OK:
		return {}
	return {
		"client_id": str(cfg.get_value("client", "client_id", "")),
		"client_secret": str(cfg.get_value("client", "client_secret", "")),
	}


## The title name sent over the network (HELLO) and used for the online pool.
## Dev builds play as Bagh Chal, so a desktop dev build can meet a phone build.
func network_id() -> String:
	return BAGH_CHAL if id == DEV else id


## The rule set for a network or saved game id, or null if this build doesn't
## offer it. Ids are the HuntRuleSets ids; Komikan with the dogs moving first
## adds "+dogs_first" (a different rule set, so a different fingerprint).
func resolve_rule_set(rule_set_id: String) -> HuntRuleSet:
	var base := rule_set_id.trim_suffix(DOGS_FIRST)
	if not rule_sets.has(base):
		return null
	if base == HuntRuleSets.KOMIKAN:
		return HuntRuleSets.komikan(HuntRuleSet.PREY if rule_set_id.ends_with(DOGS_FIRST) else HuntRuleSet.HUNTER)
	if rule_set_id != base:
		return null
	return HuntRuleSets.by_id(base)

