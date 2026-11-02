class_name BoardBuilder
extends RefCounted
## Helper for authoring BoardDef resources in code.
##
## Points are addressed by layout position, so a title can describe a board
## the way it is drawn: add_alquerque(5, 5), then extra lines through
## Vector2 positions.

var board := BoardDef.new()
var _ids := {}  # Vector2 -> point id


func _init(board_id: String) -> void:
	board.id = board_id


## Adds a point (or returns the existing one at that position).
## Rank defaults to the row (y), so "forward" means "down the drawing".
func add_point(pos: Vector2, rank: float = NAN, tag_list: PackedStringArray = PackedStringArray()) -> int:
	var key := _key(pos)
	if _ids.has(key):
		var existing: int = _ids[key]
		for t in tag_list:
			_tag(existing, t)
		return existing
	var id := board.positions.size()
	board.positions.append(pos)
	board.ranks.append(pos.y if is_nan(rank) else rank)
	_ids[key] = id
	for t in tag_list:
		_tag(id, t)
	return id


func id_at(pos: Vector2) -> int:
	return _ids.get(_key(pos), -1)


## Adds a polyline through existing or new points, given by position.
## Lines may overlap earlier ones; shared segments are merged at build time.
func add_line(points: Array) -> void:
	var line := PackedInt32Array()
	for p in points:
		line.append(add_point(p))
	board.lines.append(line)


## An alquerque lattice: rows x cols points, orthogonal lines everywhere and
## diagonals through points where row + col is even. Tags "edge", "corner",
## "edge_center" and "center" are added.
func add_alquerque(rows: int, cols: int, origin := Vector2.ZERO) -> void:
	for r in rows:
		for c in cols:
			var tags := PackedStringArray()
			var on_edge := r == 0 or c == 0 or r == rows - 1 or c == cols - 1
			if on_edge:
				tags.append("edge")
			if (r == 0 or r == rows - 1) and (c == 0 or c == cols - 1):
				tags.append("corner")
			if on_edge and (r == rows / 2 or c == cols / 2) and not ((r == 0 or r == rows - 1) and (c == 0 or c == cols - 1)):
				tags.append("edge_center")
			if r == rows / 2 and c == cols / 2:
				tags.append("center")
			add_point(origin + Vector2(c, r), NAN, tags)
	for r in rows:
		var row_line: Array = []
		for c in cols:
			row_line.append(origin + Vector2(c, r))
		add_line(row_line)
	for c in cols:
		var col_line: Array = []
		for r in rows:
			col_line.append(origin + Vector2(c, r))
		add_line(col_line)
	# Down-right diagonals start on the top row or left column at even points.
	for start in _diagonal_starts(rows, cols, 1):
		_add_diagonal(rows, cols, start, Vector2i(1, 1), origin)
	# Down-left diagonals start on the top row or right column at even points.
	for start in _diagonal_starts(rows, cols, -1):
		_add_diagonal(rows, cols, start, Vector2i(1, -1), origin)


func finish() -> BoardDef:
	board.build()
	return board


func _diagonal_starts(rows: int, cols: int, dc: int) -> Array:
	var starts: Array = []
	for c in cols:
		starts.append(Vector2i(0, c))
	var side_col := 0 if dc == 1 else cols - 1
	for r in range(1, rows):
		starts.append(Vector2i(r, side_col))
	return starts.filter(func(s: Vector2i) -> bool: return (s.x + s.y) % 2 == 0)


func _add_diagonal(rows: int, cols: int, start: Vector2i, step: Vector2i, origin: Vector2) -> void:
	var pts: Array = []
	var p := start
	while p.x >= 0 and p.x < rows and p.y >= 0 and p.y < cols:
		pts.append(origin + Vector2(p.y, p.x))
		p += step
	if pts.size() >= 2:
		add_line(pts)


func _tag(id: int, tag: String) -> void:
	var group: PackedInt32Array = board.tags.get(tag, PackedInt32Array())
	if not group.has(id):
		group.append(id)
	board.tags[tag] = group


static func _key(pos: Vector2) -> Vector2i:
	# Quarter-unit grid keeps half-step positions (1.5) exact.
	return Vector2i(roundi(pos.x * 4.0), roundi(pos.y * 4.0))
