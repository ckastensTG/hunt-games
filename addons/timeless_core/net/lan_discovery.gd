class_name LanDiscovery
extends RefCounted
## Finds games hosted on the same Wi-Fi (framework §9). Two ways, used
## together:
##   - Beacons: a host broadcasts a small beacon once a second; joiners listen
##     and list what they hear. Works on desktop and most Android phones.
##   - Probes: a joiner asks every address of its own network directly (one
##     small unicast packet each, about every 1.5 s) and each host answers
##     with its beacon. iPhones and iPads can't send or hear broadcasts
##     without Apple's restricted multicast entitlement, but unicast to the
##     local network only needs the local-network permission the game already
##     asks for (NSLocalNetworkUsageDescription). Some Android phones also
##     filter broadcasts on Wi-Fi; probes get through there too.
## Probes cover each local IPv4 network as a /24 (up to 254 addresses: home
## routers, phone hotspots). On bigger networks, or when nothing is found,
## players type the host's code (JoinCode), which always works.
##
## Ports: joiners listen on PORT (beacons and answers arrive there); hosts
## listen on PROBE_PORT. Different ports, so two copies of the game on one
## computer can host and join.

signal hosts_changed

const PORT := 45871
const PROBE_PORT := 45872
const BEACON_MS := 1000
const PROBE_MS := 1500
const EXPIRE_MS := 4000
## A host answers the same joiner at most this often.
const ANSWER_MS := 500
const MAGIC := "TGNB"
const PROBE_MAGIC := "TGNP"
const BROADCAST := "255.255.255.255"

## Tools and tests that run on a shared network (the cloud machine) turn the
## sweep of the local network off; tests give their own targets instead.
static var sweep := true

var _beacon := {}
var _sender: PacketPeerUDP
var _listener: PacketPeerUDP
var _prober: PacketPeerUDP  # host: answers probes
var _last_beacon := 0
var _last_probe := 0
var _hosts := {}  # "ip" -> {info..., "ip", "seen"}
var _answered := {}  # "ip:port" -> ms
var _listen_port := PORT
var _dest := BROADCAST
var _dest_port := PORT
var _probe_port := PROBE_PORT
var _targets: Array = []
var _targets_set := false


## For tests: send beacons to a given address and port instead of
## broadcasting.
func set_destination(address: String, port: int) -> void:
	_dest = address
	_dest_port = port


## For tests: the port hosts listen on for probes (both sides use it).
func set_probe_port(port: int) -> void:
	_probe_port = port


## For tests: the addresses a joiner probes, instead of its own networks.
func set_probe_targets(addresses: Array) -> void:
	_targets = addresses.duplicate()
	_targets_set = true


func advertise(info: Dictionary) -> void:
	_beacon = info.duplicate()
	_beacon["magic"] = MAGIC
	if _sender == null:
		_sender = PacketPeerUDP.new()
		_sender.set_broadcast_enabled(true)
		_sender.set_dest_address(_dest, _dest_port)
	if _prober == null:
		_prober = PacketPeerUDP.new()
		if _prober.bind(_probe_port) != OK:
			# Another copy is hosting on this computer: beacons still go out.
			_prober = null
	_last_beacon = -BEACON_MS


func stop_advertising() -> void:
	_beacon = {}
	if _sender != null:
		_sender.close()
		_sender = null
	if _prober != null:
		_prober.close()
		_prober = null
	_answered.clear()


func listen(port := PORT) -> bool:
	stop_listening()
	_listen_port = port
	_listener = PacketPeerUDP.new()
	if _listener.bind(port) != OK:
		_listener = null
		return false
	_listener.set_broadcast_enabled(true)
	_last_probe = -PROBE_MS
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


## The addresses a joiner probes: every other address of each private IPv4
## network this device is on, taken as a /24, then the broadcast address.
static func probe_targets(local_addresses: Array) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for a in local_addresses:
		var s := str(a)
		if s.count(".") != 3 or not _is_private(s):
			continue
		var parts := s.split(".")
		var prefix := "%s.%s.%s." % [parts[0], parts[1], parts[2]]
		if seen.has(prefix):
			continue
		seen[prefix] = true
		for host in range(1, 255):
			var target := prefix + str(host)
			if target != s:
				out.append(target)
	out.append(BROADCAST)
	return out


static func _is_private(a: String) -> bool:
	if a.begins_with("192.168.") or a.begins_with("10."):
		return true
	if a.begins_with("172."):
		var second := int(a.split(".")[1])
		return second >= 16 and second <= 31
	return false


func poll(now_ms := -1) -> void:
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	if _sender != null and not _beacon.is_empty() and now - _last_beacon >= BEACON_MS:
		_last_beacon = now
		_sender.put_packet(var_to_bytes(_beacon))
	_answer_probes(now)
	if _listener == null:
		return
	if now - _last_probe >= PROBE_MS:
		_last_probe = now
		_send_probes()
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


## Joiner: one probe to each target, from the listening socket, so the
## answers come back to it. Sends that fail (no route, no permission yet, a
## broadcast on iOS) are simply skipped.
func _send_probes() -> void:
	if not _targets_set:
		if not sweep:
			return
		_targets = probe_targets(Array(IP.get_local_addresses()))
		_targets_set = true
	var probe := var_to_bytes({"magic": PROBE_MAGIC})
	for target in _targets:
		_listener.set_dest_address(str(target), _probe_port)
		_listener.put_packet(probe)


## Host: each probe gets the beacon back, at its sender's address and port.
func _answer_probes(now: int) -> void:
	if _prober == null:
		return
	while _prober.get_available_packet_count() > 0:
		var bytes := _prober.get_packet()
		var ip := _prober.get_packet_ip()
		var port := _prober.get_packet_port()
		if _beacon.is_empty() or bytes.size() > 64:
			continue
		var v: Variant = bytes_to_var(bytes)
		if typeof(v) != TYPE_DICTIONARY or v.get("magic") != PROBE_MAGIC:
			continue
		var key := "%s:%d" % [ip, port]
		if now - int(_answered.get(key, -ANSWER_MS)) < ANSWER_MS:
			continue
		_answered[key] = now
		_prober.set_dest_address(ip, port)
		_prober.put_packet(var_to_bytes(_beacon))
