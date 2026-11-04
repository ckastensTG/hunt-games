extends SceneTree
## Headless smoke test for the greybox scene.
##   godot --headless --fixed-fps 60 --path . -s res://tools/smoke_greybox.gd
## 1. Hotseat clicks: a goat placement and a tiger step go through the same
##    path as mouse clicks.
## 2. AI vs AI (Novice) for every rule set until the game ends or 60 plies.
## 3. "How to play" for every rule set: every step shown and its moves
##    played on the board, then the walkthrough closed and the game back.
## 4. The interface in every launch language.
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
	game.autosave = false  # leave the player's saved game alone
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
		"tutorial":
			return _tutorial()
		"finish":
			if frames > _finish_at:
				return _done()
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
			game.history_start = game.state.clone()
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
		phase = "tutorial"
		queue = HuntRuleSets.ALL.duplicate()
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
		if game._animating or game.ai_thinking():
			return false
		var st: HuntState = game.state
		print("%-28s plies %3d  captured %2d  status %d  reason %d" % [current, game.history.size(), st.captured, game.status, st.last_reason])
		if st.hash_key != st.compute_hash():
			failures.append("%s: hash drift" % current)
		_next_game()
		if phase == "done":
			return _done()
	return false


var _finish_at := 0
var _tut_step := -1
var _tut_move := 0


func _tutorial() -> bool:
	if game._animating:
		return false
	var tut = game._tutorial
	if _tut_step < 0:
		if queue.is_empty():
			_languages()
			phase = "finish"
			_finish_at = frames + 3  # let the replaced interface free itself
			return false
		current = queue.pop_front()
		game.mode = GreyboxScript.Mode.HOTSEAT
		game._rule_set_id = current
		game._komikan_dogs_first = false
		game.new_game()
		game.start_tutorial()
		if not game.tutorial_active:
			failures.append("%s: walkthrough didn't start" % current)
			return false
		_tut_step = 0
		_tut_move = 0
		tut._run += 1  # drive the steps from here, not the timed playback
		game.tutorial_set_state(tut._steps[0].start)
		return false
	var step: Dictionary = tut._steps[_tut_step]
	if _tut_move < step.moves.size():
		game.tutorial_play(step.moves[_tut_move])
		_tut_move += 1
		return false
	var end: HuntState = step.end
	if game.state.hash_key != end.hash_key:
		failures.append("%s, step %d: the board ended somewhere else than the script" % [current, _tut_step + 1])
	_tut_step += 1
	_tut_move = 0
	if _tut_step >= tut._steps.size():
		tut.stop(false)
		if game.tutorial_active or game.history.size() != 0:
			failures.append("%s: closing the walkthrough didn't bring the game back" % current)
		print("%-28s how to play: %d steps ok" % [current, tut._steps.size()])
		_tut_step = -1
		return false
	tut._index = _tut_step
	tut._fill_card()
	game.tutorial_set_state(tut._steps[_tut_step].start)
	return false


## Switches the interface through every launch language: the rebuild must
## not error, and the turn banner must say something.
func _languages() -> void:
	for entry in L10n.LANGUAGES:
		TranslationServer.set_locale(entry[0])
		game._hud._build()
		if game._hud._turn.text.strip_edges() == "":
			failures.append("%s: empty turn banner" % entry[0])
	TranslationServer.set_locale("en")
	print("languages: %d checked" % L10n.LANGUAGES.size())


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

