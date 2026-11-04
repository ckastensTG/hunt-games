class_name JoinCode
extends RefCounted
## Short codes players read to each other (framework §9).
## - Nearby: the host's local IPv4 address as 7 letters/digits ("K7Q-4M2B"
##   style, Crockford base 32: no I, L, O or U, so it reads aloud cleanly).
##   The port is fixed (ENetTransport.PORT).
## - Online: a random code shown as "TG-7K4Q", stored as a lobby attribute.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


## "192.168.1.23" -> "60N-0G0Q" (7 symbols for 32 bits, grouped 3-4).
static func from_ipv4(address: String) -> String:
	var parts := address.split(".")
	if parts.size() != 4:
		return ""
	var v := 0
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return ""
		v = (v << 8) | int(p)
	var out := ""
	for _i in 7:
		out = ALPHABET[v & 31] + out
		v >>= 5
	return out.substr(0, 3) + "-" + out.substr(3)


## The address a nearby code stands for, or "" if it isn't one.
static func to_ipv4(code: String) -> String:
	var clean := normalize(code)
	if clean.length() != 7:
		return ""
	var v := 0
	for c in clean:
		v = (v << 5) | ALPHABET.find(c)
	if v >= (1 << 32):
		return ""
	return "%d.%d.%d.%d" % [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]


## Upper case, separators dropped, and the look-alike letters read the
## Crockford way (O -> 0, I/L -> 1). Unknown characters make it invalid.
static func normalize(code: String) -> String:
	var out := ""
	for ch in code.to_upper():
		if ch in [" ", "-", "_", "."]:
			continue
		var c := ch
		if c == "O":
			c = "0"
		elif c == "I" or c == "L":
			c = "1"
		if ALPHABET.find(c) < 0:
			return ""
		out += c
	return out


## A random online code, e.g. "TG-7K4Q". Four symbols: about a million codes,
## plenty for codes that live only while a host waits.
static func random_online(rng: RandomNumberGenerator) -> String:
	var out := ""
	for _i in 4:
		out += ALPHABET[rng.randi_range(0, 31)]
	return "TG-" + out


## "tg 7k4q", "TG-7K4Q", "7k4q" -> "TG-7K4Q"; "" if it can't be one.
static func normalize_online(code: String) -> String:
	var s := code.strip_edges().to_upper()
	if s.begins_with("TG"):
		s = s.substr(2)
	var clean := normalize(s)
	return "TG-" + clean if clean.length() == 4 else ""


## The device's address on the local network (private IPv4), or "".
static func local_ipv4() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or _is_172_private(a):
			return a
		if best == "":
			best = a
	return best


static func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var second := int(a.split(".")[1])
	return second >= 16 and second <= 31
