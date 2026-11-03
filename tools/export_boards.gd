extends SceneTree
## Writes the hunt boards' geometry to tools/art/boards.json for the art
## generators (tools/art/make_board.py), so the engraved lines always match
## the rules' BoardDef.
##   godot --headless --path . -s res://tools/export_boards.gd


func _initialize() -> void:
	var out := {}
	for board in [HuntBoards.alquerque_5x5(), HuntBoards.adugo_31(), HuntBoards.komikan_matus()]:
		var pts := []
		for i in board.point_count():
			var tags := []
			for tag in board.tags:
				if board.has_tag(i, tag):
					tags.append(tag)
			pts.append({"pos": [board.positions[i].x, board.positions[i].y], "tags": tags})
		var segs := []
		for a in board.point_count():
			for b in board.adj[a]:
				if b > a:
					segs.append([a, b])
		out[board.id] = {"points": pts, "segments": segs}
	var f := FileAccess.open("res://tools/art/boards.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", false))
	f.close()
	print("wrote res://tools/art/boards.json")
	quit()
