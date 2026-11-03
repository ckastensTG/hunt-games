class_name HuntText
extends RefCounted
## Player-facing sentences for the hunt titles, written out whole for each
## side, so translators never assemble "The %s won" from a side name: case,
## gender and plural endings differ by language (L10n).
##
## Titles: "bagh_chal" (tigers / goats), "adugo" (the jaguar / dogs) and
## "komikan" (the puma / dogs).

const TITLE_NAMES := {
	"bagh_chal": "Bagh Chal",
	"adugo": "Jogo da Onça",
	"komikan": "Jogo da Onça",
}


static func title_name(title: String) -> String:
	# Proper names: the same in every language (termbase: do not translate).
	return TITLE_NAMES[title]


static func rule_set_name(id: String) -> String:
	match id:
		HuntRuleSets.BAGH_CHAL_STANDARD:
			# TRANSLATORS: Subtitle under the game name: which rule set is being played.
			return L10n.t("Standard rules")
		HuntRuleSets.BAGH_CHAL_PARLETT:
			return L10n.t("Parlett 1976: hunt to the last goat")
		HuntRuleSets.ADUGO:
			return L10n.t("Adugo, the Bororo rules")
		HuntRuleSets.KOMIKAN:
			# TRANSLATORS: Komikan is a game of the Mapuche people (Chile, Argentina); our rules are a reconstruction from old written accounts.
			return L10n.t("Komikan, a Mapuche reconstruction")
	return id


static func rule_set_menu(id: String) -> String:
	match id:
		HuntRuleSets.BAGH_CHAL_STANDARD:
			return L10n.t("Bagh Chal · Standard")
		HuntRuleSets.BAGH_CHAL_PARLETT:
			return L10n.t("Bagh Chal · Parlett 1976")
		HuntRuleSets.ADUGO:
			return L10n.t("Jogo da Onça · Adugo")
		HuntRuleSets.KOMIKAN:
			return L10n.t("Jogo da Onça · Komikan")
	return id


static func to_move(title: String, hunter: bool) -> String:
	match title:
		"bagh_chal":
			return L10n.t("Tigers to move") if hunter else L10n.t("Goats to move")
		"adugo":
			return L10n.t("Jaguar to move") if hunter else L10n.t("Dogs to move")
		_:
			return L10n.t("Puma to move") if hunter else L10n.t("Dogs to move")


## The short line in the turn banner once the game is over.
static func won(title: String, hunter: bool) -> String:
	match title:
		"bagh_chal":
			return L10n.t("The tigers won") if hunter else L10n.t("The goats won")
		"adugo":
			return L10n.t("The jaguar won") if hunter else L10n.t("The dogs won")
		_:
			return L10n.t("The puma won") if hunter else L10n.t("The dogs won")


## The headline on the result card.
static func win_title(title: String, hunter: bool) -> String:
	match title:
		"bagh_chal":
			return L10n.t("The tigers win") if hunter else L10n.t("The goats win")
		"adugo":
			return L10n.t("The jaguar wins") if hunter else L10n.t("The dogs win")
		_:
			return L10n.t("The puma wins") if hunter else L10n.t("The dogs win")


static func you_play(title: String, hunter: bool) -> String:
	match title:
		"bagh_chal":
			return L10n.t("You play the tigers") if hunter else L10n.t("You play the goats")
		"adugo":
			return L10n.t("You play the jaguar") if hunter else L10n.t("You play the dogs")
		_:
			return L10n.t("You play the puma") if hunter else L10n.t("You play the dogs")


static func choose_piece(title: String, hunter: bool) -> String:
	match title:
		"bagh_chal":
			return L10n.t("Choose a tiger to move.") if hunter else L10n.t("Choose a goat to move.")
		"adugo":
			return L10n.t("Move the jaguar.") if hunter else L10n.t("Choose a dog to move.")
		_:
			return L10n.t("Move the puma.") if hunter else L10n.t("Choose a dog to move.")


static func place_prey(title: String) -> String:
	return L10n.t("Place a goat on any empty point.")


static func prey_in_hand(n: int) -> String:
	# TRANSLATORS: Goats not yet put on the board. A "Remaining: %d" style is fine where it reads better.
	return L10n.tn("%d goat still to place", "%d goats still to place", n) % n


static func reason(title: String, why: HuntState.Reason, rules: HuntRuleSet) -> String:
	var goats := title == "bagh_chal"
	match why:
		HuntState.Reason.CAPTURE_TARGET:
			var n := rules.capture_target
			if n == rules.prey_total():
				# TRANSLATORS: Reason for the hunter's win when it must take every piece. "Eaten" fits Komikan, whose puma "eats everything".
				return L10n.t("Every goat has been captured.") if goats else L10n.t("Every dog has been eaten.")
			return (L10n.tn("%d goat captured.", "%d goats captured.", n) if goats
				else L10n.tn("%d dog captured.", "%d dogs captured.", n)) % n
		HuntState.Reason.HUNTER_TRAPPED:
			match title:
				"bagh_chal":
					return L10n.t("The tigers are trapped: none of them can move.")
				"adugo":
					return L10n.t("The jaguar is trapped and can't move.")
				_:
					return L10n.t("The puma is trapped and can't move.")
		HuntState.Reason.PREY_STUCK:
			return L10n.t("The goats can't move.") if goats else L10n.t("The dogs can't move any more.")
		HuntState.Reason.REPETITION_BLOCKED:
			return L10n.t("Every move left would repeat an earlier position.")
		HuntState.Reason.THREEFOLD:
			return L10n.t("The same position came up three times.")
		HuntState.Reason.NO_CAPTURE_LIMIT:
			var each := rules.no_capture_limit_plies / 2
			# TRANSLATORS: Reason for a draw: neither side captured during this many moves each.
			return L10n.tn("No capture in %d move each.", "No capture in %d moves each.", each) % each
	return ""
