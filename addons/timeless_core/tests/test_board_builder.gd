extends TestCase


func test_alquerque_5x5_counts() -> void:
	var b := BoardBuilder.new("t")
	b.add_alquerque(5, 5)
	var board := b.finish()
	check_eq(board.point_count(), 25, "points")
	check_eq(board.line_segment_count(), 56, "lines")
	check_eq(board.jump_count(), 80, "directed jumps")


func test_alquerque_degrees_and_tags() -> void:
	var b := BoardBuilder.new("t")
	b.add_alquerque(5, 5)
	var board := b.finish()
	var corner := board.point_at(Vector2(0, 0))
	var edge_mid := board.point_at(Vector2(2, 0))
	var center := board.point_at(Vector2(2, 2))
	var odd := board.point_at(Vector2(1, 0))  # row+col odd: no diagonals
	check_eq(board.adj[corner].size(), 3, "corner degree")
	check_eq(board.adj[edge_mid].size(), 5, "edge-center degree")
	check_eq(board.adj[center].size(), 8, "center degree")
	check_eq(board.adj[odd].size(), 3, "odd edge point degree")
	check_eq(board.tagged("corner").size(), 4, "corners")
	check_eq(board.tagged("edge_center").size(), 4, "edge centers")
	check_eq(board.tagged("edge").size(), 16, "edge points")
	check(board.has_tag(center, "center"), "center tag")


func test_overlapping_lines_merge() -> void:
	var b := BoardBuilder.new("t")
	b.add_line([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	b.add_line([Vector2(1, 0), Vector2(2, 0), Vector2(3, 0)])
	var board := b.finish()
	check_eq(board.line_segment_count(), 3, "segments")
	# Jumps only come from triples on one polyline: 0-1-2 and 1-2-3, both ways.
	check_eq(board.jump_count(), 4, "jumps")


func test_uneven_spacing_jumps_follow_lines() -> void:
	# A line with uneven spacing still yields straight jumps.
	var b := BoardBuilder.new("t")
	b.add_line([Vector2(0, 0), Vector2(0, 1), Vector2(0, 1.5), Vector2(0, 2)])
	var board := b.finish()
	var a := board.point_at(Vector2(0, 1))
	var o := board.point_at(Vector2(0, 1.5))
	var l := board.point_at(Vector2(0, 2))
	check(board.jump_over[a].has(o), "jump over half-step point")
	check_eq(board.jump_land[a][board.jump_over[a].find(o)], l, "landing")


func test_ranks_default_to_rows() -> void:
	var b := BoardBuilder.new("t")
	var p := b.add_point(Vector2(3, 5.5))
	var q := b.add_point(Vector2(0, 0), 9.0)
	var board := b.finish()
	check_eq(board.ranks[p], 5.5, "default rank")
	check_eq(board.ranks[q], 9.0, "explicit rank")
