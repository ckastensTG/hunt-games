class_name NetMatch
extends RefCounted
## Plays a MatchSession between two devices over a NetTransport (framework
## §9): handshake, moves in lockstep with a position hash, resync, undo and
## draw requests, resignation, rematch, keepalive and reconnect, and the
## quick-match turn timer. The host is authoritative for the setup and, when
## the two sides disagree, for the move list.
##
## Call poll() every frame. Local moves go into `match` as usual
## (session.commit); this class sends them on by listening to the match.

signal started(session: MatchSession, local_side: int)
signal opponent_moved(move: PackedInt32Array)
signal resynced
signal connection_lost
signal reconnected
## The opponent left: on purpose (BYE) or after the reconnect window.
signal opponent_left
signal draw_offered
signal draw_declined
signal undo_requested
signal undo_answered(ok: bool)
signal rematch_requested
signal rematch_declined
signal emote_received(id: int)
## The handshake failed: "version" (different game versions), "title",
## "rules" (unknown or different rule set).
signal failed(reason: String)
## The local player's clock ran out. The game plays a move for them.
signal turn_timed_out

enum Phase { HANDSHAKE, PLAYING, RECONNECTING, CLOSED }

const PING_MS := 2000
const SILENCE_MS := 10000
const RECONNECT_TRY_MS := 3000
const RECONNECT_WINDOW_MS := 60000
const TIMEOUTS_TO_FORFEIT := 3
const BAD_MOVES_TO_FORFEIT := 3

var transport: NetTransport
var phase := Phase.HANDSHAKE
var session: MatchSession
var local_side := -1
var local_name := {}
var opponent_name := {}
var title := ""
var build := ""
## Seconds per move (quick match); 0 means no clock.
var turn_seconds := 0
var timeouts := 0
## rule_set_id -> HuntRuleSet (the title knows its rule sets).
var resolve: Callable

var _is_host := false
var _rule_set_id := ""
var _host_side := HuntState.HUNTER
var _kind := MatchSession.Kind.NEARBY
var _now := 0
var _last_heard := 0
var _last_ping := 0
var _lost_at := 0
var _last_try := 0
var _turn_started := 0
var _bad_moves := 0
var _draw_pending := false
var _undo_pending := false
var _rematch_pending := false
var _left := false


## The side that created the game: picks the rules and its own side.
static func as_host(link: NetTransport, rule_set_id: String, host_side: int, kind: MatchSession.Kind,
		turn_s: int, title_id: String, build_id: String, name: Dictionary, resolver: Callable) -> NetMatch:
	var n := NetMatch.new()
	n._is_host = true
	n._rule_set_id = rule_set_id
	n._host_side = host_side
	n._kind = kind
	n.turn_seconds = turn_s
	n._setup(link, title_id, build_id, name, resolver)
	return n


static func as_guest(link: NetTransport, title_id: String, build_id: String, name: Dictionary,
		resolver: Callable) -> NetMatch:
	var n := NetMatch.new()
	n._setup(link, title_id, build_id, name, resolver)
	return n


func _setup(link: NetTransport, title_id: String, build_id: String, name: Dictionary, resolver: Callable) -> void:
	transport = link
	title = title_id
	build = build_id
	local_name = name
	resolve = resolver
	transport.connected.connect(_on_connected)
	transport.disconnected.connect(_on_disconnected)
	transport.packet.connect(_on_packet)
	_now = Time.get_ticks_msec()
	_last_heard = _now


func is_host() -> bool:
	return _is_host


func remote_side() -> int:
	return HuntState.PREY if local_side == HuntState.HUNTER else HuntState.HUNTER


## Seconds left on the clock for the side to move, or -1 without a clock.
func seconds_left() -> int:
	if turn_seconds <= 0 or session == null or not session.is_ongoing() or phase != Phase.PLAYING:
		return -1
	return maxi(0, turn_seconds - (_now - _turn_started) / 1000)


func poll(now_ms := -1) -> void:
	_now = Time.get_ticks_msec() if now_ms < 0 else now_ms
	if transport != null:
		transport.poll()
	match phase:
		Phase.PLAYING:
			if _now - _last_ping >= PING_MS:
				_last_ping = _now
				_send(NetProtocol.Msg.PING, {"t": _now})
			if _now - _last_heard > SILENCE_MS:
				_lose_connection()
			_tick_clock()
		Phase.RECONNECTING:
			if transport.can_reconnect() and _now - _last_try >= RECONNECT_TRY_MS:
				_last_try = _now
				transport.reconnect()
			if _now - _lost_at > RECONNECT_WINDOW_MS:
				_give_up_on_opponent()


# --- Actions from the local player ------------------------------------------

func offer_draw() -> void:
	_send(NetProtocol.Msg.DRAW_OFFER)


func answer_draw(ok: bool) -> void:
	if not _draw_pending:
		return
	_draw_pending = false
	_send(NetProtocol.Msg.DRAW_RESP, {"ok": ok})
	if ok:
		session.agree_draw()


func request_undo() -> void:
	_send(NetProtocol.Msg.UNDO_REQ)


func answer_undo(ok: bool) -> void:
	if not _undo_pending:
		return
	_undo_pending = false
	_send(NetProtocol.Msg.UNDO_RESP, {"ok": ok})
	if ok:
		_undo_for(remote_side())


func resign() -> void:
	if session != null and session.is_ongoing():
		session.resign(local_side)
		_send(NetProtocol.Msg.RESIGN, {"reason": MatchSession.Ending.RESIGNED})


func request_rematch() -> void:
	_send(NetProtocol.Msg.REMATCH_REQ)


func answer_rematch(ok: bool) -> void:
	if not _rematch_pending:
		return
	_rematch_pending = false
	_send(NetProtocol.Msg.REMATCH_RESP, {"ok": ok})
	if ok and _is_host:
		_start_rematch()


func send_emote(id: int) -> void:
	_send(NetProtocol.Msg.EMOTE, {"id": id})


## Leave on purpose: the opponent is told at once.
func leave() -> void:
	if phase == Phase.CLOSED:
		return
	_send(NetProtocol.Msg.BYE)
	_close()


# --- Transport events --------------------------------------------------------

func _on_connected() -> void:
	_last_heard = _now
	var have := session.moves.size() if session != null else 0
	_send(NetProtocol.Msg.HELLO, {"proto": NetProtocol.VERSION, "build": build, "title": title,
		"name": local_name, "match_id": session.match_id if session != null else "", "have": have})


func _on_disconnected() -> void:
	if phase == Phase.PLAYING:
		_lose_connection()
	elif phase == Phase.HANDSHAKE and not _is_host:
		_close()
		failed.emit("connection")


func _on_packet(bytes: PackedByteArray) -> void:
	var msg := NetProtocol.decode(bytes)
	if msg.is_empty():
		return
	_last_heard = _now
	match int(msg.t):
		NetProtocol.Msg.HELLO:
			_on_hello(msg)
		NetProtocol.Msg.SETUP:
			_on_setup(msg)
		NetProtocol.Msg.READY:
			if _is_host and phase == Phase.HANDSHAKE and session != null:
				_begin_play()
		NetProtocol.Msg.MOVE:
			_on_move(msg)
		NetProtocol.Msg.RESYNC_REQ:
			if _is_host and session != null:
				_send(NetProtocol.Msg.RESYNC, {"moves": NetProtocol.moves_to_wire(session.moves)})
		NetProtocol.Msg.RESYNC:
			if not _is_host and session != null:
				_apply_moves(msg.moves)
				if phase == Phase.RECONNECTING:
					phase = Phase.PLAYING
					reconnected.emit()
				resynced.emit()
		NetProtocol.Msg.UNDO_REQ:
			if session != null and session.is_ongoing() and not session.moves.is_empty():
				_undo_pending = true
				undo_requested.emit()
		NetProtocol.Msg.UNDO_RESP:
			if msg.ok:
				_undo_for(local_side)
			undo_answered.emit(msg.ok)
		NetProtocol.Msg.DRAW_OFFER:
			if session != null and session.is_ongoing():
				_draw_pending = true
				draw_offered.emit()
		NetProtocol.Msg.DRAW_RESP:
			if msg.ok and session != null:
				session.agree_draw()
			elif not msg.ok:
				draw_declined.emit()
		NetProtocol.Msg.RESIGN:
			if session != null and session.is_ongoing():
				var why: int = msg.reason
				if why != MatchSession.Ending.FORFEIT_TIMEOUT:
					why = MatchSession.Ending.RESIGNED
				session.forfeit(remote_side(), why)
		NetProtocol.Msg.PING:
			_send(NetProtocol.Msg.PONG, {"t": msg.t})
		NetProtocol.Msg.REMATCH_REQ:
			_rematch_pending = true
			rematch_requested.emit()
		NetProtocol.Msg.REMATCH_RESP:
			if msg.ok and _is_host:
				_start_rematch()
			elif not msg.ok:
				rematch_declined.emit()
		NetProtocol.Msg.EMOTE:
			emote_received.emit(msg.id)
		NetProtocol.Msg.BYE:
			_left = true
			_give_up_on_opponent()


func _on_hello(msg: Dictionary) -> void:
	opponent_name = msg.name
	if msg.proto != NetProtocol.VERSION:
		_fail("version")
		return
	if msg.title != title:
		_fail("title")
		return
	if not _is_host:
		return  # the host answers with SETUP or RESYNC
	if session != null and msg.match_id == session.match_id:
		# The guest is back after a dropped connection.
		_send(NetProtocol.Msg.RESYNC, {"moves": NetProtocol.moves_to_wire(session.moves)})
		if phase == Phase.RECONNECTING:
			phase = Phase.PLAYING
			_turn_started = _now
			reconnected.emit()
		return
	_create_host_match()
	_send_setup()


func _on_setup(msg: Dictionary) -> void:
	if _is_host:
		return
	var rule_set: HuntRuleSet = resolve.call(msg.rule_set)
	if rule_set == null or rule_set.fingerprint() != msg.fingerprint:
		_fail("rules")
		return
	local_side = HuntState.PREY if msg.host_side == HuntState.HUNTER else HuntState.HUNTER
	var hunter := MatchSession.Driver.LOCAL if local_side == HuntState.HUNTER else MatchSession.Driver.REMOTE
	var prey := MatchSession.Driver.LOCAL if local_side == HuntState.PREY else MatchSession.Driver.REMOTE
	_bind(MatchSession.create(rule_set, msg.rule_set, msg.kind, hunter, prey))
	session.rng_seed = msg.seed
	session.match_id = msg.match_id
	turn_seconds = msg.turn_s
	_apply_moves(msg.moves)
	_send(NetProtocol.Msg.READY)
	_begin_play()


func _on_move(msg: Dictionary) -> void:
	if phase != Phase.PLAYING or session == null:
		return
	var expected := session.moves.size()
	if msg.seq < expected:
		return  # already have it
	if msg.seq > expected or session.side_to_move() != remote_side():
		_ask_for_moves()
		return
	if not session.commit(msg.move, remote_side()):
		_bad_moves += 1
		if _is_host and _bad_moves >= BAD_MOVES_TO_FORFEIT:
			session.forfeit(remote_side(), MatchSession.Ending.FORFEIT_ILLEGAL)
		_ask_for_moves()
		return
	opponent_moved.emit(msg.move)
	if session.position_hash() != msg.hash:
		_ask_for_moves()


# --- Internals ------------------------------------------------------------------

func _create_host_match() -> void:
	var rule_set: HuntRuleSet = resolve.call(_rule_set_id)
	local_side = _host_side
	var hunter := MatchSession.Driver.LOCAL if local_side == HuntState.HUNTER else MatchSession.Driver.REMOTE
	var prey := MatchSession.Driver.LOCAL if local_side == HuntState.PREY else MatchSession.Driver.REMOTE
	_bind(MatchSession.create(rule_set, _rule_set_id, _kind, hunter, prey))


func _send_setup() -> void:
	_send(NetProtocol.Msg.SETUP, {"rule_set": _rule_set_id, "fingerprint": session.rules.fingerprint(),
		"host_side": _host_side, "seed": session.rng_seed, "match_id": session.match_id, "kind": _kind,
		"turn_s": turn_seconds, "moves": NetProtocol.moves_to_wire(session.moves)})


func _bind(m: MatchSession) -> void:
	session = m
	session.move_committed.connect(_on_match_move)
	timeouts = 0
	_bad_moves = 0
	_draw_pending = false
	_undo_pending = false


func _begin_play() -> void:
	phase = Phase.PLAYING
	_turn_started = _now
	_last_ping = _now
	started.emit(session, local_side)


func _on_match_move(move: PackedInt32Array, side: int) -> void:
	_turn_started = _now
	if side == local_side:
		_send(NetProtocol.Msg.MOVE, {"seq": session.moves.size() - 1, "move": PackedInt32Array(move),
			"hash": session.position_hash()})


func _apply_moves(list: Array) -> void:
	# Replayed quietly: one `reset` for the presentation, nothing re-sent.
	if session.replay(session.start, list):
		_turn_started = _now


func _ask_for_moves() -> void:
	if _is_host:
		_send(NetProtocol.Msg.RESYNC, {"moves": NetProtocol.moves_to_wire(session.moves)})
	else:
		_send(NetProtocol.Msg.RESYNC_REQ)


## Takes back moves until it's `side`'s turn again (one or two moves).
func _undo_for(side: int) -> void:
	if session == null or session.moves.is_empty():
		return
	var probe := session.state.clone()
	var n := 0
	for i in range(session.moves.size() - 1, -1, -1):
		probe.unmake(session.moves[i])
		n += 1
		if probe.side == side:
			break
	session.undo(n)
	_turn_started = _now


func _start_rematch() -> void:
	# Sides swap: the old guest's side becomes the host's.
	_host_side = remote_side()
	_rule_set_id = session.rule_set_id
	if session.move_committed.is_connected(_on_match_move):
		session.move_committed.disconnect(_on_match_move)
	_create_host_match()
	phase = Phase.HANDSHAKE
	_send_setup()


func _tick_clock() -> void:
	if turn_seconds <= 0 or session == null or not session.is_ongoing():
		return
	if session.side_to_move() != local_side:
		return
	if _now - _turn_started < turn_seconds * 1000:
		return
	_turn_started = _now
	timeouts += 1
	if timeouts >= TIMEOUTS_TO_FORFEIT:
		session.forfeit(local_side, MatchSession.Ending.FORFEIT_TIMEOUT)
		_send(NetProtocol.Msg.RESIGN, {"reason": MatchSession.Ending.FORFEIT_TIMEOUT})
	else:
		turn_timed_out.emit()


func _lose_connection() -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.RECONNECTING
	_lost_at = _now
	_last_try = _now
	connection_lost.emit()


func _give_up_on_opponent() -> void:
	if session != null and session.is_ongoing():
		session.forfeit(remote_side(), MatchSession.Ending.FORFEIT_DISCONNECT)
	_close()
	opponent_left.emit()


func _fail(reason: String) -> void:
	_send(NetProtocol.Msg.BYE)
	_close()
	failed.emit(reason)


func _close() -> void:
	phase = Phase.CLOSED
	if transport != null:
		transport.close()


func _send(type: NetProtocol.Msg, fields := {}) -> void:
	if transport != null and transport.is_open():
		transport.send(NetProtocol.encode(NetProtocol.make(type, fields)))
