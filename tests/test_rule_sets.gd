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


func test_komikan_games_are_finite_and_decisive() -> void:
	# Rules §4.2: dog moves are irreversible, so every game ends with a winner
	# within ~150 plies. Random playouts check it, for both first players.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for first in [HuntRuleSet.HUNTER, HuntRuleSet.PREY]:
		var rules := HuntRuleSets.komikan(first)
		for _game in 60:
			var s := HuntState.create(rules)
			var moves: Array[PackedInt32Array] = []
			var st := s.analyze(moves)
			while st == HuntState.Status.ONGOING:
				s.make(moves[rng.randi_range(0, moves.size() - 1)])
				st = s.analyze(moves)
				if s.ply > 160:
					break
			check(st != HuntState.Status.ONGOING, "game ended")
			check(st != HuntState.Status.DRAW, "no draws in Komikan (reason %d)" % s.last_reason)
			check(s.ply <= 160, "within the bound")


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
