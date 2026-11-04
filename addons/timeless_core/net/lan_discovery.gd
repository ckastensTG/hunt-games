class_name LanDiscovery
extends RefCounted
## Finds games hosted on the same Wi-Fi (framework §9). A host broadcasts a
## small beacon once a second; joiners listen and list what they hear.
##
## UDP broadcast works on desktop and Android. iOS needs Bonjour (Apple's
## multicast entitlement is restricted, bible §5.1): when the native
## "TimelessNearby" plugin is present (NSD on Android, Bonjour on iOS) it's
## used instead. Without either, players type the host's code (JoinCode).

signal hosts_changed

const PORT := 45871
const BEACON_MS := 1000
const EXPIRE_MS := 4000
const MAGIC := "TGNB"

var _beacon := {}
var _sender: PacketPeerUDP
var _listener: PacketPeerUDP
var _last_beacon := 0
var _hosts := {}  # "ip" -> {info..., "ip", "seen"}
var _listen_port := PORT
var _dest := "255.255.255.255"
var _dest_port := PORT


## For tests: send to a given address and port instead of broadcasting.
func set_destination(address: String, port: int) -> void:
	_dest = address
	_dest_port = port


func advertise(info: Dictionary) -> void:
	_beacon = info.duplicate()
	_beacon["magic"] = MAGIC
	if _sender == null:
		_sender = PacketPeerUDP.new()
		_sender.set_broadcast_enabled(true)
		_sender.set_dest_address(_dest, _dest_port)
	_last_beacon = -BEACON_MS


func stop_advertising() -> void:
	_beacon = {}
	if _sender != null:
		_sender.close()
		_sender = null


func listen(port := PORT) -> bool:
	stop_listening()
	_listen_port = port
	_listener = PacketPeerUDP.new()
	if _listener.bind(port) != OK:
		_listener = null
		return false
	return true


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	_hosts.clear()


## Games heard recently, newest first: {title, rule_set, name, code, ip, ...}.
func hosts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ip in _hosts:
		out.append(_hosts[ip])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.seen > b.seen)
	return out


func poll(now_ms := -1) -> void:
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	if _sender != null and not _beacon.is_empty() and now - _last_beacon >= BEACON_MS:
		_last_beacon = now
		_sender.put_packet(var_to_bytes(_beacon))
	if _listener == null:
		return
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var bytes := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		var v: Variant = bytes_to_var(bytes) if bytes.size() < 1024 else null
		if typeof(v) != TYPE_DICTIONARY or v.get("magic") != MAGIC:
			continue
		var info: Dictionary = v
		info["ip"] = ip
		info["seen"] = now
		if not _hosts.has(ip):
			changed = true
		_hosts[ip] = info
	for ip in _hosts.keys():
		if now - int(_hosts[ip].seen) > EXPIRE_MS:
			_hosts.erase(ip)
			changed = true
	if changed:
		hosts_changed.emit()
