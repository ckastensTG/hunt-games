class_name FakeOnlineBackend
extends OnlineBackend
## An in-process stand-in for EOS: every FakeOnlineBackend in the same
## process shares one pretend cloud of lobbies, and P2P links are loopback
## pairs. Used by the tests and by the simulated online mode in dev builds.
## Results arrive on the next poll(), like real network calls.

static var _lobbies := {}      # id -> {id, owner, members: Array, max, attrs, searchable, created}
static var _users := {}        # user id -> FakeOnlineBackend
static var _links := {}        # lobby id -> [host transport, guest transport]
static var _next_id := 1
static var _clock := 0

var _user := ""
var _logged_in := false
var _queue: Array[Callable] = []
var available := true


static func reset_cloud() -> void:
	_lobbies.clear()
	_users.clear()
	_links.clear()
	_next_id = 1
	_clock = 0


func is_available() -> bool:
	return available


func is_logged_in() -> bool:
	return _logged_in


func login() -> void:
	_later(func() -> void:
		if not available:
			logged_in.emit(false)
			return
		if _user == "":
			_user = "user%d" % _next_id
			_next_id += 1
		_users[_user] = self
		_logged_in = true
		logged_in.emit(true))


func user_id() -> String:
	return _user


func create_lobby(attrs: Dictionary, searchable: bool, max_members := 2) -> void:
	_later(func() -> void:
		var id := "lobby%d" % _next_id
		_next_id += 1
		_clock += 1
		_lobbies[id] = {"id": id, "owner": _user, "members": [_user], "max": max_members,
			"attrs": attrs.duplicate(), "searchable": searchable, "created": _clock}
		lobby_created.emit(id))


func search_lobbies(filter: Dictionary) -> void:
	_later(func() -> void:
		var out: Array = []
		for id in _lobbies:
			var l: Dictionary = _lobbies[id]
			if not l.searchable or l.members.size() >= l.max:
				continue
			var ok := true
			for k in filter:
				if l.attrs.get(k) != filter[k]:
					ok = false
					break
			if ok:
				out.append({"id": id, "owner": l.owner, "members": l.members.size(), "max": l.max,
					"attrs": l.attrs.duplicate(), "created": l.created})
		lobbies_found.emit(out))


func join_lobby(lobby_id: String) -> void:
	_later(func() -> void:
		var l: Dictionary = _lobbies.get(lobby_id, {})
		if l.is_empty():
			lobby_error.emit("gone")
			return
		if l.members.size() >= l.max:
			lobby_error.emit("full")
			return
		l.members.append(_user)
		lobby_joined.emit(lobby_id, l.owner)
		var owner: FakeOnlineBackend = _users.get(l.owner)
		if owner != null:
			owner._later(func() -> void: owner.member_joined.emit(lobby_id, _user)))


func leave_lobby(lobby_id: String) -> void:
	var l: Dictionary = _lobbies.get(lobby_id, {})
	if l.is_empty():
		return
	l.members.erase(_user)
	if l.owner == _user or l.members.is_empty():
		for u in l.members:
			var other: FakeOnlineBackend = _users.get(u)
			if other != null:
				other._later(func() -> void: other.member_left.emit(lobby_id, _user))
		_lobbies.erase(lobby_id)
		_links.erase(lobby_id)


func open_transport(lobby_id: String, _peer_user_id: String, as_host: bool) -> NetTransport:
	if not _links.has(lobby_id):
		_links[lobby_id] = LoopbackTransport.pair()
	var pair: Array = _links[lobby_id]
	return pair[0] if as_host else pair[1]


func reset_identity() -> void:
	_users.erase(_user)
	_user = ""
	_logged_in = false


func poll() -> void:
	var due := _queue
	_queue = []
	for c in due:
		c.call()


func _later(c: Callable) -> void:
	_queue.append(c)
