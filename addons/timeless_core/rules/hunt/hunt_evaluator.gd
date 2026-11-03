class_name HuntEvaluator
extends RefCounted
## Static evaluation for hunt games, from the side to move's point of view.

var weights: HuntEvalWeights


func _init(w: HuntEvalWeights = null) -> void:
	weights = w if w else HuntEvalWeights.new()


func evaluate(s: HuntState) -> int:
	var w := weights
	var board := s.board
	var cells := s.cells
	var score := s.captured * w.capture

	var mobility := 0
	var blocked := 0
	var threatened := 0  # bitmask of prey points a hunter can jump now
	for h in s.hunters:
		var mob := 0
		for j in board.adj[h]:
			if cells[j] == HuntState.EMPTY:
				mob += 1
		var overs := board.jump_over[h]
		var lands := board.jump_land[h]
		for k in overs.size():
			if cells[overs[k]] == HuntState.PREY and cells[lands[k]] == HuntState.EMPTY:
				mob += 1
				threatened |= 1 << overs[k]
		if mob == 0:
			blocked += 1
		mobility += mob
	score += mobility * w.hunter_mobility
	score -= blocked * w.hunter_blocked
	var threats := _popcount(threatened)
	if s.side == HuntState.HUNTER:
		score += threats * w.threat_hunter_to_move
	else:
		score += threats * w.threat_prey_to_move

	if s.reserve > 0 and w.prey_edge_in_placement != 0:
		var on_edge := 0
		for p in board.tagged("edge"):
			if cells[p] == HuntState.PREY:
				on_edge += 1
		score -= on_edge * w.prey_edge_in_placement

	if s.rules.prey_forward_only and w.prey_mobility != 0:
		var prey_moves := 0
		for i in cells.size():
			if cells[i] != HuntState.PREY:
				continue
			for j in board.adj[i]:
				if cells[j] == HuntState.EMPTY and board.ranks[j] > board.ranks[i]:
					prey_moves += 1
		score -= prey_moves * w.prey_mobility

	if w.hunter_territory != 0:
		score += _territory(s) * w.hunter_territory

	return score if s.side == HuntState.HUNTER else -score


## Empty points reachable from the hunters by steps alone (prey block).
func _territory(s: HuntState) -> int:
	var board := s.board
	var cells := s.cells
	var seen := PackedByteArray()
	seen.resize(cells.size())
	var stack := PackedInt32Array()
	for h in s.hunters:
		seen[h] = 1
		stack.append(h)
	var count := 0
	while not stack.is_empty():
		var p := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		for j in board.adj[p]:
			if seen[j] == 0 and cells[j] == HuntState.EMPTY:
				seen[j] = 1
				count += 1
				stack.append(j)
	return count


static func _popcount(x: int) -> int:
	var n := 0
	while x != 0:
		x &= x - 1
		n += 1
	return n
