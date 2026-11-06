extends CanvasLayer
## The performance test, in test (debug) builds only: in-game menu →
## "Performance test (test build)". For each look it plays moves on the board
## and measures the frames: at High, Medium and Low (GameGraphics), then at Low
## with one thing changed at a time, to show where the time goes on this
## device. Phone GPUs such as the Mali-G52 don't give Godot GPU times (the
## Visual Profiler shows 0.0 ms there), so the frame time is what's measured,
## with vsync off where the phone allows it.
##
## The results show on screen, are printed with a "[perf]" prefix (Godot's
## Output when deployed with remote debug, and logcat) and are saved to
## user://perf_test.txt. The player's game, look, Graphics setting and vsync
## come back afterwards. tools/smoke_perf_test.gd runs a short version.

signal finished

## [shown name, tier, changes on top of the tier]
const CONFIGS := [
	["High", "high", []],
	["High, mipmaps", "high", ["mips"]],
	["Medium", "medium", []],
	["Low", "low", []],
	["Low, no anisotropic", "low", ["aniso_off"]],
	["Low, mipmaps", "low", ["mips"]],
	["Low, mipmaps, half size", "low", ["mips_half"]],
	["Low, mipmaps, no aniso", "low", ["mips", "aniso_off"]],
	["Low, 3D at 50%", "low", ["scale_50"]],
	["Low, no MSAA", "low", ["msaa_off"]],
	["Low, no lamps", "low", ["no_lamps"]],
	["Low, plain materials", "low", ["flat"]],
	["Low, no 3D scene", "low", ["empty"]],
]
## The detail test (from the results): which part of each look costs what.
## (The moto g(20) keeps vsync on whatever is asked, so nothing reads faster
## than its screen's refresh; the fixed part of a frame can't be split there.)
const DETAIL := [
	["Low", "low", []],
	["Low, plain board", "low", ["flat_board"]],
	["Low, plain pieces", "low", ["flat_pieces"]],
	["Low, plain set", "low", ["flat_set"]],
	["Low, no reflection probe", "low", ["no_probe"]],
	["Low, no main light", "low", ["no_key"]],
	["Low, main light only", "low", ["key_light_only"]],
	["Low, no lights", "low", ["no_lights"]],
	["Low, no interface", "low", ["no_ui"]],
	["Low, no pieces", "low", ["no_pieces"]],
	["Low, 3D at 60%", "low", ["scale_60"]],
	["Low, no lamps, 3D at 60%", "low", ["no_lamps", "scale_60"]],
]
## Follow-ups to the Low tier (round 22): what's left, and whether an even
## 30 fps (Engine.max_fps) beats an uneven 35-45.
const CANDIDATES := [
	["Low", "low", []],
	["Low, capped at 30 fps", "low", ["cap30"]],
	["Low, no fill lights", "low", ["no_fill"]],
	["Low, 3D at 60%", "low", ["scale_60"]],
	["Medium", "medium", []],
]
## The suites, in the order the results offer them.
const SUITES := {"main": CONFIGS, "detail": DETAIL, "candidates": CANDIDATES}
const TEX_PROPS := ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture",
	"orm_texture", "emission_texture", "ao_texture", "detail_albedo", "detail_normal", "rim_texture",
	"clearcoat_texture", "heightmap_texture", "backlight_texture", "subsurf_scatter_texture"]
const SAVE_PATH := "user://perf_test.txt"

## "main" (CONFIGS), "detail" (DETAIL) or "candidates" (CANDIDATES).
var suite := "main"
## Seconds after a change before measuring (new shader variants compile in
## the background meanwhile, drawn with slower fallback shaders), and seconds
## measured.
var warm := 2.0
var measure := 3.0
## The looks to measure (all of them when empty).
var looks: Array = []
var configs: Array = []
var results := {}  # "look|config index" -> {mean, p90, worst, stalls, frames}
var lines: Array[String] = []

var game: Node3D
var _jobs: Array = []
var _job: Array = []
var _job_count := 0
var _phase := ""
var _t := 0.0
var _timer := FrameTimer.new()
var _before := {}
var _start_state: HuntState
var _rng := RandomNumberGenerator.new()
var _undo: Array[Callable] = []
var _mip_cache := {}  # Texture2D -> {"full": Texture2D, "half": Texture2D}, or {} when left alone
var _flat_mat: StandardMaterial3D
var _flat := ""  # which meshes are plain: "all", "board", "pieces", "set"
var _strip: PanelContainer
var _status: Label
var _results_panel: Control
var _info := ""


func _init(owner_game: Node3D) -> void:
	game = owner_game
	name = "PerfTest"
	layer = 60


func _ready() -> void:
	_build_strip()
	_begin.call_deferred()  # after the caller has set looks, warm, measure


func is_running() -> bool:
	return _phase != "" and _phase != "done"


# --- Running ---------------------------------------------------------------

func _begin() -> void:
	var win := get_window()
	_before = {
		"look": game.current_style().id if game.current_style() else "",
		"choice": GameGraphics.choice(),
		"detected": GameGraphics.detected(),
		"auto": game.graphics_auto,
		"vsync": DisplayServer.window_get_vsync_mode(),
		"session": game.session,
		"aniso": get_viewport().anisotropic_filtering_level,
	}
	game.menu.close()
	game._stop_ai()
	game._stop_tween()
	game._anim_queue.clear()
	game.graphics_auto = false
	# Like How to play: a board of its own, no clicks, no saving, no AI.
	game.tutorial_active = true
	var rule_set: String = game.session.rule_set_id if game.session else game._rule_set_id
	var s := MatchSession.create(game.rules, rule_set, MatchSession.Kind.PASS_AND_PLAY,
		MatchSession.Driver.LOCAL, MatchSession.Driver.LOCAL)
	game._use_session(s)
	_start_state = _opening()
	if configs.is_empty():
		configs = SUITES.get(suite, CONFIGS)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if looks.is_empty():
		for st in game.art_styles():
			looks.append(st.id)
	for look in looks:
		for i in configs.size():
			_jobs.append([look, i])
	_job_count = _jobs.size()
	_info = "%s · %s · %s · %s %dx%d · %s" % [OS.get_model_name(), RenderingServer.get_video_adapter_name(),
		DeviceInfo.describe(), RenderingServer.get_current_rendering_method(), win.size.x, win.size.y,
		"vsync off requested" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED else "vsync on"]
	_out("Performance test (%s) · %s" % [suite, _info])
	if OS.get_name() == "Android":
		_out("API level: Java %d, getprop %d; OS.get_version() \"%s\"" % [DeviceInfo._from_java(),
			DeviceInfo._from_getprop(), OS.get_version()])
	_out("%-8s %-26s %7s %6s %6s %6s %6s %6s" % ["look", "setting", "mean", "fps", "p90", "worst", "stalls", "even"])
	_next()


func _next() -> void:
	if _jobs.is_empty():
		_finish()
		return
	_job = _jobs.pop_front()
	_phase = "setup"


func _process(delta: float) -> void:
	match _phase:
		"setup":
			_setup_job()
			_t = 0.0
			_phase = "warm"
		"warm":
			_keep_moving()
			_t += delta
			if _t >= warm:
				_timer.clear()
				_phase = "measure"
		"measure":
			_keep_moving()
			_timer.add(delta)
			if _timer.duration() >= measure:
				_record()
				_next()


func _setup_job() -> void:
	var look: String = _job[0]
	var cfg: Array = configs[_job[1]]
	_undo_changes()
	GameGraphics.set_choice(cfg[1])
	var style: HuntArtStyle = game.current_style()
	if style and style.id != look:
		_mip_cache.clear()  # the last look's copies
		game.set_art_style(look)
		style = game.current_style()
	else:
		game._apply_graphics()
	_rng.seed = 7
	game.tutorial_set_state(_start_state)
	for change in cfg[2]:
		_apply(change)
	_status.text = "Performance test %d/%d: %s · %s. Keep the phone still; Back stops." % [
		_job_count - _jobs.size(), _job_count, L10n.t(style.display_name) if style else look, cfg[0]]


## The same moves every time: from an opening with some goats down, quiet
## moves where there are any (captures end games quickly).
func _keep_moving() -> void:
	if game.is_animating():
		return
	var s: HuntState = game.state
	var moves: Array = s.legal_moves() if s.status() == HuntState.Status.ONGOING else []
	if moves.is_empty() or game.history.size() >= 40:
		game.tutorial_set_state(_start_state)
		return
	var quiet: Array = moves.filter(func(m: PackedInt32Array) -> bool: return HuntState.captures_in(m) == 0)
	var pick: Array = quiet if not quiet.is_empty() else moves
	game.tutorial_play(pick[_rng.randi_range(0, pick.size() - 1)])
	if _flat != "":
		_flatten()


func _opening() -> HuntState:
	var s := HuntState.create(game.rules)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 6:
		var moves := s.legal_moves()
		var quiet: Array = moves.filter(func(m: PackedInt32Array) -> bool: return HuntState.captures_in(m) == 0)
		if quiet.is_empty():
			break
		s.make(quiet[rng.randi_range(0, quiet.size() - 1)])
	return s


func _record() -> void:
	var r := {"mean": _timer.mean_ms(), "p90": _timer.percentile_ms(0.9), "worst": _timer.percentile_ms(1.0),
		"best": _timer.percentile_ms(0.0), "stalls": _timer.hitches, "frames": _timer.count(),
		"even": _evenness()}
	results["%s|%d" % _job] = r
	_out("%-8s %-26s %5.1fms %6.1f %6.1f %6.1f %6d %5.0f%%" % [_job[0], configs[_job[1]][0], r.mean,
		1000.0 / maxf(r.mean, 0.001), r.p90, r.worst, r.stalls, r.even])


## How even the frames are: the share within 20% of the median frame. Uneven
## frames (a 16.7 ms frame, then a 33.3 ms one) make movement look jerky even
## at a decent average.
func _evenness() -> float:
	var times: PackedFloat32Array = _timer._times
	if times.is_empty():
		return 0.0
	var median := _timer.percentile_ms(0.5) / 1000.0
	var near := 0
	for t in times:
		if absf(t - median) <= 0.2 * median:
			near += 1
	return 100.0 * near / times.size()


## Back (Android) or Stop: ends early and puts everything back.
func stop() -> void:
	if is_running():
		_out("stopped early")
		_finish()
	else:
		_close()


func _finish() -> void:
	_phase = "done"
	_undo_changes()
	_mip_cache.clear()
	DisplayServer.window_set_vsync_mode(_before.vsync)
	get_viewport().anisotropic_filtering_level = _before.aniso
	GameGraphics.set_choice(_before.choice)
	GameGraphics.set_detected(_before.detected)  # set_choice(AUTO) clears it
	game._stop_tween()
	game.tutorial_active = false
	var style: HuntArtStyle = game.current_style()
	if _before.look != "" and style and style.id != _before.look:
		L10n.save_setting("look_" + game._title(), _before.look)
		game.art_style_ids[game._title()] = _before.look
	if _before.session:
		game._use_session(_before.session)  # rebuilds the set and applies the Graphics setting
	else:
		game._show_idle_board()
	game.graphics_auto = _before.auto
	game._graphics_auto.restart()
	_summary()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	_strip.visible = false
	_show_results()
	finished.emit()


func _close() -> void:
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		stop()


func _out(line: String) -> void:
	lines.append(line)
	print("[perf] " + line)


## The average frame per setting and look, side by side.
func _summary() -> void:
	var best := INF
	for r: Dictionary in results.values():
		best = minf(best, r.get("best", INF))
	var hz := DisplayServer.screen_get_refresh_rate()
	var known := not is_nan(hz) and hz > 1.0
	_out("")
	if best < INF:
		_out("Fastest frame: %.1f ms (screen %s).%s" % [best, ("%.0f Hz" % hz) if known else "refresh unknown",
			" The phone kept vsync on: nothing reads faster than its refresh." if known and best > 1000.0 / hz - 1.0 else ""])
	_out("Average frame in ms while pieces move (16.7 = 60 fps, 33.3 = 30 fps):")
	var head := "%-26s" % ""
	for look in looks:
		head += "%9s" % look
	_out(head)
	for i in configs.size():
		var row := "%-26s" % configs[i][0]
		var any := false
		for look in looks:
			var r: Dictionary = results.get("%s|%d" % [look, i], {})
			row += ("%9.1f" % r.mean) if not r.is_empty() else "%9s" % "-"
			any = any or not r.is_empty()
		if any:
			_out(row)


# --- Changes on top of a tier ---------------------------------------------

func _apply(change: String) -> void:
	var vp := get_viewport()
	match change:
		"aniso_off":
			var was := vp.anisotropic_filtering_level
			vp.anisotropic_filtering_level = Viewport.ANISOTROPY_DISABLED
			_undo.append(func() -> void: vp.anisotropic_filtering_level = was)
		"mips", "mips_half":
			_swap_textures(change == "mips_half")
		"scale_50":
			vp.scaling_3d_scale = 0.5
		"msaa_off":
			vp.msaa_3d = Viewport.MSAA_DISABLED
		"no_lamps":
			for l: OmniLight3D in game._board_root.find_children("*", "OmniLight3D", true, false):
				if l.visible:
					l.visible = false
					_undo.append(func() -> void:
						if is_instance_valid(l):
							l.visible = true)
		"flat", "flat_board", "flat_pieces", "flat_set":
			_flat = "all" if change == "flat" else change.substr(5)
			_flatten()
			_undo.append(_unflatten)
		"no_probe":
			for probe: ReflectionProbe in game._board_root.find_children("*", "ReflectionProbe", true, false):
				if probe.visible:
					probe.visible = false
					_undo.append(func() -> void:
						if is_instance_valid(probe):
							probe.visible = true)
		"no_key":
			for l: Light3D in game._board_root.find_children("*", "Light3D", true, false):
				if l.visible and l.get_meta("shadow_as_made", false):
					l.visible = false
					_undo.append(func() -> void:
						if is_instance_valid(l):
							l.visible = true)
		"scale_60":
			vp.scaling_3d_scale = 0.6
		"cap30":
			var was := Engine.max_fps
			Engine.max_fps = 30
			_undo.append(func() -> void: Engine.max_fps = was)
		"no_far_lamps":
			# Lamps away from the table light only the background.
			for l: OmniLight3D in game._board_root.find_children("*", "OmniLight3D", true, false):
				if l.visible and l.global_position.length() > 8.0:
					l.visible = false
					_undo.append(func() -> void:
						if is_instance_valid(l):
							l.visible = true)
		"no_fill":
			# Weak lights without shadows besides the lamps: sky fills, rims.
			for l: Light3D in game._board_root.find_children("*", "Light3D", true, false):
				if l.visible and not (l is OmniLight3D) and not l.get_meta("shadow_as_made", false):
					l.visible = false
					_undo.append(func() -> void:
						if is_instance_valid(l):
							l.visible = true)
		"small_probe":
			for probe: ReflectionProbe in game._board_root.find_children("*", "ReflectionProbe", true, false):
				var was := probe.size
				probe.size = Vector3(10.0, 4.0, 10.0)
				_undo.append(func() -> void:
					if is_instance_valid(probe):
						probe.size = was)
		"empty":
			game._board_root.visible = false
			_undo.append(func() -> void: game._board_root.visible = true)
		"no_pieces":
			game._pieces_root.visible = false
			_undo.append(func() -> void: game._pieces_root.visible = true)
		"no_ui":
			for layer: CanvasLayer in [game._hud, game._match_ui, self]:
				if layer.visible:
					layer.visible = false
					_undo.append(func() -> void: layer.visible = true)
		"key_light_only", "no_lights":
			for l: Light3D in game._board_root.find_children("*", "Light3D", true, false):
				var keep: bool = change == "key_light_only" and l.get_meta("shadow_as_made", false)
				if l.visible and not keep:
					l.visible = false
					_undo.append(func() -> void:
						if is_instance_valid(l):
							l.visible = true)
		"full_scale":
			vp.scaling_3d_scale = 1.0
		"simple_env":
			var was: Environment = game._world_env.environment
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = was.background_color if was else Color.BLACK
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = was.ambient_light_color if was else Color.GRAY
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			game._world_env.environment = env
			_undo.append(func() -> void: game._world_env.environment = was)
		"no_3d":
			vp.disable_3d = true
			_undo.append(func() -> void: vp.disable_3d = false)


## Viewport settings come back with the next tier; the rest here.
func _undo_changes() -> void:
	for i in range(_undo.size() - 1, -1, -1):
		_undo[i].call()
	_undo.clear()


## Every material on the board and pieces. Looks cache and share their
## materials, so a swapped texture reaches new pieces too.
func _materials() -> Array:
	var found := {}
	for mi: MeshInstance3D in game._board_root.find_children("*", "MeshInstance3D", true, false):
		if mi.is_queued_for_deletion() or _leaving(mi):
			continue  # the last look's set, going this frame
		if mi.material_override:
			found[mi.material_override] = true
		if mi.material_overlay:
			found[mi.material_overlay] = true
		if mi.mesh:
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(si)
				if m == null:
					m = mi.mesh.surface_get_material(si)
				if m:
					found[m] = true
	return found.keys()


func _leaving(n: Node) -> bool:
	var p := n.get_parent()
	while p and p != game._board_root:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


## Large textures without mipmaps (the looks' boards today) swapped for
## copies with mipmaps, at full or half size.
func _swap_textures(half: bool) -> void:
	for mat in _materials():
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
			for u in (mat as ShaderMaterial).shader.get_shader_uniform_list():
				var uname: String = u.name
				var v = (mat as ShaderMaterial).get_shader_parameter(uname)
				if v is Texture2D:
					var nt := _mipped(v, half)
					if nt:
						(mat as ShaderMaterial).set_shader_parameter(uname, nt)
						_undo.append(func() -> void: (mat as ShaderMaterial).set_shader_parameter(uname, v))
		elif mat is BaseMaterial3D:
			for prop in TEX_PROPS:
				var v = mat.get(prop)
				if v is Texture2D:
					var nt := _mipped(v, half)
					if nt:
						mat.set(prop, nt)
						_undo.append(func() -> void: mat.set(prop, v))


func _mipped(tex: Texture2D, half: bool) -> Texture2D:
	if not _mip_cache.has(tex):
		_mip_cache[tex] = {}
	var entry: Dictionary = _mip_cache[tex]
	var key := "half" if half else "full"
	if entry.has(key):
		return entry[key]
	var made: Texture2D = null
	if tex.get_width() >= 256 and not entry.has("skip"):
		var img := tex.get_image()
		if img == null or img.has_mipmaps() or img.is_compressed():
			entry["skip"] = true
		else:
			if half:
				img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
			img.generate_mipmaps()
			made = ImageTexture.create_from_image(img)
	entry[key] = made
	return made


func _flatten() -> void:
	if _flat_mat == null:
		_flat_mat = StandardMaterial3D.new()
		_flat_mat.albedo_color = Color(0.55, 0.48, 0.4)
		_flat_mat.roughness = 0.8
	for mi: MeshInstance3D in game._board_root.find_children("*", "MeshInstance3D", true, false):
		if not mi.has_meta("perf_test_material") and _part_matches(mi):
			mi.set_meta("perf_test_material", [mi.material_override])
			mi.material_override = _flat_mat


## The look's board is the mesh named "Board"; pieces are under the pieces
## root; everything else is the set.
func _part_matches(mi: MeshInstance3D) -> bool:
	if _flat == "all":
		return true
	var piece: bool = game._pieces_root.is_ancestor_of(mi)
	var board := mi.name == "Board" or (mi.get_parent() and mi.get_parent().name == "Board")
	match _flat:
		"board": return board
		"pieces": return piece
		"set": return not board and not piece
	return false


func _unflatten() -> void:
	_flat = ""
	for mi: MeshInstance3D in game._board_root.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("perf_test_material"):
			mi.material_override = mi.get_meta("perf_test_material")[0]
			mi.remove_meta("perf_test_material")


# --- On screen -------------------------------------------------------------

## A thin strip while measuring (a big panel would cost frames itself).
func _build_strip() -> void:
	_strip = PanelContainer.new()
	_strip.theme = SeriesTheme.theme()
	_strip.add_theme_stylebox_override("panel", SeriesTheme.panel_box())
	_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_strip.offset_left = -420
	_strip.offset_right = 420
	_strip.offset_top = -230
	_strip.offset_bottom = -150
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = SeriesTheme.label("", "body", 15, SeriesTheme.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip.add_child(_status)
	add_child(_strip)


func _show_results() -> void:
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 0.6)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	cover.theme = SeriesTheme.theme()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", SeriesTheme.panel_box())
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Clear of the status bar at the top and Android's navigation bar at the
	# bottom (it comes up over the bottom edge when touched there).
	card.offset_left = 24
	card.offset_top = 70
	card.offset_right = -24
	card.offset_bottom = -150
	cover.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(SeriesTheme.label("Performance test", "display", 26, SeriesTheme.BRASS))
	var info := SeriesTheme.label(_info, "body", 13, SeriesTheme.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var note := SeriesTheme.label("Frames per second while pieces move, average. Saved to %s." % SAVE_PATH, "body", 14, SeriesTheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 1 + looks.size()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	grid.add_child(SeriesTheme.label("", "body", 15))
	for look in looks:
		grid.add_child(SeriesTheme.label(_look_name(look), "bold", 15, SeriesTheme.TEXT))
	for i in configs.size():
		var cells: Array[String] = []
		for look in looks:
			var r: Dictionary = results.get("%s|%d" % [look, i], {})
			cells.append("%d" % roundi(1000.0 / maxf(r.mean, 0.001)) if not r.is_empty() else "")
		if cells.all(func(c: String) -> bool: return c == ""):
			continue
		var name_label := SeriesTheme.label(configs[i][0], "body", 15, SeriesTheme.TEXT)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		for c in cells:
			var l := SeriesTheme.label(c, "code", 15, SeriesTheme.TEXT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var names: Array = SUITES.keys()
	var i := names.find(suite)
	if i >= 0 and i + 1 < names.size():
		var next_suite: String = names[i + 1]
		var more := Button.new()
		more.text = "%s test" % next_suite.capitalize()
		more.custom_minimum_size = Vector2(220, 56)
		more.pressed.connect(func() -> void:
			_close()
			game.start_perf_test.call_deferred(next_suite))
		buttons.add_child(more)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(200, 56)
	close.pressed.connect(_close)
	buttons.add_child(close)
	_results_panel = cover


func _look_name(look: String) -> String:
	for st in game.art_styles():
		if st.id == look:
			return L10n.t(st.display_name)
	return look
