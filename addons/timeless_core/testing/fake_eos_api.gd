class_name FakeEOSApi
extends EOSApi
## An in-process stand-in for EOS, for testing EOSOnlineBackend: every
## FakeEOSApi in the process shares one pretend cloud (users, lobbies, P2P
## mailboxes). Results arrive on the next tick(), like real EOS callbacks.
## Packets wait until the receiving side has opened its end, as in EOS.

static var _lobbies := {}     # id -> {id, owner, members: Array, max, attrs, bucket, public}
static var _apis := {}        # user id -> FakeEOSApi
static var _mail := {}        # user id -> Array of {peer, socket, bytes}
static var _next := 1

var started := false
var can_start := true
var user := ""
var device_has_id := false
var _queue: Array[Callable] = []
var _opened := {}             # peer|socket -> true


static func reset_cloud() -> void:
	_lobbies.clear()
	_apis.clear()
	_mail.clear()
	_next = 1


func start(_ids: Dictionary) -> bool:
	started = can_start
	return started


func tick() -> void:
	var due := _queue
	_queue = []
	for c in due:
		c.call()


func login(_display_name: String, done: Callable) -> void:
	_later(func() -> void:
		if not started:
			done.call(false, "")
			return
		if not device_has_id or user == "":
			device_has_id = true
			user = "puid%04d" % _next
			_next += 1
		_apis[user] = self
		done.call(true, user))


func delete_identity(done: Callable) -> void:
	_later(func() -> void:
		_apis.erase(user)
		user = ""
		device_has_id = false
		done.call())


func create_lobby(bucket: String, attrs: Dictionary, public: bool, max_members: int, done: Callable) -> void:
	_later(func() -> void:
		var id := "lobby%04d" % _next
		_next += 1
		_lobbies[id] = {"id": id, "owner": user, "members": [user], "max": max_members,
			"attrs": attrs.duplicate(), "bucket": bucket, "public": public}
		done.call(id))


func search_lobbies(bucket: String, filter: Dictionary, max_results: int, done: Callable) -> void:
	_later(func() -> void:
		var out: Array = []
		for id in _lobbies:
			var l: Dictionary = _lobbies[id]
			if not l.public or l.bucket != bucket:
				continue
			var ok := true
			for k in filter:
				if l.attrs.get(k) != filter[k]:
					ok = false
					break
			if ok and out.size() < max_results:
				out.append({"id": id, "owner": l.owner, "members": l.members.size(), "max": l.max,
					"attrs": l.attrs.duplicate()})
		done.call(out))


func join_lobby(lobby_id: String, done: Callable) -> void:
	_later(func() -> void:
		var l: Dictionary = _lobbies.get(lobby_id, {})
		if l.is_empty():
			done.call(false, "", "gone")
			return
		if l.members.size() >= l.max:
			done.call(false, "", "full")
			return
		l.members.append(user)
		done.call(true, l.owner, "")
		for m in l.members:
			if m != user:
				_tell(m, func(api: FakeEOSApi) -> void: api.member_joined.emit(lobby_id, user)))


func leave_lobby(lobby_id: String) -> void:
	var l: Dictionary = _lobbies.get(lobby_id, {})
	if l.is_empty():
		return
	l.members.erase(user)
	for m in l.members:
		_tell(m, func(api: FakeEOSApi) -> void: api.member_left.emit(lobby_id, user))


func destroy_lobby(lobby_id: String) -> void:
	var l: Dictionary = _lobbies.get(lobby_id, {})
	if l.is_empty() or l.owner != user:
		return
	_lobbies.erase(lobby_id)
	for m in l.members:
		if m != user:
			_tell(m, func(api: FakeEOSApi) -> void: api.lobby_closed.emit(lobby_id))


func p2p_open(peer: String, socket: String, _as_host: bool) -> void:
	_opened[peer + "|" + socket] = true
	# Both ends open: the link is up (EOS pairs them), on each side.
	var other: FakeEOSApi = _apis.get(peer)
	if other != null and other._opened.has(user + "|" + socket):
		var me := user
		_later(func() -> void: p2p_connected.emit(peer, socket))
		_tell(peer, func(api: FakeEOSApi) -> void: api.p2p_connected.emit(me, socket))


func p2p_send(peer: String, socket: String, bytes: PackedByteArray) -> bool:
	if bytes.size() > MAX_PACKET:
		return false
	if not _mail.has(peer):
		_mail[peer] = []
	_mail[peer].append({"peer": user, "socket": socket, "bytes": bytes})
	return true


func p2p_receive() -> Array:
	var box: Array = _mail.get(user, [])
	var now: Array = []
	var wait: Array = []
	for p in box:
		if _opened.has(str(p.peer) + "|" + str(p.socket)):
			now.append(p)
		else:
			wait.append(p)
	_mail[user] = wait
	return now


func p2p_close(peer: String, socket: String) -> void:
	_opened.erase(peer + "|" + socket)
	var me := user
	_tell(peer, func(api: FakeEOSApi) -> void: api.p2p_closed.emit(me, socket))


## Simulates EOS losing the link between this user and `peer` for a while.
func drop_link(peer: String, socket: String) -> void:
	var me := user
	_later(func() -> void: p2p_interrupted.emit(peer, socket))
	_tell(peer, func(api: FakeEOSApi) -> void: api.p2p_interrupted.emit(me, socket))


## Simulates EOS closing the link on both sides (it timed out: a phone was
## off Wi-Fi too long). Each side has to open its socket again.
func close_link(peer: String, socket: String) -> void:
	var me := user
	_later(func() -> void: p2p_closed.emit(peer, socket))
	_tell(peer, func(api: FakeEOSApi) -> void: api.p2p_closed.emit(me, socket))


func restore_link(peer: String, socket: String) -> void:
	var me := user
	_later(func() -> void: p2p_connected.emit(peer, socket))
	_tell(peer, func(api: FakeEOSApi) -> void: api.p2p_connected.emit(me, socket))


func _later(c: Callable) -> void:
	_queue.append(c)


static func _tell(user_id: String, what: Callable) -> void:
	var api: FakeEOSApi = _apis.get(user_id)
	if api != null:
		api._later(what.bind(api))
