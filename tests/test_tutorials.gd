extends TestCase
## Every "How to play" walkthrough plays only legal moves, and the steps that
## show a win end in that win (titles/common/hunt_tutorials.gd).


func test_every_rule_set_has_a_walkthrough() -> void:
	for id in HuntRuleSets.ALL:
		check(HuntTutorials.steps_for(id).size() >= 6, "%s: a walkthrough" % id)


func test_scripted_moves_are_legal() -> void:
	for id in HuntRuleSets.ALL:
		var rules := HuntRuleSets.by_id(id)
		var script := HuntTutorials.steps_for(id)
		var steps := HuntTutorials.build(rules)
		check_eq(steps.size(), script.size(), "%s: every step built" % id)
		for k in steps.size():
			var want: int = script[k].get("moves", []).size()
			check_eq(steps[k].moves.size(), want, "%s, \"%s\": every move legal" % [id, script[k].title])


func test_outcomes() -> void:
	for id in HuntRuleSets.ALL:
		var rules := HuntRuleSets.by_id(id)
		for step in HuntTutorials.build(rules):
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
	for id in HuntRuleSets.ALL:
		var rules := HuntRuleSets.by_id(id)
		for step in HuntTutorials.build(rules):
			for m in step.marks:
				check(m[0] >= 0 and m[0] < rules.board.point_count(), "%s: mark on a point" % id)
				check(m[1] in ["select", "step", "capture", "note"], "%s: known mark %s" % [id, m[1]])
