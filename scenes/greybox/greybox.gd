extends Node3D
## Greybox: every v1 rule set playable in 3D. Hotseat, either side against
## the AI, or AI vs AI. Builds everything in code from the BoardDef, so it
## stays correct while the boards and rules evolve. Bagh Chal shows its art
## styles (titles/bagh_chal/art/); the other titles still use placeholder
## meshes. The interface is hud.gd.

enum Mode { HOTSEAT, HUMAN_PREY, HUMAN_HUNTER, AI_VS_AI }

const SPACING := 1.0
const HudScript := preload("res://scenes/greybox/hud.gd")
const MarkShader := preload("res://scenes/greybox/mark.gdshader")
const AI_MOVE_DELAY := 0.35

const PIECE_COLORS := {
	"bagh_chal": [Color(0.86, 0.48, 0.14), Color(0.93, 0.91, 0.85)],   # tiger, goat
	"adugo": [Color(0.78, 0.6, 0.18), Color(0.5, 0.33, 0.2)],          # jaguar, dog
	"komikan": [Color(0.66, 0.55, 0.42), Color(0.5, 0.33, 0.2)],       # puma, dog
}

var rules: HuntRuleSet
var state: HuntState
var evaluator: HuntEvaluator
var personas: Array[AIPersona] = []
var mode: Mode = Mode.HUMAN_PREY
var level := 1
## Use the title's art where it exists (Bagh Chal); false shows the greybox.
var use_art := true
## The art style picked for each title that has more than one (style id).
var art_style_ids := {"bagh_chal": "brass"}
var history: Array[PackedInt32Array] = []
var status: HuntState.Status = HuntState.Status.ONGOING

var _rule_set_id := HuntRuleSets.BAGH_CHAL_STANDARD
var _komikan_dogs_first := false
var _camera: Camera3D
var _world_env: WorldEnvironment
var _grey_env: Environment
var _grey_key: DirectionalLight3D
var _styles := {}  # title id -> Array[HuntArtStyle]
var _hud: CanvasLayer
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



func _ready() -> void:
	_rng.seed = 20261102
	personas = _make_personas()
	_styles["bagh_chal"] = BaghChalArt.styles()
	_build_environment()
	_hud = HudScript.new(self)
	add_child(_hud)
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
		current_style().set_awaken(0.0 if history.is_empty() else 0.6)
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
		extent = current_style().camera_extent
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
	art_style_ids[_title()] = style_id
	_build_board()
	_sync_pieces()
	_clear_marks()
	_show_last_move()
	_refresh_ui()


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
		return current_style().make_piece(kind, variant)
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
			var node := _make_piece(state.cells[i], i)
			node.position = to_world(rules.board.positions[i])
			_pieces_root.add_child(node)
			_piece_nodes[i] = node


func _animate(move: PackedInt32Array) -> void:
	_animating = true
	var board := rules.board
	var tween := create_tween()
	match move[0]:
		HuntState.Kind.PLACE:
			var node := _make_piece(HuntState.PREY, move[1])
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
	m.shader = MarkShader
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


# --- UI --------------------------------------------------------------------

func _refresh_ui() -> void:
	if _hud:
		_hud.refresh()


static func _mat(color: Color, roughness := 0.6, metallic := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
