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

const DEV := "dev"
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
		# Confirmed by Christopher 2026-11-03; permanent once published.
		"package": "com.timegalleon.baghchal",
		"eos": {
			"product_name": "Timeless Games: Bagh Chal",
			"product_id": "21d401468aa44ca49a79daded636fb6b",
			"sandbox_id": "f9acb9d5eaac4f5f9a48151d1b5dc914",  # Live
			"deployment_id": "62e0d1d7527840f7a52383c2be071b83",  # Live Deployment
		},
	},
	JOGO_DA_ONCA: {
		"short_name": "Jogo da Onça",
		"rule_sets": [HuntRuleSets.ADUGO, HuntRuleSets.KOMIKAN],
		"package": "",  # M3
		"eos": {},  # its own EOS product, M3 (bible §5.2)
	},
}

var id: String
var short_name: String
var rule_sets: Array
var package: String
var eos: Dictionary


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
		c.package = t.package
		c.eos = t.eos.duplicate()
	else:
		c.short_name = "Hunt Games (dev)"
		c.rule_sets = HuntRuleSets.ALL.duplicate()
		c.package = ""
		c.eos = TITLES[BAGH_CHAL].eos.duplicate()
	return c


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

