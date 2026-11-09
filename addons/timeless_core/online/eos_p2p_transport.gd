class_name EOSP2PTransport
extends NetTransport
## The link to the other player over EOS P2P (framework §9), relayed by Epic
## when a direct connection isn't possible. It reports a drop (disconnected)
## and the return (connected), and NetMatch resyncs. EOS restores a briefly
## interrupted link by itself; a link EOS closed (it timed out while a phone
## was off Wi-Fi, or the other side closed it) stays down, so each side opens
## a fresh socket (can_reconnect / reconnect): the host listens again, and
## the guest connects again, also when a drop isn't restored after
## REOPEN_AFTER_MS, every REOPEN_EVERY_MS until it works. Device test
## 2026-11-08: before this, a link closed by a 10 s Wi-Fi drop never came back.
##
## EOS packets are at most EOSApi.MAX_PACKET bytes, and a resync of a long
## game is bigger, so each message is cut into chunks with a 4-byte header
## (message id: 2 bytes, chunk index, chunk count) and joined again here.
## EOSOnlineBackend routes arriving packets to deliver() and the link events
## to on_link() / on_closed().

const HEADER := 4
const MAX_CHUNKS := 255
## A drop EOS hasn't restored after this long is opened again by the guest.
const REOPEN_AFTER_MS := 8000
const REOPEN_EVERY_MS := 8000

var api: EOSApi
var peer := ""
var socket := ""

var _open := true
var _lost := false
## EOS closed the link (not us): it won't come back by itself.
var _peer_closed := false
var _lost_at := 0
var _reopened_at := -REOPEN_EVERY_MS
var _announce := true
var _next_id := 0
var _parts := {}                       # message id -> Array of chunks
var _inbox: Array[PackedByteArray] = []


func _init(eos: EOSApi, peer_id: String, socket_name: String, as_host: bool) -> void:
	api = eos
	peer = peer_id
	socket = socket_name
	is_host = as_host
	api.p2p_open(peer, socket, as_host)


func key() -> String:
	return peer + "|" + socket


func send(bytes: PackedByteArray) -> void:
	if not _open:
		return
	var room := EOSApi.MAX_PACKET - HEADER
	var count := maxi(1, ceili(bytes.size() / float(room)))
	if count > MAX_CHUNKS:
		push_error("EOSP2PTransport: message of %d bytes is too big" % bytes.size())
		return
	var id := _next_id
	_next_id = (_next_id + 1) % 65536
	for i in count:
		var chunk := PackedByteArray([id & 0xff, id >> 8, i, count])
		chunk.append_array(bytes.slice(i * room, (i + 1) * room))
		api.p2p_send(peer, socket, chunk)


## A packet from the other side, as EOS delivered it.
func deliver(raw: PackedByteArray) -> void:
	if not _open or raw.size() < HEADER:
		return
	var id := raw[0] | (raw[1] << 8)
	var index := raw[2]
	var count := raw[3]
	if count <= 1:
		_inbox.append(raw.slice(HEADER))
		return
	if index >= count:
		return
	var parts: Array = _parts.get(id, [])
	if parts.size() != count:
		parts = []
		parts.resize(count)
		_parts[id] = parts
	parts[index] = raw.slice(HEADER)
	for p in parts:
		if p == null:
			return
	var whole := PackedByteArray()
	for p in parts:
		whole.append_array(p)
	_parts.erase(id)
	_inbox.append(whole)


func poll() -> void:
	if not _open:
		return
	if _announce:
		# EOS holds packets until the link is up, so the match can start
		# talking (HELLO) at once.
		_announce = false
		connected.emit()
	while not _inbox.is_empty() and _open:
		packet.emit(_inbox.pop_front())


## The link went down for now (false) or came back (true).
func on_link(up: bool) -> void:
	if not _open:
		return
	if up and _lost:
		_lost = false
		_peer_closed = false
		connected.emit()
	elif not up and not _lost:
		_lost = true
		_lost_at = Time.get_ticks_msec()
		_parts.clear()
		disconnected.emit()


## EOS closed the link: the other side closed it, or EOS gave up on it (a
## phone off Wi-Fi too long). Down until opened again; a match that is over
## closes its own side (close()). The other side leaving on purpose says so
## first (NetMatch's BYE).
func on_closed() -> void:
	if not _open:
		return
	_peer_closed = true
	if not _lost:
		_lost = true
		_lost_at = Time.get_ticks_msec()
		_parts.clear()
		disconnected.emit()


## After EOS closed the link, both sides open a fresh socket (once per
## closing); the guest also tries again while the link stays down.
func can_reconnect() -> bool:
	if not _open or not _lost:
		return false
	if _peer_closed:
		return true
	var now := Time.get_ticks_msec()
	return not is_host and now - _lost_at >= REOPEN_AFTER_MS and now - _reopened_at >= REOPEN_EVERY_MS


func reconnect() -> void:
	if not can_reconnect():
		return
	_reopened_at = Time.get_ticks_msec()
	_peer_closed = false
	api.p2p_close(peer, socket)
	api.p2p_open(peer, socket, is_host)


func close() -> void:
	if _open:
		_open = false
		api.p2p_close(peer, socket)


func is_open() -> bool:
	return _open and not _lost


## Closed for good, by this side (a drop isn't closed: it may come back).
func is_closed() -> bool:
	return not _open
