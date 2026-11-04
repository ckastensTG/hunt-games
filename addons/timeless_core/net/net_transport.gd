class_name NetTransport
extends RefCounted
## A two-player link that carries NetProtocol messages (framework §9). The
## match code doesn't know which one it has: ENet on local Wi-Fi, EOS P2P
## online, or a loopback pair in tests and the simulated online mode.
## Call poll() every frame; it emits the signals.

signal connected
signal disconnected
signal packet(bytes: PackedByteArray)

## True on the side that created the game.
var is_host := false


func send(_bytes: PackedByteArray) -> void:
	pass


func poll() -> void:
	pass


func close() -> void:
	pass


func is_open() -> bool:
	return false


## Whether this side can try to restore a dropped link itself (the guest on
## ENet). EOS P2P reconnects on its own.
func can_reconnect() -> bool:
	return false


func reconnect() -> void:
	pass
