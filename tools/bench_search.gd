extends SceneTree
## Search speed benchmark.
##   godot --headless --path . -s res://tools/bench_search.gd -- [--depth=6]
## Prints nodes/second for each rule set from a few opening positions.

func _init() -> void:
	var depth := 6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--depth="):
			depth = int(arg.substr(8))
	print("Godot %s, %s, depth %d" % [Engine.get_version_info().string, OS.get_name(), depth])
	for id in HuntRuleSets.ALL:
		var rules := HuntRuleSets.by_id(id)
		var s := HuntState.create(rules)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		# A few random opening plies so we don't only measure the start.
		for _i in 6:
			var moves := s.legal_moves()
			if moves.is_empty():
				break
			s.make(moves[rng.randi_range(0, moves.size() - 1)])
		var search := HuntSearcher.new(HuntEvaluator.new(HuntRuleSets.weights_for(rules)))
		search.max_depth = depth
		var t := Time.get_ticks_usec()
		search.run(s)
		var secs := (Time.get_ticks_usec() - t) / 1e6
		print("%-28s depth %d  %8d nodes  %6.2f s  %8.0f nodes/s  best %s (%d)" % [
			id, search.completed_depth, search.nodes, secs, search.nodes / maxf(secs, 1e-6),
			s.describe(search.best_move), search.best_score])
	quit()
