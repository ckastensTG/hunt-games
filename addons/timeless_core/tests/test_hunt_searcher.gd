extends TestCase

const J := HuntState.Kind.JUMP


func test_hunter_takes_a_winning_capture() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(1, 0), Vector2(4, 4)], {"capture_target": 1})
	var search := HuntSearcher.new()
	search.max_depth = 3
	var m := search.run(s)
	check_eq(m[0], J, "jumps")
	check(search.is_decisive(search.best_score) and search.best_score > 0, "sees the win")
	check_eq(search.plies_to_end(search.best_score), 1, "win in one ply")


func test_prey_closes_the_trap() -> void:
	var b := HuntFixtures.alquerque()
	# Hunter in the corner. Only c2 -> b2 seals it: every other step into b2
	# opens a square the hunter can use.
	var prey := [Vector2(1, 0), Vector2(0, 1), Vector2(2, 0), Vector2(0, 2), Vector2(2, 2), Vector2(2, 1)]
	var s := HuntFixtures.state(b, [Vector2(0, 0)], prey, {"first_player": HuntRuleSet.PREY})
	var search := HuntSearcher.new()
	search.max_depth = 3
	var m := search.run(s)
	check_eq(b.positions[m[2]], Vector2(1, 1), "steps into b2")
	check(search.best_score > 0 and search.is_decisive(search.best_score), "prey sees the win")


func test_search_leaves_the_input_state_untouched() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	var before := s.hash_key
	var search := HuntSearcher.new()
	search.max_depth = 4
	search.run(s)
	check_eq(s.hash_key, before, "hash")
	check_eq(s.ply, 0, "ply")


func test_sliced_search_matches_blocking_search() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	s.make(s.legal_moves()[7])
	var a := HuntSearcher.new()
	a.max_depth = 4
	var best_a := a.run(s)
	var b := HuntSearcher.new()
	b.max_depth = 4
	b.begin(s)
	var slices := 0
	while not b.step(17):
		slices += 1
	check(slices > 10, "really ran in slices")
	check_eq(b.best_move, best_a, "same move")
	check_eq(b.best_score, a.best_score, "same score")
	check_eq(b.completed_depth, 4, "depth")


func test_exact_root_scores_cover_every_move() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	var search := HuntSearcher.new()
	search.max_depth = 2
	search.exact_root_scores = true
	search.run(s)
	check_eq(search.root_scores.size(), search.root_moves.size(), "one score per move")
	var top := -HuntSearcher.INF
	for sc in search.root_scores:
		check(sc > -HuntSearcher.INF, "every move scored")
		top = maxi(top, sc)
	check_eq(search.best_score, top, "best is the max")


func test_persona_mistakes_are_seeded() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	var p := AIPersona.new()
	p.max_depth = 2
	p.time_limit_ms = 0
	p.candidate_window = 200
	p.mistake_rate = 1.0
	var picks := []
	for _run in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		picks.append(p.choose(s, HuntEvaluator.new(), rng))
	check_eq(picks[0], picks[1], "same seed, same move")
