class_name PlayText
extends RefCounted
## Player-facing text for playing with other people: player names, connection
## problems and the endings that don't come from the board (L10n rules: whole
## sentences, no assembled phrases).


## How an online or nearby player is shown: a translated word and a number
## (PlayerNames). Each device shows the word in its own language.
static func player_name(name: Dictionary) -> String:
	if name.get("key") == "sim":
		return "Simulated opponent (test build)"  # debug builds only, never translated
	if not PlayerNames.is_valid(name):
		# TRANSLATORS: Shown instead of a player's name when it can't be read.
		return L10n.t("Opponent")
	return "%s %d" % [name_word(str(name.key)), int(name.n)]


## The words players are named with (bible §5.2: no free-text names).
static func name_word(key: String) -> String:
	# TRANSLATORS: Online players are named with an everyday occupation and a number, like "Scribe 4821". Use a short, neutral noun; gender-neutral if your language allows.
	match key:
		"scribe":
			return L10n.t("Scribe")
		"traveller":
			return L10n.t("Traveller")
		"potter":
			return L10n.t("Potter")
		"weaver":
			return L10n.t("Weaver")
		"shepherd":
			return L10n.t("Shepherd")
		"boatman":
			return L10n.t("Boatman")
		"gardener":
			return L10n.t("Gardener")
		"builder":
			return L10n.t("Builder")
	return key


## Why a game couldn't start or was lost (play_controller's error keys).
static func problem(key: String) -> String:
	match key:
		"offline":
			return L10n.t("Can't reach the online service. Check your connection and try again.")
		"not_found":
			return L10n.t("No game has that code. Check it and try again.")
		"full":
			return L10n.t("That game has already started.")
		"connection":
			return L10n.t("Couldn't connect to the other device.")
		"version":
			return L10n.t("The other device has a different version of the game. Update both and try again.")
		"title":
			return L10n.t("The other device is playing a different game.")
		"rules":
			return L10n.t("The other device uses rules this version doesn't have.")
		"port":
			return L10n.t("Couldn't start a game on this network. Close any other copy of the game and try again.")
		"permission":
			return L10n.t("Local play needs permission to find devices on your network.")
		"bad_code":
			return L10n.t("That code isn't valid. Check it and try again.")
		"no_wifi":
			return L10n.t("This device isn't on a Wi-Fi network.")
	return L10n.t("Something went wrong. Please try again.")


## The result card's line for a game that ended off the board, or "".
## `mine` is true when the ending happened to the player on this device.
static func ending(why: MatchSession.Ending, mine: bool) -> String:
	match why:
		MatchSession.Ending.RESIGNED:
			return L10n.t("You resigned.") if mine else L10n.t("Your opponent resigned.")
		MatchSession.Ending.DRAW_AGREED:
			return L10n.t("You agreed to a draw.")
		MatchSession.Ending.FORFEIT_TIMEOUT:
			return L10n.t("You ran out of time three times.") if mine else L10n.t("Your opponent ran out of time three times.")
		MatchSession.Ending.FORFEIT_DISCONNECT:
			return L10n.t("You left the game.") if mine else L10n.t("Your opponent left the game.")
		MatchSession.Ending.FORFEIT_ILLEGAL:
			return L10n.t("The other device sent moves that aren't allowed.")
	return ""


## m:ss for the turn clock.
static func clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]
