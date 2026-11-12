extends TestCase
## AIPersona's style knobs (framework §4.4): greedy captures, lapses, a style
## of evaluation per side, varied ties, and the driver reporting lapses.

const J := HuntState.Kind.JUMP


func _searched(p: AIPersona, s: HuntState, seed_value := 0) -> HuntSearcher:
	var search := p.make_searcher(p.evaluator_for(s.side, HuntEvaluator.new()), seed_value)
	search.begin(s)
	while not search.step(20000):
		pass
	return search


## A tiger with a capture on offer and plenty else to do.
func _capture_on_offer() -> HuntState:
	var b := HuntFixtures.alquerque()
	return HuntFixtures.state(b, [Vector2(2, 2)], [Vector2(3, 2), Vector2(0, 4), Vector2(4, 4)],
		{"capture_target": 5})


func test_greedy_takes_the_biggest_capture() -> void:
	var b := HuntFixtures.alquerque()
	# One jump takes one goat, the other a chain of two.
	var s := HuntFixtures.state(b, [Vector2(0, 2)], [Vector2(1, 2), Vector2(0, 1), Vector2(1, 0)],
		{"capture_target": 9, "multi_jump": true})
	var p := AIPersona.new()
	p.max_depth = 1
	p.time_limit_ms = 0
	p.greedy_captures = true
	var search := _searched(p, s)
	var m := p.pick(search, RandomNumberGenerator.new())
	check_eq(m[0], J, "a capture")
	var most := 0
	for rm in search.root_moves:
		most = maxi(most, HuntState.captures_in(rm))
	check_eq(HuntState.captures_in(m), most, "the one taking the most")


func test_greedy_still_takes_a_win() -> void:
	var b := HuntFixtures.alquerque()
	# Prey to move with a trap to close: no captures for prey anyway; and a
	# hunter one capture from winning takes the winning jump.
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(1, 0), Vector2(4, 4)], {"capture_target": 1})
	var p := AIPersona.new()
	p.max_depth = 2
	p.time_limit_ms = 0
	p.greedy_captures = true
	var m := p.pick(_searched(p, s), RandomNumberGenerator.new())
	check_eq(m[0], J, "the winning jump")


func test_lapses_are_reported_and_stay_in_their_window() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	var p := AIPersona.new()
	p.max_depth = 2
	p.time_limit_ms = 0
	p.lapse_rate = 1.0
	p.lapse_window = 300
	var search := _searched(p, s)
	check_eq(search.root_scores.size(), search.root_moves.size(), "lapses need every move scored")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in 10:
		var r := p.pick_ex(search, rng)
		check(r.lapse, "reported as a lapse")
		var i := search.root_moves.find(r.move)
		check(search.root_scores[i] >= search.best_score - 300, "within the window")
	p.lapse_rate = 0.0
	check(not p.pick_ex(search, rng).lapse, "no lapse at rate 0")


func test_mistakes_keep_their_seeded_sequence() -> void:
	# A persona without lapses picks exactly as before lapses existed: one
	# draw decides, a second picks among the candidates.
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	var p := AIPersona.new()
	p.max_depth = 2
	p.time_limit_ms = 0
	p.candidate_window = 200
	p.mistake_rate = 0.5
	var search := _searched(p, s)
	var a := RandomNumberGenerator.new()
	a.seed = 11
	var b := RandomNumberGenerator.new()
	b.seed = 11
	for _i in 8:
		var m := p.pick(search, a)
		var expect := search.best_move
		if b.randf() < 0.5:
			expect = p._within(search, b, 200)
		check_eq(m, expect, "same as the plain mistake model")


func test_style_changes_only_its_side() -> void:
	var base := HuntEvaluator.new()
	var p := AIPersona.new()
	p.prey_style = {"hunter_blocked": 2.0, "threat_prey_to_move": 1.5}
	p.hunter_style = {"capture": 1.25}
	var as_prey := p.evaluator_for(HuntState.PREY, base)
	var as_hunter := p.evaluator_for(HuntState.HUNTER, base)
	check_eq(as_prey.weights.hunter_blocked, base.weights.hunter_blocked * 2, "prey: blocked tigers count double")
	check_eq(as_prey.weights.threat_prey_to_move, roundi(base.weights.threat_prey_to_move * 1.5), "prey: threats")
	check_eq(as_prey.weights.capture, base.weights.capture, "prey: captures as before")
	check_eq(as_hunter.weights.capture, roundi(base.weights.capture * 1.25), "hunter: captures")
	check_eq(base.weights.hunter_blocked, HuntEvalWeights.new().hunter_blocked, "the title's weights untouched")
	var plain := AIPersona.new()
	check(plain.evaluator_for(HuntState.PREY, base) == base, "no style: the same evaluator")


func test_varied_ties_keep_the_best_score() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	var p := AIPersona.new()
	p.max_depth = 3
	p.time_limit_ms = 0
	var plain := _searched(p, s)
	p.vary_ties = true
	var seen := {}
	for seed_value in range(1, 13):
		var search := _searched(p, s, seed_value)
		check_eq(search.best_score, plain.best_score, "the same best score (seed %d)" % seed_value)
		seen[search.best_move] = true
	check(seen.size() > 1, "different moves among equals (%d)" % seen.size())
	var again := _searched(p, s, 5)
	check_eq(again.best_move, _searched(p, s, 5).best_move, "same seed, same move")


func test_driver_uses_the_style_and_reports_lapses() -> void:
	var s := _capture_on_offer()
	var p := AIPersona.new()
	p.max_depth = 1
	p.time_limit_ms = 0
	p.greedy_captures = true
	var driver := AIDriver.new()
	driver.start(s, p, HuntEvaluator.new(), 3)
	var move := PackedInt32Array()
	for _i in 2000:
		move = driver.poll()
		if not driver.is_thinking():
			break
		OS.delay_msec(1)
	check_eq(move[0], J, "greedy through the driver")
	check(not driver.last_was_lapse(), "not a lapse")
	var q := AIPersona.new()
	q.max_depth = 1
	q.time_limit_ms = 0
	q.lapse_rate = 1.0
	q.lapse_window = 100000
	driver.start(HuntState.create(HuntFixtures.tigers_and_goats()), q, HuntEvaluator.new(), 3)
	for _i in 2000:
		driver.poll()
		if not driver.is_thinking():
			break
		OS.delay_msec(1)
	check(driver.last_was_lapse(), "a lapse is reported")


func test_contempt_reaches_the_search() -> void:
	var p := AIPersona.new()
	check_eq(p.make_searcher(HuntEvaluator.new()).contempt, 0, "none by default")
	p.contempt = 120
	check_eq(p.make_searcher(HuntEvaluator.new()).contempt, 120, "the persona's contempt")

