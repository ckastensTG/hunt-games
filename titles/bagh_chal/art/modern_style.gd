class_name BaghChalModernStyle
extends HuntArtStyle
## Bagh Chal, "Modern edition" style: what a game company might make of the
## game today (Christopher, 2026-11-04; made colourful and plastic the same
## day). A molded plastic board, a teal field with raised sunflower lines and
## a coral rim; a lying tiger in glossy orange plastic and resting kids in
## white plastic; on a dark table under a pendant lamp, in a quiet room at
## night, with the game's box and its rules beside it.
##
## Still art direction A: one warm key light (the pendant) against darkness,
## the board awakening (the lines warm from within), with touches of B at the
## frame's edges (the box, a mug, books, the window, all soft).
##
## Generated assets (tools/art/make_modern_set.py), replaceable one for one:
##   modern/board.glb + modern/board_*.png, modern/tiger.glb, modern/goat.glb,
##   modern/mug.glb (set dressing)

const ART := "res://titles/bagh_chal/art/"
const SLAB_THICK := 0.26
const PLINTH_H := 0.05
const TABLE_Y := -(SLAB_THICK + PLINTH_H)
const TABLE_HALF := Vector2(8.5, 5.5)
const FLOOR_Y := -14.0
const TIGER_SCALE := 1.18
const GOAT_SCALE := 1.15
const TIGER_PLASTIC := Color(0.97, 0.44, 0.07)
const GOAT_PLASTIC := Color(0.93, 0.92, 0.88)
# The board's colours, for the box and the rules (make_modern_set.py).
const TEAL := Color(0.02, 0.42, 0.47)
const SUNFLOWER := Color(0.98, 0.74, 0.16)
const CORAL := Color(0.92, 0.38, 0.32)

var board_material: ShaderMaterial


func _init() -> void:
	id = "modern"
	sound_dir = "res://titles/bagh_chal/audio/modern"
	music_dir = "res://titles/bagh_chal/audio/music/modern"
	display_name = L10n.N_("Modern edition")
	description = L10n.N_("A board game company's edition of today: a bright molded board, plastic tigers and goats, under a pendant lamp.")
	camera_extent = 5.8
	far_blur_from = 10.5
	hero_from = Vector3(5.0, 1.45, 5.9)
	hero_to = Vector3(0.3, 0.55, -0.8)
	# Printed-looking highlights (HuntArtStyle.mark_ink) in colours that stand
	# off the teal field and the yellow lines.
	mark_ink = true
	mark_select = Color(1.0, 0.5, 0.06)
	mark_step = Color(0.97, 0.97, 0.94)
	mark_capture = Color(0.92, 0.1, 0.22)
	mark_last = Color(0.62, 0.76, 1.0)


func _make_environment(extras: bool) -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.06, 0.1)
	sky_mat.sky_horizon_color = Color(0.16, 0.15, 0.17)
	sky_mat.sky_curve = 0.1
	sky_mat.ground_horizon_color = Color(0.12, 0.1, 0.09)
	sky_mat.ground_bottom_color = Color(0.04, 0.035, 0.03)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 0.7
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.5, 0.56)
	env.ambient_light_energy = 0.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.03
	env.adjustment_contrast = 1.05
	if extras:
		env.ssao_enabled = true
		env.ssao_radius = 0.5
		env.ssao_intensity = 1.5
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.003
		env.volumetric_fog_albedo = Color(0.9, 0.86, 0.8)
		env.volumetric_fog_length = 60.0
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.05
	return env


# --- The set -----------------------------------------------------------------

func build_set(root: Node3D, extras: bool) -> void:
	_add_board(root)
	_add_table(root)
	_add_room(root)
	_add_table_things(root)
	_add_frame_props(root)
	_add_lights(root, extras)


func set_awaken(value: float) -> void:
	if board_material:
		board_material.set_shader_parameter("awaken", value)


func _add_board(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Board"
	mi.mesh = mesh(ART + "modern/board.glb")
	if board_material == null:
		board_material = ShaderMaterial.new()
		board_material.shader = load(ART + "shaders/board_modern.gdshader")
		board_material.set_shader_parameter("albedo_tex", load(ART + "modern/board_albedo.png"))
		board_material.set_shader_parameter("orm_tex", load(ART + "modern/board_orm.png"))
		board_material.set_shader_parameter("normal_tex", load(ART + "modern/board_normal.png"))
		board_material.set_shader_parameter("glow_tex", load(ART + "modern/board_glow.png"))
	board_material.set_shader_parameter("glow_energy", 0.25)
	mi.material_override = board_material
	root.add_child(mi)
	# A dark recessed foot, so the board seems to float a finger's width above
	# the table.
	var foot := box(root, "Foot", Vector3(4.6, PLINTH_H, 4.6), Vector3(0, TABLE_Y + PLINTH_H / 2, 0),
		plain(Color(0.05, 0.045, 0.04), 0.6))
	foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_table(root: Node3D) -> void:
	# Dark, finely textured table (micro-cement), its edge just past the board.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.1, 0.095, 0.09))
	ramp.set_color(1, Color(0.17, 0.16, 0.15))
	tex.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	m.roughness = 0.62
	box(root, "TableTop", Vector3(TABLE_HALF.x * 2, 0.6, TABLE_HALF.y * 2), Vector3(0, TABLE_Y - 0.3, 0), m)
	var legs := plain(Color(0.05, 0.045, 0.04), 0.5)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var h := TABLE_Y - 0.6 - FLOOR_Y
			box(root, "Leg", Vector3(0.5, h, 0.5), Vector3(sx * (TABLE_HALF.x - 1.0), FLOOR_Y + h / 2, sz * (TABLE_HALF.y - 1.0)), legs)


func _add_room(root: Node3D) -> void:
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mi.mesh = plane
	floor_mi.position.y = FLOOR_Y
	floor_mi.material_override = wood(Color(0.12, 0.08, 0.055), Color(0.2, 0.14, 0.09))
	root.add_child(floor_mi)
	var wall := plain(Color(0.33, 0.31, 0.29), 0.9)
	# Side A (behind the board in the AI view): a tall window onto the night,
	# a city's lights soft beyond it.
	box(root, "WallA", Vector3(120, 60, 1.0), Vector3(0, FLOOR_Y + 30, -30.0), wall)
	var night := StandardMaterial3D.new()
	night.albedo_color = Color(0.02, 0.025, 0.05)
	night.emission_enabled = true
	night.emission = Color(0.06, 0.08, 0.15)
	night.emission_energy_multiplier = 1.0
	box(root, "Window", Vector3(34, 26, 0.2), Vector3(-6, FLOOR_Y + 20, -29.4), night)
	var lights := StandardMaterial3D.new()
	lights.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lights.albedo_color = Color(0.55, 0.42, 0.26)
	for i in 40:
		var x := -21.0 + fmod(float(i) * 7.3, 30.0)
		var y := FLOOR_Y + 8.0 + fmod(float(i) * 2.9, 7.0)
		var s := 0.08 + fmod(float(i) * 0.37, 0.1)
		box(root, "CityLight", Vector3(s, s, 0.1), Vector3(x, y, -29.25), lights)
	var frame := plain(Color(0.06, 0.055, 0.05), 0.5)
	for x in [-23.0, -6.0, 11.0]:
		box(root, "Mullion", Vector3(0.5, 26, 0.6), Vector3(x, FLOOR_Y + 20, -29.2), frame)
	box(root, "Sill", Vector3(35, 0.6, 1.2), Vector3(-6, FLOOR_Y + 7.0, -29.0), frame)
	# Side B (behind the board in the prey view): a plain wall with a low
	# sideboard and one large print, lit from the room.
	box(root, "WallB", Vector3(120, 60, 1.0), Vector3(0, FLOOR_Y + 30, 26.0), wall)
	box(root, "Sideboard", Vector3(26, 8.0, 4.0), Vector3(4, FLOOR_Y + 4.0, 23.5), wood(Color(0.16, 0.1, 0.06), Color(0.26, 0.17, 0.1)))
	box(root, "PrintFrame", Vector3(14, 10, 0.4), Vector3(4, FLOOR_Y + 17.0, 25.3), frame)
	box(root, "Print", Vector3(13, 9, 0.2), Vector3(4, FLOOR_Y + 17.0, 25.05), plain(Color(0.78, 0.48, 0.3), 0.85))
	for sx in [-1, 1]:
		box(root, "WallSide", Vector3(1.0, 60, 60), Vector3(sx * 40.0, FLOOR_Y + 30, -2.0), wall)


## A cup and a few books at the table's edge, outside the playing area but in
## the corner of the frame in both views (the set turns with the board).
func _add_table_things(root: Node3D) -> void:
	var cup_root := Node3D.new()
	cup_root.name = "Cup"
	cup_root.position = Vector3(4.2, TABLE_Y, -1.2)
	var cup := MeshInstance3D.new()
	cup.name = "Mug"
	cup.mesh = mesh(ART + "modern/mug.glb")
	cup.rotation_degrees.y = 200.0
	var glaze := ShaderMaterial.new()
	glaze.shader = load(ART + "shaders/piece_modern.gdshader")
	glaze.set_shader_parameter("glaze_color", Color(0.16, 0.2, 0.26))
	glaze.set_shader_parameter("glaze_roughness", 0.45)
	glaze.set_shader_parameter("clearcoat_amount", 0.25)
	cup.material_override = glaze
	cup_root.add_child(cup)
	var coffee := MeshInstance3D.new()
	coffee.name = "Coffee"
	var tm := CylinderMesh.new()
	tm.top_radius = 0.56
	tm.bottom_radius = 0.56
	tm.height = 0.02
	tm.radial_segments = 32
	coffee.mesh = tm
	coffee.position.y = 1.16
	coffee.material_override = plain(Color(0.07, 0.035, 0.015), 0.06)
	cup_root.add_child(coffee)
	root.add_child(cup_root)
	var books := Node3D.new()
	books.name = "Books"
	books.position = Vector3(-4.6, TABLE_Y, 1.0)
	books.rotation_degrees.y = 8.0
	root.add_child(books)
	var covers := [Color(0.82, 0.79, 0.71), Color(0.08, 0.16, 0.28), Color(0.86, 0.6, 0.18)]
	var y := 0.0
	for i in 3:
		var size := Vector3(2.2 - i * 0.15, 0.24 + 0.06 * i, 3.0 - i * 0.2)
		book(books, Vector3(0.05 * i, y, 0.04 * i), size, covers[i], -4.0 * i, i == 1)
		y += size.y


## Above and below the board, so the frame stays full on a 4:3 screen and in
## portrait (the set turns with the board, so each end is "above" for one of
## the players; nothing is tall enough to hide a point):
##   above: the game's box, a teal lid over a coral base
##   below: the rules leaflet, open at the board, and a pencil
func _add_frame_props(root: Node3D) -> void:
	var game_box := Node3D.new()
	game_box.name = "GameBox"
	game_box.position = Vector3(-0.6, TABLE_Y, -4.1)
	game_box.rotation_degrees.y = 4.0
	root.add_child(game_box)
	box(game_box, "Base", Vector3(3.9, 0.46, 2.0), Vector3(0, 0.23, 0), plain(CORAL, 0.5))
	box(game_box, "Lid", Vector3(4.0, 0.32, 2.1), Vector3(0, 0.46, 0), plain(TEAL, 0.38))
	var badge := CylinderMesh.new()
	badge.top_radius = 0.55
	badge.bottom_radius = 0.55
	badge.height = 0.01
	badge.radial_segments = 40
	prop(game_box, "Badge", badge, Vector3(1.05, 0.625, 0.0), plain(SUNFLOWER, 0.4))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.41
	var r_mi := prop(game_box, "BadgeRing", ring, Vector3(1.05, 0.625, 0.0), plain(TIGER_PLASTIC, 0.35))
	r_mi.scale = Vector3(1.0, 0.05, 1.0)
	for k in 3:
		box(game_box, "Stripe", Vector3(0.1, 0.012, 0.5 - 0.1 * absf(k - 1.0)), Vector3(0.87 + 0.18 * k, 0.632, 0.0), plain(Color(0.07, 0.065, 0.06), 0.5))
	# The rules: a folded white leaflet, open, with the board printed on it.
	var rules := Node3D.new()
	rules.name = "Rules"
	rules.position = Vector3(1.1, TABLE_Y, 3.75)
	rules.rotation_degrees.y = -10.0
	root.add_child(rules)
	var paper := plain(Color(0.94, 0.93, 0.9), 0.85)
	for k in 2:
		box(rules, "Page", Vector3(1.25, 0.012, 1.7), Vector3(-0.63 + 1.26 * k, 0.006 + 0.004 * k, 0), paper)
	var print_mi := MeshInstance3D.new()
	print_mi.name = "BoardPrint"
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.95, 0.95)
	print_mi.mesh = quad
	print_mi.position = Vector3(0.63, 0.018, -0.2)
	var printed := StandardMaterial3D.new()
	printed.albedo_texture = load(ART + "modern/board_albedo.png")
	printed.roughness = 0.85
	print_mi.material_override = printed
	rules.add_child(print_mi)
	for k in 4:
		box(rules, "TextLine", Vector3(0.85 - 0.2 * float(k % 2), 0.004, 0.05), Vector3(-0.63, 0.014, -0.5 + 0.18 * k), plain(Color(0.25, 0.25, 0.27), 0.8))
	var pencil := Node3D.new()
	pencil.name = "Pencil"
	pencil.position = Vector3(-0.8, TABLE_Y + 0.05, 3.55)
	pencil.rotation_degrees = Vector3(0, 28.0, 90.0)
	root.add_child(pencil)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.05
	shaft.bottom_radius = 0.05
	shaft.height = 1.5
	shaft.radial_segments = 6
	prop(pencil, "Shaft", shaft, Vector3.ZERO, plain(SUNFLOWER, 0.45))
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.05
	tip.height = 0.18
	tip.radial_segments = 12
	prop(pencil, "Tip", tip, Vector3(0, 0.84, 0), plain(Color(0.86, 0.72, 0.52), 0.8))


func _add_lights(root: Node3D, extras: bool) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "TableReflections"
	probe.size = Vector3(30, 14, 30)
	probe.position = Vector3(0, 1.0, 0)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	hide_at_low(probe)  # the plastic barely shows it, and phones pay ~4 ms for it
	root.add_child(probe)
	# The key: a pendant lamp over the table, a little to the side (square to
	# the camera, as in the other styles, so both views get the same light).
	var key := SpotLight3D.new()
	key.name = "Key"
	key.position = Vector3(14.0, 26.0, 0.0)
	key.look_at_from_position(key.position, Vector3(0, 0, 0), Vector3.UP)
	key.light_color = Color(1.0, 0.84, 0.64)
	key.light_energy = 4.0
	key.spot_range = 80.0
	key.spot_attenuation = 0.0
	key.spot_angle = 9.5
	key.spot_angle_attenuation = 1.8
	key.shadow_enabled = not is_compatibility()
	key.shadow_blur = 1.6
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 1.5
	key.light_size = 0.5 if extras else 0.0
	key.light_volumetric_fog_energy = 1.0
	root.add_child(key)
	# The pendant itself, high above: a dark shade with a glowing rim, seen in
	# the hero shot and as a soft highlight in the glaze.
	var shade := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.6
	sm.bottom_radius = 2.4
	sm.height = 1.6
	shade.mesh = sm
	shade.position = Vector3(14.0, 27.0, 0.0)
	shade.material_override = plain(Color(0.04, 0.04, 0.04), 0.4)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shade)
	# Cool fill from the window side, low, so the shadow sides keep their form.
	var fill := DirectionalLight3D.new()
	fill.name = "WindowFill"
	fill.rotation_degrees = Vector3(-30, 180, 0)
	fill.light_color = Color(0.55, 0.65, 0.95)
	fill.light_energy = 0.12
	fill.light_volumetric_fog_energy = 0.0
	root.add_child(fill)
	# Warm bounce from the lit table.
	var bounce := OmniLight3D.new()
	bounce.name = "Bounce"
	bounce.position = Vector3(3.0, 1.5, 0.0)
	bounce.light_color = Color(1.0, 0.8, 0.6)
	bounce.light_energy = 0.35
	bounce.omni_range = 14.0
	bounce.omni_attenuation = 1.4
	bounce.light_volumetric_fog_energy = 0.0
	hide_at_low(bounce)
	root.add_child(bounce)


# --- Pieces ------------------------------------------------------------------

func make_piece(kind: int, _variant: int) -> Node3D:
	var tiger := kind == HuntState.HUNTER
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Figure"
	mi.mesh = mesh(ART + ("modern/tiger.glb" if tiger else "modern/goat.glb"))
	mi.material_override = _piece_material(tiger)
	mi.scale = Vector3.ONE * (TIGER_SCALE if tiger else GOAT_SCALE)
	root.add_child(mi)
	root.add_child(contact_shadow(0.3 if tiger else 0.21, 1.0))
	return root


func _piece_material(tiger: bool) -> ShaderMaterial:
	var key := "tiger" if tiger else "goat"
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(ART + "shaders/piece_modern.gdshader")
		if tiger:
			m.set_shader_parameter("glaze_color", TIGER_PLASTIC)
			m.set_shader_parameter("stripes", 1.0)
			m.set_shader_parameter("glaze_roughness", 0.24)
			m.set_shader_parameter("clearcoat_amount", 0.3)
		else:
			m.set_shader_parameter("glaze_color", GOAT_PLASTIC)
			m.set_shader_parameter("glaze_roughness", 0.3)
			m.set_shader_parameter("clearcoat_amount", 0.2)
		_materials[key] = m
	return _materials[key]
