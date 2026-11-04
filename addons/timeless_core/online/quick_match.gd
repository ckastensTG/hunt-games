class_name QuickMatch
extends RefCounted
## "Play with someone online" (bible §5.3): find a stranger for a standard
## game through public lobbies, with no servers of our own.
##   1. Search for open quick-match lobbies of this game and protocol.
##   2. Join the oldest one with a free seat, or host one and keep searching.
##   3. Two waiting hosts never wait for each other forever: the newer lobby
##      closes and joins the older one.
## After `timeout_s` it emits timed_out once, but keeps looking until
## cancel(): the game offers "Play the AI while we keep looking" and shows a
## toast when matched. It never invents opponents.

signal status_changed(status: Status)
signal matched(transport: NetTransport, as_host: bool)
signal timed_out
signal failed(reason: String)

enum Status { IDLE, LOGGING_IN, SEARCHING, WAITING, JOINING, MATCHED, CANCELLED, FAILED }

var backend: OnlineBackend
var game_id := ""
var protocol := 1
var timeout_s := 60
var poll_s := 4
var status: Status = Status.IDLE

var _started := 0
var _now := 0
var _timed_out := false
var _lobby := ""          # the lobby we host while waiting
var _since := 0          # when we opened it (Unix ms), for the merge rule
var _last_search := 0
var _search_pending := false
var _creating := false


func _init(online: OnlineBackend, game: String, proto: int) -> void:
	backend = online
	game_id = game
	protocol = proto
	backend.logged_in.connect(_on_logged_in)
	backend.lobbies_found.connect(_on_lobbies)
	backend.lobby_created.connect(_on_created)
	backend.lobby_joined.connect(_on_joined)
	backend.lobby_error.connect(_on_error)
	backend.member_joined.connect(_on_member_joined)


func filter() -> Dictionary:
	return {"game": game_id, "proto": protocol, "quickmatch": true}


func start(now_ms := -1) -> void:
	_now = Time.get_ticks_msec() if now_ms < 0 else now_ms
	_started = _now
	_timed_out = false
	if backend.is_logged_in():
		_search()
	else:
		_set_status(Status.LOGGING_IN)
		backend.login()


func cancel() -> void:
	if _lobby != "":
		backend.leave_lobby(_lobby)
		_lobby = ""
	if status != Status.MATCHED:
		_set_status(Status.CANCELLED)


func seconds_waiting() -> int:
	return (_now - _started) / 1000


func poll(now_ms := -1) -> void:
	_now = Time.get_ticks_msec() if now_ms < 0 else now_ms
	backend.poll()
	if status in [Status.SEARCHING, Status.WAITING]:
		if not _timed_out and _now - _started >= timeout_s * 1000:
			_timed_out = true
			timed_out.emit()
		if status == Status.WAITING and not _search_pending and _now - _last_search >= poll_s * 1000:
			_search()


func _search() -> void:
	_last_search = _now
	_search_pending = true
	if status != Status.WAITING:
		_set_status(Status.SEARCHING)
	backend.search_lobbies(filter())


func _on_logged_in(ok: bool) -> void:
	if status != Status.LOGGING_IN:
		return
	if ok:
		_search()
	else:
		_set_status(Status.FAILED)
		failed.emit("offline")


func _on_lobbies(lobbies: Array) -> void:
	if not _search_pending:
		return
	_search_pending = false
	if status not in [Status.SEARCHING, Status.WAITING]:
		return
	var best := {}
	for l in lobbies:
		if l.id == _lobby or l.owner == backend.user_id():
			continue
		if best.is_empty() or _older(l, best):
			best = l
	if best.is_empty():
		if _lobby == "" and not _creating:
			_creating = true
			_since = int(Time.get_unix_time_from_system() * 1000.0)
			var attrs := filter()
			attrs["since"] = _since
			backend.create_lobby(attrs, true)
		return
	if _lobby != "":
		# Merge rule: only the newer of two waiting hosts gives up its lobby.
		# Both compare the same two stamps, so exactly one of them moves.
		if not _older(best, {"id": _lobby, "attrs": {"since": _since}}):
			return
		backend.leave_lobby(_lobby)
		_lobby = ""
	_set_status(Status.JOINING)
	backend.join_lobby(best.id)


func _on_created(lobby_id: String) -> void:
	if not _creating:
		return
	_creating = false
	if status in [Status.CANCELLED, Status.MATCHED]:
		backend.leave_lobby(lobby_id)
		return
	_lobby = lobby_id
	_set_status(Status.WAITING)


func _on_joined(lobby_id: String, owner: String) -> void:
	if status != Status.JOINING:
		return
	_set_status(Status.MATCHED)
	matched.emit(backend.open_transport(lobby_id, owner, false), false)


func _on_member_joined(lobby_id: String, user: String) -> void:
	if lobby_id != _lobby or status != Status.WAITING:
		return
	_set_status(Status.MATCHED)
	matched.emit(backend.open_transport(lobby_id, user, true), true)


func _on_error(_what: String) -> void:
	if status == Status.JOINING:
		# Someone else got the seat: look again.
		_set_status(Status.SEARCHING)
		_search()


static func _older(a: Dictionary, b: Dictionary) -> bool:
	var sa := int(a.get("attrs", {}).get("since", 0))
	var sb := int(b.get("attrs", {}).get("since", 0))
	return sa < sb or (sa == sb and str(a.id) < str(b.id))


func _set_status(s: Status) -> void:
	if status != s:
		status = s
		status_changed.emit(s)
