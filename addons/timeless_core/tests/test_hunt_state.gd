extends TestCase

const P := HuntState.Kind.PLACE
const S := HuntState.Kind.STEP
const J := HuntState.Kind.JUMP


func test_placement_phase_offers_only_placements() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	check_eq(s.side, HuntState.PREY, "goats move first")
	var moves := s.legal_moves()
	check_eq(moves.size(), 21, "placements on the 21 empty points")
	for m in moves:
		check_eq(m[0], P, "only placements")
	s.make(moves[0])
	check_eq(s.side, HuntState.HUNTER, "tigers to move")
	check_eq(s.reserve, 19, "reserve")


func test_single_jump_rules_never_chain() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(1, 0), Vector2(3, 0)])
	var jumps := s.legal_moves().filter(func(m: PackedInt32Array) -> bool: return m[0] == J)
	check_eq(jumps.size(), 1, "one single jump")
	check_eq(HuntState.captures_in(jumps[0]), 1, "captures one")


func test_multi_jump_offers_every_prefix() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(1, 0), Vector2(3, 0)], {"multi_jump": true})
	var jumps := s.legal_moves().filter(func(m: PackedInt32Array) -> bool: return m[0] == J)
	var sizes := jumps.map(func(m: PackedInt32Array) -> int: return HuntState.captures_in(m))
	sizes.sort()
	check_eq(sizes, [1, 2], "stop after one, or continue to two")


func test_chain_never_rejumps_a_taken_prey() -> void:
	var b := HuntFixtures.alquerque()
	# After a1x c1 the origin is empty; jumping back over b1 must not be allowed.
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(1, 0)], {"multi_jump": true})
	for m in s.pseudo_moves(false):
		if m[0] != J:
			continue
		var overs := {}
		for k in range(2, m.size(), 2):
			check(not overs.has(m[k]), "prey %d jumped twice in %s" % [m[k], s.describe(m)])
			overs[m[k]] = true


func test_chain_dedupe_merges_identical_outcomes() -> void:
	var b := HuntFixtures.alquerque()
	# A ring of four prey around b2: the full loop can run either way and ends
	# on a1 with the same four captures.
	var prey := [Vector2(1, 0), Vector2(2, 1), Vector2(1, 2), Vector2(0, 1)]
	var s := HuntFixtures.state(b, [Vector2(0, 0)], prey, {"multi_jump": true})
	var all_jumps := s.pseudo_moves(false).filter(func(m: PackedInt32Array) -> bool: return m[0] == J)
	var unique_jumps := s.pseudo_moves(true).filter(func(m: PackedInt32Array) -> bool: return m[0] == J)
	check_eq(all_jumps.size(), 8, "4 prefixes each way")
	check_eq(unique_jumps.size(), 7, "the two full loops merge")
	var loop: PackedInt32Array = unique_jumps.filter(func(m: PackedInt32Array) -> bool: return HuntState.captures_in(m) == 4)[0]
	s.make(loop)
	check_eq(s.captured, 4, "four captured")
	check_eq(s.cells[b.point_at(Vector2(0, 0))], HuntState.HUNTER, "back on its start point")


func test_forward_only_prey() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(2, 2)], {"prey_forward_only": true, "first_player": HuntRuleSet.PREY})
	var targets := s.legal_moves().map(func(m: PackedInt32Array) -> Vector2: return b.positions[m[2]])
	targets.sort()
	check_eq(targets, [Vector2(1, 3), Vector2(2, 3), Vector2(3, 3)], "only steps to a higher row")


func test_make_unmake_roundtrip_and_incremental_hash() -> void:
	var variants := [
		HuntFixtures.tigers_and_goats(),
		HuntFixtures.tigers_and_goats({"multi_jump": true, "repetition": HuntRuleSet.Repetition.THREEFOLD_DRAW}),
		HuntFixtures.rules(HuntFixtures.alquerque(), [Vector2(2, 2)], [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0), Vector2(0, 1), Vector2(4, 1)],
			{"multi_jump": true, "prey_forward_only": true, "prey_stuck_result": HuntRuleSet.StuckResult.HUNTER_WIN}),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for rs in variants:
		for game in 40:
			var s := HuntState.create(rs)
			var start_hash := s.hash_key
			var start_cells := s.cells.duplicate()
			var played: Array[PackedInt32Array] = []
			for _i in 80:
				var moves: Array[PackedInt32Array] = []
				if s.analyze(moves) != HuntState.Status.ONGOING:
					break
				var m := moves[rng.randi_range(0, moves.size() - 1)]
				s.make(m)
				played.append(m)
				if s.hash_key != s.compute_hash():
					fail("incremental hash drifted after %s" % s.describe(m))
					return
			for k in range(played.size() - 1, -1, -1):
				s.unmake(played[k])
			check_eq(s.hash_key, start_hash, "hash restored")
			check_eq(s.cells, start_cells, "cells restored")
			check_eq(s.ply, 0, "ply restored")
			check_eq(s.captured, 0, "captures restored")


func test_forbid_rule_blocks_recreating_a_position() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(4, 4)], {"repetition": HuntRuleSet.Repetition.FORBID})
	s.make(HuntFixtures.move(s, S, [Vector2(0, 0), Vector2(1, 0)]))
	s.make(HuntFixtures.move(s, S, [Vector2(4, 4), Vector2(4, 3)]))
	s.make(HuntFixtures.move(s, S, [Vector2(1, 0), Vector2(0, 0)]))
	var back := HuntFixtures.move(s, S, [Vector2(4, 3), Vector2(4, 4)])
	check(s.pseudo_moves().has(back), "the move exists physically")
	check(not s.legal_moves().has(back), "but recreates the start position")


func test_threefold_repetition_draws() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(4, 4)], {"repetition": HuntRuleSet.Repetition.THREEFOLD_DRAW})
	for _cycle in 2:
		check_eq(s.status(), HuntState.Status.ONGOING, "still on")
		s.make(HuntFixtures.move(s, S, [Vector2(0, 0), Vector2(1, 0)]))
		s.make(HuntFixtures.move(s, S, [Vector2(4, 4), Vector2(4, 3)]))
		s.make(HuntFixtures.move(s, S, [Vector2(1, 0), Vector2(0, 0)]))
		s.make(HuntFixtures.move(s, S, [Vector2(4, 3), Vector2(4, 4)]))
	check_eq(s.status(), HuntState.Status.DRAW, "third occurrence")
	check_eq(s.last_reason, HuntState.Reason.THREEFOLD, "reason")


func test_no_capture_limit_draws() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(4, 4)], {"no_capture_limit_plies": 3})
	s.make(HuntFixtures.move(s, S, [Vector2(0, 0), Vector2(1, 0)]))
	s.make(HuntFixtures.move(s, S, [Vector2(4, 4), Vector2(4, 3)]))
	check_eq(s.status(), HuntState.Status.ONGOING, "2 quiet plies")
	s.make(HuntFixtures.move(s, S, [Vector2(1, 0), Vector2(2, 0)]))
	check_eq(s.status(), HuntState.Status.DRAW, "3 quiet plies")
	check_eq(s.last_reason, HuntState.Reason.NO_CAPTURE_LIMIT, "reason")


func test_quiet_plies_wait_for_the_movement_phase() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	for _i in 6:
		var moves := s.legal_moves()
		var quiet := moves.filter(func(m: PackedInt32Array) -> bool: return m[0] != J)
		s.make(quiet[0])
	check_eq(s.quiet_plies, 0, "tiger steps during placement don't count")


func test_hunter_trapped_means_prey_win() -> void:
	var b := HuntFixtures.alquerque()
	var prey := [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(2, 0), Vector2(0, 2), Vector2(2, 2)]
	var s := HuntFixtures.state(b, [Vector2(0, 0)], prey)
	check_eq(s.status(), HuntState.Status.PREY_WIN, "trapped")
	check_eq(s.last_reason, HuntState.Reason.HUNTER_TRAPPED, "reason")


func test_prey_stuck_result_is_configurable() -> void:
	var b := HuntFixtures.alquerque()
	var opts := {"prey_forward_only": true, "first_player": HuntRuleSet.PREY}
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(2, 4)], opts)
	check_eq(s.status(), HuntState.Status.DRAW, "default: draw")
	opts["prey_stuck_result"] = HuntRuleSet.StuckResult.HUNTER_WIN
	s = HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(2, 4)], opts)
	check_eq(s.status(), HuntState.Status.HUNTER_WIN, "Komikan: hunter wins")
	check_eq(s.last_reason, HuntState.Reason.PREY_STUCK, "reason")


func test_capture_target_ends_the_game() -> void:
	var b := HuntFixtures.alquerque()
	var s := HuntFixtures.state(b, [Vector2(0, 0)], [Vector2(1, 0), Vector2(4, 4)], {"capture_target": 1})
	s.make(HuntFixtures.move(s, J, [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)]))
	check_eq(s.status(), HuntState.Status.HUNTER_WIN, "target reached")
	check_eq(s.last_reason, HuntState.Reason.CAPTURE_TARGET, "reason")


func test_clone_is_independent() -> void:
	var s := HuntState.create(HuntFixtures.tigers_and_goats())
	var c := s.clone()
	c.make(c.legal_moves()[0])
	check_eq(s.ply, 0, "original untouched")
	check(s.hash_key != c.hash_key, "clone moved on")
