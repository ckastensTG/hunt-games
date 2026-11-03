extends SceneTree
## Renders the Bagh Chal style frame and the two in-game views from one
## position, for checking the art (needs a display; use xvfb-run on servers):
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##     [--rendering-method forward_plus|mobile|gl_compatibility] \
##     -s res://tools/style_frame.gd -- --out=DIR [--plies=N] [--views=hero,ai,prey] [--tag=NAME]
##
## Views: hero = the cinematic style frame; ai = the AI-vs-AI camera;
## prey = "You play the prey" (the board, and the room, turned around).
## The position comes from the Apprentice AI playing both sides from a fixed
## seed, so every run and every renderer shows the same pieces.

const GreyboxScript := preload("res://scenes/greybox/greybox.gd")

var game: Node3D
var out_dir := "user://style_frame"
var plies := 22
var views: Array = ["hero", "ai", "prey"]
var tag := ""
var moves: Array[PackedInt32Array] = []
var current := ""
var frames := 0
var hero_cam: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--plies="):
			plies = int(arg.substr(8))
		elif arg.begins_with("--views="):
			views = Array(arg.substr(8).split(","))
		elif arg.begins_with("--tag="):
			tag = "_" + arg.substr(6)
	if tag == "":
		tag = "_" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	root.add_child(game)


func _setup(view: String) -> void:
	game.level = 1
	game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
	game.mode = GreyboxScript.Mode.HUMAN_PREY if view == "prey" else GreyboxScript.Mode.AI_VS_AI
	game.new_game()
	game.mode = GreyboxScript.Mode.HOTSEAT  # nobody moves while we look
	if moves.is_empty():
		moves = _play(plies)
	for m in moves:
		game.state.make(m)
		game.history.append(m)
	game._sync_pieces()
	game._after_move()
	game._clear_marks()
	for c in game.get_children():
		if c is CanvasLayer:
			c.visible = false
	if view == "hero":
		if hero_cam == null:
			hero_cam = Camera3D.new()
			hero_cam.fov = 32.0
			hero_cam.near = 0.5
			hero_cam.far = 400.0
			var ca := CameraAttributesPractical.new()
			ca.dof_blur_near_enabled = true
			ca.dof_blur_near_distance = 3.2
			ca.dof_blur_near_transition = 2.0
			ca.dof_blur_far_enabled = true
			ca.dof_blur_far_distance = 9.5
			ca.dof_blur_far_transition = 8.0
			ca.dof_blur_amount = 0.16
			hero_cam.attributes = ca
			game.add_child(hero_cam)
		hero_cam.position = Vector3(5.2, 1.5, 6.0)
		hero_cam.look_at(Vector3(0.3, 0.7, -0.9), Vector3.UP)
		hero_cam.make_current()
	else:
		game._camera.make_current()


func _play(n: int) -> Array[PackedInt32Array]:
	var s := HuntState.create(game.rules)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261102
	var out: Array[PackedInt32Array] = []
	for _i in n:
		if s.status() != HuntState.Status.ONGOING:
			break
		var search: HuntSearcher = game.personas[1].make_searcher(game.evaluator)
		search.begin(s)
		while not search.step(4000):
			pass
		var m: PackedInt32Array = game.personas[1].pick(search, rng)
		out.append(m)
		s.make(m)
	return out


func _process(_delta: float) -> bool:
	if current == "":
		if views.is_empty():
			quit()
			return true
		current = views.pop_front()
		_setup(current)
		frames = 0
		return false
	frames += 1
	if frames < 24:  # let shadows, particles and DOF settle
		return false
	var path := out_dir.path_join("bagh_chal_%s%s.png" % [current, tag])
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)
	current = ""
	return false
