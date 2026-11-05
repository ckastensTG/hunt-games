extends SceneTree
## Headless check of the play menu and of games against other people, through
## the same calls the menu's buttons make:
##
##   godot --headless --path . -s res://tools/smoke_multiplayer.gd
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1600x900 \
##     -s res://tools/smoke_multiplayer.gd -- --out=DIR [--tag=NAME]
##
## 1. Every menu screen builds; a game against the AI starts from the menu,
##    is saved, shows the in-game menu, and "Quit to main menu" ends it.
## 2. Quick match against the simulated opponent (debug builds only): moves
##    both ways, the turn clock, a draw offer (declined), resigning, a rematch
##    with the sides swapped, leaving.
## 3. Quick match with no one around: the three choices after a minute, the
##    AI game, "Opponent ready — play now?", Play now, and the AI game saved
##    for later (Continue).
## 4. A friend game by code, with a move taken back.
## 5. Nearby: hosting on this machine's address; a second device joins by the
##    code over ENet, moves go both ways, then it leaves.
## With --out (and a display) it also saves a picture of each screen.
## Exits non-zero on any failure.

const SimOpponentScript := preload("res://scenes/play/sim_opponent.gd")
const SAVE := "user://smoke_multiplayer.save"

var game: Node3D
var failures: Array[String] = []
var out_dir := ""
var tag := ""
var _pollers: Array[Callable] = []
var _rng := RandomNumberGenerator.new()
var _toasts: Array[String] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--tag="):
			tag = "_" + arg.substr(6)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	_rng.seed = 7
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	game.save_path = SAVE
	root.add_child(game)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	var limit := 900000 if out_dir != "" else 150000  # rendering is slow on software GPUs
	if Time.get_ticks_msec() > limit and not _finishing:
		failures.append("timed out")
		_finish()
	return false


func _run() -> void:
	await _frames(4)
	game.play.toast.connect(func(t: String) -> void: _toasts.append(t))
	if not game.play.is_simulated():
		failures.append("expected the simulated online service in a debug run")
		_finish()
		return
	await _menus()
	await _quick_match()
	await _background_match()
	await _friend_game()
	await _nearby_game()
	_finish()


# --- 1. Menu ------------------------------------------------------------------

func _menus() -> void:
	_check(game.menu.is_open(), "the menu opens at start")
	for screen in ["home", "origins", "vs_ai", "pass", "nearby", "nearby_host", "online", "friend",
			"friend_setup", "friend_join"]:
		game.menu._go(screen, false)
		await _frames(3)
		_check(game.menu._card_box.get_child_count() > 1, "menu screen %s has content" % screen)
		await _shot("menu_" + screen)
	game.play.error = "offline"
	game.menu._go("error", false)
	await _frames(3)
	await _shot("menu_error")
	game.play.error = ""
	game.menu._go("home", false)
	# Starting a game against the AI from the menu.
	game.menu._go("vs_ai", false)
	game.menu._side = HuntState.HUNTER
	game.start_local(game.Mode.HUMAN_HUNTER, HuntRuleSets.BAGH_CHAL_STANDARD, 0)
	await _frames(2)
	_check(not game.menu.is_open(), "the menu closes when a game starts")
	_check(game.local_side() == HuntState.HUNTER, "playing the tigers")
	await _until(func() -> bool: return game.can_play(), 10.0, "the AI's first goat")
	_play_one()
	await _until(func() -> bool: return game.can_play(), 10.0, "our turn again")
	_check(game.has_saved_game(), "a game against the AI is saved")
	_check(game._hud._undo.visible and not game._hud._undo.disabled, "Undo is on the board")
	await _shot("game_vs_ai")
	game.menu.open("pause")
	await _frames(3)
	_check(game.menu.is_paused(), "the in-game menu opens")
	_check(game.menu._card_box.get_child_count() >= 5, "in-game menu has its rows")
	_check(not game._hud._root.visible, "the board's buttons hide under it")
	await _shot("pause_local")
	game.menu.back()
	await _frames(1)
	_check(not game.menu.is_open(), "Esc/back closes it (Continue)")
	game.quit_to_menu()
	await _frames(2)
	_check(game.menu.is_open() and game.menu._screen == "home", "Quit to main menu shows the main menu")
	_check(not game.has_saved_game(), "and the quit game is no longer saved")


# --- 2. Quick match -------------------------------------------------------------

func _quick_match() -> void:
	var play: Node = game.play
	play.sim_join_s = 1
	game.menu.open("online")
	game.menu._go("quick")
	play.quick_start()
	await _frames(3)
	await _shot("quick_searching")
	if not await _until(func() -> bool: return game.is_network(), 20.0, "quick match starts"):
		return
	_check(game.session.kind == MatchSession.Kind.QUICK_MATCH, "kind is quick match")
	_check(play.opponent_name() == "Simulated opponent (test build)", "the simulated opponent is labeled")
	_check(not game.menu.is_open(), "the menu closed for the match")
	var sim_net: NetMatch = play._sim.net
	await _play_plies(8)
	_check(game.session.position_hash() == sim_net.session.position_hash(), "both devices have the same position")
	_check(play.net.seconds_left() >= 0, "the turn clock runs")
	await _shot("quick_in_game")
	game.menu.open("pause")
	await _frames(3)
	_check(game._match_ui._strip.visible, "the opponent strip stays over the in-game menu")
	await _shot("pause_online")
	game.menu.close()
	_toasts.clear()
	play.offer_draw()
	await _until(func() -> bool: return _toasts.has(L10n.t("Your opponent declined the draw.")), 5.0, "draw declined")
	var me: int = game.local_side()
	play.resign()
	await _until(func() -> bool: return game._hud._result.visible, 5.0, "result card after resigning")
	_check(not game.session.is_ongoing(), "resigned")
	await _until(func() -> bool: return not sim_net.session.is_ongoing(), 5.0, "the other device sees the resignation")
	_check(sim_net.session.ending == MatchSession.Ending.RESIGNED,
		"the other device saw the resignation (ending %d, ours %d)" % [sim_net.session.ending, game.session.ending])
	_check(game._hud._result.visible, "result card shown")
	_check(game._hud._result_you.text == L10n.t("You lost"), "result says you lost")
	_check(game._hud._result_reason.text == L10n.t("You resigned."), "result says you resigned")
	_check(game._hud._again.text == L10n.t("Rematch"), "result offers a rematch")
	_check(game._hud._new_opponent.visible, "result offers a new opponent")
	await _shot("quick_result")
	var old: MatchSession = game.session
	play.request_rematch()
	if await _until(func() -> bool: return game.session != old and game.session.is_ongoing(), 5.0, "rematch starts"):
		_check(game.local_side() != me, "sides swap in the rematch")
	play.leave_match()
	game.leave_network()
	await _frames(2)
	_check(not game.is_network(), "back to a local game")


# --- 3. No one around: play the AI while we keep looking ----------------------------

func _background_match() -> void:
	var play: Node = game.play
	play.sim_join_s = -1
	game.menu.open("online")
	game.menu._go("quick")
	play.quick_start()
	await _frames(5)
	play._choice_at = 0  # as if a minute had passed
	if not await _until(func() -> bool: return play.quick_choices, 3.0, "choices after a minute"):
		return
	await _frames(2)
	await _shot("quick_choices")
	play.quick_play_ai(game.Mode.HUMAN_PREY, HuntRuleSets.BAGH_CHAL_STANDARD, 0)
	await _frames(2)
	_check(not game.is_network() and play.background, "playing the AI while searching")
	_check(game._match_ui._search_row.visible, "the search line shows over the board")
	await _play_plies(4)
	var ai_moves: int = game.history.size()
	_check(game.has_saved_game(), "the AI game is saved")
	# Someone turns up.
	play._sim = SimOpponentScript.new(play.title_id(), "smoke", play._resolver())
	play._sim.join_quick(0, Time.get_ticks_msec())
	if not await _until(func() -> bool: return game._match_ui._offer_open, 10.0, "opponent ready offer"):
		return
	await _shot("quick_offer")
	ai_moves = game.history.size()  # the AI may have answered meanwhile
	game._match_ui._toast_play.pressed.emit()
	if not await _until(func() -> bool: return game.is_network(), 10.0, "background match starts"):
		return
	_check(not play.background, "search stopped")
	game.quit_to_menu()  # leaves the online game (a loss: it was still going)
	await _frames(2)
	_check(not game.is_network() and game.menu.is_open(), "main menu after leaving")
	_check(game.has_saved_game(), "the AI game set aside is still saved (Continue)")
	game.continue_saved()
	await _frames(2)
	_check(not game.menu.is_open() and game.history.size() == ai_moves, "the AI game comes back")


# --- 4. A friend, by code ----------------------------------------------------------

func _friend_game() -> void:
	var play: Node = game.play
	game.menu.open("friend_setup")
	game.menu._go("friend_host")
	play.friend_host(HuntRuleSets.BAGH_CHAL_PARLETT, HuntState.PREY)
	if not await _until(func() -> bool: return play.code != "", 5.0, "friend code"):
		return
	_check(JoinCode.normalize_online(play.code) == play.code, "code looks like TG-XXXX: %s" % play.code)
	await _frames(2)
	await _shot("friend_code")
	play.simulate_friend_joining()
	if not await _until(func() -> bool: return game.is_network(), 10.0, "friend game starts"):
		return
	_check(game.session.kind == MatchSession.Kind.ONLINE_FRIEND, "kind is a friend game")
	_check(game.session.rule_set_id == HuntRuleSets.BAGH_CHAL_PARLETT, "the host's rules")
	_check(game.local_side() == HuntState.PREY, "the host's side")
	_check(play.net.seconds_left() < 0, "no turn clock with friends")
	await _play_plies(4)
	# Take back: right after our move.
	await _until(func() -> bool: return game.can_play(), 10.0, "our turn")
	var before: int = game.history.size()
	_play_one()
	await _frames(1)
	_toasts.clear()
	play.request_undo()
	if await _until(func() -> bool: return _toasts.has(L10n.t("Move taken back.")), 5.0, "undo allowed"):
		_check(game.history.size() == before, "the move was taken back (%d, %d)" % [game.history.size(), before])
		_check(game.state.side == HuntState.PREY, "our turn again")
	play.leave_match()
	game.leave_network()
	await _frames(2)


# --- 5. Nearby ---------------------------------------------------------------------

func _nearby_game() -> void:
	var play: Node = game.play
	var ip := JoinCode.local_ipv4()
	if ip == "":
		print("nearby: skipped (no private IPv4 address here)")
		return
	game.menu.open("nearby_host")
	game.menu._go("nearby_wait")
	play.nearby_host(HuntRuleSets.BAGH_CHAL_STANDARD, HuntState.HUNTER)
	await _frames(3)
	_check(play.code == JoinCode.from_ipv4(ip), "nearby code for %s" % ip)
	await _shot("nearby_wait")
	var ear := LanDiscovery.new()
	ear.listen(LanDiscovery.PORT + 1)  # the host's beacon port is busy in this one process
	# A second device joins with the code.
	var link := ENetTransport.join(JoinCode.to_ipv4(play.code))
	var guest := NetMatch.as_guest(link, play.title_id(), "smoke", {"key": "weaver", "n": 1234}, play._resolver())
	_pollers.append(func() -> void: guest.poll())
	if not await _until(func() -> bool: return game.is_network() and guest.session != null, 10.0, "nearby game starts"):
		_pollers.clear()
		return
	_check(play.opponent_name() == L10n.t("Weaver") + " 1234", "opponent name: %s" % play.opponent_name())
	_check(guest.local_side == HuntState.PREY, "the guest plays the goats")
	# Goats first: the guest moves, then us.
	guest.session.commit(guest.session.state.legal_moves(false)[0], HuntState.PREY)
	await _until(func() -> bool: return game.history.size() == 1, 5.0, "guest's move arrives")
	await _until(func() -> bool: return game.can_play(), 5.0, "our turn")
	_play_one()
	await _until(func() -> bool: return guest.session.moves.size() == 2, 5.0, "our move arrives")
	_check(guest.session.position_hash() == game.session.position_hash(), "same position on both devices")
	await _shot("nearby_in_game")
	# The guest leaves. (In one process the host can't acknowledge while the
	# guest hangs up, so its goodbye goes out first.)
	guest._send(NetProtocol.Msg.BYE)
	await _frames(10)
	guest.leave()
	await _until(func() -> bool: return game._hud._result.visible, 5.0, "guest leaves")
	_check(game._hud._result_reason.text == L10n.t("Your opponent left the game."), "result: opponent left")
	_check(game._hud._result_you.text == L10n.t("You won"), "result: you won")
	_pollers.clear()
	play.leave_match()
	game.leave_network()
	await _frames(2)


# --- Helpers ------------------------------------------------------------------------

## Plays `n` of our moves (random legal ones) as the opponent answers.
func _play_plies(n: int) -> void:
	for _i in n:
		if not await _until(func() -> bool: return game.can_play() or not game.session.is_ongoing(), 15.0, "our turn"):
			return
		if not game.session.is_ongoing():
			return
		_play_one()
		await _frames(1)


func _play_one() -> void:
	var moves: Array[PackedInt32Array] = game.state.legal_moves(false)
	game.commit(moves[_rng.randi_range(0, moves.size() - 1)])


func _until(cond: Callable, seconds: float, what: String) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			failures.append("timed out: " + what)
			return false
		await _frames(1)
	return true


func _frames(n: int) -> void:
	for _i in n:
		for p in _pollers:
			p.call()
		await process_frame


func _shot(name: String) -> void:
	if out_dir == "":
		return
	await _frames(3)
	var path := out_dir.path_join("%s%s.png" % [name, tag])
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


var _finishing := false


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	game.play.cancel()
	game.queue_free()
	await process_frame
	await process_frame
	# Sounds that were still playing are let go on the audio thread's next mix.
	await create_timer(0.3).timeout
	FakeOnlineBackend.reset_cloud()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	if failures.is_empty():
		print("multiplayer smoke: ok")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		quit(1)
