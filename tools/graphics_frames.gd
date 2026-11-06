extends SceneTree
## Renders each Bagh Chal look at each Graphics tier (High, Medium, Low), a
## game in progress, to compare how they look.
##   xvfb-run -a -s "-screen 0 1280x1800x24" godot --path . --rendering-method mobile \
##     --resolution 720x1600 -s res://tools/graphics_frames.gd -- --out=/tmp/frames

var game: Node3D
var out_dir := "user://graphics_frames"
var jobs: Array = []
var job: Array = []
var wait := 0
var _choice_before := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_choice_before = GameGraphics.choice()
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	game.autosave = false
	root.add_child(game)


func _process(_delta: float) -> bool:
	if jobs.is_empty() and job.is_empty():
		game.menu.close()
		game.mode = 0  # HOTSEAT
		game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
		game.new_game()
		for st in game.art_styles():
			for t in GameGraphics.TIERS:
				jobs.append([st.id, t])
		job = jobs.pop_front()
		_start()
		return false
	wait += 1
	if wait < 10:
		return false
	var path := out_dir.path_join("%s_%s.png" % job)
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)
	if jobs.is_empty():
		GameGraphics.set_choice(_choice_before)
		quit()
		return true
	job = jobs.pop_front()
	_start()
	return false


func _start() -> void:
	if game.current_style().id != job[0]:
		game.set_art_style(job[0])
	game.set_graphics(job[1])
	var s := HuntState.create(game.rules)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 16:
		var moves := s.legal_moves()
		var quiet: Array = moves.filter(func(m: PackedInt32Array) -> bool: return HuntState.captures_in(m) == 0)
		s.make(quiet[rng.randi_range(0, quiet.size() - 1)])
	game.tutorial_set_state(s)
	wait = 0
