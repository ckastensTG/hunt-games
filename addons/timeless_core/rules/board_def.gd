class_name BoardDef
extends Resource
## A board as points joined by lines.
##
## Lines are ordered point sequences (polylines). Two consecutive points on a
## line are adjacent; three consecutive points form a jump over the middle one.
## Nothing is derived from coordinates, so boards with uneven spacing (the
## Komikan triangle) or curved lines work the same way.

## Stable identifier, e.g. "alquerque_5x5".
@export var id: String = ""
## Layout position of each point (x = column, y = row). Used by the view and
## for diagrams; the rules never read it.
@export var positions: PackedVector2Array = PackedVector2Array()
## "Forward" axis for direction filters: a step is forward when the rank grows.
@export var ranks: PackedFloat32Array = PackedFloat32Array()
## Polylines of point ids.
@export var lines: Array[PackedInt32Array] = []
## Named point groups, e.g. "edge", "corner", "edge_center", "den".
@export var tags: Dictionary = {}

## Neighbours of each point, sorted.
var adj: Array[PackedInt32Array] = []
## For each point, parallel arrays of (over, land) pairs.
var jump_over: Array[PackedInt32Array] = []
var jump_land: Array[PackedInt32Array] = []

var _built := false


func point_count() -> int:
	return positions.size()


func is_built() -> bool:
	return _built


## Derives adjacency and jumps from the lines. Safe to call more than once.
func build() -> void:
	var n := positions.size()
	assert(ranks.size() == n, "BoardDef %s: ranks and positions differ in size" % id)
	var adj_sets: Array[Dictionary] = []
	var jump_sets: Array[Dictionary] = []
	for i in n:
		adj_sets.append({})
		jump_sets.append({})
	for line in lines:
		for k in range(line.size()):
			assert(line[k] >= 0 and line[k] < n, "BoardDef %s: bad point id %d" % [id, line[k]])
		for k in range(line.size() - 1):
			var a := line[k]
			var b := line[k + 1]
			assert(a != b, "BoardDef %s: repeated point on a line" % id)
			adj_sets[a][b] = true
			adj_sets[b][a] = true
		for k in range(line.size() - 2):
			var a := line[k]
			var o := line[k + 1]
			var b := line[k + 2]
			jump_sets[a][Vector2i(o, b)] = true
			jump_sets[b][Vector2i(o, a)] = true
	adj.clear()
	jump_over.clear()
	jump_land.clear()
	for i in n:
		var neighbours := PackedInt32Array(adj_sets[i].keys())
		neighbours.sort()
		adj.append(neighbours)
		var pairs: Array = jump_sets[i].keys()
		pairs.sort()
		var overs := PackedInt32Array()
		var lands := PackedInt32Array()
		for p: Vector2i in pairs:
			overs.append(p.x)
			lands.append(p.y)
		jump_over.append(overs)
		jump_land.append(lands)
	_built = true


## Number of distinct lines between adjacent points.
func line_segment_count() -> int:
	var total := 0
	for a in adj:
		total += a.size()
	return total / 2


## Number of directed jumps (from, over, land).
func jump_count() -> int:
	var total := 0
	for o in jump_over:
		total += o.size()
	return total


func tagged(tag: String) -> PackedInt32Array:
	return tags.get(tag, PackedInt32Array())


func has_tag(point: int, tag: String) -> bool:
	return tagged(tag).has(point)


## Point id at a layout position, or -1.
func point_at(pos: Vector2, epsilon := 0.001) -> int:
	for i in positions.size():
		if positions[i].distance_to(pos) <= epsilon:
			return i
	return -1
