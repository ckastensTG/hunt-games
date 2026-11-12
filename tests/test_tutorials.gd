extends TestCase
## "How to play" is one walkthrough per title (Christopher, 2026-11-09; bible
## v1.19): Bagh Chal's standard game in full, then what Parlett's rules
## change. It plays only legal moves, and the steps that show a win end in
## that win (titles/common/hunt_tutorials.gd). Jogo da Onça's rule sets, left
## in this project for dev builds, keep a walkthrough each.

const STANDARD_STEPS := 9
const PARLETT_STEPS := 1


func _bagh_chal() -> Array[Dictionary]:
	return HuntTutorials.build_walkthrough(HuntTutorials.walkthrough_ids(HuntRuleSets.BAGH_CHAL_STANDARD))


func test_one_walkthrough_for_bagh_chal() -> void:
	var ids := HuntTutorials.walkthrough_ids(HuntRuleSets.BAGH_CHAL_PARLETT)
	check_eq(ids, [HuntRuleSets.BAGH_CHAL_STANDARD, HuntRuleSets.BAGH_CHAL_PARLETT],
		"the same walkthrough from either rule set, the standard game first")
	check_eq(TitleConfig.for_id(TitleConfig.BAGH_CHAL).rule_sets, ids, "the title's rule sets, in its order")
	var steps := _bagh_chal()
	check_eq(steps.size(), STANDARD_STEPS + PARLETT_STEPS, "the standard game's steps, then Parlett's")
	for k in steps.size():
		var want: String = HuntRuleSets.BAGH_CHAL_STANDARD if k < STANDARD_STEPS else HuntRuleSets.BAGH_CHAL_PARLETT
		check_eq((steps[k].rules as HuntRuleSet).id, want, "step %d on %s" % [k + 1, want])
	check_eq(steps[STANDARD_STEPS].title, "The variation: Parlett 1976", "the variation is introduced")
	check_eq(steps[4].title, "Safety in numbers", "the store screenshot's step is still the fifth")
	check_eq(HuntTutorials.steps_for(HuntRuleSets.BAGH_CHAL_PARLETT).size(), 0, "no second full walkthrough")
	var wins := 0
	for step in steps:
		if step.title == "How the tigers win":
			wins += 1
	check_eq(wins, 1, "the standard win is taught once")


func test_other_rule_sets_keep_their_own() -> void:
	for id in [HuntRuleSets.ADUGO, HuntRuleSets.KOMIKAN]:
		check_eq(HuntTutorials.walkthrough_ids(id), [id], "%s: on its own" % id)
		check(HuntTutorials.steps_for(id).size() >= 6, "%s: a walkthrough" % id)


func _parts() -> Array:
	return [
		[HuntRuleSets.BAGH_CHAL_STANDARD, HuntTutorials.steps_for(HuntRuleSets.BAGH_CHAL_STANDARD)],
		[HuntRuleSets.BAGH_CHAL_PARLETT, HuntTutorials.variation_for(HuntRuleSets.BAGH_CHAL_PARLETT)],
		[HuntRuleSets.ADUGO, HuntTutorials.steps_for(HuntRuleSets.ADUGO)],
		[HuntRuleSets.KOMIKAN, HuntTutorials.steps_for(HuntRuleSets.KOMIKAN)],
	]


func test_scripted_moves_are_legal() -> void:
	for part in _parts():
		var rules := HuntRuleSets.by_id(part[0])
		var script: Array = part[1]
		var steps := HuntTutorials.build(rules, script)
		check_eq(steps.size(), script.size(), "%s: every step built" % rules.id)
		for k in steps.size():
			var want: int = script[k].get("moves", []).size()
			check_eq(steps[k].moves.size(), want, "%s, \"%s\": every move legal" % [rules.id, script[k].title])


func test_outcomes() -> void:
	for part in _parts():
		for step in HuntTutorials.build(HuntRuleSets.by_id(part[0]), part[1]):
			var id: String = (step.rules as HuntRuleSet).id
			var end: HuntState = step.end
			var st := end.status()
			match step.get("outcome", ""):
				"hunter_win":
					check_eq(st, HuntState.Status.HUNTER_WIN, "%s, \"%s\"" % [id, step.title])
				"prey_win":
					check_eq(st, HuntState.Status.PREY_WIN, "%s, \"%s\"" % [id, step.title])
				_:
					check_eq(st, HuntState.Status.ONGOING, "%s, \"%s\": still going" % [id, step.title])


func test_marks_are_on_the_board() -> void:
	for step in _bagh_chal():
		var rules: HuntRuleSet = step.rules
		check((step.start as HuntState).board == rules.board, "%s: the position is on its own board" % rules.id)
		for m in step.marks:
			check(m[0] >= 0 and m[0] < rules.board.point_count(), "%s: mark on a point" % rules.id)
			check(m[1] in ["select", "step", "capture", "note"], "%s: known mark %s" % [rules.id, m[1]])
