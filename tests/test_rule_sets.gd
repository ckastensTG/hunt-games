extends TestCase


func test_every_rule_set_starts_ongoing() -> void:
	for id in HuntRuleSets.ALL:
		var s := HuntState.create(HuntRuleSets.by_id(id))
		check_eq(s.status(), HuntState.Status.ONGOING, id)


func test_fingerprints_differ() -> void:
	var seen := {}
	for id in HuntRuleSets.ALL:
		var f := HuntRuleSets.by_id(id).fingerprint()
		check(not seen.has(f), "fingerprint collision for %s" % id)
		seen[f] = id
	var a := HuntRuleSets.komikan(HuntRuleSet.HUNTER).fingerprint()
	var b := HuntRuleSets.komikan(HuntRuleSet.PREY).fingerprint()
	check(a != b, "Komikan first-player option changes the fingerprint")


func test_bagh_chal_variants() -> void:
	check_eq(HuntRuleSets.bagh_chal_standard().capture_target, 5, "standard")
	check_eq(HuntRuleSets.bagh_chal_parlett().capture_target, 20, "Parlett 1976")


func test_komikan_movement_and_win() -> void:
	# Rules §4.2 (2026-11-03): Trapial-Kuzen movement and win on the Mátus
	# board: dogs step in any direction, three captures win, Adugo's draws.
	var r := HuntRuleSets.komikan()
	check(not r.prey_forward_only, "dogs move in any direction")
	check_eq(r.capture_target, 3, "three dogs win")
	check_eq(r.first_player, HuntRuleSet.HUNTER, "puma first by default")
	check(r.multi_jump, "capture chains")
	check_eq(r.repetition, HuntRuleSet.Repetition.THREEFOLD_DRAW, "threefold draw")
	check_eq(r.no_capture_limit_plies, 100, "50 moves each without a capture")
	check_eq(r.prey_stuck_result, HuntRuleSet.StuckResult.DRAW, "stuck dogs draw")
	# A dog may step back: c3 -> c2 once c2 is empty.
	var board := r.board
	var s := HuntState.create(r)
	var c2 := board.point_at(Vector2(2, 1))
	var c3 := board.point_at(Vector2(2, 2))
	var dogs := PackedInt32Array()
	for p in r.prey_start:
		if p != c2:
			dogs.append(p)
	dogs.append(c3)
	s.set_position(r.hunter_start, dogs, 0, 0, HuntState.PREY)
	check(s.is_legal(PackedInt32Array([HuntState.Kind.STEP, c3, c2])), "a dog steps back")


func test_quiet_count_is_hunter_moves() -> void:
	# The HUD counts the no-capture rule in the hunter's moves (50, not 100).
	var r := HuntRuleSets.adugo()
	var s := HuntState.create(r)  # the jaguar moves first
	var moves: Array[PackedInt32Array] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hunter_steps := 0
	while s.analyze(moves) == HuntState.Status.ONGOING and s.ply < 40:
		var steps := moves.filter(func(m: PackedInt32Array) -> bool: return m[0] == HuntState.Kind.STEP)
		if steps.is_empty():
			break
		if s.side == HuntState.HUNTER:
			hunter_steps += 1
		s.make(steps[rng.randi_range(0, steps.size() - 1)])
		if s.captured == 0:
			check(HuntText.quiet_moves("adugo", s, r).begins_with("Jaguar moves without capturing: %d / 50" % hunter_steps),
				"after ply %d" % s.ply)


func test_random_games_terminate_in_every_rule_set() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id in HuntRuleSets.ALL:
		var rules := HuntRuleSets.by_id(id)
		for _game in 15:
			var s := HuntState.create(rules)
			var moves: Array[PackedInt32Array] = []
			var st := s.analyze(moves)
			while st == HuntState.Status.ONGOING and s.ply < 2000:
				s.make(moves[rng.randi_range(0, moves.size() - 1)])
				st = s.analyze(moves)
			check(st != HuntState.Status.ONGOING, "%s ended by ply %d" % [id, s.ply])
