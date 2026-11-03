extends SceneTree
## AI level ladder: the greybox's AI levels (HuntPersonas) play each other, to
## see whether each level is really stronger than the one below and whether the
## top levels can lose (framework §12, "self-play").
##
##   godot --headless --path . -s res://tools/persona_ladder.gd -- \
##     [--rules=bagh_chal_standard,jogo_da_onca_adugo] [--pairs=adept:master,master:master]
##     [--games=4] [--opening=2] [--seed=1] [--csv=PATH]
##
## Each pair "a:b" plays --games games with a as the hunter and b as the prey,
## then as many with the sides swapped. The first --opening plies are picked
## among near-best moves so that games differ. Personas: novice, apprentice,
## adept, master, plus "deep" (no mistakes, depth 10 and 4x Master's time),
## standing in for a player who reads further ahead than Master.
##
## Prints the results per pair and side, then each persona's average completed
## search depth and time per move. Time limits are wall-clock, so depth depends
## on the machine: a phone reaches less than a desktop.

var rule_ids: Array = [HuntRuleSets.BAGH_CHAL_STANDARD]
var pairs: Array = ["adept:master"]
var games := 4
var opening := 2
var seed_base := 1
var csv_path := ""
var stats := {}  # persona id -> {moves, depth, ms}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rules="):
			rule_ids = Array(arg.substr(8).split(","))
		elif arg.begins_with("--pairs="):
			pairs = Array(arg.substr(8).split(","))
		elif arg.begins_with("--games="):
			games = int(arg.substr(8))
		elif arg.begins_with("--opening="):
			opening = int(arg.substr(10))
		elif arg.begins_with("--seed="):
			seed_base = int(arg.substr(7))
		elif arg.begins_with("--csv="):
			csv_path = arg.substr(6)
	var csv: FileAccess = null
	if csv_path != "":
		csv = FileAccess.open(csv_path, FileAccess.WRITE)
		csv.store_line("rules,hunter,prey,game,result,reason,plies,captured")
	print("rules                       hunter      prey         games  hunter wins  prey wins  draws  avg plies  avg captured")
	for id in rule_ids:
		var rules := HuntRuleSets.by_id(id)
		for pair in pairs:
			var names: PackedStringArray = pair.split(":")
			for swap in [false, true]:
				var hunter_id: String = names[1] if swap else names[0]
				var prey_id: String = names[0] if swap else names[1]
				var t := {"hunter": 0, "prey": 0, "draw": 0, "plies": 0, "captured": 0}
				for g in games:
					var r := play(rules, persona(hunter_id), persona(prey_id), seed_base * 1000 + g)
					t.plies += r.plies
					t.captured += r.captured
					match r.status:
						HuntState.Status.HUNTER_WIN:
							t.hunter += 1
						HuntState.Status.PREY_WIN:
							t.prey += 1
						_:
							t.draw += 1
					if csv:
						csv.store_line("%s,%s,%s,%d,%s,%s,%d,%d" % [id, hunter_id, prey_id, g,
							HuntState.Status.keys()[r.status], HuntState.Reason.keys()[r.reason], r.plies, r.captured])
						csv.flush()
				print("%-27s %-11s %-11s  %5d  %11d  %9d  %5d  %9.0f  %12.1f" % [id, hunter_id, prey_id, games,
					t.hunter, t.prey, t.draw, float(t.plies) / games, float(t.captured) / games])
	print("")
	print("persona      moves  avg completed depth  avg ms per move")
	for pid in stats:
		var st: Dictionary = stats[pid]
		print("%-11s  %5d  %19.1f  %15.0f" % [pid, st.moves, float(st.depth) / maxi(st.moves, 1),
			float(st.ms) / maxi(st.moves, 1)])
	quit()


func persona(id: String) -> AIPersona:
	if id == "deep":
		var master := HuntPersonas.make(HuntPersonas.SPECS[HuntPersonas.MASTER])
		master.id = "deep"
		master.max_depth = 10
		master.time_limit_ms *= 4
		return master
	for spec in HuntPersonas.SPECS:
		if spec[0] == id:
			return HuntPersonas.make(spec)
	push_error("unknown persona %s" % id)
	return null


func play(rules: HuntRuleSet, hunter: AIPersona, prey: AIPersona, game_seed: int) -> Dictionary:
	var s := HuntState.create(rules)
	var evaluator := HuntEvaluator.new(HuntRuleSets.weights_for(rules))
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	# Opening variety: near-best moves only, so neither side starts behind.
	var opener := AIPersona.new()
	opener.id = "opening"
	opener.max_depth = 4
	opener.candidate_window = 20
	opener.mistake_rate = 1.0
	opener.temperature = 10.0
	var moves: Array[PackedInt32Array] = []
	var status := s.analyze(moves)
	while status == HuntState.Status.ONGOING and s.ply < 300:
		var p: AIPersona = opener if s.ply < opening else (hunter if s.side == HuntState.HUNTER else prey)
		var search := p.make_searcher(evaluator)
		var t0 := Time.get_ticks_msec()
		search.begin(s)
		while not search.step(20000):
			pass
		var m := p.pick(search, rng)
		if p != opener:
			var st: Dictionary = stats.get(p.id, {"moves": 0, "depth": 0, "ms": 0})
			st.moves += 1
			st.depth += search.completed_depth
			st.ms += Time.get_ticks_msec() - t0
			stats[p.id] = st
		if m.is_empty():
			break
		s.make(m)
		status = s.analyze(moves)
	return {"status": status, "reason": s.last_reason, "plies": s.ply, "captured": s.captured}
