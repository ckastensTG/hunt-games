extends SceneTree
## A short run of the performance test (scenes/greybox/perf_test.gd): two
## looks, every change, a fraction of a second each. Checks that it measured
## them all and that the player's game, look, Graphics setting (Auto with its
## detected tier), vsync, filtering and materials all come back.
## Then a short run of the detail test on one look.
##   xvfb-run -a -s "-screen 0 1280x1400x24" godot --path . --rendering-method mobile \
##     --fixed-fps 30 --resolution 540x1200 -s res://tools/smoke_perf_test.gd

const GreyboxScript := preload("res://scenes/greybox/greybox.gd")

var game: Node3D
var test: CanvasLayer
var frame := 0
var failures: Array[String] = []
var _settings_before := {}
var _session_before: MatchSession
var _moves_before := 0
var _textures_before := {}


func _initialize() -> void:
	_settings_before = {"graphics": GameGraphics.choice(), "graphics_auto": GameGraphics.detected(),
		"look": str(L10n.load_setting("look_bagh_chal", ""))}
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	game.autosave = false
	root.add_child(game)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.menu.close()
		game.mode = GreyboxScript.Mode.HOTSEAT
		game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
		game.set_art_style("stone")
		game.new_game()
		for i in 5:
			var moves: Array = game.state.legal_moves()
			game.session.commit(moves[0], game.state.side)
		game._stop_tween()
		game._anim_queue.clear()
		game._animating = false
		game._sync_pieces()
		game._after_move()
		GameGraphics.set_choice(GameGraphics.AUTO)
		GameGraphics.set_detected(GameGraphics.MEDIUM)
		game._apply_graphics()
	if frame == 6:  # the old set has gone
		_session_before = game.session
		_moves_before = game.history.size()
		_textures_before = _board_textures()
		test = game.start_perf_test()
		check(test != null, "the test starts")
		test.looks = ["brass", "modern"]
		test.warm = 0.2
		test.measure = 0.5
		test.finished.connect(_on_finished)
	if frame > 20000:
		failures.append("timed out")
		return _end()
	return false


func _on_finished() -> void:
	var n: int = test.configs.size() * 2
	check(test.results.size() == n, "measured %d of %d" % [test.results.size(), n])
	for k in test.results:
		check(test.results[k].mean > 0.0, "%s has a time" % k)
	check(game.current_style().id == "stone", "look back to stone (%s)" % game.current_style().id)
	check(str(L10n.load_setting("look_bagh_chal", "")) == "stone", "look setting back")
	check(GameGraphics.choice() == GameGraphics.AUTO, "Graphics back to Auto")
	check(GameGraphics.detected() == GameGraphics.MEDIUM, "Auto's tier kept (%s)" % GameGraphics.detected())
	check(game.graphics_auto == (not OS.has_feature("editor")), "Auto measuring back")
	check(game.session == _session_before, "the game is back")
	check(game.history.size() == _moves_before, "its moves are back")
	check(not game.tutorial_active, "board playable again")
	check(game._board_root.visible, "board visible")
	check(root.anisotropic_filtering_level == ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level"), "filtering back")
	check(DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED, "vsync back")
	for mi: MeshInstance3D in game._board_root.find_children("*", "MeshInstance3D", true, false):
		check(not mi.has_meta("perf_test_material"), "materials back on %s" % mi.name)
	var after := _board_textures()
	for key in _textures_before:
		check(after.get(key) == _textures_before[key], "texture back: %s" % key)
	# The test switched looks: switch back to brass and check its board too.
	game.set_art_style("brass")
	# Low hides what the look marked (HuntArtStyle.hide_at_low); High shows it.
	var marked: Array = game._board_root.find_children("*", "Node3D", true, false).filter(
		func(n: Node) -> bool: return n.has_meta(HuntArtStyle.GRAPHICS_MIN) and not n.is_queued_for_deletion() and not test._leaving(n))
	check(marked.size() == 5, "brass marks 5 nodes for Low (%d)" % marked.size())
	game.set_graphics(GameGraphics.LOW)
	check(marked.all(func(n: Node3D) -> bool: return not n.visible), "hidden at Low")
	game.set_graphics(GameGraphics.HIGH)
	check(marked.all(func(n: Node3D) -> bool: return n.visible), "shown at High")
	GameGraphics.set_choice(GameGraphics.AUTO)
	GameGraphics.set_detected(GameGraphics.MEDIUM)
	game._apply_graphics()
	for mat in test._materials():
		if mat is ShaderMaterial:
			for u in mat.shader.get_shader_uniform_list():
				var v = mat.get_shader_parameter(u.name)
				check(not (v is ImageTexture), "brass %s is the imported texture" % u.name)
	game.set_art_style("stone")
	print("perf test lines:")
	for l in test.lines:
		print("  " + l)
	# The detail test, from the results' button.
	test.queue_free()
	_detail.call_deferred()


func _detail() -> void:
	test = game.start_perf_test("detail")
	check(test != null, "the detail test starts")
	if test == null:
		_end()
		return
	test.looks = ["modern"]
	test.warm = 0.2
	test.measure = 0.4
	test.finished.connect(_on_detail_finished)


func _on_detail_finished() -> void:
	check(test.results.size() == test.DETAIL.size(), "detail measured %d of %d" % [test.results.size(), test.DETAIL.size()])
	check(not root.disable_3d, "3D back on")
	check(game._hud.visible and game._match_ui.visible, "interface back")
	check(game._pieces_root.visible, "pieces back")
	for l: Light3D in game._board_root.find_children("*", "Light3D", true, false):
		check(l.visible, "light back: %s" % l.name)
	check(game._world_env.environment == game.current_style().environment(false), "environment back")
	for l in test.lines:
		print("  " + l)
	_end()


## Stone's board material textures, by parameter name.
func _board_textures() -> Dictionary:
	var out := {}
	for mat in _materials_now():
		if mat is ShaderMaterial and mat.shader:
			for u in mat.shader.get_shader_uniform_list():
				var v = mat.get_shader_parameter(u.name)
				if v is Texture2D:
					out["%s:%s" % [mat.shader.resource_path.get_file(), u.name]] = v
	return out


func _materials_now() -> Array:
	var found := {}
	for mi: MeshInstance3D in game._board_root.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override:
			found[mi.material_override] = true
		if mi.mesh:
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(si)
				if m == null:
					m = mi.mesh.surface_get_material(si)
				if m:
					found[m] = true
	return found.keys()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _end() -> bool:
	# Put the machine's own settings back.
	GameGraphics.set_choice(_settings_before.graphics)
	GameGraphics.set_detected(_settings_before.graphics_auto)
	L10n.save_setting("look_bagh_chal", _settings_before.look)
	_textures_before.clear()
	_session_before = null
	if test and is_instance_valid(test):
		test.queue_free()
	test = null
	for f in failures:
		print("FAIL " + f)
	print("smoke_perf_test: %s" % ("ok" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
	return true
