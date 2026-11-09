class_name LoopbackTransport
extends NetTransport
## Two transports wired to each other in the same process: for tests and the
## simulated online mode. drop() and restore() simulate a lost connection.

var _other: WeakRef  # weak, so a pair doesn't keep itself alive
var _inbox: Array[PackedByteArray] = []
var _open := false
var _announced := false
var _dropped := false
var _quiet := false


static func pair() -> Array[LoopbackTransport]:
	var a := LoopbackTransport.new()
	var b := LoopbackTransport.new()
	a._other = weakref(b)
	b._other = weakref(a)
	a.is_host = true
	a._open = true
	b._open = true
	return [a, b]


func other() -> LoopbackTransport:
	return _other.get_ref() if _other != null else null


func send(bytes: PackedByteArray) -> void:
	var o := other()
	if _open and not _dropped and o != null and o._open and not o._dropped:
		o._inbox.append(bytes)


func poll() -> void:
	if not _open:
		return
	if not _announced and not _dropped:
		_announced = true
		connected.emit()
	while not _inbox.is_empty() and not _dropped:
		packet.emit(_inbox.pop_front())


func close() -> void:
	if not _open:
		return
	_open = false
	var o := other()
	if o != null and o._open:
		o._open = false
		o.disconnected.emit()


func is_open() -> bool:
	return _open and (not _dropped or _quiet)


## Simulates a dropped connection on both ends. `quiet`: packets are lost
## with no event either way, and come back the same way (as an EOS link can).
func drop(quiet := false) -> void:
	for t in [self, other()]:
		if t == null:
			continue
		if not t._dropped:
			t._dropped = true
			t._inbox.clear()
			if quiet:
				t._quiet = true
			else:
				t._announced = false
				t.disconnected.emit()


func restore() -> void:
	for t in [self, other()]:
		if t != null:
			t._dropped = false
			t._quiet = false
