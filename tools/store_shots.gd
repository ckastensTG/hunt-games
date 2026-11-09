extends SceneTree
## The raw game pictures for the store screenshots, one PNG per scene at the
## window's size, in one language; tools/store/compose.py then puts each on
## its store canvas with the caption (timeless-store-assets/<title>/, next to
## the repos).
##
##   xvfb-run -a -s "-screen 0 2600x2900x24" godot --path . --rendering-method mobile \
##     --resolution 1180x2258 -s res://tools/store_shots.gd -- --out=DIR [--locale=en] \
##     [--scenes=brass,capture,...]
##
## Run it with the Mobile renderer (what phones and iPads use) at the size
## compose.py asks for (it prints the sizes). Graphics is set to High.
## --layer: "all" (the default) renders the whole picture; "3d" the game
## without its interface (once per size: it's the slow part); "ui" only the
## interface, on a transparent background with 3D off (quick: once per size
## and language). compose.py lays the "ui" picture over the "3d" one.
## Scenes:
##   brass, stone, modern   a game in progress in each look (pass and play,
##                          so the bar reads as a real game), the in-game display
##   capture                Temple brass, a tiger selected with a capture shown
##   home, vs_ai            the main menu and Play against the AI over the board
##   tutorial               How to play at "Safety in numbers"
##   origins                Game origins
## The position comes from the Apprentice AI playing both sides from a fixed
## seed, so every language and size shows the same pieces.

const GreyboxScript := preload("res://scenes/greybox/greybox.gd")
const ALL := ["brass", "capture", "stone", "modern", "vs_ai", "home", "tutorial", "origins"]
## Plies played before each scene (Bagh Chal Standard).
const PLIES := {"brass": 17, "stone": 25, "modern": 35, "vs_ai": 17, "home": 17}

var game: Node3D
var out_dir := "user://store_shots"
var locale := "en"
var scenes: Array = ALL.duplicate()
var current := ""
var frames := 0
var started_ms := 0
var _moves_cache := {}
var layer := "all"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--locale="):
			locale = arg.substr(9)
		elif arg.begins_with("--scenes="):
			scenes = Array(arg.substr(9).split(","))
		elif arg.begins_with("--layer="):
			layer = arg.substr(8)
	if layer == "ui":
		root.transparent_bg = true
		root.disable_3d = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	AdService.backend_override = "none"  # no test-build stand-ins on screen
	IAPService.backend_override = "none"
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	game.autosave = false  # leave the player's saved game alone
	root.add_child(game)


func _setup(scene: String) -> void:
	if game.tutorial_active:
		game._tutorial.stop(false)
	game.menu.close()
	game._clear_marks()
	game._selected = -1
	L10n.set_language(locale)
	game.set_graphics(GameGraphics.HIGH)
	var look := "brass"
	if scene in ["stone", "modern"]:
		look = scene
	if game.current_style() == null or game.current_style().id != look:
		game.set_art_style(look)
	game.level = 1
	game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
	game.mode = GreyboxScript.Mode.HOTSEAT
	game.new_game()
	var moves: Array[PackedInt32Array] = _capture_moves() if scene == "capture" else _play(PLIES.get(scene, 17))
	for m in moves:
		game.session.commit(m, game.state.side)
	game._stop_tween()
	game._anim_queue.clear()
	game._animating = false
	game._sync_pieces()
	game._after_move()
	game._clear_marks()
	match scene:
		"capture":
			_select_capture()
		"vs_ai", "home", "origins":
			game.menu.open(scene)
		"tutorial":
			game.start_tutorial()
			game._tutorial._show(4)  # "Safety in numbers"
	game._refresh_ui()


## Moves until a tiger to move has a capture (after the opening).
func _capture_moves() -> Array[PackedInt32Array]:
	var all := _play(60)
	var s := HuntState.create(game.rules)
	var out: Array[PackedInt32Array] = []
	for m in all:
		if out.size() >= 14 and s.side == HuntState.HUNTER:
			for lm in s.legal_moves(false):
				if lm[0] == HuntState.Kind.JUMP:
					return out
		out.append(m)
		s.make(m)
	return out


func _select_capture() -> void:
	for m in game.state.legal_moves(false):
		if m[0] == HuntState.Kind.JUMP:
			game._on_point_clicked(m[1])
			return


func _play(n: int) -> Array[PackedInt32Array]:
	if _moves_cache.has(n):
		return _moves_cache[n]
	var s := HuntState.create(game.rules)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261107
	var out: Array[PackedInt32Array] = []
	for _i in n:
		if s.status() != HuntState.Status.ONGOING:
			break
		# The plain Apprentice (no person's style), so the position stays the same.
		var apprentice := HuntPersonas.plain(HuntPersonas.APPRENTICE)
		var search: HuntSearcher = apprentice.make_searcher(game.evaluator)
		search.begin(s)
		while not search.step(4000):
			pass
		var m: PackedInt32Array = apprentice.pick(search, rng)
		out.append(m)
		s.make(m)
	_moves_cache[n] = out
	return out


func _process(_delta: float) -> bool:
	if current == "":
		if scenes.is_empty():
			quit()
			return true
		current = scenes.pop_front()
		_setup(current)
		frames = 0
		started_ms = Time.get_ticks_msec()
		return false
	frames += 1
	if layer == "3d":
		for c: CanvasLayer in root.find_children("*", "CanvasLayer", true, false):
			c.visible = false
	# Let the look's shaders, shadows, particles and the walkthrough's move settle
	# (the interface alone needs only a few frames).
	var wait_ms := 3000 if layer == "ui" else 4000
	if frames < (6 if layer == "ui" else 14) or game._animating or game.look_loading() \
			or Time.get_ticks_msec() - started_ms < wait_ms:
		return false
	var path := out_dir.path_join("%s.png" % current)
	root.get_texture().get_image().save_png(path)
	print("saved %s %s (window %s)" % [path, root.get_texture().get_size(), DisplayServer.window_get_size()])
	current = ""
	return false
