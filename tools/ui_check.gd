extends SceneTree
## Checks the interface in every language at one screen shape (run it once
## per shape, with --resolution and --shape=name): each menu screen,
## the in-game display, the result card, the questions and toast, and every
## How to play step. A check fails when a visible control reaches outside the
## screen (or, inside a scrolling area, outside it sideways), or is squeezed
## below the size its text needs.
##   xvfb-run -a -s "-screen 0 1400x1400x24" godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --resolution 540x1200 -s res://tools/ui_check.gd -- --shape=phone_portrait \
##     [--shots=DIR] [--langs=en,de] [--screens=menu,hud]
## Shapes used: phone_portrait 540x1200, phone_landscape 1200x540,
## tablet_portrait 768x1024, tablet_landscape 1024x768.
## With --shots, saves a picture of every check for the languages in --shot-langs
## (default en,de,ja) on phone sizes. Exits non-zero when anything overflows.

const GreyboxScript := preload("res://scenes/greybox/greybox.gd")
const MENU_SCREENS := ["home", "vs_ai", "pass", "nearby", "nearby_host", "nearby_wait", "nearby_join",
	"online", "friend", "friend_setup", "friend_join", "quick", "connecting", "error", "confirm_leave",
	"origins", "pause"]

var game: Node3D
var langs: Array = []
var shots_dir := ""
var shot_langs := ["en", "de", "ja"]
var shape := "phone_portrait"
var only_screens: Array = []
var jobs: Array = []        # [shape, unused, lang, screen]
var job: Array = []
var wait := 0
var phase := "boot"
var issues: Array[String] = []
var checked := 0
var _cur_lang := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
		elif arg.begins_with("--langs="):
			langs = Array(arg.substr(8).split(","))
		elif arg.begins_with("--shot-langs="):
			shot_langs = Array(arg.substr(13).split(","))
		elif arg.begins_with("--shape="):
			shape = arg.substr(8)
		elif arg.begins_with("--screens="):
			only_screens = Array(arg.substr(10).split(","))
	if langs.is_empty():
		for entry in L10n.LANGUAGES:
			langs.append(entry[0])
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	game.autosave = false
	root.add_child(game)


func _screens() -> Array:
	var list: Array = []
	for s in MENU_SCREENS:
		list.append("menu:" + s)
	list.append_array(["hud", "result", "dialog:draw", "dialog:undo", "dialog:resign", "toast"])
	var steps := HuntTutorials.build(game.rules) if game.rules else []
	for i in steps.size():
		list.append("tutorial:%d" % i)
	return list


func _process(_delta: float) -> bool:
	match phase:
		"boot":
			wait += 1
			if wait < 3:
				return false
			game.menu.close()
			game.mode = GreyboxScript.Mode.HOTSEAT
			game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
			game.new_game()
			_play_some_moves()
			# The interface is what's checked: hide the 3D board so frames are quick.
			game._board_root.visible = false
			for lang in langs:
				for screen in _screens():
					if only_screens.is_empty() or screen.get_slice(":", 0) in only_screens or screen in only_screens:
						jobs.append([shape, Vector2i.ZERO, lang, screen])
			phase = "next"
		"next":
			if jobs.is_empty():
				return _finish()
			job = jobs.pop_front()
			if job[2] != _cur_lang:
				_cur_lang = job[2]
				TranslationServer.set_locale(job[2])
				SeriesTheme.apply_locale()
			wait = 0
			phase = "settle"
		"settle":
			wait += 1
			if wait == 2:
				_setup(job[3])
			if wait < 5:
				return false
			_check("%s/%s/%s" % [job[0], job[2], job[3]])
			if shots_dir != "" and job[2] in shot_langs and job[0].begins_with("phone"):
				root.get_texture().get_image().save_png(shots_dir.path_join("%s_%s_%s.png" % [job[0], job[2], job[3].replace(":", "-")]))
			_teardown(job[3])
			phase = "next"
	return false


## A position with pieces on the board, a capture and a move list.
func _play_some_moves() -> void:
	var s: HuntState = game.state
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		var moves := s.legal_moves()
		if moves.is_empty():
			break
		var caps: Array = moves.filter(func(m: PackedInt32Array) -> bool: return HuntState.captures_in(m) > 0)
		var pick: PackedInt32Array = caps[0] if not caps.is_empty() else moves[rng.randi_range(0, moves.size() - 1)]
		game.session.commit(pick, s.side)
	game._stop_tween()
	game._anim_queue.clear()
	game._animating = false
	game._sync_pieces()
	game._after_move()


func _setup(screen: String) -> void:
	if screen.begins_with("menu:"):
		game.menu.open(screen.substr(5))
	elif screen == "hud":
		game.menu.close()
		game._hud.refresh()
	elif screen == "result":
		game.menu.close()
		game.status = HuntState.Status.HUNTER_WIN
		game._hud.refresh()
	elif screen.begins_with("dialog:"):
		game.menu.close()
		var what := screen.substr(7)
		if what == "resign":
			game._match_ui.ask_resign()
		else:
			game._match_ui._on_asked(what)
	elif screen == "toast":
		game.menu.close()
		game._match_ui._on_background_found()
	elif screen.begins_with("tutorial:"):
		game.menu.close()
		var i := int(screen.substr(9))
		if not game.tutorial_active:
			game.start_tutorial()
			game._tutorial._run += 1  # no timed playback
		game._tutorial._index = i
		game._tutorial._fill_card()


func _teardown(screen: String) -> void:
	if screen == "result":
		game.status = HuntState.Status.ONGOING
		game._hud.refresh()
	elif screen.begins_with("dialog:"):
		game._match_ui._dialog.visible = false
	elif screen == "toast":
		game._match_ui._hide_toast()
	elif screen.begins_with("tutorial:"):
		if int(screen.substr(9)) == HuntTutorials.build(game.rules).size() - 1 or jobs.is_empty() or not str(jobs[0][3]).begins_with("tutorial:"):
			game._tutorial.stop(false)
			_play_some_moves_again()


func _play_some_moves_again() -> void:
	# Closing the walkthrough brings the game back as it was.
	game._hud.refresh()


func _check(label: String) -> void:
	checked += 1
	if not label.ends_with("/result") and not label.contains("/menu:") and not label.contains("/dialog:"):
		_check_hud_overlap(label)
	var view := root.get_visible_rect()
	for layer in [game.menu, game._hud, game._match_ui, game._tutorial]:
		for c: Control in layer.find_children("*", "Control", true, false):
			if not c.is_visible_in_tree() or c.size.x < 1.0 or c.size.y < 1.0:
				continue
			var r := c.get_global_rect()
			var scroll := _scroll_parent(c)
			var bad := ""
			if scroll:
				var b := scroll.get_global_rect()
				if r.position.x < b.position.x - 1.0 or r.end.x > b.end.x + 1.0:
					bad = "outside its scroll area sideways"
			elif r.position.x < view.position.x - 1.0 or r.position.y < view.position.y - 1.0 \
					or r.end.x > view.end.x + 1.0 or r.end.y > view.end.y + 1.0:
				bad = "off screen"
			var need := c.get_combined_minimum_size()
			if bad == "" and (c.size.x + 0.5 < need.x or c.size.y + 0.5 < need.y):
				bad = "squeezed (%.0fx%.0f, needs %.0fx%.0f)" % [c.size.x, c.size.y, need.x, need.y]
			if bad != "":
				issues.append("%s: %s %s \"%s\" %s rect %s, screen %s" % [label, c.get_class(), c.name, _text_of(c), bad, r, view.size])


## The display's pieces (corner panels, banner, hint, buttons) must not
## overlap each other.
func _check_hud_overlap(label: String) -> void:
	var hud: Control = game._hud._root
	if hud == null or not hud.is_visible_in_tree():
		return
	var parts: Array[Control] = []
	for c in hud.get_children():
		if c is Control and c.is_visible_in_tree() and c != game._hud._result and c.size.x > 1.0:
			parts.append(c)
	if game.tutorial_active and game._tutorial._card.is_visible_in_tree():
		parts.append(game._tutorial._card)
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			var a := parts[i].get_global_rect().grow(-1.0)
			var b := parts[j].get_global_rect().grow(-1.0)
			if a.intersects(b):
				issues.append("%s: %s %s overlaps %s %s rect %s / %s" % [label, parts[i].get_class(), _text_inside(parts[i]),
					parts[j].get_class(), _text_inside(parts[j]), a, b])


func _text_inside(c: Control) -> String:
	for l in c.find_children("*", "Label", true, false):
		if (l as Label).text != "":
			return "\"%s\"" % (l as Label).text.left(30)
	return ""


func _scroll_parent(c: Node) -> ScrollContainer:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _text_of(c: Control) -> String:
	if c is Label or c is Button or c is LineEdit:
		return str(c.text).left(40)
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text().left(40)
	return ""


func _finish() -> bool:
	TranslationServer.set_locale("en")
	# Only the first problem for each control on each screen shape and language.
	var seen := {}
	var unique: Array[String] = []
	for i in issues:
		var key := i.get_slice(" rect ", 0)
		if not seen.has(key):
			seen[key] = true
			unique.append(i)
	for i in unique:
		print("FAIL " + i)
	print("ui check (%s, %s): %d screens checked, %d problems" % [shape, root.get_visible_rect().size, checked, unique.size()])
	quit(1 if not unique.is_empty() else 0)
	return true
