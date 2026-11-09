extends SceneTree
## Headless smoke test for the greybox scene.
##   godot --headless --fixed-fps 60 --path . -s res://tools/smoke_greybox.gd
## 1. Hotseat clicks: a goat placement and a tiger step go through the same
##    path as mouse clicks.
## 2. AI vs AI (Novice) for every rule set until the game ends or 60 plies.
## 3. "How to play" for every rule set: every step shown and its moves
##    played on the board, then the walkthrough closed and the game back.
## 4. The interface in every launch language.
## Ads run on the test stand-in (instant): no ad after the first finished
## game, one at the break after the second; one look free, the others after
## a rewarded video, built behind the loading screen. Undo only against the AI.
## Along the way, every Bagh Chal look is built and shows its move marks with
## the right shader (added light, or ink on pale boards) and loads its piece
## sounds and music; moves, captures and endings play the right sounds, and
## the music makes way for the end sting.
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
	AdService.backend_override = "sim"
	IAPService.backend_override = "sim"
	# Vibrations recorded instead of felt (and the Vibration switch shown).
	GameHaptics.recorder = []
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
		"quit":
			# Wall-clock time (frames are fixed-step here): sounds still
			# playing are let go on the audio thread's next mix.
			if Time.get_ticks_msec() >= _quit_at:
				quit(1 if not failures.is_empty() else 0)
	return false


var _click_step := 0


func _clicks() -> bool:
	if game._animating:
		return false
	var b: BoardDef = game.rules.board
	match _click_step:
		0:
			AdService.backend_override = ""
			IAPService.backend_override = ""
			(game.ads.backend as SimAdBackend).instant = true
			game.mode = GreyboxScript.Mode.HOTSEAT
			game.new_game()
			game.sfx.log_plays = true
			game._on_point_clicked(b.point_at(Vector2(2, 0)))
			_click_step = 1
		1:
			if game.history.size() != 1:
				failures.append("goat placement click did not commit")
			_check_sounds(["place"], "goat placed")
			game._on_point_clicked(b.point_at(Vector2(0, 0)))
			game._on_point_clicked(b.point_at(Vector2(1, 1)))
			_click_step = 2
		2:
			if game.history.size() != 2:
				failures.append("tiger step clicks did not commit")
			_check_sounds(["slide_tiger", "set_tiger"], "tiger step")
			game.undo()
			if game.history.size() != 2 or game.can_undo() or game._hud._undo.visible:
				failures.append("pass and play: no undo (history %d)" % game.history.size())
			game.session.undo(1)  # back to the tiger's turn for the checks below
			_check_looks()
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
			_check_sounds(["land", "land", "capture", "capture"], "two-jump chain (greybox wood)")
			# Endings: a loss for the player here, then an agreed draw.
			game.mode = GreyboxScript.Mode.HUMAN_PREY
			game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
			game.new_game()
			game.sfx.played.clear()
			game.session.resign(HuntState.PREY)
			_check_sounds(["lose"], "resigning against the AI")
			if not game.music.is_ducked():
				failures.append("the music didn't make way for the sting")
			game.new_game()
			game.sfx.played.clear()
			game.session.agree_draw()
			_check_sounds(["draw"], "an agreed draw")
			_check_undo_against_ai()
			_check_ads()
			_check_settings()
			_click_step = 4
		4:
			# The look picked after the video is built behind the loading
			# screen, which comes down once it's drawn.
			if game.look_loading():
				if game._loading == null:
					failures.append("looks: no loading screen while the look is built")
					game._look_pending = ""
				return false
			if game.current_style().id != "stone" or game._loading != null:
				failures.append("looks: stone after loading, and the loading screen gone")
			game.set_art_style(TitleConfig.free_look("bagh_chal"))
			game.mode = GreyboxScript.Mode.HOTSEAT
			_check_lines_follow_points()
			print("clicks: ok (%d failures so far)" % failures.size())
			queue = HuntRuleSets.ALL.duplicate()
			queue.append("komikan_dogs_first")
			phase = "ai"
			_next_game()
	return false


## Undo works against the AI: a goat placed, then taken back.
func _check_undo_against_ai() -> void:
	game.mode = GreyboxScript.Mode.HUMAN_PREY
	game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
	game.new_game()
	game.commit(game.state.legal_moves(false)[0])
	game._hud.refresh()
	if not game.can_undo() or not game._hud._undo.visible:
		failures.append("against the AI: Undo should be there")
	game._animating = false
	game.undo()
	if game.history.size() != 0:
		failures.append("against the AI: undo took back %d moves" % (1 - game.history.size()))


## Ads on the test stand-in: the cap (every 2nd finished game) at the Play
## again break, and the look unlock.
func _check_ads() -> void:
	var ads: AdService = game.ads
	var sim := ads.backend as SimAdBackend
	ads.policy = AdPolicy.new(Time.get_ticks_msec() - AdPolicy.MIN_GAP_MS - 1)
	var shown := sim.interstitials_shown
	game.mode = GreyboxScript.Mode.HUMAN_PREY
	game.new_game()
	game.session.resign(HuntState.PREY)
	game.session.resign(HuntState.PREY)  # the same game ending again doesn't count twice
	game.play_again()
	if sim.interstitials_shown != shown or game.status != HuntState.Status.ONGOING:
		failures.append("ads: no ad after the first game, straight into the next")
	game.session.resign(HuntState.PREY)
	game.play_again()
	if sim.interstitials_shown != shown + 1 or game.status != HuntState.Status.ONGOING:
		failures.append("ads: an ad after the second game, then the next game (%d shown)" % (sim.interstitials_shown - shown))
	game.mode = GreyboxScript.Mode.AI_VS_AI
	game.new_game()
	game.session.resign(HuntState.PREY)
	if ads.policy.games_since_ad != 0:
		failures.append("ads: AI vs AI games don't count")
	# Looks: one free, the rest after a video, for the session.
	var free := TitleConfig.free_look("bagh_chal")
	if game.look_locked(free) or not game.look_locked("stone") or game.choose_look("stone"):
		failures.append("looks: only %s is free" % free)
	ads.show_rewarded(func(r: int) -> void:
		if r == AdService.Reward.EARNED:
			ads.unlock_extras_for_session())
	if not game.choose_look("stone") or not game.look_loading() or game._loading == null:
		failures.append("looks: open after the video, behind the loading screen")
	# Remove ads on the purchase stand-in: no more ads, every look open, and
	# the in-game menu stops offering it.
	var iap: IAPService = game.iap
	if not iap.backend is SimIapBackend:
		failures.append("purchases: the test stand-in in test builds (%s)" % iap.backend.kind())
	else:
		var store := iap.backend as SimIapBackend
		store.instant = true
		store.store_path = "user://smoke_iap_store.cfg"
		iap.save_path = "user://smoke_purchases.cfg"
		iap._on_product_loaded(GreyboxScript.REMOVE_ADS, "US$1.99")
		ads.extras_unlocked_for_session = false
		game.menu.open("pause")
		var buy_text := L10n.t("Remove ads · %s") % "US$1.99"
		if not _menu_has_text(buy_text):
			failures.append("purchases: Remove ads with its price in the in-game menu")
		var got := []
		iap.buy(GreyboxScript.REMOVE_ADS, func(r: int) -> void: got.append(r))
		if got != [IAPService.Result.PURCHASED] or not ads.ads_removed or ads.ads_enabled():
			failures.append("purchases: Remove ads turns ads off (%s)" % [got])
		if game.look_locked("modern"):
			failures.append("purchases: every look open after Remove ads")
		if _menu_has_text(buy_text) or _menu_has_text(L10n.t("Restore purchases")):
			failures.append("purchases: not offered once bought")
		game.menu.close()
		iap.forget_purchases()
		ads.set_ads_removed(false)
	print("ads: ok")


## Settings from the main menu: the in-game menu's settings (sound and
## music sliders, Remove ads), and Back returns to the main menu.
func _check_settings() -> void:
	var menu: Node = game.menu
	menu.open("home")
	var settings := _menu_button(L10n.t("Settings"))
	if settings == null:
		failures.append("settings: a Settings button on the main menu")
		menu.close()
		return
	settings.pressed.emit()
	var sliders := menu.find_children("*", "HSlider", true, false).filter(
		func(n: Node) -> bool: return n.is_visible_in_tree() and not _going(n))
	if menu._screen != "settings" or sliders.size() != 2:
		failures.append("settings: opens with Sound and Music (%s, %d sliders)" % [menu._screen, sliders.size()])
	if not _menu_has_text(L10n.t("Remove ads · %s") % "US$1.99"):
		failures.append("settings: Remove ads offered there too")
	# Large text and Vibration: two switches; Large text makes every size bigger.
	var switches := _switches()
	var large: Button = switches.get(L10n.t("Large text"))
	if large == null or not switches.has(L10n.t("Vibration")):
		failures.append("settings: Large text and Vibration switches (%s)" % str(switches.keys()))
	elif large.button_pressed or SeriesTheme.fs(19) != 21:
		failures.append("settings: normal text to start with")
	else:
		large.button_pressed = true
		if not SeriesTheme.large or SeriesTheme.fs(19) != 26 or not bool(L10n.load_setting(GameText.SETTING, false)):
			failures.append("settings: Large text makes 19 + 2 into 26 and is saved")
		GameText.set_large(false, self)
		if SeriesTheme.fs(19) != 21:
			failures.append("settings: back to normal text")
	# Credits → Open-source licenses → Godot's notice, and back to Settings.
	var credits := _menu_button(L10n.t("Credits"))
	if credits == null:
		failures.append("settings: a Credits button")
	else:
		credits.pressed.emit()
		if menu._screen != "credits" or not _menu_has_label("Christopher Kastensmidt"):
			failures.append("credits: the author's line (%s)" % menu._screen)
		var licenses := _menu_button(L10n.t("Open-source licenses"))
		if licenses:
			licenses.pressed.emit()
		var godot := _menu_button("Godot Engine")
		if menu._screen != "licenses" or godot == null or _menu_button("Epic Online Services SDK") == null:
			failures.append("credits: the licence list (%s)" % menu._screen)
		elif godot:
			godot.pressed.emit()
			var texts := menu.find_children("*", "RichTextLabel", true, false).filter(
				func(n: Node) -> bool: return not _going(n) and (n as RichTextLabel).text.contains("This game uses Godot Engine"))
			if menu._screen != "license" or texts.is_empty():
				failures.append("credits: Godot's notice opens (%s)" % menu._screen)
		for i in 3:
			menu.back()
		if menu._screen != "settings":
			failures.append("credits: Back three times returns to Settings (%s)" % menu._screen)
	var back := _menu_button(L10n.t("Back"))
	if back:
		back.pressed.emit()
	if menu._screen != "home" or not menu.visible:
		failures.append("settings: Back returns to the main menu (%s)" % menu._screen)
	menu.close()
	# The in-game menu: Large text and Vibration as the app ships, also on a
	# short (landscape phone) screen; there, in a test build, the test buttons
	# take their place.
	var short: bool = game.get_viewport().get_visible_rect().size.y < 1000
	for tools in [false, true]:
		menu.test_tools = tools
		menu.open("pause")
		var has_switches := _switches().has(L10n.t("Large text"))
		var has_tests := _menu_has_text("Perf test")
		if has_switches == (tools and short) or has_tests != tools:
			failures.append("in-game menu (test buttons %s, short %s): switches %s, test buttons %s" % [tools, short, has_switches, has_tests])
		menu.close()
	menu.test_tools = OS.is_debug_build()
	# The frame-rate readout (three-finger tap) exists in test builds only.
	if (game.perf != null) != OS.is_debug_build():
		failures.append("the frame-rate readout only in test builds")
	print("settings: ok")


## The visible on/off switches in the menu, by their label.
func _switches() -> Dictionary:
	var switches := {}
	for n in game.menu.find_children("*", "SeriesSwitch", true, false):
		if n.is_visible_in_tree() and not _going(n):
			switches[(n as Button).tooltip_text] = n
	return switches


func _menu_has_text(text: String) -> bool:
	return _menu_button(text) != null


func _menu_has_label(part: String) -> bool:
	for n in game.menu.find_children("*", "Label", true, false):
		if (n as Label).text.contains(part) and n.is_visible_in_tree() and not _going(n):
			return true
	return false


func _menu_button(text: String) -> Button:
	for n in game.menu.find_children("*", "Button", true, false):
		if (n as Button).text == text and n.is_visible_in_tree() and not _going(n):
			return n
	return null


## The node or one of its parents is queued for deletion (a screen being
## replaced).
func _going(n: Node) -> bool:
	while n:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


## The sounds played since the last check, in order.
func _check_sounds(want: Array, what: String) -> void:
	var got: Array = game.sfx.played.map(func(e: Array) -> String: return e[0])
	if got != want:
		failures.append("%s: expected sounds %s, got %s" % [what, want, got])
	game.sfx.played.clear()


## Every Bagh Chal look builds, and its move marks use that look's shader.
func _check_looks() -> void:
	var b: BoardDef = game.rules.board
	var ids: Array[String] = []
	for st: HuntArtStyle in game.art_styles():
		ids.append(st.id)
	if ids.size() < 3:
		failures.append("expected at least 3 Bagh Chal looks, got %s" % [ids])
	for id in ids:
		game.set_art_style(id)
		for ev in GreyboxScript.PIECE_SOUNDS:
			if not game.sfx.has_event(ev):
				failures.append("look %s: no %s sound" % [id, ev])
		if game.music.set_id() != game.current_style().music_dir or game.music.track_count() < 3:
			failures.append("look %s: its music isn't playing (%s, %d tracks)" % [id, game.music.set_id(), game.music.track_count()])
		game._on_point_clicked(b.point_at(Vector2(0, 0)))  # select a tiger
		var want: Shader = GreyboxScript.MarkInkShader if game.current_style().mark_ink else GreyboxScript.MarkShader
		var shown := 0
		for mark: Node in game._marks_root.get_children():
			if mark.is_queued_for_deletion():
				continue
			shown += 1
			if (mark as MeshInstance3D).material_override.shader != want:
				failures.append("look %s: a move mark uses the wrong shader" % id)
				break
		if shown < 2:
			failures.append("look %s: expected the selection and its steps, got %d marks" % [id, shown])
	game._selected = -1
	game.set_art_style(ids[0])
	print("looks: %s ok" % [", ".join(ids)])


func _next_game() -> void:
	if queue.is_empty():
		phase = "tutorial"
		queue = HuntRuleSets.ALL.duplicate()
		return
	current = queue.pop_front()
	game.sfx.played.clear()
	(GameHaptics.recorder as Array).clear()
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
		# Bagh Chal games that end on the board end with a sting.
		var stings: Array = game.sfx.played.filter(func(e: Array) -> bool: return e[0] in GreyboxScript.STINGS)
		var want_sting: bool = game._title() == "bagh_chal" and game.status != HuntState.Status.ONGOING
		if stings.size() != (1 if want_sting else 0):
			failures.append("%s: expected %d end sting, got %s" % [current, 1 if want_sting else 0, stings])
		# The phone vibrates with the pieces, and once more at the end.
		var buzz: Array = GameHaptics.recorder
		if game.history.size() > 0 and not buzz.has(GameHaptics.MOVE):
			failures.append("%s: no vibration for a move" % current)
		if st.captured > 0 and not buzz.has(GameHaptics.CAPTURE):
			failures.append("%s: no vibration for a capture" % current)
		var want_end: bool = game.status != HuntState.Status.ONGOING
		if buzz.count(GameHaptics.END) != (1 if want_end else 0):
			failures.append("%s: expected %d end vibration, got %d" % [current, 1 if want_end else 0, buzz.count(GameHaptics.END)])
		if st.hash_key != st.compute_hash():
			failures.append("%s: hash drift" % current)
		_next_game()
		if phase == "done":
			return _done()
	return false


var _finish_at := 0
var _quit_at := 0
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


## Switches the interface through every language this build offers: the
## rebuild must not error, and the turn banner must say something.
func _languages() -> void:
	for entry in L10n.languages():
		TranslationServer.set_locale(entry[0])
		game._hud._build()
		if game._hud._turn.text.strip_edges() == "":
			failures.append("%s: empty turn banner" % entry[0])
	TranslationServer.set_locale("en")
	print("languages: %d checked" % L10n.languages().size())


func _done() -> bool:
	if phase == "quit":
		return false
	for f in failures:
		print("FAIL " + f)
	print("smoke: %s" % ("ok" if failures.is_empty() else "%d failures" % failures.size()))
	game._stop_ai()
	game.sfx.stop_all()
	game.music.stop()
	phase = "quit"
	_quit_at = Time.get_ticks_msec() + 300
	return false


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

