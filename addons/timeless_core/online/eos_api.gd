class_name EOSApi
extends RefCounted
## The few Epic Online Services calls that online play makes, kept apart from
## the plugin that makes them (EOSG, see EOSGApi). EOSOnlineBackend holds the
## matching logic on top; tests run it on FakeEOSApi, and a different plugin
## would only need a new subclass of this.
##
## Calls return at once. `done` callbacks and the signals arrive during
## tick(), as EOS delivers its results.
##   users    EOS Product User IDs, as strings
##   lobbies  {id, owner, members (int), max (int), attrs (Dictionary)}
##   P2P      packets of at most MAX_PACKET bytes on a named socket
## This base class is the "EOS isn't here" case: everything fails politely.

signal member_joined(lobby_id: String, user_id: String)
signal member_left(lobby_id: String, user_id: String)
## The lobby is gone: its owner closed it, or EOS did.
signal lobby_closed(lobby_id: String)
## The P2P link to `peer` on `socket` is up (again).
signal p2p_connected(peer: String, socket: String)
## The link dropped for now; EOS keeps trying to restore it.
signal p2p_interrupted(peer: String, socket: String)
## The link is closed for good (the other side closed it, or it timed out).
signal p2p_closed(peer: String, socket: String)

## Our largest P2P packet: EOS takes 1170 bytes, and the plugin wraps each
## packet in a few bytes of its own.
const MAX_PACKET := 1100


## Starts the EOS platform with the title's IDs: product_name, product_id,
## sandbox_id, deployment_id, client_id, client_secret. False when EOS can't
## run here (no plugin, unsupported platform, bad IDs).
func start(_ids: Dictionary) -> bool:
	return false


## Lets EOS run its callbacks. Call every frame.
func tick() -> void:
	pass


## Anonymous login with this device's ID, creating the ID and the EOS user
## the first time. done(ok: bool, user_id: String).
func login(_display_name: String, done: Callable) -> void:
	done.call(false, "")


## Deletes this device's ID, so the next login is a new, unrelated user.
## done().
func delete_identity(done: Callable) -> void:
	done.call()


## done(lobby_id: String), "" on failure. `public` lobbies can be found by
## search; the others only by their ID.
func create_lobby(_bucket: String, _attrs: Dictionary, _public: bool, _max_members: int, done: Callable) -> void:
	done.call("")


## Lobbies in `bucket` whose attributes match every key/value of `filter`.
## done(lobbies: Array).
func search_lobbies(_bucket: String, _filter: Dictionary, _max_results: int, done: Callable) -> void:
	done.call([])


## done(ok: bool, owner: String, error: String); error is "gone", "full" or
## "failed".
func join_lobby(_lobby_id: String, done: Callable) -> void:
	done.call(false, "", "failed")


func leave_lobby(_lobby_id: String) -> void:
	pass


## Closes a lobby we own; its members get lobby_closed.
func destroy_lobby(_lobby_id: String) -> void:
	pass


## Opens our end of the P2P link with `peer` on `socket`: the host listens
## and accepts only `peer`, the guest connects to the host. Packets sent
## before the link is up wait until it is.
func p2p_open(_peer: String, _socket: String, _as_host: bool) -> void:
	pass


## Reliable, ordered. False when EOS refused the packet.
func p2p_send(_peer: String, _socket: String, _bytes: PackedByteArray) -> bool:
	return false


## Every packet that has arrived since the last call:
## [{peer: String, socket: String, bytes: PackedByteArray}].
func p2p_receive() -> Array:
	return []


func p2p_close(_peer: String, _socket: String) -> void:
	pass
