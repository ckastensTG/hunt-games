class_name HuntState
extends RefCounted
## Deterministic state of a hunt game: hunters vs prey on a BoardDef.
##
## Moves are PackedInt32Arrays:
##   PLACE: [PLACE, to]
##   STEP:  [STEP, from, to]
##   JUMP:  [JUMP, from, over1, land1, over2, land2, ...]
## In a capture chain the captured prey stay on the board until the end of the
## turn (draughts convention), so a prey can't be jumped twice and the hunter
## can't land where a prey was taken earlier in the same chain.
##
## No scene-tree access: safe to clone and search on a worker thread.

const EMPTY := 0
const HUNTER := 1
const PREY := 2

enum Kind { PLACE = 0, STEP = 1, JUMP = 2 }
enum Status { ONGOING, HUNTER_WIN, PREY_WIN, DRAW }
enum Reason { NONE, CAPTURE_TARGET, HUNTER_TRAPPED, PREY_STUCK, REPETITION_BLOCKED, THREEFOLD, NO_CAPTURE_LIMIT }

var rules: HuntRuleSet
var board: BoardDef
var cells := PackedByteArray()
var hunters := PackedInt32Array()
var reserve: int = 0
var captured: int = 0
var side: int = HUNTER
var ply: int = 0
## Plies since the last capture, counted only once no prey remain in reserve.
var quiet_plies: int = 0
var hash_key: int = 0
## Reason for the last non-ONGOING result from status() / analyze().
var last_reason: Reason = Reason.NONE

var _z: ZobristTable
var _rep := {}  # position hash -> occurrences on the current game path
var _undo: Array[PackedInt64Array] = []


static func create(rule_set: HuntRuleSet) -> HuntState:
	var s := HuntState.new()
	s.rules = rule_set
	s.reset()
	return s


func reset() -> void:
	board = rules.board
	if not board.is_built():
		board.build()
	var n := board.point_count()
	cells.resize(n)
	cells.fill(EMPTY)
	hunters = rules.hunter_start.duplicate()
	for h in hunters:
		cells[h] = HUNTER
	for p in rules.prey_start:
		assert(cells[p] == EMPTY, "HuntRuleSet %s: overlapping start points" % rules.id)
		cells[p] = PREY
	reserve = rules.prey_reserve
	captured = 0
	side = rules.first_player
	ply = 0
	quiet_plies = 0
	last_reason = Reason.NONE
	_z = ZobristTable.for_shape(n, rules.prey_total())
	hash_key = compute_hash()
	_rep = {hash_key: 1}
	_undo.clear()


func clone() -> HuntState:
	var s := HuntState.new()
	s.rules = rules
	s.board = board
	s.cells = cells.duplicate()
	s.hunters = hunters.duplicate()
	s.reserve = reserve
	s.captured = captured
	s.side = side
	s.ply = ply
	s.quiet_plies = quiet_plies
	s.hash_key = hash_key
	s.last_reason = last_reason
	s._z = _z
	s._rep = _rep.duplicate()
	s._undo = _undo.duplicate()
	return s


func compute_hash() -> int:
	var h := 0
	for i in cells.size():
		if cells[i] != EMPTY:
			h ^= _z.piece[i * 2 + cells[i] - 1]
	if side == PREY:
		h ^= _z.side_prey
	h ^= _z.reserve[reserve]
	h ^= _z.captured[captured]
	return h


func occurrences(position_hash: int) -> int:
	return _rep.get(position_hash, 0)


func in_placement() -> bool:
	return reserve > 0


# --- Move generation -------------------------------------------------------

## Moves allowed by piece movement alone, before the repetition rule.
func pseudo_moves(dedupe_chains := true) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	if side == PREY:
		_prey_moves(out)
	else:
		_hunter_moves(out, dedupe_chains)
	return out


## Legal moves: pseudo moves minus those the repetition rule forbids.
func legal_moves(dedupe_chains := true) -> Array[PackedInt32Array]:
	var moves := pseudo_moves(dedupe_chains)
	if rules.repetition == HuntRuleSet.Repetition.FORBID:
		moves = _without_repeats(moves)
	return moves


func is_legal(move: PackedInt32Array) -> bool:
	for m in legal_moves(false):
		if m == move:
			return true
	return false


func _prey_moves(out: Array[PackedInt32Array]) -> void:
	if reserve > 0:
		for i in cells.size():
			if cells[i] == EMPTY:
				out.append(PackedInt32Array([Kind.PLACE, i]))
		return
	var forward_only := rules.prey_forward_only
	for i in cells.size():
		if cells[i] != PREY:
			continue
		for j in board.adj[i]:
			if cells[j] != EMPTY:
				continue
			if forward_only and board.ranks[j] <= board.ranks[i]:
				continue
			out.append(PackedInt32Array([Kind.STEP, i, j]))


func _hunter_moves(out: Array[PackedInt32Array], dedupe_chains: bool) -> void:
	var jumps: Array[PackedInt32Array] = []
	var steps: Array[PackedInt32Array] = []
	for h in hunters:
		for j in board.adj[h]:
			if cells[j] == EMPTY:
				steps.append(PackedInt32Array([Kind.STEP, h, j]))
		if rules.multi_jump:
			cells[h] = EMPTY  # the hunter has left its start point during a chain
			var seen := {}
			_chain(h, h, PackedInt32Array([Kind.JUMP, h]), 0, jumps, seen, dedupe_chains)
			cells[h] = HUNTER
		else:
			var overs := board.jump_over[h]
			var lands := board.jump_land[h]
			for k in overs.size():
				if cells[overs[k]] == PREY and cells[lands[k]] == EMPTY:
					jumps.append(PackedInt32Array([Kind.JUMP, h, overs[k], lands[k]]))
	if rules.forced_capture and not jumps.is_empty():
		out.append_array(jumps)
		return
	out.append_array(jumps)
	out.append_array(steps)


func _chain(origin: int, at: int, path: PackedInt32Array, taken: int,
		out: Array[PackedInt32Array], seen: Dictionary, dedupe: bool) -> void:
	var overs := board.jump_over[at]
	var lands := board.jump_land[at]
	for k in overs.size():
		var o := overs[k]
		var l := lands[k]
		if cells[o] != PREY or (taken >> o) & 1 or cells[l] != EMPTY:
			continue
		var now_taken := taken | (1 << o)
		if dedupe:
			# One 64-bit key: Vector2i is 32-bit and would truncate the mask on
			# boards with more than 31 points (Komikan has 38).
			var key := (now_taken << 6) | l
			if seen.has(key):
				continue
			seen[key] = true
		var next := path.duplicate()
		next.append(o)
		next.append(l)
		out.append(next)
		_chain(origin, l, next, now_taken, out, seen, dedupe)


func _without_repeats(moves: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var kept: Array[PackedInt32Array] = []
	for m in moves:
		# Only steps can recreate a position: placements and captures change
		# the reserve or captured count, which are part of the hash.
		if m[0] == Kind.STEP and _rep.has(_step_hash(m[1], m[2])):
			continue
		kept.append(m)
	return kept


func _step_hash(from: int, to: int) -> int:
	var pc := cells[from]
	return hash_key ^ _z.piece[from * 2 + pc - 1] ^ _z.piece[to * 2 + pc - 1] ^ _z.side_prey


# --- Status ----------------------------------------------------------------

## Result of the current position. Fills `out_moves` with the legal moves
## when the game is still on, so callers don't generate them twice.
func analyze(out_moves: Array[PackedInt32Array], dedupe_chains := true) -> Status:
	out_moves.clear()
	last_reason = Reason.NONE
	if captured >= rules.capture_target:
		last_reason = Reason.CAPTURE_TARGET
		return Status.HUNTER_WIN
	var raw := pseudo_moves(dedupe_chains)
	if raw.is_empty():
		if side == HUNTER:
			last_reason = Reason.HUNTER_TRAPPED
			return Status.PREY_WIN
		last_reason = Reason.PREY_STUCK
		if rules.prey_stuck_result == HuntRuleSet.StuckResult.HUNTER_WIN:
			return Status.HUNTER_WIN
		return Status.DRAW
	var moves := raw
	if rules.repetition == HuntRuleSet.Repetition.FORBID:
		moves = _without_repeats(raw)
		if moves.is_empty():
			last_reason = Reason.REPETITION_BLOCKED
			return Status.DRAW
	if rules.repetition == HuntRuleSet.Repetition.THREEFOLD_DRAW and occurrences(hash_key) >= 3:
		last_reason = Reason.THREEFOLD
		return Status.DRAW
	if rules.no_capture_limit_plies > 0 and quiet_plies >= rules.no_capture_limit_plies:
		last_reason = Reason.NO_CAPTURE_LIMIT
		return Status.DRAW
	out_moves.append_array(moves)
	return Status.ONGOING


func status() -> Status:
	var scratch: Array[PackedInt32Array] = []
	return analyze(scratch)


# --- Make / unmake ---------------------------------------------------------

func make(move: PackedInt32Array) -> void:
	_undo.append(PackedInt64Array([quiet_plies, hash_key]))
	match move[0]:
		Kind.PLACE:
			var t := move[1]
			cells[t] = PREY
			hash_key ^= _z.piece[t * 2 + 1]
			hash_key ^= _z.reserve[reserve]
			reserve -= 1
			hash_key ^= _z.reserve[reserve]
		Kind.STEP:
			var f := move[1]
			var t := move[2]
			var pc := cells[f]
			cells[f] = EMPTY
			cells[t] = pc
			hash_key ^= _z.piece[f * 2 + pc - 1] ^ _z.piece[t * 2 + pc - 1]
			if pc == HUNTER:
				_move_hunter(f, t)
			if reserve == 0:
				quiet_plies += 1
		Kind.JUMP:
			var f := move[1]
			var last := move[move.size() - 1]
			cells[f] = EMPTY
			hash_key ^= _z.piece[f * 2]
			var n := 0
			for k in range(2, move.size(), 2):
				var o := move[k]
				cells[o] = EMPTY
				hash_key ^= _z.piece[o * 2 + 1]
				n += 1
			cells[last] = HUNTER
			hash_key ^= _z.piece[last * 2]
			_move_hunter(f, last)
			hash_key ^= _z.captured[captured]
			captured += n
			hash_key ^= _z.captured[captured]
			quiet_plies = 0
	side = PREY if side == HUNTER else HUNTER
	hash_key ^= _z.side_prey
	ply += 1
	_rep[hash_key] = _rep.get(hash_key, 0) + 1


func unmake(move: PackedInt32Array) -> void:
	var c: int = _rep[hash_key] - 1
	if c == 0:
		_rep.erase(hash_key)
	else:
		_rep[hash_key] = c
	side = PREY if side == HUNTER else HUNTER
	ply -= 1
	match move[0]:
		Kind.PLACE:
			cells[move[1]] = EMPTY
			reserve += 1
		Kind.STEP:
			var f := move[1]
			var t := move[2]
			var pc := cells[t]
			cells[t] = EMPTY
			cells[f] = pc
			if pc == HUNTER:
				_move_hunter(t, f)
		Kind.JUMP:
			var f := move[1]
			var last := move[move.size() - 1]
			cells[last] = EMPTY
			var n := 0
			for k in range(2, move.size(), 2):
				cells[move[k]] = PREY
				n += 1
			cells[f] = HUNTER
			_move_hunter(last, f)
			captured -= n
	var u: PackedInt64Array = _undo.pop_back()
	quiet_plies = u[0]
	hash_key = u[1]


## Make a move for real (match play). Same as make(); kept separate so the
## match layer reads clearly.
func apply(move: PackedInt32Array) -> void:
	make(move)


func _move_hunter(from: int, to: int) -> void:
	for i in hunters.size():
		if hunters[i] == from:
			hunters[i] = to
			return
	assert(false, "no hunter at %d" % from)


# --- Helpers ---------------------------------------------------------------

static func captures_in(move: PackedInt32Array) -> int:
	return (move.size() - 2) / 2 if move[0] == Kind.JUMP else 0


static func destination(move: PackedInt32Array) -> int:
	return move[move.size() - 1]


func describe(move: PackedInt32Array) -> String:
	match move[0]:
		Kind.PLACE:
			return "place %s" % point_name(move[1])
		Kind.STEP:
			return "%s-%s" % [point_name(move[1]), point_name(move[2])]
		_:
			var s := point_name(move[1])
			for k in range(3, move.size(), 2):
				s += "x" + point_name(move[k])
			return s


func point_name(p: int) -> String:
	var pos := board.positions[p]
	if is_equal_approx(pos.x, roundf(pos.x)) and is_equal_approx(pos.y, roundf(pos.y)):
		return "%s%d" % [char(97 + int(pos.x)), int(pos.y) + 1]
	return "p%d" % p
