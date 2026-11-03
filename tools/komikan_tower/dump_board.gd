extends SceneTree
## Writes the Komikan board (HuntBoards.komikan_matus) and its start position
## to tools/komikan_tower/board.json for make_header.py:
##   godot --headless --path . -s res://tools/komikan_tower/dump_board.gd


func _initialize() -> void:
	var r := HuntRuleSets.komikan()
	var b: BoardDef = r.board
	var pts := []
	for i in b.point_count():
		pts.append({"id": i, "x": b.positions[i].x, "y": b.positions[i].y, "rank": b.ranks[i],
			"adj": Array(b.adj[i]), "over": Array(b.jump_over[i]), "land": Array(b.jump_land[i])})
	var out := {"points": pts, "hunter": Array(r.hunter_start), "prey": Array(r.prey_start)}
	var f := FileAccess.open("res://tools/komikan_tower/board.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("wrote res://tools/komikan_tower/board.json")
	quit()
