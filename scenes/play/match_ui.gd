extends CanvasLayer
## Over the board during games with other people: who the opponent is, the
## connection and the turn clock; the opponent's questions (draw, take back,
## rematch) and our own "resign?"; short messages (toasts), including
## "Opponent ready — play now?" while a quick match is searching in the
## background. Reads the greybox and its play controller; styled by
## SeriesTheme and rebuilt when the language changes.

const WARN := Color(0.95, 0.5, 0.38)

var game: Node
var _root: Control
var _strip: PanelContainer
var _name: Label
var _status: Label
var _clock: Label
var _search_row: HBoxContainer
var _search_label: Label
var _dialog: Control
var _dialog_text: Label
var _dialog_yes: Button
var _dialog_no: Button
var _on_answer: Callable
var _toast: PanelContainer
var _toast_label: Label
var _toast_play: Button
var _toast_later: Button
var _toast_left := 0.0
var _offer_open := false


func _init(owner_game: Node) -> void:
	game = owner_game
	layer = 4  # over the play menu (3): toasts and questions show there too


func _ready() -> void:
	var play: Node = game.play
	play.toast.connect(show_toast)
	play.asked.connect(_on_asked)
	play.background_match_found.connect(_on_background_found)
	play.connection_changed.connect(refresh)
	play.changed.connect(refresh)
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build.call_deferred()


func _build() -> void:
	var was_dialog := _dialog != null and _dialog.visible
	if _root:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = SeriesTheme.theme()
	_root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_root)
	_build_strip()
	_build_toast()
	_build_dialog()
	if was_dialog:
		_dialog.visible = false  # a language change closes it; the question can be asked again
	refresh()


func _build_strip() -> void:
	_strip = PanelContainer.new()
	var s := SeriesTheme.panel_box(SeriesTheme.PANEL_SOFT, Color(0, 0, 0, 0), 18)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 5
	s.content_margin_bottom = 6
	s.shadow_size = 0
	_strip.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_name = SeriesTheme.label("", "medium", 18, SeriesTheme.TEXT)
	_status = SeriesTheme.label("", "italic", 17, WARN)
	_clock = SeriesTheme.label("", "code", 18, SeriesTheme.ACCENT)
	row.add_child(_name)
	row.add_child(_status)
	row.add_child(_clock)
	# While playing the AI with a quick-match search going on.
	_search_row = HBoxContainer.new()
	_search_row.add_theme_constant_override("separation", 12)
	# TRANSLATORS: A small line over the board while the game keeps looking for an online opponent in the background.
	_search_label = SeriesTheme.label(L10n.t("Looking for an opponent…"), "italic", 17, SeriesTheme.TEXT_DIM)
	var stop := Button.new()
	# TRANSLATORS: Button: stop looking for an online opponent.
	stop.text = L10n.t("Stop looking")
	stop.flat = true
	stop.add_theme_font_size_override("font_size", 15)
	stop.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	stop.pressed.connect(func() -> void: game.play.decline_background())
	_search_row.add_child(_search_label)
	_search_row.add_child(stop)
	row.add_child(_search_row)
	_strip.add_child(row)
	_root.add_child(_strip)
	_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_strip.offset_top = 80


func _build_toast() -> void:
	_toast = PanelContainer.new()
	var s := SeriesTheme.panel_box(Color(0.08, 0.06, 0.05, 0.95), SeriesTheme.BRASS, 20)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 9
	s.content_margin_bottom = 10
	_toast.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_toast_label = SeriesTheme.label("", "book", 19, SeriesTheme.TEXT)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(380, 0)  # wrapping labels need a width
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_play = Button.new()
	# TRANSLATORS: Button on "Opponent ready — play now?": leave the AI game (it's saved) and start the online game.
	_toast_play.text = L10n.t("Play now")
	_toast_play.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	_toast_play.pressed.connect(func() -> void:
		_hide_toast()
		game.play.accept_background())
	_toast_later = Button.new()
	# TRANSLATORS: Button on "Opponent ready — play now?": keep playing the AI and stop looking.
	_toast_later.text = L10n.t("Not now")
	_toast_later.pressed.connect(func() -> void:
		_hide_toast()
		game.play.decline_background())
	row.add_child(_toast_label)
	row.add_child(_toast_play)
	row.add_child(_toast_later)
	_toast.add_child(row)
	_toast.visible = false
	_root.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 128


func _build_dialog() -> void:
	_dialog = Control.new()
	_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.42)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(center)
	var card := PanelContainer.new()
	var s := SeriesTheme.panel_box(Color(0.08, 0.06, 0.05, 0.97), SeriesTheme.BRASS, 14)
	s.content_margin_left = 36
	s.content_margin_right = 36
	s.content_margin_top = 26
	s.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel", s)
	card.custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_dialog_text = SeriesTheme.label("", "book", 24, SeriesTheme.TEXT)
	_dialog_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(400, 0)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	_dialog_yes = Button.new()
	_dialog_yes.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	_dialog_yes.custom_minimum_size = Vector2(150, 52)
	_dialog_yes.pressed.connect(func() -> void: _answer(true))
	_dialog_no = Button.new()
	_dialog_no.custom_minimum_size = Vector2(150, 52)
	_dialog_no.pressed.connect(func() -> void: _answer(false))
	buttons.add_child(_dialog_yes)
	buttons.add_child(_dialog_no)
	box.add_child(_dialog_text)
	box.add_child(buttons)
	card.add_child(box)
	center.add_child(card)
	_root.add_child(_dialog)


# --- Behaviour ---------------------------------------------------------------

func refresh() -> void:
	if _strip == null:
		return
	var play: Node = game.play
	var net_game: bool = game.is_network() and not game.tutorial_active
	var searching: bool = play.background and not game.is_network()
	# Hidden under the main menu; kept over the in-game menu (the clock runs on).
	var menu_open: bool = game.menu != null and game.menu.is_open() and not game.menu.is_paused()
	_strip.visible = (net_game or searching) and not menu_open
	_name.visible = net_game
	_status.visible = false
	_clock.visible = false
	_search_row.visible = searching
	if net_game:
		_name.text = play.opponent_name()
	_tick()


func _process(delta: float) -> void:
	if _toast.visible and not _offer_open:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_hide_toast()
	if _strip.visible:
		_tick()


## The parts that change every second: reconnect countdown and turn clock.
func _tick() -> void:
	var play: Node = game.play
	if not game.is_network() or play.net == null:
		return
	var secs: int = play.reconnect_seconds_left()
	if secs >= 0:
		# TRANSLATORS: The connection to the other player dropped. %d is the seconds left before the game is given up.
		_status.text = L10n.t("Reconnecting… %d s") % secs
		_status.visible = true
	elif play.net.phase == NetMatch.Phase.CLOSED and game.session.is_ongoing():
		# TRANSLATORS: The other player's device can no longer be reached.
		_status.text = L10n.t("Disconnected")
		_status.visible = true
	else:
		_status.visible = false
	var left: int = play.net.seconds_left()
	_clock.visible = left >= 0
	if left >= 0:
		_clock.text = PlayText.clock(left)
		_clock.add_theme_color_override("font_color", WARN if left <= 10 else SeriesTheme.ACCENT)


func show_toast(text: String, seconds := 3.5) -> void:
	if _offer_open:
		return  # don't cover "play now?"
	_toast_label.text = text
	_toast_play.visible = false
	_toast_later.visible = false
	_toast.visible = true
	_toast_left = seconds


func _hide_toast() -> void:
	_toast.visible = false
	_offer_open = false


func _on_background_found() -> void:
	# TRANSLATORS: A quick-match opponent was found while the player plays the AI. Short: it sits over the board with two buttons.
	_toast_label.text = L10n.t("Opponent ready — play now?")
	_toast_play.visible = true
	_toast_later.visible = true
	_toast.visible = true
	_offer_open = true


func _on_asked(what: String) -> void:
	match what:
		"draw":
			_ask(L10n.t("Your opponent offers a draw."), L10n.t("Accept"), L10n.t("Decline"),
				func(ok: bool) -> void: game.play.answer("draw", ok))
		"undo":
			_ask(L10n.t("Your opponent asks to take back their last move."), L10n.t("Allow"), L10n.t("Refuse"),
				func(ok: bool) -> void: game.play.answer("undo", ok))
		"rematch":
			_ask(L10n.t("Your opponent wants a rematch."), L10n.t("Accept"), L10n.t("Decline"),
				func(ok: bool) -> void: game.play.answer("rematch", ok))


## Asks before resigning (the Resign button).
func ask_resign() -> void:
	# TRANSLATORS: Confirmation before giving up a game against another player.
	_ask(L10n.t("Resign this game?"), L10n.t("Resign"), L10n.t("Keep playing"),
		func(ok: bool) -> void:
			if ok:
				game.play.resign())


func _ask(text: String, yes: String, no: String, on_answer: Callable) -> void:
	_dialog_text.text = text
	_dialog_yes.text = yes
	_dialog_no.text = no
	_on_answer = on_answer
	_dialog.visible = true


func _answer(ok: bool) -> void:
	_dialog.visible = false
	if _on_answer.is_valid():
		var c := _on_answer
		_on_answer = Callable()
		c.call(ok)


func dialog_open() -> bool:
	return _dialog != null and _dialog.visible
