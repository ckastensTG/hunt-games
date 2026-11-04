extends RefCounted
## TEST BUILDS ONLY. A simulated player for trying the online flows on one
## device: it joins through the simulated online service (FakeOnlineBackend)
## and plays with the Apprentice AI. Its name always reads "Simulated
## opponent (test build)". The play controller creates it only when the
## backend is the simulated one, which release builds never use (bible §5.3:
## never fake opponents).
##
## It declines draws, allows take-backs and accepts rematches, so each of
## those dialogs can be tried.

const NAME := {"key": "sim", "n": 0}
const THINK_MS := 900

var backend := FakeOnlineBackend.new()
var net: NetMatch
var _quick: QuickMatch
var _friend: FriendMatch
var _title := ""
var _build := ""
var _resolve: Callable
var _start_at := -1
var _what := ""
var _code := ""
var _ai := AIDriver.new()
var _move_at := -1
var _rng := RandomNumberGenerator.new()


func _init(title_id: String, build_id: String, resolver: Callable) -> void:
	_title = title_id
	_build = build_id
	_resolve = resolver
	_rng.randomize()


func join_quick(delay_ms: int, now_ms: int) -> void:
	_what = "quick"
	_start_at = now_ms + delay_ms


func join_friend(code: String, delay_ms: int, now_ms: int) -> void:
	_what = "friend"
	_code = code
	_start_at = now_ms + delay_ms


func stop() -> void:
	_ai.cancel()
	_start_at = -1
	if _quick:
		_quick.cancel()
	if _friend:
		_friend.cancel()
	if net:
		net.leave()
	backend.poll()  # run what's queued: queued calls hold the backend


func poll(now_ms: int) -> void:
	if _start_at >= 0 and now_ms >= _start_at:
		_start_at = -1
		if _what == "quick":
			_quick = QuickMatch.new(backend, _title, NetProtocol.VERSION)
			_quick.matched.connect(_on_matched)
			_quick.start(now_ms)
		else:
			_friend = FriendMatch.new(backend, _title, NetProtocol.VERSION)
			_friend.matched.connect(_on_matched)
			_friend.join(_code)
	if _quick:
		_quick.poll(now_ms)
	if _friend:
		_friend.poll()
	if net:
		net.poll(now_ms)
		_play(now_ms)


func _on_matched(link: NetTransport, as_host: bool) -> void:
	if as_host:
		var side := HuntState.HUNTER if _rng.randi() % 2 == 0 else HuntState.PREY
		var rule_set: String = TitleConfig.active().rule_sets[0]
		net = NetMatch.as_host(link, rule_set, side, MatchSession.Kind.QUICK_MATCH, 60, _title, _build, NAME, _resolve)
	else:
		net = NetMatch.as_guest(link, _title, _build, NAME, _resolve)
	# Bound methods, not lambdas: a lambda would hold this object and leak it.
	net.draw_offered.connect(_on_draw_offered)
	net.undo_requested.connect(_on_undo_requested)
	net.rematch_requested.connect(_on_rematch_requested)


func _on_draw_offered() -> void:
	net.answer_draw(false)


func _on_undo_requested() -> void:
	net.answer_undo(true)


func _on_rematch_requested() -> void:
	net.answer_rematch(true)


func _play(now_ms: int) -> void:
	var s := net.session
	if s == null or not s.is_ongoing() or net.phase != NetMatch.Phase.PLAYING or s.side_to_move() != net.local_side:
		_ai.cancel()
		_move_at = -1
		return
	if _ai.is_thinking():
		var move := _ai.poll()
		if not _ai.is_thinking() and not move.is_empty():
			s.commit(move, net.local_side)
		return
	if _move_at < 0:
		_move_at = now_ms + THINK_MS
	elif now_ms >= _move_at:
		_move_at = -1
		var evaluator := HuntEvaluator.new(HuntRuleSets.weights_for(s.rules))
		_ai.start(s.state, HuntPersonas.all()[1], evaluator, _rng.randi())
