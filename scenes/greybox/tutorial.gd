extends CanvasLayer
## "How to play": plays the title's walkthrough (HuntTutorials) on the real
## board, switching to the variation's rule set for the steps at the end. For
## each step it sets the position, shows the marks, then plays the
## scripted moves one by one, highlighting the piece and where it goes, while
## a card on the left (where the game settings usually are) explains the rule. Back, Next, Replay and Close;
## the game that was on the board comes back afterwards.
##
## The greybox owns the board and pieces; this only drives them, the same way
## a player's clicks or the AI do (framework §7, TutorialRunner, built here
## first and moved to timeless-core's shell later).

const FIRST_MOVE_DELAY := 1.1
const BETWEEN_MOVES := 0.8
const SHOW_TARGET := 0.6

signal finished(play_now: bool)

var game: Node
var _steps: Array[Dictionary] = []
var _index := 0
var _run := 0  # bumps on every step change, so stale coroutines stop

var _card: PanelContainer
var _counter: Label
var _title: Label
var _text: Label
var _back: Button
var _next: Button
var _replay: Button


func _init(owner_game: Node) -> void:
	game = owner_game
	layer = 2
	visible = false


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(func() -> void:
		if _card:
			_place.call_deferred())


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = SeriesTheme.theme()
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(root)
	_card = PanelContainer.new()
	var s := SeriesTheme.panel_box(Color(0.08, 0.06, 0.05, 0.94), SeriesTheme.BRASS, 14)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 20
	s.content_margin_bottom = 20
	_card.add_theme_stylebox_override("panel", s)
	_card.custom_minimum_size = Vector2(430, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_counter = SeriesTheme.label("", "caps", 15, SeriesTheme.TEXT_DIM)
	box.add_child(_counter)
	_title = SeriesTheme.label("", "display", 28, SeriesTheme.ACCENT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(370, 0)
	box.add_child(_title)
	_text = SeriesTheme.label("", "book", 20, SeriesTheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(370, 0)
	box.add_child(_text)
	box.add_child(HSeparator.new())
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 8)
	var close := Button.new()
	close.text = L10n.t("Close")
	close.pressed.connect(func() -> void: stop(false))
	_replay = Button.new()
	# TRANSLATORS: Button: play this step of the walkthrough again.
	_replay.text = L10n.t("Replay")
	_replay.pressed.connect(func() -> void: _show(_index))
	_back = Button.new()
	_back.text = L10n.t("‹ Back")
	_back.pressed.connect(func() -> void: _show(_index - 1))
	_next = Button.new()
	_next.add_theme_color_override("font_color", SeriesTheme.ACCENT)
	_next.pressed.connect(_on_next)
	buttons.add_child(_back)
	buttons.add_child(_next)
	buttons.add_child(_replay)
	buttons.add_child(close)
	box.add_child(buttons)
	_card.add_child(box)
	root.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	_place()


## Top left, under the menu button and the title plate (landscape: with
## Large text the plate reaches lower); in portrait, under the turn banner
## (which sits below the top corners there).
func _place() -> void:
	var size := get_viewport().get_visible_rect().size
	var y := 118.0
	var hud: Node = game._hud
	if size.y > size.x and hud and hud._turn_panel:
		var banner: Control = hud._turn_panel
		y = banner.offset_top + banner.get_combined_minimum_size().y + 14.0
	elif hud and hud._title_box and hud._title_box.visible:
		var plate: Control = hud._title_box
		y = maxf(y, plate.position.y + plate.get_combined_minimum_size().y + 12.0)
	_card.position = Vector2(28, y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_rebuild.call_deferred()


func _rebuild() -> void:
	_build()
	if visible:
		_fill_card()


func is_running() -> bool:
	return visible


## `rule_set_ids`: the rule sets the walkthrough covers, the main one first
## (HuntTutorials.walkthrough_ids).
func start(rule_set_ids: Array) -> void:
	_steps = HuntTutorials.build_walkthrough(rule_set_ids)
	if _steps.is_empty():
		return
	visible = true
	_show(0)


func stop(play_now: bool) -> void:
	_run += 1
	visible = false
	finished.emit(play_now)


func _on_next() -> void:
	if _index >= _steps.size() - 1:
		stop(true)
	else:
		_show(_index + 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_RIGHT, KEY_SPACE, KEY_ENTER:
			_on_next()
		KEY_LEFT:
			if _index > 0:
				_show(_index - 1)
		KEY_R:
			_show(_index)
		KEY_ESCAPE:
			stop(false)
	get_viewport().set_input_as_handled()


func _fill_card() -> void:
	_place.call_deferred()
	var step := _steps[_index]
	_title.text = L10n.t(step.title)
	_text.text = L10n.t(step.text)
	# TRANSLATORS: Step counter in the walkthrough: step number and number of steps.
	_counter.text = L10n.t("How to play · %d of %d") % [_index + 1, _steps.size()]
	_back.disabled = _index == 0
	_replay.disabled = step.moves.is_empty()
	_next.text = L10n.t("Start playing") if _index == _steps.size() - 1 else L10n.t("Next ›")


func _show(index: int) -> void:
	_index = clampi(index, 0, _steps.size() - 1)
	_run += 1
	var run := _run
	_fill_card()
	var step := _steps[_index]
	_set_position(step)
	for m in step.marks:
		game.tutorial_mark(m[0], m[1])
	if step.moves.is_empty():
		return
	await get_tree().create_timer(FIRST_MOVE_DELAY).timeout
	for mv: PackedInt32Array in step.moves:
		if run != _run:
			return
		game.tutorial_clear_marks()
		if mv[0] != HuntState.Kind.PLACE:
			game.tutorial_mark(mv[1], "select")
		game.tutorial_mark(mv[mv.size() - 1], "capture" if mv[0] == HuntState.Kind.JUMP else "step")
		await get_tree().create_timer(SHOW_TARGET).timeout
		if run != _run:
			return
		game.tutorial_play(mv)
		while game.is_animating():
			await get_tree().process_frame
			if run != _run:
				return
		game.tutorial_clear_marks()
		game.tutorial_show_last_move()
		await get_tree().create_timer(BETWEEN_MOVES).timeout


## A step's position, on its rule set (the variation's steps switch rule
## sets; going back switches back).
func _set_position(step: Dictionary) -> void:
	var r: HuntRuleSet = step.rules
	if game.rules == null or game.rules.id != r.id:
		game.tutorial_use_rules(r)
	game.tutorial_set_state(step.start)
	# The HUD lays itself out (deferred) for the new position: the score
	# panel fits its lines, so the turn banner can move. Place the card again
	# after that, or it sits where the last step's banner was.
	_place.call_deferred()
