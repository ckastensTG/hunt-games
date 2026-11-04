class_name EOSOnlineBackend
extends OnlineBackend
## Online play over Epic Online Services (bible §5.2–5.3): an anonymous Device
## ID login, lobbies found by attribute for quick match and friend codes, and
## EOS P2P for the moves. No servers of our own and nothing stored online.
##
## The EOS calls go through an EOSApi (EOSGApi in builds, FakeEOSApi in
## tests). Lobbies live in a bucket per game and protocol version
## ("bagh_chal:1"), so different titles and incompatible versions never meet;
## inside it, QuickMatch and FriendMatch search by their own attributes.

const REQUIRED_IDS := ["product_id", "sandbox_id", "deployment_id", "client_id", "client_secret"]
const SEARCH_RESULTS := 20
## The EOSG plugin (addons/epic-online-services-godot): its native singleton,
## and our adapter for it. The adapter has no class_name and is only loaded
## when the plugin is there, so projects and tests without it still parse.
const EOSG_SINGLETON := "IEOS"
const EOSG_API := "res://addons/timeless_core/online/eosg_api.gd"

var api: EOSApi
## Shown by EOS for the device's user; never seen by other players (they see
## the curated word names the match sends itself).
var display_name := "Player"

var _started := false
var _user := ""
var _logging_in := false
var _queue: Array[Callable] = []
var _owned := {}         # lobby id -> true: lobbies we created
var _joined := {}        # lobby id -> owner: lobbies we joined
var _transports := {}    # peer|socket -> EOSP2PTransport


## `ids`: product_name, product_id, sandbox_id, deployment_id, client_id,
## client_secret (the title supplies them).
func _init(eos: EOSApi, ids: Dictionary) -> void:
	api = eos
	_started = has_ids(ids) and api.start(ids)
	api.member_joined.connect(_on_member_joined)
	api.member_left.connect(_on_member_left)
	api.lobby_closed.connect(_on_lobby_closed)
	api.p2p_connected.connect(_on_p2p_up)
	api.p2p_interrupted.connect(_on_p2p_down)
	api.p2p_closed.connect(_on_p2p_closed)


## The EOSApi for this build: the EOSG plugin's when it is in the project
## and runs on this platform, otherwise the "EOS isn't here" one.
static func plugin_api() -> EOSApi:
	if Engine.has_singleton(EOSG_SINGLETON) and ResourceLoader.exists(EOSG_API):
		return load(EOSG_API).new()
	return EOSApi.new()


static func has_ids(ids: Dictionary) -> bool:
	for k in REQUIRED_IDS:
		if str(ids.get(k, "")) == "":
			return false
	return true


## The P2P socket for a lobby: EOS socket names are short and alphanumeric.
static func socket_for(lobby_id: String) -> String:
	return "tg" + lobby_id.md5_text().substr(0, 24)


## The lobby bucket for a set of attributes (game and protocol version).
static func bucket_for(attrs: Dictionary) -> String:
	return "%s:%s" % [attrs.get("game", ""), attrs.get("proto", "")]


func is_available() -> bool:
	return _started


func is_logged_in() -> bool:
	return _user != ""


func user_id() -> String:
	return _user


func login() -> void:
	if not _started:
		_later(func() -> void: logged_in.emit(false))
		return
	if _user != "":
		_later(func() -> void: logged_in.emit(true))
		return
	if _logging_in:
		return
	_logging_in = true
	api.login(display_name, func(ok: bool, uid: String) -> void:
		_logging_in = false
		_user = uid if ok else ""
		logged_in.emit(ok and uid != ""))


func create_lobby(attrs: Dictionary, searchable: bool, max_members := 2) -> void:
	if not is_logged_in():
		_later(func() -> void: lobby_error.emit("offline"))
		return
	api.create_lobby(bucket_for(attrs), attrs, searchable, max_members, func(lobby_id: String) -> void:
		if lobby_id == "":
			lobby_error.emit("failed")
			return
		_owned[lobby_id] = true
		lobby_created.emit(lobby_id))


func search_lobbies(filter: Dictionary) -> void:
	if not is_logged_in():
		_later(func() -> void: lobbies_found.emit([]))
		return
	api.search_lobbies(bucket_for(filter), filter, SEARCH_RESULTS, func(found: Array) -> void:
		var open: Array = []
		for l in found:
			if int(l.get("members", 0)) < int(l.get("max", 0)):
				open.append(l)
		lobbies_found.emit(open))


func join_lobby(lobby_id: String) -> void:
	if not is_logged_in():
		_later(func() -> void: lobby_error.emit("offline"))
		return
	api.join_lobby(lobby_id, func(ok: bool, owner: String, error: String) -> void:
		if not ok:
			lobby_error.emit(error if error != "" else "failed")
			return
		_joined[lobby_id] = owner
		lobby_joined.emit(lobby_id, owner))


func leave_lobby(lobby_id: String) -> void:
	if _owned.has(lobby_id):
		_owned.erase(lobby_id)
		api.destroy_lobby(lobby_id)
	elif _joined.has(lobby_id):
		_joined.erase(lobby_id)
		api.leave_lobby(lobby_id)


func open_transport(lobby_id: String, peer_user_id: String, as_host: bool) -> NetTransport:
	var t := EOSP2PTransport.new(api, peer_user_id, socket_for(lobby_id), as_host)
	_transports[t.key()] = t
	return t


func reset_identity() -> void:
	for l in _owned.keys() + _joined.keys():
		leave_lobby(l)
	_user = ""
	api.delete_identity(func() -> void: pass)


func poll() -> void:
	api.tick()
	for p in api.p2p_receive():
		var t: EOSP2PTransport = _transports.get(str(p.peer) + "|" + str(p.socket))
		if t != null:
			t.deliver(p.bytes)
	for k in _transports.keys():
		if (_transports[k] as EOSP2PTransport).is_closed():
			_transports.erase(k)
	var due := _queue
	_queue = []
	for c in due:
		c.call()


func _later(c: Callable) -> void:
	_queue.append(c)


func _on_member_joined(lobby_id: String, user: String) -> void:
	if (_owned.has(lobby_id) or _joined.has(lobby_id)) and user != _user:
		member_joined.emit(lobby_id, user)


func _on_member_left(lobby_id: String, user: String) -> void:
	if (_owned.has(lobby_id) or _joined.has(lobby_id)) and user != _user:
		member_left.emit(lobby_id, user)


func _on_lobby_closed(lobby_id: String) -> void:
	if _joined.has(lobby_id):
		var owner: String = _joined[lobby_id]
		_joined.erase(lobby_id)
		member_left.emit(lobby_id, owner)
	_owned.erase(lobby_id)


func _on_p2p_up(peer: String, socket: String) -> void:
	var t: EOSP2PTransport = _transports.get(peer + "|" + socket)
	if t != null:
		t.on_link(true)


func _on_p2p_down(peer: String, socket: String) -> void:
	var t: EOSP2PTransport = _transports.get(peer + "|" + socket)
	if t != null:
		t.on_link(false)


func _on_p2p_closed(peer: String, socket: String) -> void:
	var t: EOSP2PTransport = _transports.get(peer + "|" + socket)
	if t != null:
		t.on_closed()
