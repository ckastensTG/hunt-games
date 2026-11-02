class_name ZobristTable
extends RefCounted
## 64-bit Zobrist keys for hunt positions. The hash covers pieces, side to
## move, prey in reserve and prey captured, so positions before and after an
## irreversible move (placement, capture) can never collide. That lets one
## repetition counter serve the whole game.

const SEED := 0x7157_6A11

var piece := PackedInt64Array()     # index: point * 2 + (piece - 1)
var side_prey: int = 0              # xor-ed in when the prey side is to move
var reserve := PackedInt64Array()   # index: prey in reserve
var captured := PackedInt64Array()  # index: prey captured

static var _cache := {}


static func for_shape(points: int, prey_total: int) -> ZobristTable:
	var key := Vector2i(points, prey_total)
	if not _cache.has(key):
		_cache[key] = ZobristTable.new(points, prey_total)
	return _cache[key]


func _init(points: int, prey_total: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	piece.resize(points * 2)
	for i in piece.size():
		piece[i] = _rand64(rng)
	side_prey = _rand64(rng)
	reserve.resize(prey_total + 1)
	captured.resize(prey_total + 1)
	for i in prey_total + 1:
		reserve[i] = _rand64(rng)
		captured[i] = _rand64(rng)


static func _rand64(rng: RandomNumberGenerator) -> int:
	return (int(rng.randi()) << 32) ^ int(rng.randi())
