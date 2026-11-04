class_name ENetTransport
extends NetTransport
## Local Wi-Fi play over ENet (reliable, ordered). The host listens on PORT
## and takes one guest; the guest connects to the host's address.

const PORT := 45870
const CHANNELS := 1

var _conn: ENetConnection
var _peer: ENetPacketPeer
var _host_address := ""
var _port := PORT


static func host(port := PORT) -> ENetTransport:
	var t := ENetTransport.new()
	t.is_host = true
	t._port = port
	t._conn = ENetConnection.new()
	if t._conn.create_host_bound("*", port, 1, CHANNELS) != OK:
		return null
	return t


static func join(address: String, port := PORT) -> ENetTransport:
	var t := ENetTransport.new()
	t._host_address = address
	t._port = port
	t._connect()
	return t


func _connect() -> void:
	if _conn != null:
		_conn.destroy()
	_conn = ENetConnection.new()
	if _conn.create_host(1, CHANNELS) != OK:
		_conn = null
		return
	_peer = _conn.connect_to_host(_host_address, _port, CHANNELS)


func send(bytes: PackedByteArray) -> void:
	if is_open():
		_peer.send(0, bytes, ENetPacketPeer.FLAG_RELIABLE)


func poll() -> void:
	if _conn == null:
		return
	for _i in 64:
		if _conn == null:
			break  # closed while handling a packet (a BYE)
		var ev: Array = _conn.service(0)
		var type: int = ev[0]
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = ev[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				if is_host and _peer != null and _peer != peer and _peer.is_active():
					peer.peer_disconnect()  # one guest only
				else:
					_peer = peer
					peer.set_timeout(0, 4000, 8000)
					connected.emit()
			ENetConnection.EVENT_DISCONNECT:
				if peer == _peer:
					_peer = null
					disconnected.emit()
			ENetConnection.EVENT_RECEIVE:
				var bytes := peer.get_packet()
				if peer == _peer:
					packet.emit(bytes)


func close() -> void:
	if _peer != null and _peer.is_active() and _conn != null:
		# Let what's queued (a BYE) arrive before hanging up: on a hard
		# disconnect ENet drops it on the other side. At most ~0.2 s.
		_peer.peer_disconnect_later()
		var until := Time.get_ticks_msec() + 200
		while Time.get_ticks_msec() < until:
			var ev: Array = _conn.service(20)
			if ev[0] == ENetConnection.EVENT_ERROR or (ev[0] == ENetConnection.EVENT_DISCONNECT and ev[1] == _peer):
				break
		if _peer.is_active():
			_peer.peer_disconnect_now()
	_peer = null
	if _conn != null:
		_conn.destroy()
		_conn = null


func is_open() -> bool:
	return _peer != null and _peer.get_state() == ENetPacketPeer.STATE_CONNECTED


func can_reconnect() -> bool:
	return not is_host


func reconnect() -> void:
	if not is_host:
		_connect()
