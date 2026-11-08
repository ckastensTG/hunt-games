extends TestCase
## When Bagh Chal's achievements are earned (HuntAchievements), and the
## title's achievement IDs (TitleConfig).

const STD := HuntRuleSets.BAGH_CHAL_STANDARD
const PARLETT := HuntRuleSets.BAGH_CHAL_PARLETT
const H := HuntState.HUNTER
const P := HuntState.PREY
const AI := MatchSession.Driver.AI
const ME := MatchSession.Driver.LOCAL
const REMOTE := MatchSession.Driver.REMOTE


## A game of `kind` with this device on `side` (the AI, or the other device,
## on the other side at `level`).
func _game(kind: MatchSession.Kind, side: int, rules_id := STD, level := HuntPersonas.APPRENTICE) -> MatchSession:
	var other := AI if kind == MatchSession.Kind.VS_AI else REMOTE
	if kind in [MatchSession.Kind.PASS_AND_PLAY]:
		other = ME
	if kind == MatchSession.Kind.AI_VS_AI:
		side = -1
	var hunter := ME if side == H else other
	var prey := ME if side == P else other
	if kind == MatchSession.Kind.AI_VS_AI:
		hunter = AI
		prey = AI
	var s := MatchSession.create(HuntRuleSets.by_id(rules_id), rules_id, kind, hunter, prey)
	s.ai_level = {H: level, P: level}
	return s


## The tigers reach their capture target.
func _tigers_win(s: MatchSession) -> MatchSession:
	s.state.captured = s.rules.capture_target
	return s


func _got(s: MatchSession, side: int) -> Array:
	var a := HuntAchievements.for_game(s, side)
	a.sort()
	return a


func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


func test_wins_against_the_ai() -> void:
	var s := _tigers_win(_game(MatchSession.Kind.VS_AI, H))
	check_eq(_got(s, H), ["the_hunt"], "a win as the tigers")
	s = _tigers_win(_game(MatchSession.Kind.VS_AI, H, STD, HuntPersonas.MASTER))
	check_eq(_got(s, H), _sorted(["the_hunt", "apex"]), "against the Master")
	s = _game(MatchSession.Kind.VS_AI, P, STD, HuntPersonas.MASTER)
	s.resign(H)
	check_eq(_got(s, P), _sorted(["herd_holds", "tiger_tamer"]), "the goats beat the Master")
	s = _game(MatchSession.Kind.VS_AI, P, STD, HuntPersonas.ADEPT)
	s.resign(H)
	check_eq(_got(s, P), ["herd_holds"], "the goats beat the Adept")


func test_losses_and_draws_earn_no_win() -> void:
	var s := _tigers_win(_game(MatchSession.Kind.VS_AI, P, STD, HuntPersonas.MASTER))
	check_eq(_got(s, P), [], "the goats lost")
	s = _game(MatchSession.Kind.VS_AI, H)
	s.agree_draw()
	check_eq(_got(s, H), [], "a draw")
	check_eq(_got(_game(MatchSession.Kind.VS_AI, H), H), [], "still going")


func test_parlett_all_twenty_goats() -> void:
	var s := _tigers_win(_game(MatchSession.Kind.VS_AI, H, PARLETT))
	check_eq(s.state.captured, 20, "Parlett's target is every goat")
	check_eq(_got(s, H), _sorted(["the_hunt", "not_one_left"]), "every goat taken")
	s = _game(MatchSession.Kind.VS_AI, H, PARLETT)
	s.resign(P)
	check_eq(_got(s, H), ["the_hunt"], "a win without taking them all")
	s = _tigers_win(_game(MatchSession.Kind.VS_AI, H, STD))
	check(not "not_one_left" in HuntAchievements.for_game(s, H), "only under Parlett's rules")


func test_one_person_on_both_sides_earns_nothing() -> void:
	check_eq(_got(_tigers_win(_game(MatchSession.Kind.PASS_AND_PLAY, H)), H), [], "pass and play")
	check_eq(_got(_tigers_win(_game(MatchSession.Kind.PASS_AND_PLAY, H)), -1), [], "pass and play, no side")
	check_eq(_got(_tigers_win(_game(MatchSession.Kind.AI_VS_AI, H, STD, HuntPersonas.MASTER)), -1), [], "AI vs AI")


func test_games_against_another_device() -> void:
	var s := _game(MatchSession.Kind.NEARBY, P)
	s.resign(P)
	check_eq(_got(s, P), ["neighbors"], "a Wi-Fi game, lost by resigning")
	s = _tigers_win(_game(MatchSession.Kind.NEARBY, H, STD, HuntPersonas.MASTER))
	check_eq(_got(s, H), _sorted(["neighbors", "the_hunt"]), "won on Wi-Fi: no Master there")
	s = _game(MatchSession.Kind.QUICK_MATCH, H)
	s.agree_draw()
	check_eq(_got(s, H), ["across_the_world"], "an online draw")
	s = _game(MatchSession.Kind.ONLINE_FRIEND, P)
	s.forfeit(H, MatchSession.Ending.FORFEIT_TIMEOUT)
	check_eq(_got(s, P), _sorted(["across_the_world", "herd_holds"]), "won on time online")
	s = _game(MatchSession.Kind.QUICK_MATCH, P)
	s.forfeit(H, MatchSession.Ending.FORFEIT_DISCONNECT)
	check_eq(_got(s, P), [], "the other device dropped out: nothing")


func test_only_bagh_chal() -> void:
	var id := HuntRuleSets.ADUGO
	var s := MatchSession.create(HuntRuleSets.by_id(id), id, MatchSession.Kind.VS_AI, ME, AI)
	s.resign(P)
	check_eq(_got(s, H), [], "Jogo da Onça has its own, later")


func test_title_ids() -> void:
	var c := TitleConfig.for_id(TitleConfig.BAGH_CHAL)
	var keys := c.achievements.keys()
	keys.sort()
	check_eq(keys, _sorted(HuntAchievements.ALL), "an ID entry for every achievement")
	var seen := {}
	for key in c.achievements:
		var gc := str(c.achievements[key].game_center)
		check(gc == "baghchal." + key, "%s: Game Center ID baghchal.%s" % [key, key])
		check(not seen.has(gc), "unique")
		seen[gc] = true
		var pg := str(c.achievements[key].play_games)
		check(pg.begins_with("CgkI"), "%s: a Google Play Games ID" % key)
		check(not seen.has(pg), "unique")
		seen[pg] = true
	check_eq(c.author, "Christopher Kastensmidt", "the Credits line")
	check_eq(c.achievements_setup().achievements, c.achievements, "what AchievementService gets")
	check(TitleConfig.for_id(TitleConfig.JOGO_DA_ONCA).achievements.is_empty(), "Jogo da Onça: none yet")
