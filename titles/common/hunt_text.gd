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


## A title's name in its own language's script, used when the interface is
## in that language (termbase, "Bagh Chal": बाघचाल in Nepali).
const NATIVE_TITLE_NAMES := {
	"bagh_chal": {"ne": "बाघचाल"},
}


static func title_name(title: String) -> String:
	# Proper names: the same in every language (termbase: do not translate),
	# except in the game's own language, where it's written in its own script.
	var native: Dictionary = NATIVE_TITLE_NAMES.get(title, {})
	return native.get(L10n.current_language(), TITLE_NAMES[title])


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
			# Only the hunters capture, so the limit is told as their moves.
			var n := rules.no_capture_limit_plies / 2
			match title:
				"bagh_chal":
					# TRANSLATORS: Reason for a draw: the tigers made this many moves in a row without a capture.
					return L10n.tn("The tigers went %d move without capturing.", "The tigers went %d moves without capturing.", n) % n
				"adugo":
					return L10n.tn("The jaguar went %d move without capturing.", "The jaguar went %d moves without capturing.", n) % n
				_:
					return L10n.tn("The puma went %d move without capturing.", "The puma went %d moves without capturing.", n) % n
	return ""


## The count toward the no-capture draw, in the hunter's moves (the rule is
## 50 moves each, and only the hunter captures): "Tiger moves without
## capturing: 12 / 50".
static func quiet_moves(title: String, state: HuntState, rules: HuntRuleSet) -> String:
	var q := state.quiet_plies
	# The last ply was by the side not to move; with an odd count it also made the first.
	var hunter_moves := (q + 1) / 2 if q % 2 == 1 and state.side == HuntState.PREY else q / 2
	var limit := rules.no_capture_limit_plies / 2
	match title:
		"bagh_chal":
			# TRANSLATORS: Count toward the draw rule: tiger moves since the last capture / the limit.
			return L10n.t("Tiger moves without capturing: %d / %d") % [hunter_moves, limit]
		"adugo":
			return L10n.t("Jaguar moves without capturing: %d / %d") % [hunter_moves, limit]
		_:
			return L10n.t("Puma moves without capturing: %d / %d") % [hunter_moves, limit]
