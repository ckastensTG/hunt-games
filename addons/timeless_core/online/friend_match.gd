class_name FriendMatch
extends RefCounted
## "Play with a friend" (bible §5.2): the host gets a short code (TG-7K4Q) to
## share; the friend types it in. The code is a lobby attribute, so it works
## across Android and iOS (and Steam later) without accounts.

signal code_ready(code: String)
signal matched(transport: NetTransport, as_host: bool)
signal failed(reason: String)  # "offline", "not_found", "full"

var backend: OnlineBackend
var game_id := ""
var protocol := 1
var code := ""
var _hosting := false
var _joining := false
var _lobby := ""
var _rng := RandomNumberGenerator.new()


func _init(online: OnlineBackend, game: String, proto: int) -> void:
	backend = online
	game_id = game
	protocol = proto
	_rng.randomize()
	backend.logged_in.connect(_on_logged_in)
	backend.lobby_created.connect(_on_created)
	backend.lobbies_found.connect(_on_found)
	backend.lobby_joined.connect(_on_joined)
	backend.lobby_error.connect(_on_error)
	backend.member_joined.connect(_on_member_joined)


func host() -> void:
	_hosting = true
	code = JoinCode.random_online(_rng)
	_go()


func join(typed_code: String) -> void:
	code = JoinCode.normalize_online(typed_code)
	if code == "":
		failed.emit("not_found")
		return
	_joining = true
	_go()


func cancel() -> void:
	if _lobby != "":
		backend.leave_lobby(_lobby)
		_lobby = ""
	_hosting = false
	_joining = false


func poll() -> void:
	backend.poll()


func _go() -> void:
	if backend.is_logged_in():
		_on_logged_in(true)
	else:
		backend.login()


func _attrs() -> Dictionary:
	return {"game": game_id, "proto": protocol, "code": code}


func _on_logged_in(ok: bool) -> void:
	if not (_hosting or _joining):
		return
	if not ok:
		failed.emit("offline")
		return
	if _hosting:
		backend.create_lobby(_attrs(), true)
	else:
		backend.search_lobbies(_attrs())


func _on_created(lobby_id: String) -> void:
	if not _hosting or _lobby != "":
		return
	_lobby = lobby_id
	code_ready.emit(code)


func _on_found(lobbies: Array) -> void:
	if not _joining:
		return
	if lobbies.is_empty():
		_joining = false
		failed.emit("not_found")
		return
	backend.join_lobby(lobbies[0].id)


func _on_joined(lobby_id: String, owner: String) -> void:
	if not _joining:
		return
	_joining = false
	_lobby = lobby_id
	matched.emit(backend.open_transport(lobby_id, owner, false), false)


func _on_error(what: String) -> void:
	if _joining:
		_joining = false
		failed.emit("full" if what == "full" else "not_found")


func _on_member_joined(lobby_id: String, user: String) -> void:
	if not _hosting or lobby_id != _lobby:
		return
	_hosting = false
	matched.emit(backend.open_transport(lobby_id, user, true), true)
