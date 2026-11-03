extends SceneTree
## Komikan balance test: AI self-play under the shipped rules (rules doc §4.2)
## and under other readings, to see how hard each side finds it to win.
##
##   godot --headless --path . -s res://tools/komikan_balance.gd -- \
##     [--variants=shipped,matus,sideways,free,adugo] [--matches=2v2,4v4,6v6,d6p2,d2p6]
##     [--games=16] [--first=hunter|prey] [--seed=1] [--csv=PATH] [--territory=W]
##
## Variants:
##   shipped   the rules in the game since 2026-11-03 (Trapial-Kuzen movement
##             and win): dogs step in any direction, 3 captures win, threefold
##             repetition, the 100-ply no-capture limit and stuck dogs draw.
##   matus     the rules until 2026-11-03 (Mátus 1918-19): dogs step forward
##             only, never sideways or back; the puma must eat all 12; dogs
##             that can't move lose. The dogs can never trap a puma that stays
##             in the tower (tools/komikan_tower/).
##   sideways  matus, but dogs may also step sideways, never back. Threefold
##             repetition and the 100-ply no-capture limit are draws.
##   free      dogs move in any direction and the puma must eat all 12.
##   adugo     Jogo da Onça's own rules, for comparison (14 dogs, 5 captures).
##
## Matches: "4v4" = dogs search depth 4 vs puma depth 4; "d6p2" = dogs 6 vs
## puma 2. Depth 0 plays a random legal move (a careless beginner). Both sides pick among moves within a few points of their best, so
## games differ without either side playing badly. --territory=W adds the
## evaluator's territory term (the puma's reachable space), which the dogs
## need to plan a trap.

var variants := ["shipped", "matus", "sideways", "free"]
var matches := ["2v2", "4v4", "6v6", "d6p2", "d2p6"]
var games := 16
var first := HuntRuleSet.HUNTER
var seed_base := 1
var csv_path := ""
var territory := 0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variants="):
			variants = Array(arg.substr(11).split(","))
		elif arg.begins_with("--matches="):
			matches = Array(arg.substr(10).split(","))
		elif arg.begins_with("--games="):
			games = int(arg.substr(8))
		elif arg == "--first=prey":
			first = HuntRuleSet.PREY
		elif arg.begins_with("--seed="):
			seed_base = int(arg.substr(7))
		elif arg.begins_with("--csv="):
			csv_path = arg.substr(6)
		elif arg.begins_with("--territory="):
			territory = int(arg.substr(12))
	var csv: FileAccess = null
	if csv_path != "":
		csv = FileAccess.open(csv_path, FileAccess.WRITE)
		csv.store_line("variant,first,match,game,result,reason,plies,captured")
	print("variant   first  match  games  dogs win  puma win (capture target / dogs stuck / other)  draws  avg plies  avg eaten")
	for v in variants:
		var rules := make_rules(v)
		for m in matches:
			var depths := parse_match(m)
			var tally := {"dogs": 0, "puma": 0, "eaten": 0, "stuck": 0, "puma_other": 0, "draw": 0, "plies": 0, "captured": 0}
			for g in games:
				var r := play(rules, depths[0], depths[1], seed_base * 1000 + g)
				tally.plies += r.plies
				tally.captured += r.captured
				match r.status:
					HuntState.Status.PREY_WIN:
						tally.dogs += 1
					HuntState.Status.HUNTER_WIN:
						tally.puma += 1
						if r.reason == HuntState.Reason.CAPTURE_TARGET:
							tally.eaten += 1
						elif r.reason == HuntState.Reason.PREY_STUCK:
							tally.stuck += 1
						else:
							tally.puma_other += 1
					_:
						tally.draw += 1
				if csv:
					csv.store_line("%s,%s,%s,%d,%s,%s,%d,%d" % [v, "puma" if first == HuntRuleSet.HUNTER else "dogs", m, g,
						HuntState.Status.keys()[r.status], HuntState.Reason.keys()[r.reason], r.plies, r.captured])
					csv.flush()
			print("%-9s %-6s %-6s %5d  %8d  %8d (%d / %d / %d)  %32d  %9.0f  %9.1f" % [
				v, "puma" if first == HuntRuleSet.HUNTER else "dogs", m, games, tally.dogs, tally.puma,
				tally.eaten, tally.stuck, tally.puma_other, tally.draw,
				float(tally.plies) / games, float(tally.captured) / games])
	quit()


func make_rules(variant: String) -> HuntRuleSet:
	var r := HuntRuleSets.komikan(first)
	var matus := {"prey_forward_only": true, "capture_target": 12, "repetition": HuntRuleSet.Repetition.NONE,
		"no_capture_limit_plies": 0, "prey_stuck_result": HuntRuleSet.StuckResult.HUNTER_WIN}
	match variant:
		"shipped":
			return r
		"matus":
			return r.copy_with(matus)
		"sideways":
			matus.merge({"prey_sideways": true, "repetition": HuntRuleSet.Repetition.THREEFOLD_DRAW,
				"no_capture_limit_plies": 100}, true)
			return r.copy_with(matus)
		"free":
			return r.copy_with({"capture_target": 12})
		"adugo":
			return HuntRuleSets.adugo()
	push_error("unknown variant %s" % variant)
	return r


## "4v4" -> [4, 4]; "d6p2" -> [6, 2]  (dogs depth, puma depth)
func parse_match(m: String) -> Array:
	if m.begins_with("d"):
		var parts := m.substr(1).split("p")
		return [int(parts[0]), int(parts[1])]
	var parts2 := m.split("v")
	return [int(parts2[0]), int(parts2[1])]


func play(rules: HuntRuleSet, dog_depth: int, puma_depth: int, game_seed: int) -> Dictionary:
	var s := HuntState.create(rules)
	var w := HuntRuleSets.weights_for(rules)
	w.hunter_territory = territory
	var evaluator := HuntEvaluator.new(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	var dogs := persona(dog_depth)
	var puma := persona(puma_depth)
	var moves: Array[PackedInt32Array] = []
	var status := s.analyze(moves)
	while status == HuntState.Status.ONGOING and s.ply < 400:
		var p := puma if s.side == HuntState.HUNTER else dogs
		var m: PackedInt32Array
		if p == null:
			m = moves[rng.randi_range(0, moves.size() - 1)]
		else:
			m = p.choose(s, evaluator, rng)
		if m.is_empty():
			break
		s.make(m)
		status = s.analyze(moves)
	return {"status": status, "reason": s.last_reason, "plies": s.ply, "captured": s.captured}


func persona(depth: int) -> AIPersona:
	if depth <= 0:
		return null
	var p := AIPersona.new()
	p.max_depth = depth
	p.time_limit_ms = 0
	p.candidate_window = 15  # near-best moves only: variety, not mistakes
	p.mistake_rate = 1.0
	p.temperature = 4.0
	return p
