extends Node
## Starts and runs games against other people (framework §9, bible §5.1–5.3):
##   - nearby: local Wi-Fi, ENet, found by a LAN beacon or a code;
##   - online with a friend: a TG-XXXX code;
##   - online quick match, with "play the AI while we keep looking".
## The menu calls it; it hands each match that starts to the greybox and tells
## the interface what happens (signals below). The network work itself is in
## timeless_core (NetMatch, QuickMatch, FriendMatch, LanDiscovery).
##
## Online goes through an OnlineBackend. Until the EOS plugin is in (bible
## §13 #2), release builds get the unavailable backend, so the online menu
## hides, and debug builds get a simulated service on this device with a
## simulated opponent, always labeled "test build". Release builds never
## create one (bible §5.3: never fake opponents).

## Something the menu shows changed (flow, error, code, search time).
signal changed
signal nearby_hosts_changed
## A quick-match opponent turned up while the player was playing the AI.
signal background_match_found
## A short message for the player (already translated).
signal toast(text: String)
## The opponent asks something: "draw", "undo" or "rematch".
signal asked(what: String)
## The connection state changed (lost, back, opponent gone).
signal connection_changed

enum Flow { NONE, NEARBY_HOST, NEARBY_BROWSE, CONNECTING, FRIEND_HOST, FRIEND_JOIN, QUICK, PLAYING }

const SimOpponentScript := preload("res://scenes/play/sim_opponent.gd")
const QUICK_TURN_SECONDS := 60
const QUICK_CHOICE_MS := 60000
const HANDSHAKE_MS := 15000
const BACKGROUND_OFFER_MS := 20000
const LOCAL_NETWORK_PERMISSION := "android.permission.ACCESS_LOCAL_NETWORK"

var game: Node
var flow: Flow = Flow.NONE
## Why the last attempt failed (PlayText.problem keys), or "".
var error := ""
## The code to show: a nearby code ("XXX-XXXX") or an online one ("TG-XXXX").
var code := ""
var net: NetMatch
var backend: OnlineBackend
## This device's player name ({key, n}), kept between sessions.
var player_name := {}
## Quick match: the three choices are showing (no one found yet).
var quick_choices := false
## Quick match: still searching while the player plays the AI.
var background := false
## Debug builds: when the simulated opponent joins a quick match (seconds;
## -1 never).
var sim_join_s := 8

var _quick: QuickMatch
var _friend: FriendMatch
var _lan: LanDiscovery
var _sim: RefCounted
var _host_rule_set := ""
var _host_side := HuntState.PREY
var _kind: MatchSession.Kind = MatchSession.Kind.NEARBY
var _quick_started := 0
var _choice_at := 0
var _handshake_until := 0
var _pending_transport: NetTransport
var _pending_host := false
var _pending_until := 0
var _after_permission: Callable
var _rng := RandomNumberGenerator.new()
var _now := 0


func _init(owner_game: Node) -> void:
	game = owner_game
	_rng.randomize()
	if OS.is_debug_build():
		backend = FakeOnlineBackend.new()
	else:
		backend = OnlineBackend.new()  # unavailable until the EOS backend lands


func _ready() -> void:
	var saved: Variant = L10n.load_setting("player_name", {})
	if typeof(saved) == TYPE_DICTIONARY and PlayerNames.is_valid(saved):
		player_name = saved
	else:
		player_name = PlayerNames.random(_rng)
		L10n.save_setting("player_name", player_name)
	get_tree().on_request_permissions_result.connect(_on_permission)


# --- What the menu asks ------------------------------------------------------

func online_available() -> bool:
	return backend.is_available()


## True when online play is the simulated test service (debug builds).
func is_simulated() -> bool:
	return backend is FakeOnlineBackend


func title_id() -> String:
	return TitleConfig.active().network_id()


## Nearby games heard on this Wi-Fi: [{name, rule_set, code, ip}], checked.
func nearby_hosts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _lan == null:
		return out
	for h in _lan.hosts():
		# Beacons come from anyone on the network: keep only well-formed ones.
		if h.get("title") != title_id() or typeof(h.get("name")) != TYPE_DICTIONARY:
			continue
		if typeof(h.get("rule_set")) != TYPE_STRING or TitleConfig.active().resolve_rule_set(h.rule_set) == null:
			continue
		out.append({"name": h.name, "rule_set": h.rule_set, "code": str(h.get("code", "")), "ip": str(h.ip)})
	return out


## Seconds since the quick-match search started.
func quick_seconds() -> int:
	return maxi(0, (_now - _quick_started) / 1000)


## True when a click may play a move in the network game now.
func can_move() -> bool:
	return net != null and net.phase == NetMatch.Phase.PLAYING


func is_reconnecting() -> bool:
	return net != null and net.phase == NetMatch.Phase.RECONNECTING


## Seconds left in the reconnect window, or -1.
func reconnect_seconds_left() -> int:
	if not is_reconnecting():
		return -1
	return maxi(0, (NetMatch.RECONNECT_WINDOW_MS - (_now - net._lost_at)) / 1000)


func opponent_name() -> String:
	return PlayText.player_name(net.opponent_name) if net else ""


func match_kind() -> MatchSession.Kind:
	return net.session.kind if net and net.session else _kind


# --- Nearby (local Wi-Fi) ----------------------------------------------------

func nearby_host(rule_set_id: String, side: int) -> void:
	cancel()
	_with_local_network(func() -> void: _nearby_host(rule_set_id, side))


func _nearby_host(rule_set_id: String, side: int) -> void:
	var ip := JoinCode.local_ipv4()
	if ip == "":
		_fail("no_wifi")
		return
	var link := ENetTransport.host()
	if link == null:
		_fail("port")
		return
	code = JoinCode.from_ipv4(ip)
	_lan = LanDiscovery.new()
	_lan.advertise({"title": title_id(), "rule_set": rule_set_id, "name": player_name, "code": code})
	_kind = MatchSession.Kind.NEARBY
	_start_net(NetMatch.as_host(link, rule_set_id, side, MatchSession.Kind.NEARBY, 0,
		title_id(), _build(), player_name, _resolver()), false)
	_set_flow(Flow.NEARBY_HOST)


func nearby_browse() -> void:
	cancel()
	_with_local_network(_nearby_browse)


func _nearby_browse() -> void:
	_lan = LanDiscovery.new()
	_lan.hosts_changed.connect(func() -> void: nearby_hosts_changed.emit())
	if not _lan.listen():
		_lan = null
		_fail("port")
		return
	_set_flow(Flow.NEARBY_BROWSE)


func nearby_join(address: String) -> void:
	_stop_lan()
	var link := ENetTransport.join(address)
	if link == null:
		_fail("connection")
		return
	_kind = MatchSession.Kind.NEARBY
	_start_net(NetMatch.as_guest(link, title_id(), _build(), player_name, _resolver()), true)
	_set_flow(Flow.CONNECTING)


func nearby_join_code(typed: String) -> void:
	var ip := JoinCode.to_ipv4(typed)
	if ip == "":
		_fail("bad_code")
		return
	_with_local_network(func() -> void: nearby_join(ip))


# --- Online: a friend --------------------------------------------------------

func friend_host(rule_set_id: String, side: int) -> void:
	cancel()
	_host_rule_set = rule_set_id
	_host_side = side
	_kind = MatchSession.Kind.ONLINE_FRIEND
	_friend = FriendMatch.new(backend, title_id(), NetProtocol.VERSION)
	_friend.code_ready.connect(func(c: String) -> void:
		code = c
		changed.emit())
	_friend.matched.connect(_on_online_matched)
	_friend.failed.connect(_fail)
	code = ""
	_set_flow(Flow.FRIEND_HOST)
	_friend.host()


func friend_join(typed: String) -> void:
	cancel()
	_kind = MatchSession.Kind.ONLINE_FRIEND
	_friend = FriendMatch.new(backend, title_id(), NetProtocol.VERSION)
	_friend.matched.connect(_on_online_matched)
	_friend.failed.connect(_fail)
	_set_flow(Flow.FRIEND_JOIN)
	_friend.join(typed)


## Debug builds: a simulated friend types the code shown.
func simulate_friend_joining() -> void:
	if not is_simulated() or code == "":
		return
	_sim = SimOpponentScript.new(title_id(), _build(), _resolver())
	_sim.join_friend(code, 1500, _now)


# --- Online: quick match -----------------------------------------------------

func quick_start() -> void:
	cancel()
	_kind = MatchSession.Kind.QUICK_MATCH
	_quick = QuickMatch.new(backend, title_id(), NetProtocol.VERSION)
	_quick.matched.connect(_on_quick_matched)
	_quick.failed.connect(_fail)
	_quick.status_changed.connect(func(_s: int) -> void: changed.emit())
	_now = Time.get_ticks_msec()
	_quick_started = _now
	_choice_at = _now + QUICK_CHOICE_MS
	quick_choices = false
	background = false
	_set_flow(Flow.QUICK)
	_quick.start(_now)
	if is_simulated() and sim_join_s >= 0:
		_sim = SimOpponentScript.new(title_id(), _build(), _resolver())
		_sim.join_quick(sim_join_s * 1000, _now)


## "Play against the AI while we keep looking."
func quick_play_ai(mode: int, rule_set_id: String, ai_level: int) -> void:
	quick_choices = false
	background = true
	game.start_local(mode, rule_set_id, ai_level)
	toast.emit(L10n.t("We'll let you know when an opponent is ready."))
	changed.emit()


func quick_keep_searching() -> void:
	quick_choices = false
	_choice_at = _now + QUICK_CHOICE_MS
	changed.emit()


## The toast's "Play now".
func accept_background() -> void:
	if _pending_transport == null:
		return
	background = false
	var link := _pending_transport
	_pending_transport = null
	_begin_quick(link, _pending_host)


## The toast's "Not now" (or no answer): stop looking.
func decline_background() -> void:
	if _pending_transport != null:
		_pending_transport.close()
		_pending_transport = null
	background = false
	cancel()


# --- In a match --------------------------------------------------------------

func offer_draw() -> void:
	if net and net.session and net.session.is_ongoing():
		net.offer_draw()
		toast.emit(L10n.t("Draw offered. Waiting for an answer."))


func request_undo() -> void:
	if net and net.session and net.session.is_ongoing() and not net.session.moves.is_empty():
		net.request_undo()
		toast.emit(L10n.t("Asked to take back your last move."))


func resign() -> void:
	if net:
		net.resign()


func request_rematch() -> void:
	if net and net.phase != NetMatch.Phase.CLOSED:
		net.request_rematch()
		toast.emit(L10n.t("Rematch offered. Waiting for an answer."))
	else:
		toast.emit(L10n.t("Your opponent left the game."))


func answer(what: String, ok: bool) -> void:
	if net == null:
		return
	match what:
		"draw":
			net.answer_draw(ok)
		"undo":
			net.answer_undo(ok)
		"rematch":
			net.answer_rematch(ok)


## True when the opponent can still be asked for a rematch.
func can_rematch() -> bool:
	return net != null and net.phase != NetMatch.Phase.CLOSED


## Leaves the network game: a game still going counts as resigned. The board
## keeps showing it; the caller decides what comes next.
func leave_match() -> void:
	if net:
		if net.session and net.session.is_ongoing():
			net.resign()
		net.leave()
	net = null
	flow = Flow.NONE
	cancel()


## Stops whatever is being set up (not a game in progress: see leave_match).
func cancel() -> void:
	_stop_lan()
	if _quick:
		_quick.cancel()
		_quick = null
	if _friend:
		_friend.cancel()
		_friend = null
	if _sim:
		_sim.stop()
		_sim = null
	if _pending_transport:
		_pending_transport.close()
		_pending_transport = null
	if net and flow != Flow.PLAYING:
		net.leave()
		net = null
	quick_choices = false
	background = false
	code = ""
	error = ""
	_handshake_until = 0
	if flow != Flow.PLAYING:
		_set_flow(Flow.NONE)


# --- Running -----------------------------------------------------------------

func _process(_delta: float) -> void:
	_now = Time.get_ticks_msec()
	if _lan:
		_lan.poll(_now)
	if _quick:
		_quick.poll(_now)
		if flow == Flow.QUICK and not background and not quick_choices and _now >= _choice_at:
			quick_choices = true
			changed.emit()
	if _friend:
		_friend.poll()
	if _sim:
		_sim.poll(_now)
	if net:
		net.poll(_now)
		if _handshake_until > 0 and net and net.phase == NetMatch.Phase.HANDSHAKE and _now > _handshake_until:
			_handshake_until = 0
			_on_net_failed("connection")
	if _pending_transport and _now > _pending_until:
		decline_background()


func _start_net(n: NetMatch, with_deadline: bool) -> void:
	if net and net != n:
		net.leave()
	net = n
	error = ""
	_handshake_until = Time.get_ticks_msec() + HANDSHAKE_MS if with_deadline else 0
	n.started.connect(_on_started)
	n.failed.connect(_on_net_failed)
	n.connection_lost.connect(func() -> void: connection_changed.emit())
	n.reconnected.connect(func() -> void:
		toast.emit(L10n.t("Reconnected."))
		connection_changed.emit())
	n.opponent_left.connect(func() -> void:
		toast.emit(L10n.t("Your opponent left the game."))
		connection_changed.emit())
	n.draw_offered.connect(func() -> void: asked.emit("draw"))
	n.undo_requested.connect(func() -> void: asked.emit("undo"))
	n.rematch_requested.connect(func() -> void: asked.emit("rematch"))
	n.draw_declined.connect(func() -> void: toast.emit(L10n.t("Your opponent declined the draw.")))
	n.undo_answered.connect(func(ok: bool) -> void:
		toast.emit(L10n.t("Move taken back.") if ok else L10n.t("Your opponent said no to taking back the move.")))
	n.rematch_declined.connect(func() -> void: toast.emit(L10n.t("Your opponent declined the rematch.")))
	n.turn_timed_out.connect(_on_turn_timed_out)


func _on_started(session: MatchSession, side: int) -> void:
	_handshake_until = 0
	_stop_lan()
	if _quick:
		_quick.cancel()  # leaves the lobby; the game has its own connection
		_quick = null
	if _friend:
		_friend.cancel()
		_friend = null
	quick_choices = false
	_set_flow(Flow.PLAYING)
	game.start_network(session, side)
	# TRANSLATORS: Shown when a game with another player starts. %s is their name, e.g. "Scribe 4821".
	toast.emit(L10n.t("Playing against %s") % opponent_name())


func _on_net_failed(reason: String) -> void:
	_handshake_until = 0
	if net:
		net.leave()
		net = null
	if flow == Flow.QUICK or _kind == MatchSession.Kind.QUICK_MATCH and flow != Flow.PLAYING:
		# A quick-match opponent who doesn't connect: keep looking.
		toast.emit(L10n.t("The other player didn't connect. Still looking…"))
		var was_background := background
		quick_start()
		background = was_background
		return
	_fail(reason)


func _on_online_matched(link: NetTransport, as_host: bool) -> void:
	if as_host:
		_start_net(NetMatch.as_host(link, _host_rule_set, _host_side, MatchSession.Kind.ONLINE_FRIEND, 0,
			title_id(), _build(), player_name, _resolver()), true)
	else:
		_start_net(NetMatch.as_guest(link, title_id(), _build(), player_name, _resolver()), true)
	_set_flow(Flow.CONNECTING)


func _on_quick_matched(link: NetTransport, as_host: bool) -> void:
	if background:
		_pending_transport = link
		_pending_host = as_host
		_pending_until = _now + BACKGROUND_OFFER_MS
		background_match_found.emit()
		return
	_begin_quick(link, as_host)


func _begin_quick(link: NetTransport, as_host: bool) -> void:
	# Standard rules only, side at random (bible §5.3).
	if as_host:
		var side := HuntState.HUNTER if _rng.randi() % 2 == 0 else HuntState.PREY
		_start_net(NetMatch.as_host(link, TitleConfig.active().rule_sets[0], side, MatchSession.Kind.QUICK_MATCH,
			QUICK_TURN_SECONDS, title_id(), _build(), player_name, _resolver()), true)
	else:
		_start_net(NetMatch.as_guest(link, title_id(), _build(), player_name, _resolver()), true)
	_set_flow(Flow.CONNECTING)


## The clock ran out: a quick move is played for the player (Novice), and
## the third time the game is lost (bible §5.3).
func _on_turn_timed_out() -> void:
	var s := net.session
	if s == null or not s.is_ongoing() or s.side_to_move() != net.local_side:
		return
	var persona: AIPersona = HuntPersonas.all()[0]
	var move := AIDriver.choose_now(s.state, persona, HuntEvaluator.new(HuntRuleSets.weights_for(s.rules)), _rng.randi())
	if not move.is_empty():
		s.commit(move, net.local_side)
	# TRANSLATORS: The turn clock in online quick match ran out. %d is 1 or 2; at 3 the game is lost.
	toast.emit(L10n.t("Time ran out, so a move was played for you (%d of 3).") % net.timeouts)


func _fail(reason: String) -> void:
	error = reason
	_stop_lan()
	if _quick:
		_quick.cancel()
		_quick = null
	if _friend:
		_friend.cancel()
		_friend = null
	if net and flow != Flow.PLAYING:
		net.leave()
		net = null
	_set_flow(Flow.NONE)
	changed.emit()


func _stop_lan() -> void:
	if _lan:
		_lan.stop_advertising()
		_lan.stop_listening()
		_lan = null


func _set_flow(f: Flow) -> void:
	flow = f
	changed.emit()


func _resolver() -> Callable:
	var title := TitleConfig.active()
	return func(id: String) -> HuntRuleSet: return title.resolve_rule_set(id)


func _build() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


# --- Android: local network permission ---------------------------------------

## Android 17 asks before an app can see the local network (targetSdk 37);
## older versions don't have the permission. Elsewhere this just runs `then`.
func _with_local_network(then: Callable) -> void:
	if OS.get_name() != "Android" or _android_major() < 17:
		then.call()
		return
	if OS.request_permission(LOCAL_NETWORK_PERMISSION):
		then.call()
		return
	_after_permission = then  # the answer comes in _on_permission


func _on_permission(permission: String, granted: bool) -> void:
	if permission != LOCAL_NETWORK_PERMISSION or not _after_permission.is_valid():
		return
	var then := _after_permission
	_after_permission = Callable()
	if granted:
		then.call()
	else:
		_fail("permission")


static func _android_major() -> int:
	return OS.get_version().get_slice(".", 0).to_int()
