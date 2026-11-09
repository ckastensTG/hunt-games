class_name HuntOpponents
extends RefCounted
## The named AI opponents a title offers, weakest first: one person per AI
## level (HuntPersonas, which also holds how each one plays). Shown on
## "Play against the AI" (play_menu.gd) and over the board during the game
## (hud.gd), each with an emblem drawn by OpponentEmblem.
##
## Bagh Chal's four (Christopher, 2026-11-08: "The names, icons and
## descriptions are fine"; no lines spoken, "it will be too repetitive"):
## people around a pati in a Nepali town. Their names use kinship words
## (Didi, older sister; Dai, older brother; Hajurba, grandfather) instead of
## family names, so no caste or ethnic names, like the player-name words.
## Titles without people (Jogo da Onça until M3) show the plain levels.

## The title's people, weakest first ([] when it has none). Names and lines
## are English source text, translated where shown.
static func people(title: String) -> Array:
	if title != "bagh_chal":
		return []
	return [
		{
			"level": HuntPersonas.NOVICE, "emblem": "kite",
			# TRANSLATORS: Name of the weakest computer opponent in Bagh Chal, a Nepali boy ("Sanu" is a common nickname, "little one"). Write it in your script as a name (e.g. ru Сану, ja サヌ); languages written in Latin letters keep "Sanu".
			"name": L10n.N_("Sanu"),
			# TRANSLATORS: One line about the computer opponent Sanu (a beginner, a boy).
			"about": L10n.N_("Just learned the game. Plays fast, and loves the tigers."),
		},
		{
			"level": HuntPersonas.APPRENTICE, "emblem": "tea",
			# TRANSLATORS: Name of a computer opponent in Bagh Chal: Maya, a Nepali woman, with "Didi" ("older sister", a respectful way to address a woman in Nepal). Write it in your script as a name (e.g. ru Майя Диди, ja マヤ・ディディ); languages written in Latin letters keep "Maya Didi".
			"name": L10n.N_("Maya Didi"),
			# TRANSLATORS: One line about the computer opponent Maya Didi, who runs a tea stall. "When she's looking": she plays well when she isn't distracted.
			"about": L10n.N_("Plays between customers at her tea stall. Steady, when she's looking."),
		},
		{
			"level": HuntPersonas.ADEPT, "emblem": "chisel",
			# TRANSLATORS: Name of a computer opponent in Bagh Chal: Hari, a Nepali man, with "Dai" ("older brother", a friendly way to address a man in Nepal). Write it in your script as a name (e.g. ru Хари Дай, ja ハリ・ダイ); languages written in Latin letters keep "Hari Dai".
			"name": L10n.N_("Hari Dai"),
			# TRANSLATORS: One line about the computer opponent Hari Dai, a woodcarver. "A trap": in Bagh Chal the goats win by trapping the tigers.
			"about": L10n.N_("Carved his own board. Patient, and fond of a trap."),
		},
		{
			"level": HuntPersonas.MASTER, "emblem": "topi",
			# TRANSLATORS: Name of the strongest computer opponent in Bagh Chal: "Hajurba", Nepali for grandfather, used as his name. Write it in your script as a name (e.g. ru Хаджурба, ja ハジュルバ); languages written in Latin letters keep "Hajurba".
			"name": L10n.N_("Hajurba"),
			# TRANSLATORS: One line about the computer opponent Hajurba, an old man. A pati is a public rest-house in Nepal where people meet and play: keep the word as in "Game origins".
			"about": L10n.N_("Sixty years of evenings at the pati. Rarely speaks. Rarely loses."),
		},
	]


static func has_people(title: String) -> bool:
	return not people(title).is_empty()


## The person at an AI level, or {} when the title has none.
static func at_level(title: String, level: int) -> Dictionary:
	for p in people(title):
		if p.level == level:
			return p
	return {}


## The opponent's name as shown (translated), or the level's name.
static func display_name(title: String, level: int) -> String:
	var p := at_level(title, level)
	return L10n.t(p.name) if not p.is_empty() else level_name(level)


## The level's name: Novice, Apprentice, Adept, Master.
static func level_name(level: int) -> String:
	match level:
		HuntPersonas.NOVICE:
			# TRANSLATORS: The weakest computer opponent level.
			return L10n.t("Novice")
		HuntPersonas.APPRENTICE:
			# TRANSLATORS: The second computer opponent level.
			return L10n.t("Apprentice")
		HuntPersonas.ADEPT:
			# TRANSLATORS: The third computer opponent level.
			return L10n.t("Adept")
		_:
			# TRANSLATORS: The strongest computer opponent level.
			return L10n.t("Master")
