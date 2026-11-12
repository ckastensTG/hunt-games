class_name AIPersona
extends Resource
## A named AI opponent: search limits, a model of plausible mistakes, and a
## style of play (framework §4.4).
##
## Mistakes are never random moves. With probability `mistake_rate` the
## persona picks among root moves scoring within `candidate_window` of the
## best, weighted by a softmax with `temperature`. A shallow `max_depth` adds
## the human-like horizon: it simply doesn't see deep tactics.
##
## Style, on top of strength:
##   greedy_captures   takes a capture whenever it has one (a beginner)
##   lapse_rate/window now and then a bigger slip (a player who looks away),
##                     picked with a flatter softmax (at least window / 2);
##                     with lapse_pause_ms, the move comes later, too
##   hunter_style /    its own idea of a good position on each side: weight
##   prey_style        name → multiplier over the title's HuntEvalWeights
##   vary_ties         among equally good moves, a different one from game to
##                     game (the root moves are tried in a varied order; no
##                     cost in strength)
##   think_ms          the least time a move takes to appear (its pace)
##   contempt          how much worse than even a draw is for it (points; a
##                     capture is about 1000): it plays on instead of
##                     repeating (HuntSearcher.contempt)

@export var id: String = ""
@export var display_name_key: String = ""
@export var max_depth: int = 4
@export var time_limit_ms: int = 1500
@export var candidate_window: int = 0
@export var temperature: float = 60.0
@export_range(0.0, 1.0) var mistake_rate: float = 0.0
@export var greedy_captures := false
@export_range(0.0, 1.0) var lapse_rate: float = 0.0
@export var lapse_window: int = 0
@export var hunter_style: Dictionary = {}
@export var prey_style: Dictionary = {}
@export var vary_ties := false
@export var think_ms: int = 0
@export var lapse_pause_ms: int = 0
@export var contempt: int = 0


## The evaluator this persona plays `side` with: the title's, with the
## persona's style for that side applied (a copy; `base` is untouched).
func evaluator_for(side: int, base: HuntEvaluator) -> HuntEvaluator:
	var style: Dictionary = hunter_style if side == HuntState.HUNTER else prey_style
	if style.is_empty() or base == null:
		return base
	var w: HuntEvalWeights = base.weights.duplicate()
	for key in style:
		var v: Variant = w.get(key)
		if v == null:
			push_warning("AIPersona %s: no weight called %s" % [id, key])
			continue
		w.set(key, roundi(float(v) * float(style[key])))
	return HuntEvaluator.new(w)


## A searcher with this persona's limits. `seed_value` varies the order of
## equally good moves when `vary_ties` is on.
func make_searcher(evaluator: HuntEvaluator, seed_value := 0) -> HuntSearcher:
	var s := HuntSearcher.new(evaluator)
	s.max_depth = max_depth
	s.time_limit_ms = time_limit_ms
	s.exact_root_scores = (candidate_window > 0 and mistake_rate > 0.0) or (lapse_window > 0 and lapse_rate > 0.0)
	s.contempt = contempt
	if vary_ties:
		s.vary_seed = seed_value if seed_value != 0 else 1
	return s


## Picks the move from a finished search.
func pick(s: HuntSearcher, rng: RandomNumberGenerator) -> PackedInt32Array:
	return pick_ex(s, rng).move


## The move and how it came about: {move, lapse} (lapse: a bigger slip).
func pick_ex(s: HuntSearcher, rng: RandomNumberGenerator) -> Dictionary:
	if s.root_moves.is_empty():
		return {"move": PackedInt32Array(), "lapse": false}
	var greedy := _greedy_capture(s)
	if not greedy.is_empty():
		return {"move": greedy, "lapse": false}
	var scored := s.root_scores.size() == s.root_moves.size()
	var lapses := lapse_window > 0 and lapse_rate > 0.0 and scored
	var slips := candidate_window > 0 and mistake_rate > 0.0 and scored
	if not lapses and not slips:
		return {"move": s.best_move, "lapse": false}
	var r := rng.randf()
	if lapses and r < lapse_rate:
		# A lapse spreads wider than a slip: the softmax is flatter too.
		return {"move": _within(s, rng, lapse_window, maxf(temperature, lapse_window / 2.0)), "lapse": true}
	var slip_until := (lapse_rate if lapses else 0.0) + mistake_rate
	if slips and r < slip_until:
		return {"move": _within(s, rng, candidate_window), "lapse": false}
	return {"move": s.best_move, "lapse": false}


## Blocking search + pick. The game runs this on a worker thread.
func choose(state: HuntState, evaluator: HuntEvaluator, rng: RandomNumberGenerator) -> PackedInt32Array:
	var s := make_searcher(evaluator_for(state.side, evaluator), rng.randi() if vary_ties else 0)
	s.begin(state)
	while not s.step(20000):
		pass
	return pick(s, rng)


## A move among those within `window` of the best, softmax-weighted.
func _within(s: HuntSearcher, rng: RandomNumberGenerator, window: int, temp := -1.0) -> PackedInt32Array:
	if temp <= 0.0:
		temp = temperature
	var best := s.best_score
	var candidates: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	for i in s.root_moves.size():
		var sc: int = s.root_scores[i]
		if sc < best - window:
			continue
		# Never blunder into a forced loss the persona can see.
		if s.is_decisive(sc) and sc < 0 and sc < best:
			continue
		var w := exp(float(sc - best) / maxf(temp, 1.0))
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


## With greedy_captures: the capture to take, or an empty move. The one
## taking the most pieces (then the best scored); none when the best move
## wins by force or every capture is a loss it can see.
func _greedy_capture(s: HuntSearcher) -> PackedInt32Array:
	if not greedy_captures:
		return PackedInt32Array()
	if s.is_decisive(s.best_score) and s.best_score > 0:
		return PackedInt32Array()
	var scored := s.root_scores.size() == s.root_moves.size()
	var pick_i := -1
	var pick_caps := 0
	var pick_score := 0
	for i in s.root_moves.size():
		var m: PackedInt32Array = s.root_moves[i]
		var caps := HuntState.captures_in(m)
		if caps <= 0:
			continue
		var sc: int = s.root_scores[i] if scored else 0
		if scored and s.is_decisive(sc) and sc < 0:
			continue
		if pick_i < 0 or caps > pick_caps or (caps == pick_caps and sc > pick_score):
			pick_i = i
			pick_caps = caps
			pick_score = sc
	return s.root_moves[pick_i] if pick_i >= 0 else PackedInt32Array()
