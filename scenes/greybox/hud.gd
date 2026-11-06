extends CanvasLayer
## The in-game interface: the menu button, title, whose turn it is, the
## score, a contextual hint, Undo (local games), the move list and the
## game-over card. Game choices live in the menus (scenes/play/play_menu.gd):
## the main menu sets up a game, and the menu button opens the in-game menu
## (Continue, Look, Language, Quit to main menu). It reads the greybox's
## state and calls its methods; it never touches the rules itself. Styled by
## SeriesTheme.
##
## Text: every string is English source text, translated through L10n (and
## HuntText for sentences that name a side). Controls don't auto-translate;
## the whole interface is rebuilt when the language changes.
##
## Keys: Esc closes the result card or opens the in-game menu; U undoes.
##
## Against another device the opponent strip, toasts and questions are in
## scenes/play/match_ui.gd.

const HUNTER_TOKEN := Color(0.93, 0.62, 0.25)
const PREY_TOKEN := Color(0.9, 0.88, 0.82)

var game: Node

var _root: Control
var _title: Label
var _subtitle: Label
var _turn_token: Panel
var _turn: Label
var _thinking: Label
var _captured_label: Label
var _captured_pips: HFlowContainer
var _hand: Label
var _quiet: Label
var _title_box: VBoxContainer
var _menu_button: Button
var _score_panel: PanelContainer
var _undo: Button
var _result_you: Label
var _again: Button
var _new_opponent: Button
var _hint: Label
var _hint_panel: PanelContainer
var _turn_panel: PanelContainer
var _stop: Button
var _moves_panel: PanelContainer
var _moves: RichTextLabel
var _result: Control
var _result_title: Label
var _result_reason: Label
var _result_dismissed := false
var _thinking_t := 0.0


func _init(owner_game: Node) -> void:
	game = owner_game
	layer = 1


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_build()


func _build() -> void:
	if _root:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = SeriesTheme.theme()
	_root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_root)
	_build_menu_button()
	_build_title()
	_build_turn()
	_build_score()
	_build_undo()
	_build_hint()
	_build_moves()
	_build_result()
	_layout()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build.call_deferred()


# --- Building ----------------------------------------------------------------

func _margin(c: Control, preset: int, x: float, y: float) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	match preset:
		Control.PRESET_TOP_LEFT:
			c.grow_horizontal = Control.GROW_DIRECTION_END
			c.grow_vertical = Control.GROW_DIRECTION_END
			c.position = Vector2(x, y)
		Control.PRESET_BOTTOM_LEFT:
			c.grow_horizontal = Control.GROW_DIRECTION_END
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.offset_left = x
			c.offset_bottom = -y
		Control.PRESET_TOP_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			c.offset_right = -x
			c.offset_top = y
		Control.PRESET_BOTTOM_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.offset_right = -x
			c.offset_bottom = -y
		Control.PRESET_CENTER_TOP:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.offset_top = y
		Control.PRESET_CENTER_BOTTOM:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.offset_bottom = -y


func _build_title() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = SeriesTheme.label("", "display", 44, SeriesTheme.TEXT)
	_subtitle = SeriesTheme.label("", "italic", 20, SeriesTheme.TEXT_DIM)
	box.add_child(_title)
	box.add_child(_subtitle)
	_root.add_child(box)
	_margin(box, Control.PRESET_TOP_LEFT, 96, 18)
	_title_box = box


## The round button that opens the in-game menu.
func _build_menu_button() -> void:
	_menu_button = Button.new()
	_menu_button.custom_minimum_size = Vector2(60, 60)
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.tooltip_text = L10n.t("Menu")
	for st in ["normal", "hover", "pressed"]:
		var bg := SeriesTheme.PANEL if st == "normal" else SeriesTheme.BUTTON_HOVER
		_menu_button.add_theme_stylebox_override(st, SeriesTheme.panel_box(bg, SeriesTheme.BRASS_DIM, 28))
	var icon := SeriesIcon.make("menu", 26)
	icon.position = Vector2(15, 15)  # centered in the 56 px button
	_menu_button.add_child(icon)
	_menu_button.pressed.connect(func() -> void: game.menu.open("pause"))
	_root.add_child(_menu_button)
	_margin(_menu_button, Control.PRESET_TOP_LEFT, 28, 22)


## Undo, for games on this device (against the AI, pass and play).
func _build_undo() -> void:
	_undo = Button.new()
	_undo.custom_minimum_size = Vector2(0, 56)
	_undo.focus_mode = Control.FOCUS_NONE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(SeriesIcon.make("undo", 20))
	var l := SeriesTheme.label(L10n.t("Undo"), "medium", 18, SeriesTheme.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	_undo.add_child(row)
	_undo.custom_minimum_size.x = l.get_minimum_size().x + 70
	_undo.pressed.connect(func() -> void: game.undo())
	_root.add_child(_undo)
	_margin(_undo, Control.PRESET_BOTTOM_LEFT, 28, 22)


func _build_turn() -> void:
	var panel := PanelContainer.new()
	var s := SeriesTheme.panel_box(SeriesTheme.PANEL, SeriesTheme.BRASS_DIM, 24)
	s.content_margin_left = 22
	s.content_margin_right = 24
	s.content_margin_top = 8
	s.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_turn_token = SeriesTheme.token(HUNTER_TOKEN, 16)
	_turn_token.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_turn = SeriesTheme.label("", "medium", 24)
	_thinking = SeriesTheme.label("", "italic", 19, SeriesTheme.TEXT_DIM)
	row.add_child(_turn_token)
	row.add_child(_turn)
	row.add_child(_thinking)
	panel.add_child(row)
	_root.add_child(panel)
	_margin(panel, Control.PRESET_CENTER_TOP, 0, 22)
	_turn_panel = panel


func _build_score() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_captured_label = SeriesTheme.label("", "caps", 16, SeriesTheme.ACCENT)
	_captured_pips = HFlowContainer.new()
	_captured_pips.add_theme_constant_override("h_separation", 6)
	_captured_pips.add_theme_constant_override("v_separation", 6)
	_hand = SeriesTheme.label("", "body", 17, SeriesTheme.TEXT)
	_quiet = SeriesTheme.label("", "body", 15, SeriesTheme.TEXT_DIM)
	box.add_child(_captured_label)
	box.add_child(_captured_pips)
	box.add_child(_hand)
	box.add_child(_quiet)
	panel.add_child(box)
	_root.add_child(panel)
	_margin(panel, Control.PRESET_TOP_RIGHT, 28, 22)
	_score_panel = panel


func _build_hint() -> void:
	var panel := PanelContainer.new()
	var s := SeriesTheme.panel_box(SeriesTheme.PANEL_SOFT, Color(0, 0, 0, 0), 20)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 7
	s.content_margin_bottom = 8
	s.shadow_size = 0
	panel.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_hint = SeriesTheme.label("", "book", 20, SeriesTheme.TEXT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stop = Button.new()
	# TRANSLATORS: Button: end a chain of captures after the current jump.
	_stop.text = L10n.t("Stop here")
	_stop.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	_stop.pressed.connect(func() -> void:
		if game._chain.size() > 2:
			game.commit(game._chain))
	row.add_child(_hint)
	row.add_child(_stop)
	panel.add_child(row)
	_root.add_child(panel)
	_margin(panel, Control.PRESET_CENTER_BOTTOM, 0, 22)
	_hint_panel = panel


func _build_moves() -> void:
	_moves_panel = PanelContainer.new()
	_moves_panel.custom_minimum_size = Vector2(270, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	# TRANSLATORS: Title of the list of moves played so far.
	box.add_child(SeriesTheme.label(L10n.t("Moves"), "caps", 16, SeriesTheme.ACCENT))
	_moves = RichTextLabel.new()
	_moves.bbcode_enabled = true
	_moves.fit_content = true
	_moves.scroll_active = false
	_moves.custom_minimum_size = Vector2(240, 0)
	_moves.add_theme_font_override("normal_font", SeriesTheme.font("ui"))
	_moves.add_theme_font_size_override("normal_font_size", SeriesTheme.fs(16))
	_moves.add_theme_constant_override("line_separation", 3)
	box.add_child(_moves)
	_moves_panel.add_child(box)
	_root.add_child(_moves_panel)
	_margin(_moves_panel, Control.PRESET_BOTTOM_RIGHT, 28, 22)


func _build_result() -> void:
	_result = Control.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.42)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(center)
	var card := PanelContainer.new()
	var s := SeriesTheme.panel_box(Color(0.08, 0.06, 0.05, 0.96), SeriesTheme.BRASS, 14)
	s.content_margin_left = 44
	s.content_margin_right = 44
	s.content_margin_top = 30
	s.content_margin_bottom = 30
	card.add_theme_stylebox_override("panel", s)
	card.custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_result_you = SeriesTheme.label("", "caps", 20, SeriesTheme.TEXT_DIM)
	_result_you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_you)
	_result_title = SeriesTheme.label("", "display", 46, SeriesTheme.ACCENT)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_reason = SeriesTheme.label("", "italic", 22, SeriesTheme.TEXT)
	_result_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_reason.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_result_title)
	box.add_child(_result_reason)
	box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	var again := Button.new()
	again.text = L10n.t("Play again")
	again.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	again.pressed.connect(func() -> void:
		if game.is_network():
			game.play.request_rematch()
		else:
			game.new_game())
	_again = again
	_new_opponent = Button.new()
	# TRANSLATORS: Button after an online quick match: look for someone else to play.
	_new_opponent.text = L10n.t("New opponent")
	_new_opponent.pressed.connect(func() -> void:
		game.quit_to_menu("quick")
		game.play.quick_start())
	var to_menu := Button.new()
	# TRANSLATORS: Button on the game-over card: back to the main menu.
	to_menu.text = L10n.t("Main menu")
	to_menu.pressed.connect(func() -> void: game.quit_to_menu())
	var look := Button.new()
	# TRANSLATORS: Button on the game-over card: close it to look at the final position.
	look.text = L10n.t("Look at the board")
	look.pressed.connect(func() -> void:
		_result_dismissed = true
		refresh())
	buttons.add_child(again)
	buttons.add_child(_new_opponent)
	buttons.add_child(to_menu)
	buttons.add_child(look)
	box.add_child(buttons)
	card.add_child(box)
	center.add_child(card)
	_root.add_child(_result)


## Portrait (phones held upright) has no room for the title beside the turn
## banner; the in-game menu shows the game's name instead.
## Places what depends on the screen's shape. Landscape: the turn banner at
## the top and the hint at the bottom, between the corner panels. Portrait
## (narrow): the turn banner goes under the top corners, and the hint, wrapped
## to the screen, above the Undo button and the move list.
func _layout() -> void:
	if _title_box == null:
		return
	var size := get_viewport().get_visible_rect().size
	var portrait := size.y > size.x
	_title_box.visible = not portrait
	var edge := 28.0
	var side_w := _score_panel.get_combined_minimum_size().x
	if portrait:
		_turn_panel.offset_top = 22.0 + maxf(_score_panel.get_combined_minimum_size().y, _menu_button.custom_minimum_size.y) + 14.0
	else:
		_turn_panel.offset_top = 22.0
	# The hint wraps at the room it has (the panel adds 44 of padding).
	var room := size.x - 2.0 * edge - 44.0 if portrait else size.x - 2.0 * (edge + side_w + 24.0) - 44.0
	if _stop.visible:
		room -= _stop.get_combined_minimum_size().x + 14.0
	var font := _hint.get_theme_font("font")
	var one_line := font.get_string_size(_hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _hint.get_theme_font_size("font_size")).x
	_hint.custom_minimum_size.x = minf(ceilf(one_line) + 2.0, maxf(room, 120.0))
	var bottom := 22.0
	if portrait:
		var under := maxf(_undo.get_combined_minimum_size().y if _undo.visible else 0.0,
			_moves_panel.get_combined_minimum_size().y if _moves_panel.visible else 0.0)
		bottom += under + 14.0
	_hint_panel.offset_bottom = -bottom


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or game.tutorial_active or game.menu.is_open() or game._match_ui.dialog_open():
		return
	match k.keycode:
		KEY_U:
			game.undo()
		KEY_ESCAPE:
			if _result.visible:
				_result_dismissed = true
				refresh()
			else:
				game.menu.open("pause")


func _process(delta: float) -> void:
	if _thinking.visible:
		_thinking_t += delta
		# TRANSLATORS: The AI is choosing its move. Shown after the turn banner, followed by animated dots.
		_thinking.text = L10n.t("thinking") + ".".repeat(1 + int(_thinking_t * 2.5) % 3)


## Called by the greybox whenever anything changes.
func refresh() -> void:
	if _title == null or game.state == null:
		return
	var title_id: String = game._title()
	var state: HuntState = game.state
	var rules: HuntRuleSet = game.rules
	var teaching: bool = game.tutorial_active
	_title.text = HuntText.title_name(title_id)
	_subtitle.text = HuntText.rule_set_name(game._rule_set_id)
	var net_game: bool = game.is_network()
	var shown: bool = not teaching
	_root.visible = game.menu == null or not game.menu.is_open()
	_menu_button.visible = shown
	_undo.visible = shown and not net_game and game.mode != game.Mode.AI_VS_AI
	_undo.disabled = not game.can_undo()
	_moves_panel.visible = shown

	# Turn.
	var hunter_turn := state.side == HuntState.HUNTER
	(_turn_token.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = HUNTER_TOKEN if hunter_turn else PREY_TOKEN
	var thinking: bool = game.ai_thinking() or (game.status == HuntState.Status.ONGOING and game._is_ai_side(state.side))
	match game.status:
		HuntState.Status.ONGOING:
			_turn.text = HuntText.to_move(title_id, hunter_turn)
		HuntState.Status.HUNTER_WIN:
			_turn.text = HuntText.won(title_id, true)
		HuntState.Status.PREY_WIN:
			_turn.text = HuntText.won(title_id, false)
		_:
			_turn.text = L10n.t("A draw")
	_thinking.visible = thinking and game.status == HuntState.Status.ONGOING
	if not _thinking.visible:
		_thinking_t = 0.0

	# Score.
	# TRANSLATORS: Pieces captured so far / captures needed to win.
	_captured_label.text = L10n.t("Captured %d / %d") % [state.captured, rules.capture_target]
	for c in _captured_pips.get_children():
		c.queue_free()
	var pip := 12 if rules.capture_target <= 12 else 9
	for i in rules.capture_target:
		_captured_pips.add_child(SeriesTheme.token(PREY_TOKEN, pip, i < state.captured))
	_hand.visible = state.reserve > 0
	_hand.text = HuntText.prey_in_hand(state.reserve)
	var quiet_on: bool = rules.no_capture_limit_plies > 0 and state.reserve == 0 and state.quiet_plies >= 2
	_quiet.visible = quiet_on
	_quiet.text = HuntText.quiet_moves(title_id, state, rules)

	# Hint.
	_hint.text = "" if teaching else _hint_text(title_id)
	_stop.visible = game._chain.size() > 2 and not teaching
	_hint_panel.visible = _hint.text != "" or _stop.visible

	# Moves.
	var lines: PackedStringArray = []
	var start := maxi(0, game.history.size() - 10)
	var replay: HuntState = game.history_start.clone() if game.history_start else HuntState.create(rules)
	for k in game.history.size():
		if k >= start:
			var mv: PackedInt32Array = game.history[k]
			var who: Color = HUNTER_TOKEN if replay.side == HuntState.HUNTER else PREY_TOKEN
			lines.append("[color=#%s]%3d[/color]  [color=#%s]●[/color] %s" % [
				SeriesTheme.TEXT_DIM.to_html(false), k + 1, who.to_html(false), _describe(replay, mv)])
		replay.make(game.history[k])
	_moves.text = "\n".join(lines) if not lines.is_empty() else "[color=#%s]%s[/color]" % [SeriesTheme.TEXT_DIM.to_html(false), L10n.t("No moves yet")]

	# Result card (not during the walkthrough: it shows wins on purpose).
	var over: bool = game.status != HuntState.Status.ONGOING
	if not over:
		_result_dismissed = false
	_result.visible = over and not _result_dismissed and not teaching
	if over:
		match game.status:
			HuntState.Status.HUNTER_WIN:
				_result_title.text = HuntText.win_title(title_id, true)
			HuntState.Status.PREY_WIN:
				_result_title.text = HuntText.win_title(title_id, false)
			_:
				_result_title.text = L10n.t("A draw")
		var session: MatchSession = game.session
		var me: int = game.local_side()
		_result_you.visible = me >= 0 and game.status != HuntState.Status.DRAW
		var my_win: bool = (game.status == HuntState.Status.HUNTER_WIN) == (me == HuntState.HUNTER)
		# TRANSLATORS: Small line above the result when one player is on this device.
		_result_you.text = L10n.t("You won") if my_win else L10n.t("You lost")
		if session.ending != MatchSession.Ending.NONE:
			_result_reason.text = PlayText.ending(session.ending, session.ending_side == me)
		else:
			_result_reason.text = HuntText.reason(title_id, state.last_reason, rules)
		# TRANSLATORS: Button after a game against another player: play them again (sides swap).
		_again.text = L10n.t("Rematch") if net_game else L10n.t("Play again")
		_again.disabled = net_game and not game.play.can_rematch()
		_new_opponent.visible = net_game and session.kind == MatchSession.Kind.QUICK_MATCH
	# The hint and the move list change size: place them again once laid out.
	_layout.call_deferred()


## A move for the move list: point names stay as they are ("c3"), the word
## for a placement is translated.
func _describe(s: HuntState, mv: PackedInt32Array) -> String:
	if mv[0] == HuntState.Kind.PLACE:
		# TRANSLATORS: Move list entry for putting a goat on the board. %s is a point name such as c3.
		return L10n.t("place %s") % s.point_name(mv[1])
	return s.describe(mv)


func _hint_text(title_id: String) -> String:
	if game.status != HuntState.Status.ONGOING:
		return ""
	var state: HuntState = game.state
	if game.mode == 3:
		return L10n.t("Watching the AI play both sides.")
	if game._is_ai_side(state.side):
		return ""
	if game.is_network() and state.side != game.local_side():
		return L10n.t("Waiting for your opponent's move.")
	if game._chain.size() > 2:
		return L10n.t("Capture chain: pick the next landing, or stop here.")
	if state.side == HuntState.PREY and state.reserve > 0:
		return HuntText.place_prey(title_id)
	if game._selected >= 0:
		for m in state.legal_moves(false):
			if m[0] == HuntState.Kind.JUMP and m[1] == game._selected:
				return L10n.t("Pick where it goes. A broken ring marks a capture.")
		return L10n.t("Pick where it goes.")
	return HuntText.choose_piece(title_id, state.side == HuntState.HUNTER)
