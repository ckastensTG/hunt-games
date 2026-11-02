extends SceneTree
## Headless smoke test for the greybox scene.
##   godot --headless --fixed-fps 60 --path . -s res://tools/smoke_greybox.gd
## 1. Hotseat clicks: a goat placement and a tiger step go through the same
##    path as mouse clicks.
## 2. AI vs AI (Novice) for every rule set until the game ends or 60 plies.
## Exits non-zero on any failure.

const MAX_PLIES := 60
const GreyboxScript := preload("res://scenes/greybox/greybox.gd")

var game: Node3D
var queue: Array = []
var phase := ""
var current := ""
var frames := 0
var failures: Array[String] = []


func _initialize() -> void:
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	root.add_child(game)
	phase = "clicks"


func _process(_delta: float) -> bool:
	frames += 1
	if Time.get_ticks_msec() > 6 * 60 * 1000:
		failures.append("timed out in %s %s" % [phase, current])
		return _done()
	match phase:
		"clicks":
			return _clicks()
		"ai":
			return _ai()
	return false


var _click_step := 0


func _clicks() -> bool:
	if game._animating:
		return false
	var b: BoardDef = game.rules.board
	match _click_step:
		0:
			game.mode = GreyboxScript.Mode.HOTSEAT
			game.new_game()
			game._on_point_clicked(b.point_at(Vector2(2, 0)))
			_click_step = 1
		1:
			if game.history.size() != 1:
				failures.append("goat placement click did not commit")
			game._on_point_clicked(b.point_at(Vector2(0, 0)))
			game._on_point_clicked(b.point_at(Vector2(1, 1)))
			_click_step = 2
		2:
			if game.history.size() != 2:
				failures.append("tiger step clicks did not commit")
			game.undo()
			if game.history.size() != 1:
				failures.append("hotseat undo")
			# A two-jump chain on the Adugo board: c3 x c4 -> c5 (apex) x c6 -> c7.
			var adugo := HuntRuleSets.adugo()
			var ab := adugo.board
			var custom := adugo.copy_with({
				"hunter_start": PackedInt32Array([ab.point_at(Vector2(2, 2))]),
				"prey_start": PackedInt32Array([ab.point_at(Vector2(2, 3)), ab.point_at(Vector2(2, 5)), ab.point_at(Vector2(0, 0))]),
			})
			game._rule_set_id = HuntRuleSets.ADUGO
			game.rules = custom
			game.state = HuntState.create(custom)
			game.history.clear()
			game._build_board()
			game._sync_pieces()
			game._after_move()
			game._on_point_clicked(ab.point_at(Vector2(2, 2)))
			game._on_point_clicked(ab.point_at(Vector2(2, 4)))
			if game.history.size() != 0:
				failures.append("chain committed too early")
			game._on_point_clicked(ab.point_at(Vector2(2, 6)))
			_click_step = 3
		3:
			if game.history.size() != 1 or HuntState.captures_in(game.history[0]) != 2:
				failures.append("chain clicks: expected one 2-capture move, got %s" % [game.history])
			_check_lines_follow_points()
			print("clicks: ok (%d failures so far)" % failures.size())
			queue = HuntRuleSets.ALL.duplicate()
			queue.append("komikan_dogs_first")
			phase = "ai"
			_next_game()
	return false


func _next_game() -> void:
	if queue.is_empty():
		phase = "done"
		return
	current = queue.pop_front()
	game.mode = GreyboxScript.Mode.AI_VS_AI
	game.level = 0
	if current == "komikan_dogs_first":
		game._rule_set_id = HuntRuleSets.KOMIKAN
		game._komikan_dogs_first = true
	else:
		game._rule_set_id = current
		game._komikan_dogs_first = false
	game.new_game()


func _ai() -> bool:
	if game.status != HuntState.Status.ONGOING or game.history.size() >= MAX_PLIES:
		if game._animating or game._ai_task >= 0:
			return false
		var st: HuntState = game.state
		print("%-28s plies %3d  captured %2d  status %d  reason %d" % [current, game.history.size(), st.captured, game.status, st.last_reason])
		if st.hash_key != st.compute_hash():
			failures.append("%s: hash drift" % current)
		_next_game()
		if phase == "done":
			return _done()
	return false


func _done() -> bool:
	for f in failures:
		print("FAIL " + f)
	print("smoke: %s" % ("ok" if failures.is_empty() else "%d failures" % failures.size()))
	game._stop_ai()
	quit(1 if not failures.is_empty() else 0)
	return true


## Regression: the drawn lines must sit on the board's real lines after the
## board is rebuilt while turned for a prey player.
func _check_lines_follow_points() -> void:
	game.mode = GreyboxScript.Mode.HUMAN_PREY
	for id in [HuntRuleSets.ADUGO, HuntRuleSets.KOMIKAN]:
		game._rule_set_id = id
		game.new_game()
		game.new_game()  # second build happens with the board already turned
		var board: BoardDef = game.rules.board
		var seen := 0
		for c in game._board_root.get_children():
			if c.is_queued_for_deletion() or not c.has_meta("segment"):
				continue
			seen += 1
			var ab: Vector2i = c.get_meta("segment")
			var pa: Vector3 = game.to_world(board.positions[ab.x])
			var pb: Vector3 = game.to_world(board.positions[ab.y])
			var mid := (pa + pb) / 2.0
			var axis: Vector3 = -c.transform.basis.z
			if not (Vector2(c.position.x, c.position.z).is_equal_approx(Vector2(mid.x, mid.z)) and absf(axis.normalized().dot((pb - pa).normalized())) > 0.999):
				failures.append("%s: line %s drawn off the board's line" % [id, ab])
				return
		if seen != board.line_segment_count():
			failures.append("%s: drew %d lines, board has %d" % [id, seen, board.line_segment_count()])
	game.mode = GreyboxScript.Mode.HOTSEAT

