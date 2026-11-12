extends TestCase
## Bagh Chal's named AI opponents (HuntOpponents) and how each one plays
## (HuntPersonas.STYLES).


func test_four_people_one_per_level() -> void:
	var people := HuntOpponents.people("bagh_chal")
	check_eq(people.size(), 4, "four people")
	var names := {}
	for i in people.size():
		var p: Dictionary = people[i]
		check_eq(p.level, i, "weakest first")
		check(p.emblem in OpponentEmblem.KINDS, "%s has an emblem" % p.name)
		check(str(p.about).length() > 10, "%s has a line" % p.name)
		names[p.name] = true
	check_eq(names.size(), 4, "four names")
	check_eq(HuntOpponents.display_name("bagh_chal", HuntPersonas.MASTER), "Hajurba", "the Master is Hajurba")
	check_eq(HuntOpponents.at_level("bagh_chal", HuntPersonas.NOVICE).name, "Sanu", "the Novice is Sanu")


func test_other_titles_show_the_levels() -> void:
	check(not HuntOpponents.has_people("adugo"), "Jogo da Onça has no people yet")
	check_eq(HuntOpponents.display_name("adugo", HuntPersonas.ADEPT), "Adept", "the level's name instead")


func test_every_style_names_real_weights() -> void:
	var w := HuntEvalWeights.new()
	for i in HuntPersonas.STYLES.size():
		var p := HuntPersonas.styled(i)
		for side_style in [p.hunter_style, p.prey_style]:
			for key in side_style:
				check(w.get(key) != null, "%s: %s is a weight" % [p.id, key])
		for key in HuntPersonas.STYLES[i]:
			check(key in p, "%s: %s is a persona setting" % [p.id, key])


func test_each_person_plays_their_own_way() -> void:
	var sanu := HuntPersonas.styled(HuntPersonas.NOVICE)
	var maya := HuntPersonas.styled(HuntPersonas.APPRENTICE)
	var hari := HuntPersonas.styled(HuntPersonas.ADEPT)
	var hajurba := HuntPersonas.styled(HuntPersonas.MASTER)
	check(sanu.greedy_captures, "Sanu takes every capture")
	check(maya.lapse_rate > 0.0 and maya.lapse_pause_ms > 0, "Maya Didi has her lapses, after a pause")
	check(hari.prey_style.get("hunter_blocked", 1.0) > 1.0, "Hari Dai's goats value a trapped tiger more")
	check(hajurba.vary_ties, "Hajurba varies among equal moves")
	check(sanu.think_ms < maya.think_ms and maya.think_ms < hari.think_ms and hari.think_ms < hajurba.think_ms,
		"each takes longer than the one before")
	var depths := HuntPersonas.all().map(func(p: AIPersona) -> int: return p.max_depth)
	check_eq(depths, [2, 3, 5, 8], "strength still rises by level")
	# Hari Dai's goats see a blocked tiger as worth more than the title's own weights do.
	var base := HuntEvaluator.new(HuntRuleSets.weights_for(HuntRuleSets.by_id(HuntRuleSets.BAGH_CHAL_STANDARD)))
	check(hari.evaluator_for(HuntState.PREY, base).weights.hunter_blocked > base.weights.hunter_blocked, "his evaluation")
	check(hajurba.evaluator_for(HuntState.PREY, base) == base, "Hajurba plays with the title's own")


## Even the best slips now and then, so a win against him is possible
## (Christopher, 2026-11-09; bible v1.19); the plain Master (tools) doesn't.
func test_the_master_slips_now_and_then() -> void:
	var hajurba := HuntPersonas.styled(HuntPersonas.MASTER)
	check(hajurba.mistake_rate > 0.0 and hajurba.candidate_window > 0, "small slips")
	check(hajurba.lapse_rate > 0.0 and hajurba.lapse_window > hajurba.candidate_window, "and now and then a real one")
	check(hajurba.lapse_window < HuntRuleSets.weights_for(HuntRuleSets.by_id(HuntRuleSets.BAGH_CHAL_STANDARD)).capture,
		"never as much as a whole goat")
	check(hajurba.lapse_rate + hajurba.mistake_rate < HuntPersonas.styled(HuntPersonas.ADEPT).mistake_rate + 0.01,
		"less often than Hari Dai")
	check_eq(HuntPersonas.plain(HuntPersonas.MASTER).mistake_rate, 0.0, "the plain Master is exact")
	check_eq(HuntPersonas.plain(HuntPersonas.MASTER).lapse_rate, 0.0, "and never lapses")


func test_plain_levels_have_no_style() -> void:
	for i in HuntPersonas.SPECS.size():
		var p := HuntPersonas.plain(i)
		check(not p.greedy_captures and p.lapse_rate == 0.0 and not p.vary_ties and p.think_ms == 0
			and p.hunter_style.is_empty() and p.prey_style.is_empty(), "%s is plain" % p.id)
