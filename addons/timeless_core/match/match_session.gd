class_name MatchSession
extends RefCounted
## One game in progress (framework §5): the rule set, the position, the moves
## played and who controls each side. Every mode goes through it: against the
## AI, pass and play, nearby (Wi-Fi) and online. The presentation listens to
## its signals and never changes the state itself.
##
## Moves are validated here, whoever makes them, so a remote player can't
## play an illegal move or move out of turn.

signal move_committed(move: PackedInt32Array, side: int)
signal undone(count: int)
## The position or move list was replaced wholesale (a resync, a new start):
## redraw from the state instead of animating.
signal reset
signal game_over(status: int, reason: int)

enum Kind { VS_AI, PASS_AND_PLAY, NEARBY, ONLINE_FRIEND, QUICK_MATCH, AI_VS_AI }
## Who moves a side.
enum Driver { LOCAL, AI, REMOTE }
## Endings that don't come from the position.
enum Ending { NONE, RESIGNED, DRAW_AGREED, FORFEIT_TIMEOUT, FORFEIT_DISCONNECT, FORFEIT_ILLEGAL }

const SAVE_VERSION := 1

var kind: Kind = Kind.PASS_AND_PLAY
var rules: HuntRuleSet
## Identifies the rule set across saves and the network (the title resolves it).
var rule_set_id := ""
var state: HuntState
var start: HuntState
var moves: Array[PackedInt32Array] = []
## Control per side: control[HuntState.HUNTER], control[HuntState.PREY].
var control := {HuntState.HUNTER: Driver.LOCAL, HuntState.PREY: Driver.LOCAL}
## AI level per AI-controlled side (an index into the title's personas).
var ai_level := {HuntState.HUNTER: 1, HuntState.PREY: 1}
var rng_seed := 0
var match_id := ""
## Set when a game ends off the board: resignation, agreed draw, forfeit.
var ending: Ending = Ending.NONE
## The side that resigned or forfeited (or -1).
var ending_side := -1
var _over_emitted := false


static func create(rule_set: HuntRuleSet, id: String, match_kind: Kind, hunter: Driver, prey: Driver) -> MatchSession:
	var m := MatchSession.new()
	m.rules = rule_set
	m.rule_set_id = id
	m.kind = match_kind
	m.control = {HuntState.HUNTER: hunter, HuntState.PREY: prey}
	m.state = HuntState.create(rule_set)
	m.start = m.state.clone()
	m.rng_seed = randi()
	m.match_id = "%08x%08x" % [randi(), randi()]
	return m


## Starts from a set position instead of the opening (walkthroughs, puzzles).
func start_from(position: HuntState) -> void:
	state = position.clone()
	start = position.clone()
	moves.clear()
	ending = Ending.NONE
	ending_side = -1
	_over_emitted = false
	reset.emit()


## Replaces the moves with `list`, played from `from` (a resync from the other
## device). Checks every move first; returns false and changes nothing if one
## is illegal. Emits `reset` once instead of a move_committed per move.
func replay(from: HuntState, list: Array) -> bool:
	var probe := from.clone()
	for m in list:
		if typeof(m) != TYPE_PACKED_INT32_ARRAY or not probe.is_legal(m):
			return false
		probe.make(m)
	start = from.clone()
	state = probe
	moves.clear()
	for m in list:
		moves.append(PackedInt32Array(m))
	ending = Ending.NONE
	ending_side = -1
	_over_emitted = false
	reset.emit()
	_check_over()
	return true


func side_to_move() -> int:
	return state.side


func is_local_turn() -> bool:
	return is_ongoing() and control[state.side] == Driver.LOCAL


func is_remote(side: int) -> bool:
	return control[side] == Driver.REMOTE


func is_ongoing() -> bool:
	return status() == HuntState.Status.ONGOING


## The result, taking resignations, agreed draws and forfeits into account.
func status() -> int:
	match ending:
		Ending.NONE:
			return state.status()
		Ending.DRAW_AGREED:
			return HuntState.Status.DRAW
		_:
			return HuntState.Status.PREY_WIN if ending_side == HuntState.HUNTER else HuntState.Status.HUNTER_WIN


## Plays a move for `side`. Returns false (and changes nothing) if it isn't
## that side's turn, the game is over, or the move is illegal.
func commit(move: PackedInt32Array, side: int) -> bool:
	if not is_ongoing() or side != state.side or not state.is_legal(move):
		return false
	moves.append(move)
	state.make(move)
	move_committed.emit(move, side)
	_check_over()
	return true


## Takes back `count` moves (local games only; the caller decides how many).
func undo(count := 1) -> int:
	var n := 0
	while n < count and not moves.is_empty():
		state.unmake(moves.pop_back())
		n += 1
	if n > 0:
		ending = Ending.NONE
		ending_side = -1
		_over_emitted = false
		undone.emit(n)
	return n


## How many moves an undo button should take back: to the last time a local
## player was to move (two against the AI, one in pass and play).
func undo_count() -> int:
	if moves.is_empty() or kind in [Kind.NEARBY, Kind.ONLINE_FRIEND, Kind.QUICK_MATCH]:
		return 0
	var probe := state.clone()
	var n := 0
	for i in range(moves.size() - 1, -1, -1):
		probe.unmake(moves[i])
		n += 1
		if control[probe.side] == Driver.LOCAL:
			return n
	return 0


func resign(side: int) -> void:
	_end_off_board(Ending.RESIGNED, side)


func agree_draw() -> void:
	_end_off_board(Ending.DRAW_AGREED, -1)


func forfeit(side: int, why: Ending) -> void:
	_end_off_board(why, side)


func _end_off_board(why: Ending, side: int) -> void:
	if not is_ongoing():
		return
	ending = why
	ending_side = side
	_check_over()


func _check_over() -> void:
	if _over_emitted:
		return
	var st := status()
	if st != HuntState.Status.ONGOING:
		_over_emitted = true
		game_over.emit(st, state.last_reason)


## The 64-bit position hash, sent with every network move.
func position_hash() -> int:
	return state.hash_key


# --- Saves -------------------------------------------------------------------

## A small, version-tolerant save: the setup plus the moves (framework §5).
func to_dict() -> Dictionary:
	var mv: Array = []
	for m in moves:
		mv.append(Array(m))
	return {
		"version": SAVE_VERSION,
		"kind": kind,
		"rule_set_id": rule_set_id,
		"fingerprint": rules.fingerprint(),
		"control": {"hunter": control[HuntState.HUNTER], "prey": control[HuntState.PREY]},
		"ai_level": {"hunter": ai_level[HuntState.HUNTER], "prey": ai_level[HuntState.PREY]},
		"seed": rng_seed,
		"match_id": match_id,
		"moves": mv,
		"ending": ending,
		"ending_side": ending_side,
	}


## Rebuilds a match from a save by replaying its moves. `resolve` turns a rule
## set id into a HuntRuleSet. Returns null if the save doesn't fit.
static func from_dict(d: Dictionary, resolve: Callable) -> MatchSession:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return null
	var rule_set: HuntRuleSet = resolve.call(str(d.get("rule_set_id", "")))
	if rule_set == null or rule_set.fingerprint() != int(d.get("fingerprint", 0)):
		return null
	var c: Dictionary = d.get("control", {})
	var m := MatchSession.create(rule_set, str(d.rule_set_id), int(d.get("kind", Kind.PASS_AND_PLAY)),
		int(c.get("hunter", Driver.LOCAL)), int(c.get("prey", Driver.LOCAL)))
	var lv: Dictionary = d.get("ai_level", {})
	m.ai_level = {HuntState.HUNTER: int(lv.get("hunter", 1)), HuntState.PREY: int(lv.get("prey", 1))}
	m.rng_seed = int(d.get("seed", 0))
	m.match_id = str(d.get("match_id", m.match_id))
	for raw in d.get("moves", []):
		var move := PackedInt32Array(raw)
		if not m.state.is_legal(move):
			return null
		m.moves.append(move)
		m.state.make(move)
	m.ending = int(d.get("ending", Ending.NONE))
	m.ending_side = int(d.get("ending_side", -1))
	m._over_emitted = m.status() != HuntState.Status.ONGOING
	return m
