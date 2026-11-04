class_name OnlineBackend
extends RefCounted
## What online play needs from a provider (bible §5.2–5.3): an anonymous
## login, lobbies found by attribute, and a P2P link to the other player.
## The EOS backend (GD-EOS or EOSG plugin, after the spike) implements this;
## FakeOnlineBackend stands in for tests and the simulated mode.
## Calls return at once; results arrive as signals during poll().

signal logged_in(ok: bool)
signal lobby_created(lobby_id: String)
## Each lobby: {id, owner, members (int), max (int), attrs (Dictionary), created (int)}.
signal lobbies_found(lobbies: Array)
signal lobby_joined(lobby_id: String, owner: String)
signal lobby_error(what: String)
signal member_joined(lobby_id: String, user_id: String)
signal member_left(lobby_id: String, user_id: String)


## False when the service can't be reached; the online menu then hides.
func is_available() -> bool:
	return false


func is_logged_in() -> bool:
	return false


func login() -> void:
	logged_in.emit(false)


func user_id() -> String:
	return ""


## `searchable` lobbies can be found by attribute (quick match and friend
## codes); others only by invitation.
func create_lobby(_attrs: Dictionary, _searchable: bool, _max_members := 2) -> void:
	lobby_error.emit("unavailable")


## Lobbies whose attributes include every key/value in `filter` and have a
## free seat.
func search_lobbies(_filter: Dictionary) -> void:
	lobbies_found.emit([])


func join_lobby(_lobby_id: String) -> void:
	lobby_error.emit("unavailable")


func leave_lobby(_lobby_id: String) -> void:
	pass


## The P2P link to `peer_user_id` in a lobby both have joined.
func open_transport(_lobby_id: String, _peer_user_id: String, _as_host: bool) -> NetTransport:
	return null


## The title's remote config from Title Storage (bible §5.3), or {}.
func title_config() -> Dictionary:
	return {}


## Forgets this device's online ID ("Reset online ID / delete my online data").
func reset_identity() -> void:
	pass


func poll() -> void:
	pass
