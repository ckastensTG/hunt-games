class_name HuntSearcher
extends RefCounted
## Negamax alpha-beta with iterative deepening, a transposition table and a
## capture quiescence step, written with an explicit stack so the search can
## pause and resume (step()). Native builds run step() on a worker thread; a
## future single-threaded web build can call it a few ms per frame.
##
## Usage:
##   var s := HuntSearcher.new(evaluator)
##   s.max_depth = 6
##   s.begin(state)            # works on a clone; `state` is never touched
##   while not s.step(20000):  # nodes per slice
##       pass
##   s.best_move, s.best_score, s.root_scores

const INF := 1 << 40
const WIN := 1 << 30
const WIN_THRESHOLD := WIN - 10000

const TT_EXACT := 0
const TT_LOWER := 1
const TT_UPPER := 2

# Frame layout (plain Arrays, mutated in place).
const F_MOVES := 0
const F_I := 1
const F_ALPHA := 2
const F_BETA := 3
const F_BEST := 4
const F_BEST_I := 5
const F_DEPTH := 6
const F_PLY := 7
const F_ALPHA0 := 8
const F_KEY := 9
const F_QNODE := 10

var evaluator: HuntEvaluator
var max_depth: int = 6
## Stop after this many nodes (0 = no limit).
var max_nodes: int = 0
## Stop after this many ms (0 = no limit). Checked between nodes.
var time_limit_ms: int = 0
## Search every root move with a full window, so root_scores are exact.
## Costs some pruning at the root; personas use it to pick plausible
## second-best moves.
var exact_root_scores: bool = false
## Stop iterating once a forced win or loss is proven.
var stop_on_decisive: bool = true
## Non-zero: the root moves start in an order shuffled with this seed
## (captures still first), so among moves that score the same a different
## one is chosen from game to game. Strength is unchanged (AIPersona.vary_ties).
var vary_seed: int = 0
var tt_max_entries: int = 300000

# Results of the last completed iteration.
var best_move := PackedInt32Array()
var best_score: int = 0
var completed_depth: int = 0
var root_moves: Array[PackedInt32Array] = []
var root_scores := PackedInt64Array()
var nodes: int = 0
var done: bool = true

var _state: HuntState
var _stack: Array = []
var _depth: int = 0
var _start_ms: int = 0
var _tt := {}
var _iter_scores := PackedInt64Array()


func _init(eval: HuntEvaluator = null) -> void:
	evaluator = eval if eval else HuntEvaluator.new()


func begin(state: HuntState) -> void:
	_state = state.clone()
	_stack.clear()
	nodes = 0
	completed_depth = 0
	best_score = 0
	best_move = PackedInt32Array()
	root_scores = PackedInt64Array()
	_start_ms = Time.get_ticks_msec()
	done = false
	if _tt.size() > tt_max_entries:
		_tt.clear()
	var moves: Array[PackedInt32Array] = []
	if _state.analyze(moves) != HuntState.Status.ONGOING:
		root_moves = []
		done = true
		return
	_order(moves, null)
	if vary_seed != 0:
		_shuffle_root(moves)
	root_moves = moves
	best_move = root_moves[0]
	if root_moves.size() == 1 and not exact_root_scores:
		done = true
		return
	_depth = 1
	_push_root()


## Runs up to `budget` nodes. Returns true when the search is finished.
func step(budget: int) -> bool:
	var stop_at := nodes + budget
	while not done:
		if nodes >= stop_at:
			return false
		if _out_of_limits():
			_finish()
			break
		var f: Array = _stack[_stack.size() - 1]
		if f[F_MOVES] == null:
			nodes += 1
			var v: Variant = _enter(f)
			if v != null:
				_stack.pop_back()
				_child_returned(v)
			continue
		var moves: Array = f[F_MOVES]
		var i: int = f[F_I]
		if i < moves.size() and f[F_ALPHA] < f[F_BETA]:
			_state.make(moves[i])
			var a: int = -f[F_BETA]
			var b: int = -f[F_ALPHA]
			if f[F_PLY] == 0 and exact_root_scores:
				a = -INF
				b = INF
			_stack.append(_frame(f[F_DEPTH] - 1, a, b, f[F_PLY] + 1))
			continue
		var value := _exit(f)
		_stack.pop_back()
		if _stack.is_empty():
			_iteration_done(f)
		else:
			_child_returned(value)
	return true


## Blocking convenience for tests and tools.
func run(state: HuntState) -> PackedInt32Array:
	begin(state)
	while not step(50000):
		pass
	return best_move


func cancel() -> void:
	_finish()


func is_decisive(score: int) -> bool:
	return absi(score) >= WIN_THRESHOLD


## Plies to the end of the game for a decisive score (from the root).
func plies_to_end(score: int) -> int:
	return WIN - absi(score)


func elapsed_ms() -> int:
	return Time.get_ticks_msec() - _start_ms


# --- Internals -------------------------------------------------------------

func _frame(depth: int, alpha: int, beta: int, ply: int) -> Array:
	return [null, 0, alpha, beta, -INF, -1, depth, ply, alpha, 0, false]


func _push_root() -> void:
	_iter_scores = PackedInt64Array()
	_iter_scores.resize(root_moves.size())
	_iter_scores.fill(-INF)
	var f := _frame(_depth, -INF, INF, 0)
	f[F_MOVES] = root_moves
	f[F_KEY] = _state.hash_key
	_stack.append(f)


func _enter(f: Array) -> Variant:
	var moves: Array[PackedInt32Array] = []
	var st := _state.analyze(moves)
	var ply: int = f[F_PLY]
	if st != HuntState.Status.ONGOING:
		return _terminal_score(st, ply)
	var depth: int = f[F_DEPTH]
	if depth <= 0:
		var stand := evaluator.evaluate(_state)
		if _state.side != HuntState.HUNTER or -depth >= 4:
			return stand
		var caps: Array[PackedInt32Array] = []
		for m in moves:
			if m[0] == HuntState.Kind.JUMP:
				caps.append(m)
		if caps.is_empty() or stand >= f[F_BETA]:
			return stand
		if stand > f[F_ALPHA]:
			f[F_ALPHA] = stand
		f[F_BEST] = stand
		_order(caps, null)
		f[F_MOVES] = caps
		f[F_QNODE] = true
		return null
	var key := _state.hash_key
	f[F_KEY] = key
	var tt_move: Variant = null
	var e: Variant = _tt.get(key)
	if e != null:
		var e_score := _from_tt(e[2], ply)
		if e[0] >= depth:
			var alpha: int = f[F_ALPHA]
			var beta: int = f[F_BETA]
			match e[1]:
				TT_EXACT:
					return e_score
				TT_LOWER:
					alpha = maxi(alpha, e_score)
				TT_UPPER:
					beta = mini(beta, e_score)
			if alpha >= beta:
				return e_score
			f[F_ALPHA] = alpha
			f[F_BETA] = beta
		tt_move = e[3]
	_order(moves, tt_move)
	f[F_MOVES] = moves
	return null


func _exit(f: Array) -> int:
	var best: int = f[F_BEST]
	if not f[F_QNODE] and f[F_PLY] > 0:
		var flag := TT_EXACT
		if best <= f[F_ALPHA0]:
			flag = TT_UPPER
		elif best >= f[F_BETA]:
			flag = TT_LOWER
		var best_i: int = f[F_BEST_I]
		var mv: Variant = f[F_MOVES][best_i] if best_i >= 0 else null
		_tt[f[F_KEY]] = [f[F_DEPTH], flag, _to_tt(best, f[F_PLY]), mv]
	return best


func _child_returned(value: int) -> void:
	var f: Array = _stack[_stack.size() - 1]
	var i: int = f[F_I]
	_state.unmake(f[F_MOVES][i])
	var score := -value
	if f[F_PLY] == 0:
		_iter_scores[i] = score
	if score > f[F_BEST]:
		f[F_BEST] = score
		f[F_BEST_I] = i
	if score > f[F_ALPHA]:
		f[F_ALPHA] = score
	f[F_I] = i + 1


func _iteration_done(root: Array) -> void:
	completed_depth = _depth
	root_scores = _iter_scores.duplicate()
	best_score = root[F_BEST]
	best_move = root_moves[root[F_BEST_I]]
	if _depth >= max_depth or (stop_on_decisive and is_decisive(best_score) and not exact_root_scores):
		_finish()
		return
	# Next iteration: best-scoring root moves first.
	var order: Array = range(root_moves.size())
	order.sort_custom(func(a: int, b: int) -> bool: return root_scores[a] > root_scores[b])
	var moves: Array[PackedInt32Array] = []
	var scores := PackedInt64Array()
	for i in order:
		moves.append(root_moves[i])
		scores.append(root_scores[i])
	root_moves = moves
	root_scores = scores
	_depth += 1
	_push_root()


## Shuffles the captures among themselves and the other moves among
## themselves (captures stay in front: they're searched first).
func _shuffle_root(moves: Array[PackedInt32Array]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = vary_seed
	var caps := 0
	while caps < moves.size() and moves[caps][0] == HuntState.Kind.JUMP:
		caps += 1
	for part in [[0, caps], [caps, moves.size()]]:
		var a: int = part[0]
		var b: int = part[1]
		for i in range(b - 1, a, -1):
			var j := rng.randi_range(a, i)
			var t := moves[i]
			moves[i] = moves[j]
			moves[j] = t


func _finish() -> void:
	done = true
	_stack.clear()


func _out_of_limits() -> bool:
	if max_nodes > 0 and nodes >= max_nodes and completed_depth > 0:
		return true
	if time_limit_ms > 0 and (nodes & 255) == 0 and completed_depth > 0:
		return Time.get_ticks_msec() - _start_ms >= time_limit_ms
	return false


func _terminal_score(st: HuntState.Status, ply: int) -> int:
	if st == HuntState.Status.DRAW:
		return 0
	var hunter_won := st == HuntState.Status.HUNTER_WIN
	var mover_is_hunter := _state.side == HuntState.HUNTER
	return (WIN - ply) if hunter_won == mover_is_hunter else -(WIN - ply)


func _order(moves: Array[PackedInt32Array], first: Variant) -> void:
	# Captures first (bigger chains first), then everything else in
	# generation order. The TT move, if any, goes to the front.
	var caps: Array[PackedInt32Array] = []
	var rest: Array[PackedInt32Array] = []
	for m in moves:
		if m[0] == HuntState.Kind.JUMP:
			caps.append(m)
		else:
			rest.append(m)
	if caps.size() > 1:
		caps.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a.size() > b.size())
	moves.clear()
	moves.append_array(caps)
	moves.append_array(rest)
	if first != null:
		var idx := moves.find(first)
		if idx > 0:
			moves.remove_at(idx)
			moves.insert(0, first)


static func _to_tt(score: int, ply: int) -> int:
	if score >= WIN_THRESHOLD:
		return score + ply
	if score <= -WIN_THRESHOLD:
		return score - ply
	return score


static func _from_tt(score: int, ply: int) -> int:
	if score >= WIN_THRESHOLD:
		return score - ply
	if score <= -WIN_THRESHOLD:
		return score + ply
	return score
