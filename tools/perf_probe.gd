extends SceneTree
## Where the frame time goes, per Bagh Chal look, and what each setting saves.
##   xvfb-run -a -s "-screen 0 1280x1400x24" godot --path . --rendering-method mobile \
##     --resolution 540x1200 -s res://tools/perf_probe.gd [-- --frames=12]
## Prints, for each look: scene counts (meshes, vertices, lights, particles,
## textures), draw calls and primitives (main and shadow passes), the time to
## build the set and make pieces, and the measured CPU/GPU render time at
## High with each setting switched off in turn, then at Medium and Low
## (GameGraphics). On a software GPU (lavapipe) the times are only good for
## comparing settings with each other.

const GreyboxScript := preload("res://scenes/greybox/greybox.gd")

var game: Node3D
var frames := 12
var looks: Array = []
var look := ""
var configs: Array = ["high", "no_dof", "no_glow", "msaa_2x", "msaa_off", "no_shadows", "scale_0.75", "no_particles", "no_lamps", "medium", "low"]
var _choice_before := ""
var config_i := 0
var phase := "start"
var count := 0
var samples_gpu: Array = []
var samples_cpu: Array = []
var results := {}
var _saved := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = int(arg.substr(9))
	_choice_before = GameGraphics.choice()
	GameGraphics.set_choice(GameGraphics.HIGH)
	game = load("res://scenes/greybox/greybox.tscn").instantiate()
	game.autosave = false
	root.add_child(game)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


func _process(_delta: float) -> bool:
	match phase:
		"start":
			game.menu.close()
			game.mode = GreyboxScript.Mode.HOTSEAT
			game._rule_set_id = HuntRuleSets.BAGH_CHAL_STANDARD
			game.new_game()
			for st in game.art_styles():
				looks.append(st.id)
			print("renderer: %s, %s, viewport %s" % [RenderingServer.get_current_rendering_method(),
				RenderingServer.get_video_adapter_name(), root.get_visible_rect().size])
			phase = "look"
		"look":
			if looks.is_empty():
				print("done")
				GameGraphics.set_choice(_choice_before)
				quit()
				return true
			look = looks.pop_front()
			var t0 := Time.get_ticks_usec()
			game.set_art_style(look)
			var t_build := (Time.get_ticks_usec() - t0) / 1000.0
			t0 = Time.get_ticks_usec()
			game.tutorial_set_state(_mid_game())
			var t_pieces := (Time.get_ticks_usec() - t0) / 1000.0
			t0 = Time.get_ticks_usec()
			game.tutorial_set_state(_mid_game())
			var t_pieces_again := (Time.get_ticks_usec() - t0) / 1000.0
			t0 = Time.get_ticks_usec()
			game.new_game()
			var t_rebuild := (Time.get_ticks_usec() - t0) / 1000.0
			game.tutorial_set_state(_mid_game())
			print("\n== %s: build the set %.0f ms (a new game rebuilds it: %.0f ms); place 20 pieces %.0f ms first time, %.0f ms again" % [look, t_build, t_rebuild, t_pieces, t_pieces_again])
			config_i = 0
			_apply(configs[0])
			phase = "warm"
			count = 0
		"warm":
			count += 1
			if count == 2 and config_i == 0:
				_scene_stats()  # a frame later: the old set has been freed
			if count >= 6:
				phase = "measure"
				count = 0
				samples_gpu.clear()
				samples_cpu.clear()
		"measure":
			var vp := root.get_viewport_rid()
			samples_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			samples_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			count += 1
			if count == 2:
				_render_info(configs[config_i])
			if count >= frames:
				samples_gpu.sort()
				samples_cpu.sort()
				var g: float = samples_gpu[samples_gpu.size() / 2]
				var c: float = samples_cpu[samples_cpu.size() / 2]
				var base: float = results.get(look + "/high", g)
				results[look + "/" + configs[config_i]] = g
				print("  %-13s GPU %7.1f ms (%+5.0f%%)  CPU %5.1f ms" % [configs[config_i], g, 100.0 * (g - base) / base, c])
				_restore()
				config_i += 1
				if config_i >= configs.size():
					phase = "look"
				else:
					_apply(configs[config_i])
					phase = "warm"
					count = 0
	return false


## A position after placement has started: 12 goats down, some steps.
func _mid_game() -> HuntState:
	var s := HuntState.create(game.rules)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 16:
		var moves := s.legal_moves()
		if moves.is_empty():
			break
		var quiet: Array = moves.filter(func(m: PackedInt32Array) -> bool: return HuntState.captures_in(m) == 0)
		var pick: PackedInt32Array = (quiet if not quiet.is_empty() else moves)[rng.randi_range(0, (quiet if not quiet.is_empty() else moves).size() - 1)]
		s.make(pick)
	return s


func _scene_stats() -> void:
	var meshes := 0
	var surfaces := 0
	var verts := 0
	var shadow_casters := 0
	var omni := 0
	var spot := 0
	var directional := 0
	var shadowed := 0
	var particles := 0
	var textures := {}
	for n in game.find_children("*", "", true, false):
		if n is MeshInstance3D and n.is_visible_in_tree() and n.mesh:
			meshes += 1
			surfaces += n.mesh.get_surface_count()
			for si in n.mesh.get_surface_count():
				var arr: Array = n.mesh.surface_get_arrays(si)
				if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
					verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var mat: Material = n.material_override if n.material_override else n.get_active_material(si)
				_collect_textures(mat, textures)
			if n.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow_casters += 1
		elif n is Light3D and n.is_visible_in_tree():
			if n is OmniLight3D:
				omni += 1
			elif n is SpotLight3D:
				spot += 1
			else:
				directional += 1
			if n.shadow_enabled:
				shadowed += 1
		elif n is GPUParticles3D and n.is_visible_in_tree():
			particles += n.amount
	var big: Array = []
	var tex_mb := 0.0
	for t: Texture2D in textures:
		var img := t.get_image() if t is ImageTexture or t is CompressedTexture2D else null
		var fmt := img.get_format() if img else -1
		var mips := img.has_mipmaps() if img else false
		var mb := (img.get_data_size() / 1048576.0) if img else 0.0
		tex_mb += mb
		if t.get_width() >= 1024:
			big.append("%s %dx%d %s%s %.1fMB" % [t.resource_path.get_file(), t.get_width(), t.get_height(),
				_fmt_name(fmt), " mips" if mips else " NO mips", mb])
	print("  scene: %d meshes, %d surfaces, %d vertices, %d shadow casters; lights: %d omni, %d spot, %d directional, %d with shadows; %d particles" % [meshes, surfaces, verts, shadow_casters, omni, spot, directional, shadowed, particles])
	print("  textures: %d, %.1f MB in memory; large ones: %s" % [textures.size(), tex_mb, ", ".join(big)])


func _fmt_name(f: int) -> String:
	match f:
		Image.FORMAT_RGBA8: return "RGBA8"
		Image.FORMAT_RGB8: return "RGB8"
		Image.FORMAT_L8: return "L8"
		Image.FORMAT_RG8: return "RG8"
		Image.FORMAT_ETC2_RGB8: return "ETC2"
		Image.FORMAT_ETC2_RGBA8: return "ETC2A"
		Image.FORMAT_ASTC_4x4: return "ASTC"
		Image.FORMAT_DXT1: return "DXT1"
		Image.FORMAT_DXT5: return "DXT5"
		Image.FORMAT_BPTC_RGBA: return "BPTC"
	return "fmt%d" % f


func _collect_textures(mat: Material, out: Dictionary) -> void:
	if mat is ShaderMaterial:
		for p in mat.shader.get_shader_uniform_list():
			var v = mat.get_shader_parameter(p.name)
			if v is Texture2D:
				out[v] = true
	elif mat is BaseMaterial3D:
		for prop in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "orm_texture", "emission_texture", "ao_texture"]:
			var v = mat.get(prop)
			if v is Texture2D:
				out[v] = true


func _render_info(label: String) -> void:
	if label != "high":
		return
	var vp := root.get_viewport_rid()
	var R := RenderingServer
	print("  draw calls: %d main + %d shadow; primitives: %d main + %d shadow; objects %d" % [
		R.viewport_get_render_info(vp, R.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, R.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		R.viewport_get_render_info(vp, R.VIEWPORT_RENDER_INFO_TYPE_SHADOW, R.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		R.viewport_get_render_info(vp, R.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, R.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		R.viewport_get_render_info(vp, R.VIEWPORT_RENDER_INFO_TYPE_SHADOW, R.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		R.viewport_get_render_info(vp, R.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, R.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)])


func _lights() -> Array:
	return game.find_children("*", "Light3D", true, false)


func _apply(cfg: String) -> void:
	_saved.clear()
	var env: Environment = game._world_env.environment
	var vp := root.get_viewport()
	var low := false
	if cfg == "medium" or cfg == "low":
		game.set_graphics(cfg)
		return
	if cfg == "no_dof" or low:
		_saved["attrs"] = game._camera.attributes
		game._camera.attributes = null
	if cfg == "no_glow" or low:
		_saved["glow"] = env.glow_enabled
		env.glow_enabled = false
	if cfg == "msaa_off":
		_saved["msaa"] = vp.msaa_3d
		vp.msaa_3d = Viewport.MSAA_DISABLED
	if cfg == "msaa_2x" or low:
		_saved["msaa"] = vp.msaa_3d
		vp.msaa_3d = Viewport.MSAA_2X
	if cfg == "no_shadows":
		_saved["shadows"] = []
		for l in _lights():
			if l.shadow_enabled:
				_saved["shadows"].append(l)
				l.shadow_enabled = false
	if cfg == "scale_0.75" or low:
		_saved["scale"] = vp.scaling_3d_scale
		vp.scaling_3d_scale = 0.75
	if cfg == "no_particles" or low:
		_saved["particles"] = []
		for p in game.find_children("*", "GPUParticles3D", true, false):
			if p.visible:
				_saved["particles"].append(p)
				p.visible = false
	if cfg == "no_lamps":
		_saved["lamps"] = []
		for l in _lights():
			if l is OmniLight3D and l.visible:
				_saved["lamps"].append(l)
				l.visible = false


func _restore() -> void:
	if GameGraphics.choice() != GameGraphics.HIGH:
		game.set_graphics(GameGraphics.HIGH)
	var env: Environment = game._world_env.environment
	var vp := root.get_viewport()
	if _saved.has("attrs"):
		game._camera.attributes = _saved["attrs"]
	if _saved.has("glow"):
		env.glow_enabled = _saved["glow"]
	if _saved.has("msaa"):
		vp.msaa_3d = _saved["msaa"]
	if _saved.has("scale"):
		vp.scaling_3d_scale = _saved["scale"]
	for l in _saved.get("shadows", []):
		l.shadow_enabled = true
	for p in _saved.get("particles", []):
		p.visible = true
	for l in _saved.get("lamps", []):
		l.visible = true
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
