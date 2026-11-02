extends TestCase
## Board fixtures from the rules doc, verified independently by script
## (2026-11-01/02). If one of these changes, the board is wrong.


func test_bagh_chal_board() -> void:
	var b := HuntBoards.alquerque_5x5()
	check_eq(b.point_count(), 25, "points")
	check_eq(b.line_segment_count(), 56, "lines")
	check_eq(b.jump_count(), 80, "directed jumps")


func test_adugo_board() -> void:
	var b := HuntBoards.adugo_31()
	check_eq(b.point_count(), 31, "points")
	check_eq(b.line_segment_count(), 66, "lines")
	check_eq(b.jump_count(), 96, "directed jumps")
	check_eq(b.tagged("den").size(), 6, "triangle points")


func test_komikan_board() -> void:
	var b := HuntBoards.komikan_matus()
	check_eq(b.point_count(), 38, "points (Depaulis: 25 + 13)")
	check_eq(b.line_segment_count(), 79, "lines")
	check_eq(b.jump_count(), 116, "directed jumps")
	check_eq(b.tagged("den").size(), 13, "triangle points")


func test_adugo_opening() -> void:
	var s := HuntState.create(HuntRuleSets.adugo())
	check_eq(s.side, HuntState.HUNTER, "jaguar first")
	check_eq(s.rules.prey_start.size(), 14, "14 dogs")
	var targets := s.legal_moves().map(func(m: PackedInt32Array) -> Vector2: return s.board.positions[m[2]])
	targets.sort()
	check_eq(targets, [Vector2(1, 3), Vector2(2, 3), Vector2(3, 3)], "three steps, no capture")


func test_komikan_opening() -> void:
	var s := HuntState.create(HuntRuleSets.komikan())
	check_eq(s.rules.prey_start.size(), 12, "12 dogs")
	check_eq(s.legal_moves().size(), 4, "the puma has four steps")
	var dogs_first := HuntState.create(HuntRuleSets.komikan(HuntRuleSet.PREY))
	var forward := dogs_first.legal_moves()
	check_eq(forward.size(), 9, "nine forward dog steps (two sideways steps excluded)")


func test_every_jump_follows_a_straight_drawn_line() -> void:
	# A jump must pass through two adjacent segments of one straight line,
	# with the jumped point in the middle.
	for board in [HuntBoards.alquerque_5x5(), HuntBoards.adugo_31(), HuntBoards.komikan_matus()]:
		for a in board.point_count():
			for k in board.jump_over[a].size():
				var o: int = board.jump_over[a][k]
				var l: int = board.jump_land[a][k]
				var straight: bool = (board.positions[o] - board.positions[a]).normalized().is_equal_approx(
					(board.positions[l] - board.positions[o]).normalized())
				check(board.adj[a].has(o) and board.adj[o].has(l) and straight,
					"%s: %s over %s to %s" % [board.id, board.positions[a], board.positions[o], board.positions[l]])


func test_chain_dedupe_keeps_every_distinct_outcome() -> void:
	# Deduplicated chains must cover exactly the distinct (landing, captured
	# set) outcomes. Komikan's 38 points exercise point ids above 31.
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	for id in [HuntRuleSets.ADUGO, HuntRuleSets.KOMIKAN]:
		for _game in 120:
			var s := HuntState.create(HuntRuleSets.by_id(id))
			var moves: Array[PackedInt32Array] = []
			while s.analyze(moves) == HuntState.Status.ONGOING and s.ply < 200:
				if s.side == HuntState.HUNTER:
					var outcomes := {}
					for m in s.pseudo_moves(false):
						if m[0] == HuntState.Kind.JUMP:
							var taken := []
							for k in range(2, m.size(), 2):
								taken.append(m[k])
							taken.sort()
							outcomes[[m[m.size() - 1], taken]] = true
					var unique := s.pseudo_moves(true).filter(func(m: PackedInt32Array) -> bool: return m[0] == HuntState.Kind.JUMP)
					check_eq(unique.size(), outcomes.size(), "%s at ply %d" % [id, s.ply])
				s.make(moves[rng.randi_range(0, moves.size() - 1)])
