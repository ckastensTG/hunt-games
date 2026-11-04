extends CanvasLayer
## The menus. The main menu (how to play and against whom) opens when the
## game starts without a game to resume, and after "Quit to main menu". The
## in-game menu ("pause") opens from the menu button on the board, Esc or
## Android's back gesture.
##
##   Home ─ Play against the AI · Pass and play · Play local · Play online
##          · How to play · Game origins · Language · Quit game (not on iOS)
##          (Continue only when an AI game was set aside for an online match)
##   Game origins ─ the game's history and its sources (HuntOrigins)
##   Play against the AI ─ side, opponent level, rules → Start
##   Pass and play ─ rules → Start
##   Play local ─ Host a game (side, rules → waiting, with a code)
##              └ Join a game (games heard on this Wi-Fi, or type a code)
##   Play online ─ Play with someone online (quick match: searching; after a
##               │ minute: play against the AI while we keep looking / keep
##               │ searching / invite a friend)
##               └ Play with a friend ─ Create a code (side, rules → code to
##                                     share) · Enter a code
##   Pause ─ Continue · (against another device: Offer a draw, Ask to undo,
##           Resign) · Look · Language · Quit to main menu
##
## "Play online" only shows when an online service is available (bible §5.2:
## offline-first). The network work is in play_controller.gd; this only
## shows its state and calls it. Rebuilt when the language changes.

const CARD_WIDTH := 600
const PlayController := preload("res://scenes/play/play_controller.gd")

var game: Node
var _root: Control
var _card_box: VBoxContainer
var _screen := "home"
var _stack: Array[String] = []
## Choices kept between screens (and sessions, for the AI ones).
var _side := HuntState.PREY
var _rule_set := ""
var _typed_code := ""
var _hosts_box: VBoxContainer
var _live_label: Label
var _error_back := "home"
var _after_confirm: Callable


func _init(owner_game: Node) -> void:
	game = owner_game
	layer = 3
	visible = false


func _ready() -> void:
	_side = int(L10n.load_setting("vs_ai_side", HuntState.PREY))
	var play: Node = game.play
	play.changed.connect(_on_play_changed)
	play.nearby_hosts_changed.connect(_fill_hosts)
	get_viewport().size_changed.connect(_on_resized)
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build.call_deferred()


func is_open() -> bool:
	return visible


func open(screen := "home") -> void:
	if game.tutorial_active:
		return
	visible = true
	_stack.clear()
	_go(screen, false)
	game._refresh_ui()


func close() -> void:
	if not visible:
		return
	visible = false
	_stack.clear()
	game._refresh_ui()


## True while the in-game menu is showing (the board's game goes on under it).
func is_paused() -> bool:
	return visible and _screen == "pause"


## Esc / Android back: one screen back. The in-game menu closes (Continue);
## Android's back on the main menu's first screen leaves the app.
func back(from_android := false) -> void:
	if not visible:
		return
	if _screen in ["nearby_wait", "nearby_join", "connecting", "friend_host", "friend_join", "quick"]:
		game.play.cancel()
	if _stack.is_empty():
		if _screen == "pause":
			close()
		elif _screen != "home":
			_go("home", false)
		elif from_android:
			get_tree().quit()
		return
	_go(_stack.pop_back(), false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		back()
		get_viewport().set_input_as_handled()


func _go(screen: String, remember := true) -> void:
	if remember and visible and _screen != screen:
		_stack.append(_screen)
	_screen = screen
	_render()


# --- Building ----------------------------------------------------------------

func _build() -> void:
	if _root:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = SeriesTheme.theme()
	_root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var card := PanelContainer.new()
	var s := SeriesTheme.panel_box(Color(0.075, 0.057, 0.045, 0.97), SeriesTheme.BRASS, 16)
	s.content_margin_left = 44
	s.content_margin_right = 44
	s.content_margin_top = 30
	s.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", s)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 14)
	card.add_child(_card_box)
	center.add_child(card)
	if visible:
		_render()


func _render() -> void:
	if _card_box == null:
		return
	for c in _card_box.get_children():
		c.queue_free()
	_hosts_box = null
	_live_label = null
	match _screen:
		"home":
			_home()
		"vs_ai":
			_vs_ai()
		"pass":
			_pass_and_play()
		"nearby":
			_nearby()
		"nearby_host":
			_host_setup("nearby")
		"nearby_wait":
			_nearby_wait()
		"nearby_join":
			_nearby_join()
		"online":
			_online()
		"friend":
			_friend()
		"friend_setup":
			_host_setup("friend")
		"friend_host":
			_friend_host()
		"friend_join":
			_friend_join()
		"quick":
			_quick()
		"connecting":
			_connecting()
		"error":
			_error()
		"confirm_leave":
			_confirm_leave()
		"pause":
			_pause()
		"origins":
			_origins()


## The Game origins text is sized to the screen: lay it out again after a turn.
func _on_resized() -> void:
	if visible and _screen == "origins":
		_render.call_deferred()


func _title(text: String, size := 40) -> void:
	var l := SeriesTheme.label(text, "display", size, SeriesTheme.ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_box.add_child(l)


func _text(text: String, role := "book", size := 20, color := SeriesTheme.TEXT) -> Label:
	var l := SeriesTheme.label(text, role, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_WIDTH - 100, 0)
	_card_box.add_child(l)
	return l


func _button(text: String, on_press: Callable, accent := false, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", 22)
	if accent:
		b.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	b.pressed.connect(on_press)
	(parent if parent else _card_box).add_child(b)
	return b


## Back (or Cancel) at the bottom of a screen.
func _back_button(text := "") -> void:
	var b := _button(L10n.t("Back") if text == "" else text, back)
	b.flat = true
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_color_override("font_color", SeriesTheme.TEXT_DIM)


func _gap(h := 4) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	_card_box.add_child(c)


func _row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := SeriesTheme.label(label_text, "body", 19, SeriesTheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(130, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 52
	row.add_child(l)
	row.add_child(control)
	_card_box.add_child(row)


## Two buttons, one per side, as whole sentences ("You play the goats").
func _side_picker() -> void:
	var group := ButtonGroup.new()
	var title: String = _title_id()
	for side in [HuntState.PREY, HuntState.HUNTER]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = HuntText.you_play(title, side == HuntState.HUNTER)
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 20)
		b.button_pressed = side == _side
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_side = side)
		_card_box.add_child(b)


func _rules_picker() -> void:
	var sets: Array = TitleConfig.active().rule_sets
	if _rule_set == "" or not sets.has(_rule_set):
		_rule_set = game._rule_set_id if sets.has(game._rule_set_id) else sets[0]
	if sets.size() < 2:
		return
	var pick := OptionButton.new()
	pick.add_theme_font_size_override("font_size", 19)
	for id in sets:
		pick.add_item(HuntText.rule_set_menu(id))
	pick.selected = sets.find(_rule_set)
	pick.item_selected.connect(func(i: int) -> void: _rule_set = sets[i])
	_row(L10n.t("Rules"), pick)


## The language picker, with a globe so it's found in any language.
func _language_row() -> void:
	var lang := OptionButton.new()
	lang.add_theme_font_size_override("font_size", 17)
	for entry in L10n.LANGUAGES:
		lang.add_item(entry[1])
	lang.selected = L10n.LANGUAGES.map(func(e: Array) -> String: return e[0]).find(L10n.current_language())
	lang.item_selected.connect(func(i: int) -> void: L10n.set_language(L10n.LANGUAGES[i][0]))
	lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang.custom_minimum_size.y = 52
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := HBoxContainer.new()
	label.add_theme_constant_override("separation", 8)
	label.custom_minimum_size = Vector2(130, 0)
	label.add_child(SeriesIcon.make("globe", 22))
	var l := SeriesTheme.label(L10n.t("Language"), "body", 19, SeriesTheme.TEXT_DIM)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_child(l)
	row.add_child(label)
	row.add_child(lang)
	_card_box.add_child(row)


func _title_id() -> String:
	var id := _rule_set if _rule_set != "" else str(game._rule_set_id)
	if id == HuntRuleSets.ADUGO:
		return "adugo"
	if id == HuntRuleSets.KOMIKAN:
		return "komikan"
	return "bagh_chal"


# --- Screens -----------------------------------------------------------------

func _home() -> void:
	_title(HuntText.title_name(_title_id()), 56)
	_gap(6)
	# Only an AI game set aside for an online match waits here; any other
	# game is resumed from the in-game menu, or straight away at start.
	if game.has_saved_game():
		# TRANSLATORS: Menu button: go back to the game that was set aside.
		_button(L10n.t("Continue"), func() -> void: game.continue_saved(), true)
	_button(L10n.t("Play against the AI"), func() -> void: _guard(func() -> void: _go("vs_ai")))
	# TRANSLATORS: Menu button: two people share this device and take turns.
	_button(L10n.t("Pass and play"), func() -> void: _guard(func() -> void: _go("pass")))
	# TRANSLATORS: Menu button: play with someone on the same Wi-Fi network (each on their own device).
	_button(L10n.t("Play local"), func() -> void: _guard(func() -> void: _go("nearby")))
	if game.play.online_available():
		_button(L10n.t("Play online"), func() -> void: _guard(func() -> void: _go("online")))
	_button(L10n.t("How to play"), func() -> void: _guard(func() -> void: game.start_tutorial()))
	if HuntOrigins.has_text(_title_id()):
		# TRANSLATORS: Main menu button: opens a short history of the game, with its sources.
		_button(L10n.t("Game origins"), func() -> void: _go("origins"))
	_gap(2)
	_language_row()
	# Not on iOS: apps there don't close themselves (Apple: users leave with
	# the Home gesture; a self-closing app looks like a crash).
	if not (OS.has_feature("ios") or OS.has_feature("web")):
		# TRANSLATORS: Main menu button: close the game completely.
		var quit := _button(L10n.t("Quit game"), func() -> void:
			game.play.cancel()
			get_tree().quit())
		quit.flat = true
		quit.custom_minimum_size = Vector2(0, 48)
		quit.add_theme_color_override("font_color", SeriesTheme.TEXT_DIM)


func _vs_ai() -> void:
	_title(L10n.t("Play against the AI"))
	_side_picker()
	var level := OptionButton.new()
	level.add_theme_font_size_override("font_size", 19)
	for label in [L10n.t("Novice"), L10n.t("Apprentice"), L10n.t("Adept"), L10n.t("Master")]:
		level.add_item(label)
	level.selected = game.level
	level.item_selected.connect(func(i: int) -> void: game.level = i)
	# TRANSLATORS: Menu label: how strong the computer opponent is.
	_row(L10n.t("Opponent"), level)
	_rules_picker()
	_gap()
	_button(L10n.t("Start"), func() -> void:
		L10n.save_setting("vs_ai_side", _side)
		var mode: int = game.Mode.HUMAN_PREY if _side == HuntState.PREY else game.Mode.HUMAN_HUNTER
		game.start_local(mode, _rule_set, game.level), true)
	_back_button()


func _pass_and_play() -> void:
	_title(L10n.t("Pass and play"))
	_text(L10n.t("Two players share this device and take turns."), "book", 20, SeriesTheme.TEXT_DIM)
	_rules_picker()
	_gap()
	_button(L10n.t("Start"), func() -> void: game.start_local(game.Mode.HOTSEAT, _rule_set), true)
	_back_button()


func _nearby() -> void:
	_title(L10n.t("Play local"))
	_text(L10n.t("Both devices need to be on the same Wi-Fi."), "book", 20, SeriesTheme.TEXT_DIM)
	_gap()
	# TRANSLATORS: Menu button: start a game that another device on the same Wi-Fi can join.
	_button(L10n.t("Host a game"), func() -> void: _go("nearby_host"), true)
	# TRANSLATORS: Menu button: join a game another device on the same Wi-Fi is hosting.
	_button(L10n.t("Join a game"), func() -> void:
		_error_back = "nearby"
		_go("nearby_join")
		game.play.nearby_browse())
	_back_button()


## Side and rules for a game this device hosts (nearby or with a friend).
func _host_setup(kind: String) -> void:
	_title(L10n.t("Host a game") if kind == "nearby" else L10n.t("Create a code"))
	_side_picker()
	_rules_picker()
	_gap()
	_button(L10n.t("Start"), func() -> void:
		if kind == "nearby":
			_error_back = "nearby"
			_go("nearby_wait")
			game.play.nearby_host(_rule_set, _side)
		else:
			_error_back = "friend"
			_go("friend_host")
			game.play.friend_host(_rule_set, _side), true)
	_back_button()


func _nearby_wait() -> void:
	var play: Node = game.play
	_title(L10n.t("Waiting for a player"))
	_text(L10n.t("On the other device, choose Play local, then Join a game."), "book", 20, SeriesTheme.TEXT_DIM)
	if play.code != "":
		_gap(2)
		# TRANSLATORS: Above a code like 7KQ-2M4P that the other player can type to join.
		_text(L10n.t("If the game doesn't appear there, enter this code"), "body", 17, SeriesTheme.TEXT_DIM)
		_text(play.code, "code", 52, SeriesTheme.ACCENT)
	_gap(2)
	_your_name()
	_live_label = _text("", "italic", 18, SeriesTheme.TEXT_DIM)
	_back_button(L10n.t("Cancel"))


func _nearby_join() -> void:
	_title(L10n.t("Join a game"))
	# TRANSLATORS: Shown while listening for games hosted on the same Wi-Fi; a list of games appears below.
	_text(L10n.t("Looking for games on this Wi-Fi…"), "italic", 19, SeriesTheme.TEXT_DIM)
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 10)
	_card_box.add_child(_hosts_box)
	_fill_hosts()
	_gap(4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var field := LineEdit.new()
	field.text = _typed_code
	# TRANSLATORS: Placeholder in the box for typing a nearby game's code.
	field.placeholder_text = L10n.t("Code")
	field.max_length = 9
	field.custom_minimum_size = Vector2(0, 54)
	field.add_theme_font_size_override("font_size", 22)
	field.add_theme_font_override("font", SeriesTheme.font("code"))
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(func(t: String) -> void: _typed_code = t)
	var join := Button.new()
	join.text = L10n.t("Join")
	join.custom_minimum_size = Vector2(120, 54)
	join.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	var go := func() -> void:
		_error_back = "nearby_join"
		_go("connecting")
		game.play.nearby_join_code(_typed_code)
	join.pressed.connect(go)
	field.text_submitted.connect(func(_t: String) -> void: go.call())
	row.add_child(field)
	row.add_child(join)
	_card_box.add_child(row)
	_back_button()


func _fill_hosts() -> void:
	if _hosts_box == null:
		return
	for c in _hosts_box.get_children():
		c.queue_free()
	for h in game.play.nearby_hosts():
		var b := Button.new()
		b.text = "%s  ·  %s" % [PlayText.player_name(h.name), HuntText.rule_set_name(h.rule_set)]
		b.custom_minimum_size = Vector2(0, 58)
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", SeriesTheme.ACCENT)
		var ip: String = h.ip
		b.pressed.connect(func() -> void:
			_error_back = "nearby_join"
			_go("connecting")
			game.play.nearby_join(ip))
		_hosts_box.add_child(b)


func _online() -> void:
	_title(L10n.t("Play online"))
	# TRANSLATORS: Menu button: quick match against a random online player.
	_button(L10n.t("Play with someone online"), func() -> void:
		_error_back = "online"
		_go("quick")
		game.play.quick_start(), true)
	# TRANSLATORS: Small print under "Play with someone online".
	_text(L10n.t("Standard rules, about a minute per move"), "italic", 17, SeriesTheme.TEXT_DIM)
	_button(L10n.t("Play with a friend"), func() -> void: _go("friend"))
	if game.play.is_simulated():
		_dev_online_options()
	_back_button()


## Debug builds only, not translated: online play is simulated on this device.
func _dev_online_options() -> void:
	_gap(2)
	_text("Test build: online play is simulated on this device.", "body", 15, Color(0.95, 0.6, 0.4))
	var pick := OptionButton.new()
	var choices := [5, 8, 75, -1]
	for s in choices:
		pick.add_item("never joins" if s < 0 else "joins after %d s" % s)
	pick.selected = maxi(0, choices.find(game.play.sim_join_s))
	pick.item_selected.connect(func(i: int) -> void: game.play.sim_join_s = choices[i])
	_row("Simulated opponent", pick)


func _friend() -> void:
	_title(L10n.t("Play with a friend"))
	_text(L10n.t("One of you creates a code, the other enters it. It works between phones, tablets and computers."),
		"book", 19, SeriesTheme.TEXT_DIM)
	_button(L10n.t("Create a code"), func() -> void: _go("friend_setup"), true)
	_button(L10n.t("Enter a code"), func() -> void:
		_typed_code = "TG-"
		_go("friend_join"))
	_back_button()


func _friend_host() -> void:
	var play: Node = game.play
	_title(L10n.t("Your code"))
	if play.code == "":
		_text(L10n.t("Connecting…"), "italic", 20, SeriesTheme.TEXT_DIM)
	else:
		_text(play.code, "code", 60, SeriesTheme.ACCENT)
		_text(L10n.t("Send this code to your friend. The game starts when they enter it."), "book", 19, SeriesTheme.TEXT_DIM)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var share := _button(L10n.t("Share"), func() -> void: _share(play.code), true, row)
		share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var copy := _button(L10n.t("Copy"), func() -> void:
			DisplayServer.clipboard_set(play.code)
			# TRANSLATORS: Toast after copying the game code.
			game._match_ui.show_toast(L10n.t("Copied")), false, row)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_card_box.add_child(row)
		_live_label = _text("", "italic", 18, SeriesTheme.TEXT_DIM)
		if play.is_simulated():
			var sim := _button("Simulate a friend joining (test build)", func() -> void: play.simulate_friend_joining())
			sim.add_theme_font_size_override("font_size", 16)
	_back_button(L10n.t("Cancel"))


## The system share sheet where a plugin provides one; otherwise copies.
func _share(code: String) -> void:
	# TRANSLATORS: Message sent with the system share sheet. %s is a code like TG-7KQ2.
	var text := L10n.t("Play with me in Timeless Games! My game code is %s.") % code
	for plugin in ["GodotShare", "Share"]:
		if Engine.has_singleton(plugin):
			Engine.get_singleton(plugin).call("shareText", "Timeless Games", "", text)
			return
	DisplayServer.clipboard_set(text)
	game._match_ui.show_toast(L10n.t("Copied"))


func _friend_join() -> void:
	_title(L10n.t("Enter a code"))
	var field := LineEdit.new()
	field.text = _typed_code
	field.placeholder_text = "TG-XXXX"
	field.max_length = 8
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.custom_minimum_size = Vector2(0, 64)
	field.add_theme_font_size_override("font_size", 30)
	field.add_theme_font_override("font", SeriesTheme.font("code"))
	field.text_changed.connect(func(t: String) -> void: _typed_code = t)
	var go := func() -> void:
		_error_back = "friend_join"
		_go("connecting")
		game.play.friend_join(_typed_code)
	field.text_submitted.connect(func(_t: String) -> void: go.call())
	_card_box.add_child(field)
	_button(L10n.t("Join"), go, true)
	_back_button()
	field.grab_focus.call_deferred()
	field.caret_column = _typed_code.length()


func _quick() -> void:
	var play: Node = game.play
	if play.quick_choices:
		# TRANSLATORS: Quick match found no one after about a minute.
		_title(L10n.t("No one is free right now"), 34)
		_text(L10n.t("We can keep looking while you play."), "book", 20, SeriesTheme.TEXT_DIM)
		_button(L10n.t("Play against the AI while we keep looking"), func() -> void:
			var mode: int = game.Mode.HUMAN_PREY if _side == HuntState.PREY else game.Mode.HUMAN_HUNTER
			play.quick_play_ai(mode, TitleConfig.active().rule_sets[0], game.level), true)
		_button(L10n.t("Keep searching"), func() -> void: play.quick_keep_searching())
		_button(L10n.t("Invite a friend instead"), func() -> void:
			play.cancel()
			_go("friend_setup"))
		_back_button(L10n.t("Cancel"))
		return
	# TRANSLATORS: Quick match is searching for an online opponent.
	_title(L10n.t("Looking for an opponent…"), 34)
	_live_label = _text("0:00", "code", 44, SeriesTheme.ACCENT)
	_text(L10n.t("Standard rules, about a minute per move"), "italic", 18, SeriesTheme.TEXT_DIM)
	_your_name()
	_back_button(L10n.t("Cancel"))


func _connecting() -> void:
	_title(L10n.t("Connecting…"), 36)
	_back_button(L10n.t("Cancel"))


func _error() -> void:
	# TRANSLATORS: Title over a message saying why a game with another player couldn't start.
	_title(L10n.t("Couldn't start the game"), 32)
	_text(PlayText.problem(game.play.error), "book", 21)
	_gap()
	_button(L10n.t("OK"), func() -> void:
		game.play.error = ""
		_stack.clear()
		_go(_error_back if _error_back != "" else "home", false), true)


func _confirm_leave() -> void:
	# TRANSLATORS: Asked before leaving a game against another player that's still going.
	_title(L10n.t("Leave this game?"), 34)
	_text(L10n.t("It counts as a loss."), "book", 20, SeriesTheme.TEXT_DIM)
	_button(L10n.t("Leave"), func() -> void:
		var then := _after_confirm
		_after_confirm = Callable()
		if then.is_valid():
			then.call(), true)
	# TRANSLATORS: Button: don't leave the game against another player.
	_button(L10n.t("Stay"), func() -> void:
		_after_confirm = Callable()
		back())


## Game origins: the game's history, then its sources as written (HuntOrigins).
## The text scrolls inside the card, which keeps the menu's size and style.
func _origins() -> void:
	var title := _title_id()
	_title(HuntText.title_name(title), 44)
	_text(L10n.t("Game origins"), "italic", 19, SeriesTheme.TEXT_DIM)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var screen_h := get_viewport().get_visible_rect().size.y
	scroll.custom_minimum_size = Vector2(CARD_WIDTH - 88, clampf(screen_h - 330.0, 260.0, 1060.0))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_theme_constant_override("separation", 16)
	for p in HuntOrigins.paragraphs(title):
		box.add_child(_rich(p, 20, SeriesTheme.TEXT))
	var line := HSeparator.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	# TRANSLATORS: Heading over the list of books and articles at the end of "Game origins".
	var heading := SeriesTheme.label(L10n.t("Sources"), "medium", 18, SeriesTheme.ACCENT)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(heading)
	for s in HuntOrigins.sources(title):
		box.add_child(_rich(s, 16, SeriesTheme.TEXT_DIM))
	var pad := MarginContainer.new()  # keeps the text clear of the scroll bar
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_child(box)
	scroll.add_child(pad)
	_card_box.add_child(scroll)
	_back_button()


## Body text with [i]…[/i] italics, wrapping to the card's width. It lets
## drags through, so a finger scrolls the text.
func _rich(bbcode: String, size: int, color: Color) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", SeriesTheme.font("book"))
	r.add_theme_font_override("italics_font", SeriesTheme.font("book_italic"))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.add_theme_constant_override("line_separation", 3)
	r.text = bbcode
	return r


## The in-game menu.
func _pause() -> void:
	_title(HuntText.title_name(game._title()), 46)
	_text(HuntText.rule_set_name(game._rule_set_id), "italic", 19, SeriesTheme.TEXT_DIM)
	_gap(2)
	_button(L10n.t("Continue"), close, true)
	var s: MatchSession = game.session
	if game.is_network() and s and s.is_ongoing():
		# Against another device: the game's own actions.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var draw := _small_button(L10n.t("Offer a draw"), row, func() -> void:
			close()
			game.play.offer_draw())
		draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if s.kind != MatchSession.Kind.QUICK_MATCH:
			var undo := _small_button(L10n.t("Ask to undo"), row, func() -> void:
				close()
				game.play.request_undo())
			undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			undo.disabled = s.moves.is_empty()
		var resign := _small_button(L10n.t("Resign"), row, func() -> void:
			close()
			game._match_ui.ask_resign())
		resign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_card_box.add_child(row)
	var styles: Array = game.art_styles()
	if styles.size() > 1:
		var look := OptionButton.new()
		look.add_theme_font_size_override("font_size", 17)
		for st in styles:
			look.add_item(L10n.t(st.display_name))
			look.set_item_tooltip(look.item_count - 1, L10n.t(st.description))
		look.selected = maxi(0, styles.find(game.current_style()))
		look.item_selected.connect(func(i: int) -> void: game.set_art_style(styles[i].id))
		# TRANSLATORS: Menu label: the visual style of board and pieces (a noun, not "to look"). Keep it short.
		_row(L10n.t("Look"), look)
	_language_row()
	_gap(2)
	# TRANSLATORS: In-game menu button: end this game and go back to the main menu.
	var quit := _button(L10n.t("Quit to main menu"), func() -> void:
		if game.is_network() and game.session.is_ongoing():
			_after_confirm = func() -> void: game.quit_to_menu()
			_go("confirm_leave")
		else:
			game.quit_to_menu())
	quit.flat = true
	quit.add_theme_color_override("font_color", SeriesTheme.TEXT_DIM)


func _small_button(text: String, parent: Control, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## Runs `action`, first leaving a network game (asking if it's still going).
func _guard(action: Callable) -> void:
	if not game.is_network():
		action.call()
		return
	if game.session and game.session.is_ongoing():
		_after_confirm = func() -> void:
			_leave_network()
			_stack.clear()
			_go("home", false)
			action.call()
		_go("confirm_leave")
		return
	_leave_network()
	action.call()


func _leave_network() -> void:
	game.play.leave_match()
	game.leave_network()
	visible = true  # leave_network may close the menu while loading the saved game


func _your_name() -> void:
	# TRANSLATORS: Followed by this player's name as others see it, e.g. "Your name: Potter 4821".
	_text(L10n.t("Your name: %s") % PlayText.player_name(game.play.player_name), "body", 17, SeriesTheme.TEXT_DIM)


# --- Following the play controller -------------------------------------------

func _on_play_changed() -> void:
	if not visible:
		return
	var play: Node = game.play
	if play.error != "" and _screen != "error":
		_go("error", false)
		return
	match play.flow:
		PlayController.Flow.CONNECTING:
			if _screen != "connecting":
				_go("connecting", false)
		PlayController.Flow.FRIEND_HOST:
			if _screen == "friend_host":
				_render()  # the code arrived
		PlayController.Flow.QUICK:
			if _screen == "quick":
				_render()
		PlayController.Flow.NEARBY_HOST:
			if _screen == "nearby_wait":
				_render()


func _process(_delta: float) -> void:
	if not visible or _live_label == null:
		return
	match _screen:
		"quick":
			if not game.play.quick_choices:
				_live_label.text = PlayText.clock(game.play.quick_seconds())
		"nearby_wait", "friend_host":
			if game.play.code != "":
				# TRANSLATORS: Shown, with animated dots, while waiting for the other player to join.
				_live_label.text = L10n.t("Waiting") + ".".repeat(1 + int(Time.get_ticks_msec() / 400) % 3)
