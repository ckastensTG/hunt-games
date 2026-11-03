extends Node3D
## Greybox: every v1 rule set playable on a placeholder 3D board.
## Hotseat, either side against the AI, or AI vs AI. Builds everything in code
## from the BoardDef, so it stays correct while the boards and rules evolve.
## Art replaces the meshes later; the rules and AI underneath stay the same.

enum Mode { HOTSEAT, HUMAN_PREY, HUMAN_HUNTER, AI_VS_AI }

const SPACING := 1.0
const AI_MOVE_DELAY := 0.35

const PIECE_COLORS := {
	"bagh_chal": [Color(0.86, 0.48, 0.14), Color(0.93, 0.91, 0.85)],   # tiger, goat
	"adugo": [Color(0.78, 0.6, 0.18), Color(0.5, 0.33, 0.2)],          # jaguar, dog
	"komikan": [Color(0.66, 0.55, 0.42), Color(0.5, 0.33, 0.2)],       # puma, dog
}

const RULE_SET_LABELS := {
	HuntRuleSets.BAGH_CHAL_STANDARD: "Bagh Chal: Standard",
	HuntRuleSets.BAGH_CHAL_PARLETT: "Bagh Chal: Parlett 1976",
	HuntRuleSets.ADUGO: "Jogo da Onça: Adugo",
	HuntRuleSets.KOMIKAN: "Jogo da Onça: Komikan",
}

const REASONS := {
	HuntState.Reason.CAPTURE_TARGET: "capture target reached",
	HuntState.Reason.HUNTER_TRAPPED: "the hunter is trapped",
	HuntState.Reason.PREY_STUCK: "the prey can't move",
	HuntState.Reason.REPETITION_BLOCKED: "every move would repeat a position",
	HuntState.Reason.THREEFOLD: "threefold repetition",
	HuntState.Reason.NO_CAPTURE_LIMIT: "no capture for 50 moves each",
}

var rules: HuntRuleSet
var state: HuntState
var evaluator: HuntEvaluator
var personas: Array[AIPersona] = []
var mode: Mode = Mode.HUMAN_PREY
var level := 1
## Use the title's art set where one exists (Bagh Chal, style-frame stage).
var use_art := true
var history: Array[PackedInt32Array] = []
var status: HuntState.Status = HuntState.Status.ONGOING

var _rule_set_id := HuntRuleSets.BAGH_CHAL_STANDARD
var _komikan_dogs_first := false
var _camera: Camera3D
var _world_env: WorldEnvironment
var _grey_env: Environment
var _grey_key: DirectionalLight3D
var _art_env: Environment
var _board_root: Node3D
var _pieces_root: Node3D
var _marks_root: Node3D
var _piece_nodes := {}  # point id -> Node3D
var _center := Vector2.ZERO
var _selected := -1
var _chain := PackedInt32Array()
var _pending_click := Vector2.INF
var _animating := false
var _ai_task := -1
var _ai_cancel := false
var _ai_result := PackedInt32Array()
var _ai_wait := 0.0
var _rng := RandomNumberGenerator.new()

var _ui_status: Label
var _ui_info: Label
var _ui_moves: Label
var _ui_end_chain: Button
var _ui_dogs_first: CheckBox
var _ui_rule_set: OptionButton
var _ui_mode: OptionButton
var _ui_level: OptionButton


func _ready() -> void:
	_rng.seed = 20261102
	personas = _make_personas()
	_build_environment()
	_build_ui()
	new_game()


func _make_personas() -> Array[AIPersona]:
	var out: Array[AIPersona] = []
	for spec in [
		["novice", 2, 0, 400, 0.6, 120.0],
		["apprentice", 3, 0, 200, 0.35, 80.0],
		["adept", 5, 1500, 80, 0.15, 40.0],
		["master", 8, 2500, 0, 0.0, 1.0],
	]:
		var p := AIPersona.new()
		p.id = spec[0]
		p.max_depth = spec[1]
		p.time_limit_ms = spec[2]
		p.candidate_window = spec[3]
		p.mistake_rate = spec[4]
		p.temperature = spec[5]
		out.append(p)
	return out


# --- Game flow -------------------------------------------------------------

func new_game() -> void:
	_stop_ai()
	if _rule_set_id == HuntRuleSets.KOMIKAN:
		rules = HuntRuleSets.komikan(HuntRuleSet.PREY if _komikan_dogs_first else HuntRuleSet.HUNTER)
	else:
		rules = HuntRuleSets.by_id(_rule_set_id)
	state = HuntState.create(rules)
	evaluator = HuntEvaluator.new(HuntRuleSets.weights_for(rules))
	history.clear()
	_selected = -1
	_chain = PackedInt32Array()
	_build_board()
	_sync_pieces()
	_after_move()


func commit(move: PackedInt32Array) -> void:
	if not state.is_legal(move):
		push_warning("illegal move %s" % state.describe(move))
		return
	_selected = -1
	_chain = PackedInt32Array()
	_clear_marks()
	history.append(move)
	_animate(move)
	state.make(move)


func undo() -> void:
	if _animating or history.is_empty():
		return
	_stop_ai()
	var steps := 1
	if mode == Mode.HUMAN_PREY or mode == Mode.HUMAN_HUNTER:
		# Back to the human's turn.
		steps = 2 if _is_ai_side(state.side) == false and history.size() >= 2 else 1
	for _i in steps:
		if history.is_empty():
			break
		state.unmake(history.pop_back())
	_selected = -1
	_chain = PackedInt32Array()
	_sync_pieces()
	_after_move()


func _after_move() -> void:
	status = state.status()
	if _has_art():
		BaghChalArt.set_awaken(0.0 if history.is_empty() else 0.6)
	_refresh_ui()
	_show_last_move()
	if status == HuntState.Status.ONGOING and _is_ai_side(state.side):
		_ai_wait = AI_MOVE_DELAY


func _is_ai_side(side: int) -> bool:
	match mode:
		Mode.HUMAN_PREY:
			return side == HuntState.HUNTER
		Mode.HUMAN_HUNTER:
			return side == HuntState.PREY
		Mode.AI_VS_AI:
			return true
	return false


func _process(delta: float) -> void:
	if _ai_wait > 0.0 and not _animating:
		_ai_wait -= delta
		if _ai_wait <= 0.0 and _is_ai_side(state.side):
			_start_ai()
	if _ai_task >= 0 and WorkerThreadPool.is_task_completed(_ai_task):
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1
		if not _ai_cancel and not _ai_result.is_empty():
			commit(_ai_result)
		_ai_cancel = false


func _start_ai() -> void:
	if _ai_task >= 0 or status != HuntState.Status.ONGOING:
		return
	_ai_cancel = false
	_ai_result = PackedInt32Array()
	var snapshot := state.clone()
	var persona := personas[level]
	var seed := _rng.randi()
	_ai_task = WorkerThreadPool.add_task(_ai_work.bind(persona, snapshot, seed), false, "hunt AI")
	_refresh_ui()


func _ai_work(persona: AIPersona, snapshot: HuntState, seed: int) -> void:
	var search := persona.make_searcher(evaluator)
	search.begin(snapshot)
	while not search.step(4000):
		if _ai_cancel:
			search.cancel()
			return
	var r := RandomNumberGenerator.new()
	r.seed = seed
	_ai_result = persona.pick(search, r)


func _stop_ai() -> void:
	_ai_wait = 0.0
	if _ai_task >= 0:
		_ai_cancel = true
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1
	_ai_cancel = false


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pending_click = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and _chain.size() > 2:
			commit(_chain)


func _physics_process(_delta: float) -> void:
	if _pending_click == Vector2.INF:
		return
	var click := _pending_click
	_pending_click = Vector2.INF
	if _animating or _ai_task >= 0 or status != HuntState.Status.ONGOING or _is_ai_side(state.side):
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
		extent = BaghChalArt.CAMERA_EXTENT
	else:
		_build_grey_board(board, size)
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
	_board_root.rotation.y = PI if mode == Mode.HUMAN_PREY else 0.0
	_camera.position = Vector3(0, extent * 1.25, extent * 0.95)
	_camera.look_at(Vector3(0, 0, extent * 0.06), Vector3.UP)


func _has_art() -> bool:
	return use_art and _title() == "bagh_chal"


func _build_art_set() -> void:
	var extras := RenderingServer.get_current_rendering_method() == "forward_plus"
	if _art_env == null:
		_art_env = BaghChalArt.make_environment(extras)
	_world_env.environment = _art_env
	_camera.attributes = BaghChalArt.make_camera_attributes(11.0)
	# A tight depth range: the Compatibility renderer lights shadowed lights in
	# extra passes, and with the default 0.05..4000 range those passes z-fought
	# into stripes across the board.
	_camera.near = 0.5
	_camera.far = 400.0
	_grey_key.visible = false
	var set_root := Node3D.new()
	set_root.name = "ArtSet"
	_board_root.add_child(set_root)
	BaghChalArt.build_set(set_root, extras)
	BaghChalArt.set_awaken(0.0 if history.is_empty() else 0.6)


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


func _make_piece(kind: int) -> Node3D:
	if _has_art():
		return BaghChalArt.make_piece(kind)
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
	return root


func _sync_pieces() -> void:
	for c in _pieces_root.get_children():
		c.queue_free()
	_piece_nodes.clear()
	for i in state.cells.size():
		if state.cells[i] != HuntState.EMPTY:
			var node := _make_piece(state.cells[i])
			node.position = to_world(rules.board.positions[i])
			_pieces_root.add_child(node)
			_piece_nodes[i] = node


func _animate(move: PackedInt32Array) -> void:
	_animating = true
	var board := rules.board
	var tween := create_tween()
	match move[0]:
		HuntState.Kind.PLACE:
			var node := _make_piece(HuntState.PREY)
			var target := to_world(board.positions[move[1]])
			node.position = target + Vector3(0, 1.2, 0)
			node.rotation.y = _facing(target, move[1])
			_pieces_root.add_child(node)
			_piece_nodes[move[1]] = node
			tween.tween_property(node, "position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		HuntState.Kind.STEP:
			var node: Node3D = _piece_nodes[move[1]]
			_piece_nodes.erase(move[1])
			_piece_nodes[move[2]] = node
			var to := to_world(board.positions[move[2]])
			tween.tween_property(node, "rotation:y", _turn_toward(node.rotation.y, _facing(to, move[2])), 0.12)
			tween.tween_property(node, "position", to, 0.25).set_trans(Tween.TRANS_SINE)
		HuntState.Kind.JUMP:
			var node: Node3D = _piece_nodes[move[1]]
			_piece_nodes.erase(move[1])
			for k in range(2, move.size(), 2):
				var land := to_world(board.positions[move[k + 1]])
				var mid := (node.position if k == 2 else to_world(board.positions[move[k - 1]])).lerp(land, 0.5) + Vector3(0, 0.55, 0)
				tween.tween_property(node, "position", mid, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tween.tween_property(node, "position", land, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			_piece_nodes[move[move.size() - 1]] = node
			var last := to_world(board.positions[move[move.size() - 1]])
			tween.tween_property(node, "rotation:y", _turn_toward(node.rotation.y, _facing(last, move[move.size() - 1])), 0.15)
			for k in range(2, move.size(), 2):
				var victim: Node3D = _piece_nodes.get(move[k])
				_piece_nodes.erase(move[k])
				if victim:
					tween.tween_property(victim, "scale", Vector3(0.01, 0.01, 0.01), 0.12)
					tween.tween_callback(victim.queue_free)
	tween.tween_callback(func() -> void:
		_animating = false
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


# --- View: marks -----------------------------------------------------------

func _clear_marks() -> void:
	for c in _marks_root.get_children():
		c.queue_free()


func _mark(p: int, color: Color, radius := 0.24) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.05
	torus.outer_radius = radius
	mi.mesh = torus
	mi.material_override = _mat(color, 0.3, 0.0, true)
	mi.position = to_world(rules.board.positions[p]) + Vector3(0, 0.03, 0)
	_marks_root.add_child(mi)


func _show_targets(moves: Array[PackedInt32Array]) -> void:
	_clear_marks()
	_show_last_move()
	_mark(_selected, Color(1.0, 0.85, 0.3), 0.3)
	for m in moves:
		if m[1] != _selected:
			continue
		if m[0] == HuntState.Kind.STEP:
			_mark(m[2], Color(0.4, 0.9, 0.5))
		elif m[0] == HuntState.Kind.JUMP and m.size() == 4:
			_mark(m[3], Color(1.0, 0.35, 0.25))


func _show_chain_marks(moves: Array[PackedInt32Array]) -> void:
	_clear_marks()
	_mark(_chain[_chain.size() - 1], Color(1.0, 0.85, 0.3), 0.3)
	for m in _chain_continuations(moves):
		_mark(m[m.size() - 1], Color(1.0, 0.35, 0.25))
	_refresh_ui()


func _show_last_move() -> void:
	if history.is_empty():
		return
	var m := history[history.size() - 1]
	_mark(m[m.size() - 1], Color(0.45, 0.6, 1.0), 0.2)


# --- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(330, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Hunt games: greybox"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	var rs := OptionButton.new()
	_ui_rule_set = rs
	for id in HuntRuleSets.ALL:
		rs.add_item(RULE_SET_LABELS[id])
	rs.item_selected.connect(func(i: int) -> void:
		_rule_set_id = HuntRuleSets.ALL[i]
		new_game())
	box.add_child(rs)

	_ui_dogs_first = CheckBox.new()
	_ui_dogs_first.text = "Dogs move first (Komikan option)"
	_ui_dogs_first.toggled.connect(func(on: bool) -> void:
		_komikan_dogs_first = on
		new_game())
	box.add_child(_ui_dogs_first)

	var md := OptionButton.new()
	_ui_mode = md
	for label in ["Hotseat (two players)", "You play the prey", "You play the hunter", "AI vs AI"]:
		md.add_item(label)
	md.selected = mode
	md.item_selected.connect(func(i: int) -> void:
		mode = i as Mode
		new_game())
	box.add_child(md)

	var lv := OptionButton.new()
	_ui_level = lv
	for label in ["AI: Novice", "AI: Apprentice", "AI: Adept", "AI: Master"]:
		lv.add_item(label)
	lv.selected = level
	lv.item_selected.connect(func(i: int) -> void: level = i)
	box.add_child(lv)

	var row := HBoxContainer.new()
	var ng := Button.new()
	ng.text = "New game"
	ng.pressed.connect(new_game)
	row.add_child(ng)
	var ud := Button.new()
	ud.text = "Undo"
	ud.pressed.connect(undo)
	row.add_child(ud)
	_ui_end_chain = Button.new()
	_ui_end_chain.text = "End capture chain"
	_ui_end_chain.pressed.connect(func() -> void:
		if _chain.size() > 2:
			commit(_chain))
	row.add_child(_ui_end_chain)
	box.add_child(row)

	_ui_status = Label.new()
	_ui_status.add_theme_font_size_override("font_size", 17)
	_ui_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_ui_status)
	_ui_info = Label.new()
	box.add_child(_ui_info)
	_ui_moves = Label.new()
	_ui_moves.autowrap_mode = TextServer.AUTOWRAP_WORD
	_ui_moves.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	box.add_child(_ui_moves)
	var help := Label.new()
	help.text = "Click a piece, then a point. Capture chains: click each landing,\nthen the hunter or right-click to stop."
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	box.add_child(help)


func _refresh_ui() -> void:
	if _ui_status == null:
		return
	var names := _side_names()
	# Keep the controls in step when code (tools, tests) changes the setup.
	_ui_rule_set.selected = HuntRuleSets.ALL.find(_rule_set_id)
	_ui_mode.selected = mode
	_ui_level.selected = level
	_ui_dogs_first.set_pressed_no_signal(_komikan_dogs_first)
	_ui_dogs_first.visible = _rule_set_id == HuntRuleSets.KOMIKAN
	_ui_end_chain.visible = _chain.size() > 2
	match status:
		HuntState.Status.ONGOING:
			var who: String = names[0] if state.side == HuntState.HUNTER else names[1]
			_ui_status.text = "%s to move%s" % [who.capitalize(), " (AI thinking...)" if _ai_task >= 0 else ""]
		HuntState.Status.HUNTER_WIN:
			_ui_status.text = "%s win: %s" % [names[0].capitalize(), REASONS.get(state.last_reason, "")]
		HuntState.Status.PREY_WIN:
			_ui_status.text = "%s win: %s" % [names[1].capitalize(), REASONS.get(state.last_reason, "")]
		HuntState.Status.DRAW:
			_ui_status.text = "Draw: %s" % REASONS.get(state.last_reason, "")
	var info := "Captured %d / %d" % [state.captured, rules.capture_target]
	if state.reserve > 0:
		info += "    %s to place: %d" % [names[1], state.reserve]
	if rules.no_capture_limit_plies > 0 and state.reserve == 0:
		info += "    quiet plies %d / %d" % [state.quiet_plies, rules.no_capture_limit_plies]
	_ui_info.text = info
	var shown: Array[String] = []
	var start := maxi(0, history.size() - 10)
	var replay := HuntState.create(rules)
	for k in history.size():
		if k >= start:
			shown.append("%d. %s" % [k + 1, replay.describe(history[k])])
		replay.make(history[k])
	_ui_moves.text = "  ".join(shown)


func _side_names() -> Array[String]:
	match _title():
		"bagh_chal":
			return ["tigers", "goats"]
		"adugo":
			return ["jaguar", "dogs"]
	return ["puma", "dogs"]


static func _mat(color: Color, roughness := 0.6, metallic := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
