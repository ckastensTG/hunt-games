extends Node3D
## Greybox: every v1 rule set playable in 3D. Builds everything in code from
## the BoardDef, so it stays correct while the boards and rules evolve. Bagh
## Chal shows its art styles (titles/bagh_chal/art/); the other titles still
## use placeholder meshes. The interface is hud.gd; "How to play" is
## tutorial.gd; the play menu and network games are in scenes/play/.
##
## Every game is a MatchSession (framework §5): against the AI, pass and play,
## AI vs AI, nearby and online. The board listens to the session, so a move is
## animated the same way whether it came from a click, the AI or the other
## device. Local games are saved after every move (Continue in the menu).

enum Mode { HOTSEAT, HUMAN_PREY, HUMAN_HUNTER, AI_VS_AI, NETWORK }

const SPACING := 1.0
const HudScript := preload("res://scenes/greybox/hud.gd")
const TutorialScript := preload("res://scenes/greybox/tutorial.gd")
const MarkShader := preload("res://scenes/greybox/mark.gdshader")
const MarkInkShader := preload("res://scenes/greybox/mark_ink.gdshader")
const PlayControllerScript := preload("res://scenes/play/play_controller.gd")
const PlayMenuScript := preload("res://scenes/play/play_menu.gd")
const MatchUIScript := preload("res://scenes/play/match_ui.gd")
const PerfTestScript := preload("res://scenes/greybox/perf_test.gd")
const AI_MOVE_DELAY := 0.35
const SAVE_PATH := "user://match.save"
## Piece sounds every look provides (tools/audio/make_sounds.py), and the
## end-of-game stings each title provides.
const PIECE_SOUNDS := ["place", "slide_goat", "slide_tiger", "set_goat", "set_tiger", "land", "capture"]
const STINGS := ["win", "lose", "draw"]
## The greybox's wooden pieces, and each title's stings.
const GREYBOX_SOUNDS := "res://titles/common/audio/wood"
const TITLE_STINGS := {"bagh_chal": "res://titles/bagh_chal/audio/stings"}
## The music fades out for this long when a sting plays (the longest sting
## is 3.6 s), then comes back.
const STING_DUCK := 5.0

const PIECE_COLORS := {
	"bagh_chal": [Color(0.86, 0.48, 0.14), Color(0.93, 0.91, 0.85)],   # tiger, goat
	"adugo": [Color(0.78, 0.6, 0.18), Color(0.5, 0.33, 0.2)],          # jaguar, dog
	"komikan": [Color(0.66, 0.55, 0.42), Color(0.5, 0.33, 0.2)],       # puma, dog
}

## The game on the board.
var session: MatchSession
## The rules, position and moves of `session`. The walkthrough and the tools
## read and set these directly.
var rules: HuntRuleSet:
	get:
		return session.rules if session else null
	set(value):
		session.rules = value
var state: HuntState:
	get:
		return session.state if session else null
	set(value):
		session.state = value
var history: Array[PackedInt32Array]:
	get:
		return session.moves if session else _no_moves
	set(value):
		session.moves = value
## The position `history` starts from (the opening, or a tutorial position).
var history_start: HuntState:
	get:
		return session.start if session else null
	set(value):
		session.start = value
## Who plays which side. Setting it during a local game hands the sides over
## at once (the tools use HOTSEAT to stop the AI). NETWORK is set by
## start_network().
var mode: Mode = Mode.HUMAN_PREY:
	set(value):
		mode = value
		if session and value != Mode.NETWORK and not tutorial_active and not _is_network_kind(session.kind):
			_apply_mode(session)
var evaluator: HuntEvaluator
var personas: Array[AIPersona] = []
var level := 1
## Use the title's art where it exists (Bagh Chal); false shows the greybox.
var use_art := true
## The art style picked for each title that has more than one (style id).
var art_style_ids := {"bagh_chal": "brass"}
var status: HuntState.Status = HuntState.Status.ONGOING
## True while "How to play" drives the board: no AI, no clicks.
var tutorial_active := false
## Saves local games after every move (tools turn it off, or save elsewhere).
var autosave := true
var save_path := SAVE_PATH
## Network games: the controller, and the side played on this device.
var play: Node
var menu: CanvasLayer
## Piece sounds and stings (on the SFX bus; Sound in the in-game menu).
var sfx: SfxPlayer
## The look's music (MusicPlayer, on the Music bus).
var music: MusicPlayer
## The frame-rate readout for testing (F3 or a three-finger tap).
var perf: PerfOverlay
## Auto graphics measures and steps down on devices (not in the editor).
var graphics_auto := not OS.has_feature("editor")
var _graphics_auto := GameGraphics.Auto.new()
## Test builds: the performance test from the in-game menu (perf_test.gd).
var perf_test: CanvasLayer

var _rule_set_id := HuntRuleSets.BAGH_CHAL_STANDARD
var _komikan_dogs_first := false
var _no_moves: Array[PackedInt32Array] = []
var _local_mode: Mode = Mode.HUMAN_PREY
var _net_side := -1
var _camera: Camera3D
var _world_env: WorldEnvironment
var _grey_env: Environment
var _grey_key: DirectionalLight3D
var _styles := {}  # title id -> Array[HuntArtStyle]
var _hud: CanvasLayer
var _match_ui: CanvasLayer
var _tutorial: CanvasLayer
var _saved_session: MatchSession
var _tutorial_from_menu := false
var _tween: Tween
var _anim_queue: Array[PackedInt32Array] = []
var _board_root: Node3D
var _pieces_root: Node3D
var _marks_root: Node3D
var _piece_nodes := {}  # point id -> Node3D
var _center := Vector2.ZERO
var _selected := -1
var _chain := PackedInt32Array()
var _pending_click := Vector2.INF
var _animating := false
var _ai := AIDriver.new()
var _ai_wait := 0.0
var _rng := RandomNumberGenerator.new()
var _sound_dirs := ["", ""]   # the piece and sting folders loaded
var _sting_pending := false



func _ready() -> void:
	_rng.seed = 20261102
	var title := TitleConfig.active()
	if not title.rule_sets.has(_rule_set_id):
		_rule_set_id = title.rule_sets[0]
	L10n.apply_saved_locale()
	personas = _make_personas()
	_styles["bagh_chal"] = BaghChalArt.styles()
	var saved_look := str(L10n.load_setting("look_bagh_chal", ""))
	for st in _styles["bagh_chal"]:
		if st.id == saved_look:
			art_style_ids["bagh_chal"] = saved_look
	level = clampi(int(L10n.load_setting("ai_level", level)), 0, personas.size() - 1)
	GameSound.apply_saved()
	sfx = SfxPlayer.new()
	add_child(sfx)
	music = MusicPlayer.new()
	add_child(music)
	perf = PerfOverlay.new()
	perf.info = _perf_info
	add_child(perf)
	_build_environment()
	play = PlayControllerScript.new(self)
	add_child(play)
	_hud = HudScript.new(self)
	add_child(_hud)
	_match_ui = MatchUIScript.new(self)
	add_child(_match_ui)
	_tutorial = TutorialScript.new(self)
	_tutorial.finished.connect(_on_tutorial_finished)
	add_child(_tutorial)
	menu = PlayMenuScript.new(self)
	add_child(menu)
	# A game left unfinished (the app was closed) carries on where it was;
	# otherwise the main menu, over an empty board.
	if not continue_saved():
		_show_idle_board()
		menu.open()


func _make_personas() -> Array[AIPersona]:
	return HuntPersonas.all()


## The rule set for an id; Komikan with the dogs first is
## "<komikan>+dogs_first" (TitleConfig.DOGS_FIRST).
static func make_rule_set(id: String) -> HuntRuleSet:
	var base := id.trim_suffix(TitleConfig.DOGS_FIRST)
	if base == HuntRuleSets.KOMIKAN:
		return HuntRuleSets.komikan(HuntRuleSet.PREY if id.ends_with(TitleConfig.DOGS_FIRST) else HuntRuleSet.HUNTER)
	return HuntRuleSets.by_id(base)


# --- Game flow -------------------------------------------------------------

## A new local game with the current mode, rule set and level.
func new_game() -> void:
	if tutorial_active or mode == Mode.NETWORK:
		return
	if menu:
		menu.close()
	var id := _rule_set_id
	if id == HuntRuleSets.KOMIKAN and _komikan_dogs_first:
		id += TitleConfig.DOGS_FIRST
	var s := MatchSession.create(make_rule_set(id), id, MatchSession.Kind.PASS_AND_PLAY,
		MatchSession.Driver.LOCAL, MatchSession.Driver.LOCAL)
	_apply_mode(s)
	_use_session(s)
	_save()


## Starts a local game from the menu.
func start_local(new_mode: Mode, rule_set_id: String, ai_level := level) -> void:
	if mode == Mode.NETWORK:
		play.leave_match()
		_net_side = -1
	mode = new_mode
	_local_mode = new_mode
	_rule_set_id = rule_set_id.trim_suffix(TitleConfig.DOGS_FIRST)
	level = ai_level
	L10n.save_setting("ai_level", level)
	new_game()


## Shows a network game started by the play controller (both devices built
## the same session; moves arrive through it).
func start_network(s: MatchSession, side: int) -> void:
	if tutorial_active:
		_tutorial.stop(false)
	if mode != Mode.NETWORK:
		_local_mode = mode
	mode = Mode.NETWORK
	_net_side = side
	_rule_set_id = s.rule_set_id.trim_suffix(TitleConfig.DOGS_FIRST)
	if menu:
		menu.close()
	_use_session(s)


## "Quit to main menu": ends the game on the board (a game against another
## device counts as lost if it's still going) and opens the main menu over an
## empty board. A local game's save is dropped; an AI game set aside for an
## online match stays saved, and the main menu offers to continue it.
func quit_to_menu(screen := "home") -> void:
	if tutorial_active:
		return
	_stop_ai()
	if mode == Mode.NETWORK:
		play.leave_match()
		_net_side = -1
		mode = _local_mode
	else:
		if play.background:
			play.decline_background()  # stop looking for an online opponent
		_clear_save()
	_show_idle_board()
	menu.open(screen)


## An empty board for behind the main menu: no AI, nothing saved.
func _show_idle_board() -> void:
	var id := _rule_set_id
	if id == HuntRuleSets.KOMIKAN and _komikan_dogs_first:
		id += TitleConfig.DOGS_FIRST
	_use_session(MatchSession.create(make_rule_set(id), id, MatchSession.Kind.PASS_AND_PLAY,
		MatchSession.Driver.LOCAL, MatchSession.Driver.LOCAL))


func _clear_save() -> void:
	if autosave and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## After a network game: back to the local game that was saved, or a new one.
func leave_network() -> void:
	if mode != Mode.NETWORK:
		return
	_net_side = -1
	mode = _local_mode
	if not continue_saved():
		new_game()


func is_network() -> bool:
	return mode == Mode.NETWORK


static func _is_network_kind(k: MatchSession.Kind) -> bool:
	return k in [MatchSession.Kind.NEARBY, MatchSession.Kind.ONLINE_FRIEND, MatchSession.Kind.QUICK_MATCH]


## The side played on this device, or -1 when both or neither are.
func local_side() -> int:
	match mode:
		Mode.HUMAN_PREY:
			return HuntState.PREY
		Mode.HUMAN_HUNTER:
			return HuntState.HUNTER
		Mode.NETWORK:
			return _net_side
	return -1


func _apply_mode(s: MatchSession) -> void:
	var me := MatchSession.Driver.LOCAL
	var ai := MatchSession.Driver.AI
	match mode:
		Mode.HUMAN_PREY:
			s.kind = MatchSession.Kind.VS_AI
			s.control = {HuntState.HUNTER: ai, HuntState.PREY: me}
		Mode.HUMAN_HUNTER:
			s.kind = MatchSession.Kind.VS_AI
			s.control = {HuntState.HUNTER: me, HuntState.PREY: ai}
		Mode.AI_VS_AI:
			s.kind = MatchSession.Kind.AI_VS_AI
			s.control = {HuntState.HUNTER: ai, HuntState.PREY: ai}
		_:
			s.kind = MatchSession.Kind.PASS_AND_PLAY
			s.control = {HuntState.HUNTER: me, HuntState.PREY: me}
	s.ai_level = {HuntState.HUNTER: level, HuntState.PREY: level}


func _mode_for(s: MatchSession) -> Mode:
	var ai := MatchSession.Driver.AI
	var hunter_ai: bool = s.control[HuntState.HUNTER] == ai
	var prey_ai: bool = s.control[HuntState.PREY] == ai
	if hunter_ai and prey_ai:
		return Mode.AI_VS_AI
	if hunter_ai:
		return Mode.HUMAN_PREY
	if prey_ai:
		return Mode.HUMAN_HUNTER
	return Mode.HOTSEAT


## Puts a session on the board and listens to it.
func _use_session(s: MatchSession) -> void:
	_stop_ai()
	_stop_tween()
	_anim_queue.clear()
	if session and session != s:
		for pair in [[session.move_committed, _on_move_committed], [session.undone, _on_undone],
				[session.reset, _on_reset], [session.game_over, _on_game_over]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	session = s
	_sting_pending = false
	if not s.move_committed.is_connected(_on_move_committed):
		s.move_committed.connect(_on_move_committed)
		s.undone.connect(_on_undone)
		s.reset.connect(_on_reset)
		s.game_over.connect(_on_game_over)
	evaluator = HuntEvaluator.new(HuntRuleSets.weights_for(s.rules))
	_selected = -1
	_chain = PackedInt32Array()
	_build_board()
	_sync_pieces()
	_clear_marks()
	_after_move()


## A move from this device (a click or the walkthrough's "play it").
func commit(move: PackedInt32Array) -> void:
	if not session.commit(move, state.side):
		push_warning("move refused: %s" % state.describe(move))


func undo() -> void:
	if _animating or tutorial_active or mode == Mode.NETWORK or history.is_empty():
		return
	_stop_ai()
	var n := session.undo_count()
	if n == 0:
		n = 1  # AI vs AI: one move back
	session.undo(n)


func can_undo() -> bool:
	return mode != Mode.NETWORK and not history.is_empty()


func _on_move_committed(move: PackedInt32Array, _side: int) -> void:
	_selected = -1
	_chain = PackedInt32Array()
	_clear_marks()
	_save()
	if _animating:
		_anim_queue.append(move)
		return
	_animate(move)


func _on_undone(_count: int) -> void:
	_redraw()
	_save()


func _on_reset() -> void:
	_redraw()


func _on_game_over(_status: int, _reason: int) -> void:
	_save()
	# The sting waits for the last move to land.
	_sting_pending = not tutorial_active
	if not _animating:
		_play_sting()
		_after_move()


## Redraws the pieces from the position (undo, resync), without animating.
func _redraw() -> void:
	_stop_ai()
	_stop_tween()
	_anim_queue.clear()
	_sting_pending = false
	_selected = -1
	_chain = PackedInt32Array()
	_clear_marks()
	_sync_pieces()
	_after_move()


func _after_move() -> void:
	status = session.status()
	if _has_art():
		current_style().set_awaken(0.0 if history.is_empty() else 0.6)
	_refresh_ui()
	_show_last_move()
	if status == HuntState.Status.ONGOING and _is_ai_side(state.side):
		_ai_wait = AI_MOVE_DELAY


func _is_ai_side(side: int) -> bool:
	if tutorial_active or session == null:
		return false
	return session.control.get(side) == MatchSession.Driver.AI


## True while the AI is choosing a move.
func ai_thinking() -> bool:
	return _ai.is_thinking()


## True when a click on the board would play a move now.
func can_play() -> bool:
	if tutorial_active or _animating or _ai.is_thinking() or session == null or status != HuntState.Status.ONGOING:
		return false
	if session.control.get(state.side) != MatchSession.Driver.LOCAL:
		return false
	return mode != Mode.NETWORK or play.can_move()


func _process(delta: float) -> void:
	if graphics_auto and _graphics_auto.step(delta):
		_apply_graphics()
	# The AI waits while a menu covers the board.
	if _ai_wait > 0.0 and not _animating and not (menu and menu.is_open()):
		_ai_wait -= delta
		if _ai_wait <= 0.0 and _is_ai_side(state.side):
			_start_ai()
	if _ai.is_thinking():
		var move := _ai.poll()
		if not _ai.is_thinking():
			if not move.is_empty() and _is_ai_side(state.side):
				session.commit(move, state.side)
			_refresh_ui()


func _start_ai() -> void:
	if _ai.is_thinking() or status != HuntState.Status.ONGOING:
		return
	_ai.start(state, personas[level], evaluator, _rng.randi())
	_refresh_ui()


func _stop_ai() -> void:
	_ai_wait = 0.0
	_ai.cancel()


# --- Saves -----------------------------------------------------------------

## Local games (against the AI, pass and play) are saved after every move.
func _save() -> void:
	if not autosave or tutorial_active or session == null:
		return
	if session.kind != MatchSession.Kind.VS_AI and session.kind != MatchSession.Kind.PASS_AND_PLAY:
		return
	session.ai_level = {HuntState.HUNTER: level, HuntState.PREY: level}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session.to_dict()))


func _load_saved() -> MatchSession:
	if not FileAccess.file_exists(save_path):
		return null
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(v) != TYPE_DICTIONARY:
		return null
	var title := TitleConfig.active()
	var s := MatchSession.from_dict(v, func(id: String) -> HuntRuleSet: return title.resolve_rule_set(id))
	if s == null or not s.is_ongoing() or s.moves.is_empty():
		return null
	return s


## True when there's a saved local game to go back to.
func has_saved_game() -> bool:
	return _load_saved() != null


## Goes back to the saved local game. False if there isn't one.
func continue_saved() -> bool:
	if tutorial_active:
		return false
	var s := _load_saved()
	if s == null:
		return false
	if mode == Mode.NETWORK:
		_net_side = -1
	_rule_set_id = s.rule_set_id.trim_suffix(TitleConfig.DOGS_FIRST)
	_komikan_dogs_first = s.rule_set_id.ends_with(TitleConfig.DOGS_FIRST)
	var ai_side := HuntState.HUNTER if s.control[HuntState.HUNTER] == MatchSession.Driver.AI else HuntState.PREY
	level = clampi(int(s.ai_level.get(ai_side, level)), 0, personas.size() - 1)
	mode = _mode_for(s)
	_local_mode = mode
	_use_session(s)
	if menu:
		menu.close()
	return true


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pending_click = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and _chain.size() > 2 and can_play():
			commit(_chain)


func _physics_process(_delta: float) -> void:
	if _pending_click == Vector2.INF:
		return
	var click := _pending_click
	_pending_click = Vector2.INF
	if not can_play():
		return
	var origin := _camera.project_ray_origin(click)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(click) * 200.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider.has_meta("point"):
		return
	_on_point_clicked(hit.collider.get_meta("point"))


func _on_point_clicked(p: int) -> void:
	var moves := state.legal_moves(false)
	if _chain.size() > 2:
		var here := _chain[_chain.size() - 1]
		if p == here:
			commit(_chain)
			return
		for m in _chain_continuations(moves):
			if m[m.size() - 1] == p:
				_chain = m
				if _chain_continuations(moves).is_empty():
					commit(_chain)
				else:
					_show_chain_marks(moves)
				return
		return
	if state.side == HuntState.PREY and state.reserve > 0:
		var place := PackedInt32Array([HuntState.Kind.PLACE, p])
		if moves.has(place):
			commit(place)
		return
	var own := HuntState.HUNTER if state.side == HuntState.HUNTER else HuntState.PREY
	if state.cells[p] == own:
		_selected = p
		_show_targets(moves)
		return
	if _selected < 0:
		return
	var step := PackedInt32Array([HuntState.Kind.STEP, _selected, p])
	if moves.has(step):
		commit(step)
		return
	for m in moves:
		if m[0] == HuntState.Kind.JUMP and m[1] == _selected and m.size() == 4 and m[3] == p:
			if rules.multi_jump:
				_chain = m
				if _chain_continuations(moves).is_empty():
					commit(_chain)
				else:
					_show_chain_marks(moves)
			else:
				commit(m)
			return


func _chain_continuations(moves: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for m in moves:
		if m.size() == _chain.size() + 2 and m.slice(0, _chain.size()) == _chain:
			out.append(m)
	return out


# --- View: board and pieces ------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.03, 0.028)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_world_env = we
	_grey_env = env
	var key := DirectionalLight3D.new()
	_grey_key = key
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 1.5
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-58, -32, 0)
	add_child(key)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	add_child(_camera)
	get_viewport().size_changed.connect(_fit_orientation)
	_fit_orientation()
	_board_root = Node3D.new()
	add_child(_board_root)
	_pieces_root = Node3D.new()
	_board_root.add_child(_pieces_root)
	_marks_root = Node3D.new()
	_board_root.add_child(_marks_root)


func _build_board() -> void:
	for c in _board_root.get_children():
		if c != _pieces_root and c != _marks_root:
			c.queue_free()
	var board := rules.board
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in board.positions:
		lo = lo.min(p)
		hi = hi.max(p)
	_center = (lo + hi) / 2.0
	var size := (hi - lo) * SPACING
	var extent := maxf(size.x + 1.4, size.y + 1.4)
	if _has_art():
		_build_art_set()
		extent = current_style().camera_extent
	else:
		_build_grey_board(board, size)
	_load_sounds()
	# Points: a pick collider on each (the art and the greybox share these).
	for i in board.point_count():
		var body := StaticBody3D.new()
		body.set_meta("point", i)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.32
		shape.shape = sphere
		body.add_child(shape)
		body.position = to_world(board.positions[i])
		_board_root.add_child(body)
	# Prey players sit at the near edge.
	_board_root.rotation.y = PI if local_side() == HuntState.PREY else 0.0
	_camera.position = Vector3(0, extent * 1.25, extent * 0.95)
	_camera.look_at(Vector3(0, 0, extent * 0.06), Vector3.UP)
	_apply_graphics()
	_graphics_auto.restart()  # building the set stalls a frame or two


## Phones turn both ways (project setting: sensor). In portrait the camera
## keeps the board's width on screen instead of its height, and the interface
## uses a portrait base size so text keeps its size.
func _fit_orientation() -> void:
	var size := get_viewport().get_visible_rect().size
	var portrait := size.y > size.x
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	_camera.fov = 43.0 if portrait else 38.0
	var win := get_window()
	var base := Vector2i(900, 1600) if portrait else Vector2i(1600, 900)
	if win.content_scale_size != base:
		win.content_scale_size = base
	# Low's 3D size depends on the window's pixel count (a desktop window can
	# be resized).
	if _board_root:
		get_viewport().scaling_3d_scale = GameGraphics.render_scale(GameGraphics.tier(), win.size)


func _has_art() -> bool:
	return current_style() != null


## The art styles the current title offers (empty: greybox only).
func art_styles() -> Array:
	if not use_art:
		return []
	return _styles.get(_title(), [])


## The active art style for the current title, or null for the greybox.
func current_style() -> HuntArtStyle:
	var list := art_styles()
	if list.is_empty():
		return null
	var want: String = art_style_ids.get(_title(), "")
	for st in list:
		if st.id == want:
			return st
	return list[0]


## Switch the look without touching the game in progress.
func set_art_style(style_id: String) -> void:
	L10n.save_setting("look_" + _title(), style_id)
	art_style_ids[_title()] = style_id
	_build_board()
	_sync_pieces()
	_clear_marks()
	_show_last_move()
	_refresh_ui()


# --- Graphics ----------------------------------------------------------------

## Applies the Graphics tier (GameGraphics): MSAA, the 3D render scale (FSR 1
## below full size on desktop, bilinear on phones), the far blur, glow, dust
## motes, light shadows, and the lights and reflections a look hides at Low.
## Glow and shadows only go off where the look had them on.
func _apply_graphics() -> void:
	var s := GameGraphics.settings(GameGraphics.tier())
	var vp := get_viewport()
	vp.msaa_3d = s.msaa
	var scale := GameGraphics.render_scale(GameGraphics.tier(), get_window().size)
	# FSR 1 only exists in the Forward+ renderer (desktop); phones (Mobile)
	# scale the 3D up bilinearly.
	var fsr := scale < 1.0 and RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	if _camera.attributes is CameraAttributesPractical:
		(_camera.attributes as CameraAttributesPractical).dof_blur_far_enabled = s.dof
	var env := _world_env.environment
	if env:
		if not env.has_meta("glow_as_made"):
			env.set_meta("glow_as_made", env.glow_enabled)
		env.glow_enabled = env.get_meta("glow_as_made") and s.glow
	for p: GPUParticles3D in _board_root.find_children("*", "GPUParticles3D", true, false):
		p.amount_ratio = s.particles
		p.visible = s.particles > 0.0
	for l: Light3D in _board_root.find_children("*", "Light3D", true, false):
		if not l.has_meta("shadow_as_made"):
			l.set_meta("shadow_as_made", l.shadow_enabled)
		l.shadow_enabled = l.get_meta("shadow_as_made") and s.shadows
	# Lights and reflections a look shows only from a tier up
	# (HuntArtStyle.hide_at_low).
	var rank := GameGraphics.TIERS.find(GameGraphics.tier())
	for n: Node in _board_root.find_children("*", "Node3D", true, false):
		if n.has_meta(HuntArtStyle.GRAPHICS_MIN):
			(n as Node3D).visible = rank <= GameGraphics.TIERS.find(str(n.get_meta(HuntArtStyle.GRAPHICS_MIN)))


## The player changed the Graphics setting in the menu.
func set_graphics(choice: String) -> void:
	GameGraphics.set_choice(choice)
	_apply_graphics()
	_graphics_auto.restart()


## Test builds only (the in-game menu offers it there): measures each look at
## each tier and with single changes, on this device (perf_test.gd).
func start_perf_test(suite := "main") -> CanvasLayer:
	if not OS.is_debug_build() or tutorial_active or is_network() or (perf_test and is_instance_valid(perf_test) and not perf_test.is_queued_for_deletion()):
		return null
	perf_test = PerfTestScript.new(self)
	perf_test.suite = suite
	add_child(perf_test)
	return perf_test


## The overlay's last line: the tier and what it sets.
func _perf_info() -> String:
	var t := GameGraphics.tier()
	var s := GameGraphics.settings(t)
	return "graphics %s%s · 3D at %d%% · MSAA %dx" % [t, " (auto)" if GameGraphics.choice() == GameGraphics.AUTO else "",
		roundi(100.0 * get_viewport().scaling_3d_scale), [1, 2, 4, 8][s.msaa]]


func _build_art_set() -> void:
	var style := current_style()
	var extras := RenderingServer.get_current_rendering_method() == "forward_plus"
	_world_env.environment = style.environment(extras)
	_camera.attributes = style.camera_attributes()
	# A tight depth range: the Compatibility renderer lights shadowed lights in
	# extra passes, and with the default 0.05..4000 range those passes z-fought
	# into stripes across the board.
	_camera.near = 0.5
	_camera.far = 400.0
	_grey_key.visible = false
	var set_root := Node3D.new()
	set_root.name = "ArtSet"
	_board_root.add_child(set_root)
	style.build_set(set_root, extras)
	style.set_awaken(0.0 if history.is_empty() else 0.6)


func _build_grey_board(board: BoardDef, size: Vector2) -> void:
	_world_env.environment = _grey_env
	_camera.attributes = null
	_grey_key.visible = true
	# Slab.
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 1.4, 0.24, size.y + 1.4)
	slab.mesh = box
	slab.position = Vector3(0, -0.12, 0)
	slab.material_override = _mat(Color(0.33, 0.24, 0.17), 0.85)
	_board_root.add_child(slab)
	# Lines.
	var line_mat := _mat(Color(0.82, 0.68, 0.42), 0.4, 0.6)
	for a in board.point_count():
		for b in board.adj[a]:
			if b < a:
				continue
			var pa := to_world(board.positions[a])
			var pb := to_world(board.positions[b])
			var seg := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.035, 0.012, pa.distance_to(pb))
			seg.mesh = sm
			seg.material_override = line_mat
			# Local transform, so the lines turn with the board. (look_at works in
			# global space and drew the lines unrotated once the board had been
			# turned for a prey player.)
			seg.transform = Transform3D(Basis.looking_at(pb - pa, Vector3.UP), (pa + pb) / 2.0 + Vector3(0, 0.006, 0))
			seg.set_meta("segment", Vector2i(a, b))
			_board_root.add_child(seg)
	# Points: a small stud.
	var stud_mat := _mat(Color(0.9, 0.75, 0.45), 0.35, 0.7)
	var den_mat := _mat(Color(0.75, 0.5, 0.3), 0.5, 0.3)
	for i in board.point_count():
		var stud := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 0.02
		stud.mesh = cyl
		stud.material_override = den_mat if board.has_tag(i, "den") else stud_mat
		stud.position = to_world(board.positions[i]) + Vector3(0, 0.01, 0)
		_board_root.add_child(stud)


func to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - _center.x) * SPACING, 0.0, (p.y - _center.y) * SPACING)


func _title() -> String:
	if rules.id == HuntRuleSets.KOMIKAN:
		return "komikan"
	if rules.id == HuntRuleSets.ADUGO:
		return "adugo"
	return "bagh_chal"


func _make_piece(kind: int, variant: int) -> Node3D:
	if _has_art():
		var piece := current_style().make_piece(kind, variant)
		piece.set_meta("kind", kind)
		return piece
	var colors: Array = PIECE_COLORS[_title()]
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	if kind == HuntState.HUNTER:
		var cap := CapsuleMesh.new()
		cap.radius = 0.19
		cap.height = 0.62
		mi.mesh = cap
		mi.position.y = 0.31
		mi.material_override = _mat(colors[0], 0.45, 0.25)
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.13
		cyl.bottom_radius = 0.17
		cyl.height = 0.24
		mi.mesh = cyl
		mi.position.y = 0.12
		mi.material_override = _mat(colors[1], 0.6)
	root.add_child(mi)
	root.set_meta("kind", kind)
	return root


func _sync_pieces() -> void:
	for c in _pieces_root.get_children():
		c.queue_free()
	_piece_nodes.clear()
	for i in state.cells.size():
		if state.cells[i] != HuntState.EMPTY:
			var node := _make_piece(state.cells[i], i)
			node.position = to_world(rules.board.positions[i])
			_pieces_root.add_child(node)
			_piece_nodes[i] = node


func _animate(move: PackedInt32Array) -> void:
	_animating = true
	var board := rules.board
	var tween := create_tween()
	_tween = tween
	match move[0]:
		HuntState.Kind.PLACE:
			var node := _make_piece(HuntState.PREY, move[1])
			var target := to_world(board.positions[move[1]])
			node.position = target + Vector3(0, 1.2, 0)
			node.rotation.y = _facing(target, move[1])
			_pieces_root.add_child(node)
			_piece_nodes[move[1]] = node
			tween.tween_property(node, "position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_callback(_piece_sound.bind("place", HuntState.PREY))
		HuntState.Kind.STEP:
			var node: Node3D = _piece_nodes[move[1]]
			_piece_nodes.erase(move[1])
			_piece_nodes[move[2]] = node
			var to := to_world(board.positions[move[2]])
			var kind: int = node.get_meta("kind", HuntState.PREY)
			tween.tween_property(node, "rotation:y", _turn_toward(node.rotation.y, _facing(to, move[2])), 0.12)
			tween.tween_callback(_piece_sound.bind("slide", kind))
			tween.tween_property(node, "position", to, 0.25).set_trans(Tween.TRANS_SINE)
			tween.tween_callback(_piece_sound.bind("set", kind))
		HuntState.Kind.JUMP:
			var node: Node3D = _piece_nodes[move[1]]
			_piece_nodes.erase(move[1])
			for k in range(2, move.size(), 2):
				var land := to_world(board.positions[move[k + 1]])
				var mid := (node.position if k == 2 else to_world(board.positions[move[k - 1]])).lerp(land, 0.5) + Vector3(0, 0.55, 0)
				tween.tween_property(node, "position", mid, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tween.tween_property(node, "position", land, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				tween.tween_callback(_piece_sound.bind("land", HuntState.HUNTER))
			_piece_nodes[move[move.size() - 1]] = node
			var last := to_world(board.positions[move[move.size() - 1]])
			tween.tween_property(node, "rotation:y", _turn_toward(node.rotation.y, _facing(last, move[move.size() - 1])), 0.15)
			for k in range(2, move.size(), 2):
				var victim: Node3D = _piece_nodes.get(move[k])
				_piece_nodes.erase(move[k])
				if victim:
					tween.tween_callback(_piece_sound.bind("capture", HuntState.PREY))
					tween.tween_property(victim, "scale", Vector3(0.01, 0.01, 0.01), 0.12)
					tween.tween_callback(victim.queue_free)
	tween.tween_callback(func() -> void:
		_animating = false
		if not _anim_queue.is_empty():
			_animate(_anim_queue.pop_front())
			return
		_play_sting()
		_after_move())


## Yaw that turns a piece (modeled facing -Z) toward the middle of the board,
## with a little per-point variety so a row of goats doesn't look stamped.
func _facing(at: Vector3, point: int) -> float:
	var jitter := (float((point * 7919) % 23) / 22.0 - 0.5) * 0.5
	if at.length() < 0.01:
		return jitter
	return atan2(at.x, at.z) + jitter


## The same yaw, unwrapped so a tween turns the short way round.
func _turn_toward(from: float, to: float) -> float:
	return from + wrapf(to - from, -PI, PI)


# --- Sound -------------------------------------------------------------------

## The look's piece sounds (the greybox's wooden ones without art), the
## title's stings and the look's music (switching looks fades the music over
## to the new look's). Called whenever the board is built.
func _load_sounds() -> void:
	var style := current_style()
	music.play_folder(style.music_dir if style else "")
	var pieces := style.sound_dir if style and style.sound_dir != "" else GREYBOX_SOUNDS
	var stings: String = TITLE_STINGS.get(_title(), "")
	if pieces != _sound_dirs[0]:
		sfx.load_events(pieces, PIECE_SOUNDS)
	if stings != _sound_dirs[1]:
		sfx.load_events(stings, STINGS)
	_sound_dirs = [pieces, stings]


## "slide" and "set" have a take for each piece (the tiger is heavier).
func _piece_sound(event: String, kind: int) -> void:
	if event == "slide" or event == "set":
		event += "_tiger" if kind == HuntState.HUNTER else "_goat"
	sfx.play(event)


## The end of the game: a win or a loss for the player on this device; with
## both or neither here (pass and play, AI vs AI), the win sting.
func _play_sting() -> void:
	if not _sting_pending or session == null:
		return
	_sting_pending = false
	var st := session.status()
	if st == HuntState.Status.ONGOING:
		return
	var event := "draw"
	if st != HuntState.Status.DRAW:
		var me := local_side()
		event = "win" if me < 0 or (st == HuntState.Status.HUNTER_WIN) == (me == HuntState.HUNTER) else "lose"
	music.duck(STING_DUCK)
	sfx.play(event, 1.0, 0.0, false)


# --- View: marks -----------------------------------------------------------

func _clear_marks() -> void:
	for c in _marks_root.get_children():
		c.queue_free()


enum MarkShape { SELECTED, STEP, CAPTURE, LAST }


## A highlight on a point. Shape and color both differ per kind, so they read
## for colorblind players too (framework §6); colors come from the art style.
func _mark(p: int, shape: MarkShape) -> void:
	var style := current_style()
	var colors := {
		MarkShape.SELECTED: style.mark_select if style else Color(1.0, 0.85, 0.3),
		MarkShape.STEP: style.mark_step if style else Color(0.4, 0.9, 0.5),
		MarkShape.CAPTURE: style.mark_capture if style else Color(1.0, 0.35, 0.25),
		MarkShape.LAST: style.mark_last if style else Color(0.45, 0.6, 1.0),
	}
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = MarkInkShader if style and style.mark_ink else MarkShader
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("color", colors[shape])
	mi.material_override = m
	mi.position = to_world(rules.board.positions[p]) + Vector3(0, 0.012, 0)
	_marks_root.add_child(mi)


func _show_targets(moves: Array[PackedInt32Array]) -> void:
	_clear_marks()
	_show_last_move()
	_mark(_selected, MarkShape.SELECTED)
	for m in moves:
		if m[1] != _selected:
			continue
		if m[0] == HuntState.Kind.STEP:
			_mark(m[2], MarkShape.STEP)
		elif m[0] == HuntState.Kind.JUMP and m.size() == 4:
			_mark(m[3], MarkShape.CAPTURE)
	_refresh_ui()


func _show_chain_marks(moves: Array[PackedInt32Array]) -> void:
	_clear_marks()
	_mark(_chain[_chain.size() - 1], MarkShape.SELECTED)
	for m in _chain_continuations(moves):
		_mark(m[m.size() - 1], MarkShape.CAPTURE)
	_refresh_ui()


func _show_last_move() -> void:
	if history.is_empty():
		return
	var m := history[history.size() - 1]
	_mark(m[m.size() - 1], MarkShape.LAST)


# --- How to play -----------------------------------------------------------

func start_tutorial() -> void:
	if tutorial_active or mode == Mode.NETWORK:
		return
	_stop_ai()
	_tutorial_from_menu = menu != null and menu.is_open()
	if menu:
		menu.close()
	# The walkthrough gets a session of its own; the game comes back after.
	_saved_session = session
	var s := MatchSession.create(rules, session.rule_set_id, MatchSession.Kind.PASS_AND_PLAY,
		MatchSession.Driver.LOCAL, MatchSession.Driver.LOCAL)
	tutorial_active = true
	_use_session(s)
	_tutorial.start(rules)
	_refresh_ui()


func _on_tutorial_finished(play_now: bool) -> void:
	_stop_tween()
	tutorial_active = false
	var back := _saved_session
	_saved_session = null
	if play_now or back == null:
		if mode == Mode.NETWORK:
			mode = _local_mode
		new_game()
		return
	_use_session(back)
	if _tutorial_from_menu:
		menu.open()


func is_animating() -> bool:
	return _animating


## Shows a tutorial position (a copy: the walkthrough keeps its own).
func tutorial_set_state(s: HuntState) -> void:
	_stop_tween()
	state = s.clone()
	history_start = s.clone()
	history.clear()
	_selected = -1
	_chain = PackedInt32Array()
	_clear_marks()
	_sync_pieces()
	status = state.status()
	if _has_art():
		current_style().set_awaken(0.6)
	_refresh_ui()


func tutorial_mark(p: int, kind: String) -> void:
	var shapes := {"select": MarkShape.SELECTED, "step": MarkShape.STEP,
		"capture": MarkShape.CAPTURE, "note": MarkShape.LAST}
	_mark(p, shapes.get(kind, MarkShape.LAST))


func tutorial_clear_marks() -> void:
	_clear_marks()


func tutorial_show_last_move() -> void:
	_show_last_move()


func tutorial_play(move: PackedInt32Array) -> void:
	history.append(move)
	_animate(move)
	state.make(move)


func _stop_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	_animating = false


# --- UI --------------------------------------------------------------------

func _refresh_ui() -> void:
	if _hud:
		_hud.refresh()
	if _match_ui:
		_match_ui.refresh()


## Android's back gesture: closes the walkthrough, steps back through the
## menus, opens the in-game menu during a game, and leaves the app from the
## main menu. (project.godot sets quit_on_go_back off.) Coming back to the
## app, Auto graphics measures afresh.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_graphics_auto.restart()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and menu:
		if perf_test and is_instance_valid(perf_test):
			perf_test.stop()
		elif tutorial_active:
			_tutorial.stop(false)
		elif menu.is_open():
			menu.back(true)
		else:
			menu.open("pause")


static func _mat(color: Color, roughness := 0.6, metallic := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
