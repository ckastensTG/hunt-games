class_name HuntAchievements
extends RefCounted
## When Bagh Chal's achievements are earned (Christopher, 2026-11-08; launch
## checklist §5.8). AchievementService keeps and sends them; the names and
## descriptions players see live in Game Center and Google Play Games, in
## every store language.
##
##   first_lesson      First lesson: finish How to play (its last step)
##   the_hunt          The hunt: win as the tigers
##   herd_holds        The herd holds: win as the goats
##   tiger_tamer       Tiger tamer: beat the Master as the goats
##   apex              Apex: beat the Master as the tigers
##   not_one_left      Not one left: win Parlett's 1976 rules as the tigers,
##                     with all twenty goats captured
##   neighbors         Neighbors: finish a game on the same Wi-Fi
##   across_the_world  Across the world: finish a game online
##
## A win counts against the AI or another device, never in pass and play or
## AI vs AI (one person plays both sides there). A game won because the other
## device dropped out doesn't count as a win; a resignation does. "Finish"
## means played to its end: a result on the board, a resignation or an
## agreed draw, but not a dropped connection.

const FIRST_LESSON := "first_lesson"
const THE_HUNT := "the_hunt"
const HERD_HOLDS := "herd_holds"
const TIGER_TAMER := "tiger_tamer"
const APEX := "apex"
const NOT_ONE_LEFT := "not_one_left"
const NEIGHBORS := "neighbors"
const ACROSS_THE_WORLD := "across_the_world"
const ALL := [FIRST_LESSON, THE_HUNT, HERD_HOLDS, TIGER_TAMER, APEX, NOT_ONE_LEFT, NEIGHBORS, ACROSS_THE_WORLD]

const ONLINE := [MatchSession.Kind.ONLINE_FRIEND, MatchSession.Kind.QUICK_MATCH]
## Kinds where one person plays one side against an opponent.
const AGAINST_SOMEONE := [MatchSession.Kind.VS_AI, MatchSession.Kind.NEARBY,
	MatchSession.Kind.ONLINE_FRIEND, MatchSession.Kind.QUICK_MATCH]


## What a finished game earns. `side`: the side played on this device
## (HuntState.HUNTER or PREY; -1 when both or neither are).
static func for_game(s: MatchSession, side: int) -> Array[String]:
	var out: Array[String] = []
	if s == null or s.is_ongoing() or s.rules == null or not s.rule_set_id.begins_with("bagh_chal"):
		return out
	if s.ending == MatchSession.Ending.FORFEIT_DISCONNECT:
		return out
	if s.kind == MatchSession.Kind.NEARBY:
		out.append(NEIGHBORS)
	elif s.kind in ONLINE:
		out.append(ACROSS_THE_WORLD)
	if not s.kind in AGAINST_SOMEONE or side < 0:
		return out
	var won: bool = (s.status() == HuntState.Status.HUNTER_WIN and side == HuntState.HUNTER) \
			or (s.status() == HuntState.Status.PREY_WIN and side == HuntState.PREY)
	if not won:
		return out
	var opponent := HuntState.PREY if side == HuntState.HUNTER else HuntState.HUNTER
	var master: bool = s.kind == MatchSession.Kind.VS_AI and s.control.get(opponent) == MatchSession.Driver.AI \
			and int(s.ai_level.get(opponent, -1)) == HuntPersonas.MASTER
	if side == HuntState.HUNTER:
		out.append(THE_HUNT)
		if master:
			out.append(APEX)
		if s.rule_set_id == HuntRuleSets.BAGH_CHAL_PARLETT and s.state.captured >= s.rules.prey_total():
			out.append(NOT_ONE_LEFT)
	else:
		out.append(HERD_HOLDS)
		if master:
			out.append(TIGER_TAMER)
	return out
