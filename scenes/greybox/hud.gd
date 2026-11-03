extends CanvasLayer
## The greybox's in-game interface: title, whose turn it is, the score, a
## contextual hint, the game settings, the move list and the game-over card.
## It reads the greybox's state and calls its methods; it never touches the
## rules itself. Styled by SeriesTheme. All player-facing text goes through
## tr() (framework §0.6); the English strings are the source text.
##
## Keys: N new game, U undo, H hide the panels, Esc close the result card.

const TITLE_NAMES := {
	"bagh_chal": "Bagh Chal",
	"adugo": "Jogo da Onça",
	"komikan": "Jogo da Onça",
}
const RULE_NAMES := {
	HuntRuleSets.BAGH_CHAL_STANDARD: "Standard rules",
	HuntRuleSets.BAGH_CHAL_PARLETT: "Parlett 1976: hunt to the last goat",
	HuntRuleSets.ADUGO: "Adugo",
	HuntRuleSets.KOMIKAN: "Komikan (a Mapuche reconstruction)",
}
const RULE_MENU := {
	HuntRuleSets.BAGH_CHAL_STANDARD: "Bagh Chal · Standard",
	HuntRuleSets.BAGH_CHAL_PARLETT: "Bagh Chal · Parlett 1976",
	HuntRuleSets.ADUGO: "Jogo da Onça · Adugo",
	HuntRuleSets.KOMIKAN: "Jogo da Onça · Komikan",
}
## Side names: [hunter, hunters, prey, preys]. One jaguar or puma, so the
## singular and plural read the same.
const SIDES := {
	"bagh_chal": ["tiger", "tigers", "goat", "goats"],
	"adugo": ["jaguar", "jaguar", "dog", "dogs"],
	"komikan": ["puma", "puma", "dog", "dogs"],
}
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
var _settings_body: VBoxContainer
var _hide_btn: Button
var _rules: OptionButton
var _players: OptionButton
var _level: OptionButton
var _look_row: HBoxContainer
var _look: OptionButton
var _dogs_first: CheckBox
var _undo: Button
var _hint: Label
var _stop: Button
var _moves_panel: PanelContainer
var _moves: RichTextLabel
var _result: Control
var _result_title: Label
var _result_reason: Label
var _panels: Array[Control] = []
var _result_dismissed := false
var _thinking_t := 0.0


func _init(owner_game: Node) -> void:
	game = owner_game
	layer = 1


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = SeriesTheme.theme()
	add_child(_root)
	_build_title()
	_build_turn()
	_build_score()
	_build_settings()
	_build_hint()
	_build_moves()
	_build_result()


# --- Building ----------------------------------------------------------------

func _margin(c: Control, preset: int, x: float, y: float) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	match preset:
		Control.PRESET_TOP_LEFT:
			c.position = Vector2(x, y)
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
	_margin(box, Control.PRESET_TOP_LEFT, 28, 18)


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


func _build_score() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
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
	_panels.append(panel)


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := SeriesTheme.label(tr(label_text), "body", 16, SeriesTheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(70, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(control)
	return row


func _build_settings() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	var caps := SeriesTheme.label(tr("Game"), "caps", 18, SeriesTheme.ACCENT)
	caps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hide_btn = Button.new()
	_hide_btn.text = tr("Hide")
	_hide_btn.flat = true
	_hide_btn.add_theme_font_size_override("font_size", 15)
	_hide_btn.add_theme_color_override("font_color", SeriesTheme.TEXT_DIM)
	_hide_btn.pressed.connect(_toggle_settings)
	head.add_child(caps)
	head.add_child(_hide_btn)
	box.add_child(head)

	_settings_body = VBoxContainer.new()
	_settings_body.add_theme_constant_override("separation", 10)
	box.add_child(_settings_body)

	_rules = OptionButton.new()
	for id in HuntRuleSets.ALL:
		_rules.add_item(tr(RULE_MENU[id]))
	_rules.item_selected.connect(func(i: int) -> void:
		game._rule_set_id = HuntRuleSets.ALL[i]
		game.new_game())
	_settings_body.add_child(_row("Rules", _rules))

	_dogs_first = CheckBox.new()
	_dogs_first.text = tr("The dogs move first")
	_dogs_first.toggled.connect(func(on: bool) -> void:
		game._komikan_dogs_first = on
		game.new_game())
	_settings_body.add_child(_dogs_first)

	_players = OptionButton.new()
	for i in 4:
		_players.add_item("")
	_players.item_selected.connect(func(i: int) -> void:
		game.mode = i
		game.new_game())
	_settings_body.add_child(_row("Players", _players))

	_level = OptionButton.new()
	for label in ["Novice", "Apprentice", "Adept", "Master"]:
		_level.add_item(tr(label))
	_level.item_selected.connect(func(i: int) -> void:
		game.level = i
		refresh())
	_settings_body.add_child(_row("AI", _level))

	_look = OptionButton.new()
	_look.item_selected.connect(func(i: int) -> void:
		var styles: Array = game.art_styles()
		if i < styles.size():
			game.set_art_style(styles[i].id))
	_look_row = _row("Look", _look)
	_settings_body.add_child(_look_row)

	_settings_body.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var new_game := Button.new()
	new_game.text = tr("New game")
	new_game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_game.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	new_game.pressed.connect(func() -> void: game.new_game())
	_undo = Button.new()
	_undo.text = tr("Undo")
	_undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo.pressed.connect(func() -> void: game.undo())
	buttons.add_child(new_game)
	buttons.add_child(_undo)
	_settings_body.add_child(buttons)
	var keys := SeriesTheme.label(tr("N new game · U undo · H hide panels"), "body", 14, Color(SeriesTheme.TEXT_DIM, 0.75))
	_settings_body.add_child(keys)

	panel.add_child(box)
	_root.add_child(panel)
	_margin(panel, Control.PRESET_TOP_LEFT, 28, 118)
	_panels.append(panel)


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
	_stop = Button.new()
	_stop.text = tr("Stop here")
	_stop.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	_stop.pressed.connect(func() -> void:
		if game._chain.size() > 2:
			game.commit(game._chain))
	row.add_child(_hint)
	row.add_child(_stop)
	panel.add_child(row)
	_root.add_child(panel)
	_margin(panel, Control.PRESET_CENTER_BOTTOM, 0, 22)


func _build_moves() -> void:
	_moves_panel = PanelContainer.new()
	_moves_panel.custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(SeriesTheme.label(tr("Moves"), "caps", 16, SeriesTheme.ACCENT))
	_moves = RichTextLabel.new()
	_moves.bbcode_enabled = true
	_moves.fit_content = true
	_moves.scroll_active = false
	_moves.custom_minimum_size = Vector2(220, 0)
	_moves.add_theme_font_override("normal_font", SeriesTheme.font("ui"))
	_moves.add_theme_font_size_override("normal_font_size", 16)
	_moves.add_theme_constant_override("line_separation", 3)
	box.add_child(_moves)
	_moves_panel.add_child(box)
	_root.add_child(_moves_panel)
	_margin(_moves_panel, Control.PRESET_BOTTOM_RIGHT, 28, 22)
	_panels.append(_moves_panel)


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
	card.custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
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
	again.text = tr("Play again")
	again.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	again.pressed.connect(func() -> void: game.new_game())
	var look := Button.new()
	look.text = tr("Look at the board")
	look.pressed.connect(func() -> void:
		_result_dismissed = true
		refresh())
	buttons.add_child(again)
	buttons.add_child(look)
	box.add_child(buttons)
	card.add_child(box)
	center.add_child(card)
	_root.add_child(_result)


# --- Behaviour ---------------------------------------------------------------

func _toggle_settings() -> void:
	_settings_body.visible = not _settings_body.visible
	_hide_btn.text = tr("Hide") if _settings_body.visible else tr("Show")


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_N:
			game.new_game()
		KEY_U:
			game.undo()
		KEY_H:
			for p in _panels:
				p.visible = not p.visible
		KEY_ESCAPE:
			if _result.visible:
				_result_dismissed = true
				refresh()


func _process(delta: float) -> void:
	if _thinking.visible:
		_thinking_t += delta
		_thinking.text = tr("thinking") + ".".repeat(1 + int(_thinking_t * 2.5) % 3)


func _sides() -> Array:
	return SIDES[game._title()]


## Called by the greybox whenever anything changes.
func refresh() -> void:
	if _title == null:
		return
	var sides := _sides()
	var title_id: String = game._title()
	var state: HuntState = game.state
	var rules: HuntRuleSet = game.rules
	_title.text = tr(TITLE_NAMES[title_id])
	_subtitle.text = tr(RULE_NAMES[game._rule_set_id])
	# Settings, kept in step when code (tools, tests) changes the setup.
	_rules.selected = HuntRuleSets.ALL.find(game._rule_set_id)
	_players.set_item_text(0, tr("Two players (hotseat)"))
	_players.set_item_text(1, tr("You play the %s") % tr(sides[3]))
	_players.set_item_text(2, tr("You play the %s") % tr(sides[1]))
	_players.set_item_text(3, tr("Watch the AI play"))
	_players.selected = game.mode
	_level.selected = game.level
	_dogs_first.set_pressed_no_signal(game._komikan_dogs_first)
	_dogs_first.visible = game._rule_set_id == HuntRuleSets.KOMIKAN
	var styles: Array = game.art_styles()
	_look_row.visible = styles.size() > 1
	_look.clear()
	for st in styles:
		_look.add_item(tr(st.display_name))
		_look.set_item_tooltip(_look.item_count - 1, tr(st.description))
	var cur = game.current_style()
	if cur:
		_look.selected = styles.find(cur)
	_undo.disabled = game.history.is_empty()

	# Turn.
	var hunter_turn := state.side == HuntState.HUNTER
	var mover: String = sides[1] if hunter_turn else sides[3]
	(_turn_token.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = HUNTER_TOKEN if hunter_turn else PREY_TOKEN
	var thinking: bool = game._ai_task >= 0 or (game.status == HuntState.Status.ONGOING and game._is_ai_side(state.side))
	match game.status:
		HuntState.Status.ONGOING:
			_turn.text = tr("%s to move") % tr(mover).capitalize()
		HuntState.Status.HUNTER_WIN:
			_turn.text = tr("The %s won") % tr(sides[1])
		HuntState.Status.PREY_WIN:
			_turn.text = tr("The %s won") % tr(sides[3])
		_:
			_turn.text = tr("A draw")
	_thinking.visible = thinking and game.status == HuntState.Status.ONGOING
	if not _thinking.visible:
		_thinking_t = 0.0

	# Score.
	_captured_label.text = tr("Captured  %d / %d") % [state.captured, rules.capture_target]
	for c in _captured_pips.get_children():
		c.queue_free()
	var pip := 12 if rules.capture_target <= 12 else 9
	for i in rules.capture_target:
		_captured_pips.add_child(SeriesTheme.token(PREY_TOKEN, pip, i < state.captured))
	_hand.visible = state.reserve > 0
	_hand.text = tr("%d %s still to place") % [state.reserve, tr(sides[3])]
	var quiet_on: bool = rules.no_capture_limit_plies > 0 and state.reserve == 0 and state.quiet_plies > 0
	_quiet.visible = quiet_on
	_quiet.text = tr("Moves without a capture: %d / %d") % [state.quiet_plies, rules.no_capture_limit_plies]

	# Hint.
	_hint.text = _hint_text(sides)
	_stop.visible = game._chain.size() > 2
	_hint.get_parent().get_parent().visible = _hint.text != "" or _stop.visible

	# Moves.
	var lines: PackedStringArray = []
	var start := maxi(0, game.history.size() - 10)
	var replay := HuntState.create(rules)
	for k in game.history.size():
		if k >= start:
			var mv: PackedInt32Array = game.history[k]
			var who: Color = HUNTER_TOKEN if replay.side == HuntState.HUNTER else PREY_TOKEN
			lines.append("[color=#%s]%3d[/color]  [color=#%s]●[/color] %s" % [
				SeriesTheme.TEXT_DIM.to_html(false), k + 1, who.to_html(false), replay.describe(mv)])
		replay.make(game.history[k])
	_moves.text = "\n".join(lines) if not lines.is_empty() else "[color=#%s]%s[/color]" % [SeriesTheme.TEXT_DIM.to_html(false), tr("No moves yet")]

	# Result card.
	var over: bool = game.status != HuntState.Status.ONGOING
	if not over:
		_result_dismissed = false
	_result.visible = over and not _result_dismissed
	if over:
		match game.status:
			HuntState.Status.HUNTER_WIN:
				_result_title.text = tr("The %s win") % tr(sides[1]) if sides[1] != sides[0] else tr("The %s wins") % tr(sides[0])
			HuntState.Status.PREY_WIN:
				_result_title.text = tr("The %s win") % tr(sides[3])
			_:
				_result_title.text = tr("A draw")
		_result_reason.text = _reason_text(sides, state, rules)


func _hint_text(sides: Array) -> String:
	if game.status != HuntState.Status.ONGOING:
		return ""
	var state: HuntState = game.state
	if game.mode == 3:
		return tr("Watching the AI play both sides.")
	if game._is_ai_side(state.side):
		return ""
	if game._chain.size() > 2:
		return tr("Capture chain: pick the next landing, or stop here.")
	if state.side == HuntState.PREY and state.reserve > 0:
		return tr("Place a %s on any empty point.") % tr(sides[2])
	if game._selected >= 0:
		for m in state.legal_moves(false):
			if m[0] == HuntState.Kind.JUMP and m[1] == game._selected:
				return tr("Pick where it goes. A broken ring marks a capture.")
		return tr("Pick where it goes.")
	var piece: String = sides[0] if state.side == HuntState.HUNTER else sides[2]
	return tr("Choose a %s to move.") % tr(piece)


func _reason_text(sides: Array, state: HuntState, rules: HuntRuleSet) -> String:
	match state.last_reason:
		HuntState.Reason.CAPTURE_TARGET:
			return tr("%d %s captured.") % [rules.capture_target, tr(sides[3])]
		HuntState.Reason.HUNTER_TRAPPED:
			if sides[0] == sides[1]:
				return tr("The %s is trapped and can't move.") % tr(sides[0])
			return tr("The %s are trapped: none of them can move.") % tr(sides[1])
		HuntState.Reason.PREY_STUCK:
			return tr("The %s can't move.") % tr(sides[3])
		HuntState.Reason.REPETITION_BLOCKED:
			return tr("Every move left would repeat an earlier position.")
		HuntState.Reason.THREEFOLD:
			return tr("The same position came up three times.")
		HuntState.Reason.NO_CAPTURE_LIMIT:
			return tr("No capture in %d moves each.") % (rules.no_capture_limit_plies / 2)
	return ""
