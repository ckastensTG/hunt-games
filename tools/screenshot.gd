extends SceneTree
## Renders the greybox to PNGs (needs a display; use xvfb-run on CI/servers).
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
##     -s res://tools/screenshot.gd -- --out=/tmp/shots [--plies=12]
## One image per rule set, after a few AI plies so pieces are on the board.

const GreyboxScript := preload("res://scenes/greybox/greybox.gd")

var game: Node3D
var out_dir := "user://shots"
var plies := 12
var mode_name := "ai"
var queue: Array = []
var current := ""
var wait := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--plies="):
			plies = int(arg.substr(8))
		elif arg.begins_with("--mode="):
			mode_name = arg.substr(7)  # "ai" (AI vs AI) or "prey" (you play the prey)
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	root.add_child(game)
	queue = HuntRuleSets.ALL.duplicate()


func _next() -> void:
	current = queue.pop_front()
	game.mode = GreyboxScript.Mode.HUMAN_PREY if mode_name == "prey" else GreyboxScript.Mode.AI_VS_AI
	game.level = 1
	game._rule_set_id = current
	game.new_game()
	wait = 0


func _process(_delta: float) -> bool:
	if current == "":
		_next()  # the scene's _ready has run by the first frame
		return false
	if game.history.size() >= plies or game.status != HuntState.Status.ONGOING:
		if mode_name != "prey":
			game.mode = GreyboxScript.Mode.HOTSEAT  # stop the AI
		if game._animating or game._ai_task >= 0:
			return false
		wait += 1
		if wait < 10:
			return false
		var path := out_dir.path_join("%s_%s.png" % [current, mode_name])
		root.get_texture().get_image().save_png(path)
		print("saved %s" % path)
		if queue.is_empty():
			quit()
			return true
		_next()
	return false
