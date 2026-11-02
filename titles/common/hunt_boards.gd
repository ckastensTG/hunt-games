class_name HuntBoards
extends RefCounted
## The three hunt boards, built from the rules doc (claude/games/bagh-chal-jogo-da-onca-rules.md).
##
## Layout positions are Vector2(x = column, y = row): row 0 is the prey's side,
## and the Adugo / Komikan triangle hangs below row 4 at the apex (2, 4).
## Triangle points are T(h, x) = Vector2(2 + x, 4 + h). A point's rank is its
## row, so "forward" for Komikan's dogs means toward the triangle.

static var _cache := {}


## Bagh Chal: 25 points, 56 lines, 80 directed jumps.
static func alquerque_5x5() -> BoardDef:
	return _cached("alquerque_5x5", func() -> BoardDef:
		var b := BoardBuilder.new("alquerque_5x5")
		b.add_alquerque(5, 5)
		return b.finish())


## Jogo da Onça (Adugo): 31 points, 66 lines, 96 directed jumps.
## Triangle with one horizontal and one vertical line (Culin's design).
static func adugo_31() -> BoardDef:
	return _cached("adugo_31", func() -> BoardDef:
		var b := BoardBuilder.new("adugo_31")
		b.add_alquerque(5, 5)
		for p in [_t(1, -1), _t(1, 0), _t(1, 1), _t(2, -2), _t(2, 0), _t(2, 2)]:
			b.add_point(p, NAN, PackedStringArray(["den"]))
		b.add_line([Vector2(4, 2), Vector2(3, 3), _t(0, 0), _t(1, -1), _t(2, -2)])
		b.add_line([Vector2(0, 2), Vector2(1, 3), _t(0, 0), _t(1, 1), _t(2, 2)])
		b.add_line([Vector2(2, 0), Vector2(2, 1), Vector2(2, 2), Vector2(2, 3), _t(0, 0), _t(1, 0), _t(2, 0)])
		b.add_line([_t(1, -1), _t(1, 0), _t(1, 1)])
		b.add_line([_t(2, -2), _t(2, 0), _t(2, 2)])
		return b.finish())


## Komikan: 38 points, 79 lines, 116 directed jumps.
## Mátus 1918-19, Fig. 51 (redrawn by Depaulis 1998, Fig. 13).
static func komikan_matus() -> BoardDef:
	return _cached("komikan_matus", func() -> BoardDef:
		var b := BoardBuilder.new("komikan_matus")
		b.add_alquerque(5, 5)
		for h in [1.0, 1.5, 2.0]:
			for x in _matus_row(h):
				b.add_point(_t(h, x), NAN, PackedStringArray(["den"]))
		b.add_line([Vector2(4, 2), Vector2(3, 3), _t(0, 0), _t(1, -1), _t(1.5, -1.5), _t(2, -2)])
		b.add_line([Vector2(0, 2), Vector2(1, 3), _t(0, 0), _t(1, 1), _t(1.5, 1.5), _t(2, 2)])
		b.add_line([Vector2(2, 0), Vector2(2, 1), Vector2(2, 2), Vector2(2, 3), _t(0, 0), _t(1, 0), _t(1.5, 0), _t(2, 0)])
		b.add_line([_t(1, -1), _t(1.5, -1), _t(2, -1)])
		b.add_line([_t(1, 1), _t(1.5, 1), _t(2, 1)])
		for h in [1.0, 1.5, 2.0]:
			var row: Array = []
			for x in _matus_row(h):
				row.append(_t(h, x))
			b.add_line(row)
		return b.finish())


## Triangle point at height h above the apex, offset x from the center line.
static func _t(h: float, x: float) -> Vector2:
	return Vector2(2.0 + x, 4.0 + h)


static func _matus_row(h: float) -> Array:
	if h == 1.0:
		return [-1.0, 0.0, 1.0]
	if h == 1.5:
		return [-1.5, -1.0, 0.0, 1.0, 1.5]
	return [-2.0, -1.0, 0.0, 1.0, 2.0]


static func _cached(key: String, make: Callable) -> BoardDef:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]
