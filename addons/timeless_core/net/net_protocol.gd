class_name NetProtocol
extends RefCounted
## Messages between two players' devices (framework §9), version 1. The same
## messages go over every transport: ENet on local Wi-Fi, EOS P2P online.
## Each message is a Dictionary {"t": Msg, ...}, sent as Godot's binary
## variant encoding without objects, and checked field by field on arrival:
## the other side is never trusted.

const VERSION := 1
const MAX_BYTES := 16384

enum Msg {
	HELLO = 1,      # proto, build, title, name, match_id, have (moves the guest already has)
	SETUP,          # rule_set, fingerprint, host_side, seed, match_id, kind, turn_s, moves
	READY,          # (guest has built the match)
	MOVE,           # seq, move, hash
	RESYNC_REQ,     # (asks the host for the full move list)
	RESYNC,         # moves
	UNDO_REQ,       # (take back my last move?)
	UNDO_RESP,      # ok
	DRAW_OFFER,
	DRAW_RESP,      # ok
	RESIGN,         # reason (MatchSession.Ending)
	PING,           # t
	PONG,           # t
	REMATCH_REQ,
	REMATCH_RESP,   # ok
	EMOTE,          # id
	BYE,            # leaving on purpose
}

## Required fields and their types, per message.
const FIELDS := {
	Msg.HELLO: {"proto": TYPE_INT, "build": TYPE_STRING, "title": TYPE_STRING, "name": TYPE_DICTIONARY,
		"match_id": TYPE_STRING, "have": TYPE_INT},
	Msg.SETUP: {"rule_set": TYPE_STRING, "fingerprint": TYPE_INT, "host_side": TYPE_INT, "seed": TYPE_INT,
		"match_id": TYPE_STRING, "kind": TYPE_INT, "turn_s": TYPE_INT, "moves": TYPE_ARRAY},
	Msg.READY: {},
	Msg.MOVE: {"seq": TYPE_INT, "move": TYPE_PACKED_INT32_ARRAY, "hash": TYPE_INT},
	Msg.RESYNC_REQ: {},
	Msg.RESYNC: {"moves": TYPE_ARRAY},
	Msg.UNDO_REQ: {},
	Msg.UNDO_RESP: {"ok": TYPE_BOOL},
	Msg.DRAW_OFFER: {},
	Msg.DRAW_RESP: {"ok": TYPE_BOOL},
	Msg.RESIGN: {"reason": TYPE_INT},
	Msg.PING: {"t": TYPE_INT},
	Msg.PONG: {"t": TYPE_INT},
	Msg.REMATCH_REQ: {},
	Msg.REMATCH_RESP: {"ok": TYPE_BOOL},
	Msg.EMOTE: {"id": TYPE_INT},
	Msg.BYE: {},
}


static func make(type: Msg, fields := {}) -> Dictionary:
	var d := fields.duplicate()
	d["t"] = type
	return d


static func encode(msg: Dictionary) -> PackedByteArray:
	return var_to_bytes(msg)


## The message, or {} if the bytes aren't a valid version-1 message.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8 or bytes.size() > MAX_BYTES:
		return {}
	var v: Variant = bytes_to_var(bytes)  # never decodes objects
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var msg: Dictionary = v
	if typeof(msg.get("t")) != TYPE_INT or not FIELDS.has(msg.t):
		return {}
	var spec: Dictionary = FIELDS[msg.t]
	for key in spec:
		if typeof(msg.get(key)) != spec[key]:
			return {}
	if msg.t == Msg.SETUP or msg.t == Msg.RESYNC:
		if not _valid_moves(msg.moves):
			return {}
	if msg.t == Msg.MOVE and (msg.move.size() < 2 or msg.move.size() > 64):
		return {}
	return msg


static func _valid_moves(list: Array) -> bool:
	if list.size() > 2000:
		return false
	for m in list:
		if typeof(m) != TYPE_PACKED_INT32_ARRAY or m.size() < 2 or m.size() > 64:
			return false
	return true


static func moves_to_wire(moves: Array[PackedInt32Array]) -> Array:
	var out: Array = []
	for m in moves:
		out.append(PackedInt32Array(m))
	return out
