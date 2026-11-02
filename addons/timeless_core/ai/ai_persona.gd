class_name AIPersona
extends Resource
## A named AI opponent: search limits plus a model of plausible mistakes.
##
## Mistakes are never random moves. With probability `mistake_rate` the
## persona picks among root moves scoring within `candidate_window` of the
## best, weighted by a softmax with `temperature`. A shallow `max_depth` adds
## the human-like horizon: it simply doesn't see deep tactics.

@export var id: String = ""
@export var display_name_key: String = ""
@export var max_depth: int = 4
@export var time_limit_ms: int = 1500
@export var candidate_window: int = 0
@export var temperature: float = 60.0
@export_range(0.0, 1.0) var mistake_rate: float = 0.0


func make_searcher(evaluator: HuntEvaluator) -> HuntSearcher:
	var s := HuntSearcher.new(evaluator)
	s.max_depth = max_depth
	s.time_limit_ms = time_limit_ms
	s.exact_root_scores = candidate_window > 0 and mistake_rate > 0.0
	return s


## Picks the move from a finished search.
func pick(s: HuntSearcher, rng: RandomNumberGenerator) -> PackedInt32Array:
	if s.root_moves.is_empty():
		return PackedInt32Array()
	if candidate_window <= 0 or mistake_rate <= 0.0 or s.root_scores.size() != s.root_moves.size():
		return s.best_move
	if rng.randf() >= mistake_rate:
		return s.best_move
	var best := s.best_score
	var candidates: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	for i in s.root_moves.size():
		var sc: int = s.root_scores[i]
		if sc < best - candidate_window:
			continue
		# Never blunder into a forced loss the persona can see.
		if s.is_decisive(sc) and sc < 0 and sc < best:
			continue
		var w := exp(float(sc - best) / maxf(temperature, 1.0))
		candidates.append(i)
		weights.append(w)
		total += w
	if candidates.is_empty():
		return s.best_move
	var r := rng.randf() * total
	for k in candidates.size():
		r -= weights[k]
		if r <= 0.0:
			return s.root_moves[candidates[k]]
	return s.root_moves[candidates[candidates.size() - 1]]


## Blocking search + pick. The game runs this on a worker thread.
func choose(state: HuntState, evaluator: HuntEvaluator, rng: RandomNumberGenerator) -> PackedInt32Array:
	var s := make_searcher(evaluator)
	s.begin(state)
	while not s.step(20000):
		pass
	return pick(s, rng)
