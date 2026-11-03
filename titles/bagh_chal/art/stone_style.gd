class_name BaghChalStoneStyle
extends HuntArtStyle
## Bagh Chal, "Stone and pebbles" style: the historical look. How the game
## has long been played in Nepal: the lines scratched into stone (or the
## ground) and chalked, larger stones for the tigers, small pebbles for the
## goats. Here the stone sits on a woven straw mat (sukul) on the brick floor
## of a pati, a public rest house, in late-afternoon sun.
## Sources: claude/games/hunt-games-dev-handoff.md, "Historical style".
##
## Same art direction as the brass style, applied to humbler materials: one
## warm key light (a shaft of low sun) against a shaded interior, the courtyard
## soft beyond, leaf shadows and dust in the light.
##
## Generated assets (tools/art/make_stone_set.py), replaceable one for one:
##   stone/board.glb + stone/board_*.png, stone/tiger_0..3.glb, stone/goat_0..7.glb

const ART := "res://titles/bagh_chal/art/"
const STONE_THICK := 0.4      # the slab: its face is y = 0
const MAT_THICK := 0.12
const FLOOR_Y := -(STONE_THICK + MAT_THICK)
const MAT_HALF := Vector2(5.6, 4.6)
const TIGER_SCALE := 1.12
const GOAT_SCALE := 1.15
## Light layer for the sunlit courtyard outside, so its sun doesn't light the
## shaded interior (the mat and board get only the key's shaft of sun).
const OUTSIDE_LAYER := 2

var board_material: ShaderMaterial


func _init() -> void:
	id = "stone"
	display_name = "Stone and pebbles"
	description = "The historical way: lines scratched in stone, tigers and goats of river stone, on a straw mat."
	camera_extent = 5.9
	far_blur_from = 11.0
	# From inside the rest house, looking out toward the sunlit courtyard, so
	# the stones are rim-lit by the low sun.
	hero_from = Vector3(-5.6, 1.6, 5.2)
	hero_to = Vector3(0.6, 0.6, -0.8)
	mark_select = Color(1.0, 0.8, 0.4)
	mark_step = Color(0.5, 0.95, 0.6)
	mark_capture = Color(1.0, 0.4, 0.25)
	mark_last = Color(0.55, 0.75, 1.0)


func _make_environment(extras: bool) -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.42, 0.62)
	sky_mat.sky_horizon_color = Color(0.86, 0.72, 0.55)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.5, 0.4, 0.3)
	sky_mat.ground_bottom_color = Color(0.2, 0.16, 0.12)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 0.9
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.55, 0.48)
	env.ambient_light_energy = 0.22
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.05
	if extras:
		env.ssao_enabled = true
		env.ssao_radius = 0.5
		env.ssao_intensity = 1.6
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.004
		env.volumetric_fog_albedo = Color(0.9, 0.85, 0.75)
		env.volumetric_fog_length = 70.0
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.1
	return env


# --- The set -----------------------------------------------------------------

func build_set(root: Node3D, extras: bool) -> void:
	_add_board(root)
	_add_mat(root)
	_add_pati(root)
	_add_lights(root, extras)
	_add_leaf_shadows(root)
	_add_dust(root)


func set_awaken(value: float) -> void:
	if board_material:
		board_material.set_shader_parameter("awaken", value)


func _add_board(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Board"
	mi.mesh = mesh(ART + "stone/board.glb")
	if board_material == null:
		board_material = ShaderMaterial.new()
		board_material.shader = load(ART + "shaders/board_stone.gdshader")
		board_material.set_shader_parameter("albedo_tex", load(ART + "stone/board_albedo.png"))
		board_material.set_shader_parameter("orm_tex", load(ART + "stone/board_orm.png"))
		board_material.set_shader_parameter("normal_tex", load(ART + "stone/board_normal.png"))
		board_material.set_shader_parameter("glow_tex", load(ART + "stone/board_glow.png"))
	mi.material_override = board_material
	root.add_child(mi)


func _add_mat(root: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(ART + "shaders/straw_mat.gdshader")
	mat.set_shader_parameter("half_size", MAT_HALF)
	mat.set_shader_parameter("straw_width", 0.06)
	mat.set_shader_parameter("row_spacing", 0.95)
	mat.set_shader_parameter("rope_color", Color(0.5, 0.38, 0.22))
	var mi := box(root, "StrawMat", Vector3(MAT_HALF.x * 2, MAT_THICK, MAT_HALF.y * 2),
		Vector3(0, -STONE_THICK - MAT_THICK / 2, 0), mat)
	mi.rotation_degrees.y = 3.0   # laid down by hand, not quite square to the room


func _add_pati(root: Node3D) -> void:
	# Brick floor of the rest house.
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 140)
	floor_mi.mesh = plane
	floor_mi.position = Vector3(-16, FLOOR_Y, 0)
	var brick := ShaderMaterial.new()
	brick.shader = load(ART + "shaders/courtyard_brick.gdshader")
	brick.set_shader_parameter("brick_width", 1.8)
	brick.set_shader_parameter("brick_a", Color(0.46, 0.22, 0.13))
	brick.set_shader_parameter("brick_b", Color(0.33, 0.15, 0.09))
	floor_mi.material_override = brick
	root.add_child(floor_mi)
	var post_wood := wood(Color(0.1, 0.06, 0.035), Color(0.2, 0.12, 0.07))
	var stone := plain(Color(0.45, 0.42, 0.38), 0.9)
	var brick_wall := plain(Color(0.4, 0.19, 0.11), 0.92)
	# The open side (+x): the platform's edge and a row of wooden posts. One
	# post stands just off each far corner of the frame, in both views.
	box(root, "PlatformEdge", Vector3(1.6, 6.0, 140), Vector3(14.6, FLOOR_Y - 3.0, 0), stone)
	for z in [-27.0, -9.0, 9.0, 27.0]:
		box(root, "PostBase", Vector3(2.4, 1.4, 2.4), Vector3(9.5, FLOOR_Y + 0.7, z), stone)
		box(root, "Post", Vector3(1.7, 40.0, 1.7), Vector3(9.5, FLOOR_Y + 21.4, z), post_wood)
	# The back (-x) and far ends: brick walls, a wooden lattice window.
	box(root, "BackWall", Vector3(2.0, 44, 140), Vector3(-30, FLOOR_Y + 22, 0), brick_wall)
	for zs in [-1.0, 1.0]:
		box(root, "EndWall", Vector3(46, 44, 2.0), Vector3(-8, FLOOR_Y + 22, zs * 36.0), brick_wall)
	var win := Vector3(-29.0, FLOOR_Y + 14.0, 0)
	box(root, "WindowFrame", Vector3(0.8, 10.0, 14.0), win, post_wood)
	for i in 8:
		box(root, "Lattice", Vector3(0.5, 9.0, 0.3), win + Vector3(0.5, 0, -5.6 + i * 1.6), post_wood)
	# Outside: the sunlit courtyard and the houses across it, soft in the
	# distance. Lit only by the outdoor sun (OUTSIDE_LAYER).
	var outside := Node3D.new()
	outside.name = "Outside"
	root.add_child(outside)
	var ground := box(outside, "Courtyard", Vector3(120, 1.0, 160), Vector3(76, FLOOR_Y - 6.5, 0), plain(Color(0.6, 0.55, 0.47), 0.9))
	var houses := plain(Color(0.55, 0.3, 0.2), 0.9)
	var roofs := plain(Color(0.22, 0.14, 0.1), 0.9)
	for i in 6:
		var z := -55.0 + i * 22.0
		var h := 26.0 + float((i * 7) % 5) * 4.0
		box(outside, "House", Vector3(14, h, 20), Vector3(64, FLOOR_Y - 6.0 + h / 2, z), houses)
		box(outside, "Eave", Vector3(18, 1.2, 23), Vector3(62, FLOOR_Y - 6.0 + h + 0.6, z), roofs)
	for mi in outside.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 << (OUTSIDE_LAYER - 1)
	ground.layers = 1 << (OUTSIDE_LAYER - 1)


func _add_lights(root: Node3D, extras: bool) -> void:
	# The key: low afternoon sun through the open side, a shaft that falls on
	# the mat. From the side, square to the camera, as in the brass style, so
	# the AI view and the prey view get the same light, mirrored.
	var key := SpotLight3D.new()
	key.name = "Key"
	key.position = Vector3(26.0, 26.0, 0.0)
	key.look_at_from_position(key.position, Vector3(0, 0, 0), Vector3.UP)
	key.light_color = Color(1.0, 0.82, 0.58)
	key.light_energy = 3.4
	key.spot_range = 90.0
	key.spot_attenuation = 0.0
	key.spot_angle = 9.0
	key.spot_angle_attenuation = 2.0
	key.light_cull_mask = 1
	# As in the brass style: no key shadow on Compatibility (it striped the
	# board in software GL); contact shadows ground the pieces there.
	key.shadow_enabled = not is_compatibility()
	key.shadow_blur = 1.2
	key.shadow_bias = 0.06
	key.shadow_normal_bias = 1.5
	key.light_size = 0.4 if extras else 0.0
	key.light_volumetric_fog_energy = 2.0
	root.add_child(key)
	# The sun on the courtyard outside (and nothing inside).
	var sun := DirectionalLight3D.new()
	sun.name = "OutdoorSun"
	sun.rotation_degrees = Vector3(-35, 90, 0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 2.2
	sun.light_cull_mask = 1 << (OUTSIDE_LAYER - 1)
	sun.light_volumetric_fog_energy = 0.0
	root.add_child(sun)
	# Bounce from the sunlit floor into the room: low, warm, no shadows.
	var bounce := OmniLight3D.new()
	bounce.name = "Bounce"
	bounce.position = Vector3(6.0, 2.0, 0.0)
	bounce.light_color = Color(1.0, 0.75, 0.5)
	bounce.light_energy = 0.5
	bounce.omni_range = 18.0
	bounce.omni_attenuation = 1.2
	bounce.light_cull_mask = 1
	bounce.light_volumetric_fog_energy = 0.0
	root.add_child(bounce)


func _add_leaf_shadows(root: Node3D) -> void:
	# A branch outside the open side: its leaves throw moving dapples across
	# one end of the mat and the edge of the stone. Shadow-only.
	var mat := ShaderMaterial.new()
	mat.shader = load(ART + "shaders/leaf_shadow.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4061
	var branch := Node3D.new()
	branch.name = "LeafShadows"
	# About halfway along the key's path to the mat beyond the stone's right
	# edge, so the dapples fall on the straw and only touch the stone's rim.
	branch.position = Vector3(15.6, 13.2, -1.0)
	root.add_child(branch)
	for i in 40:
		var leaf := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.32, 0.5)
		leaf.mesh = q
		leaf.material_override = mat
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		leaf.position = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.8, 0.8), rng.randf_range(-2.4, 2.4))
		leaf.rotation = Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(0, TAU), rng.randf_range(-1.0, 1.0))
		branch.add_child(leaf)


func _add_dust(root: Node3D) -> void:
	# Lit, not glowing: the motes only show inside the shaft of sun.
	var p := GPUParticles3D.new()
	p.name = "DustMotes"
	p.amount = 140
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.position = Vector3(1.5, 4.0, -0.5)
	p.visibility_aabb = AABB(Vector3(-10, -8, -10), Vector3(20, 18, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.8, 3.6, 3.8)
	pm.gravity = Vector3(0, -0.006, 0)
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	p.process_material = pm
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 32
	dot.height = 32
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g
	var quad := QuadMesh.new()
	quad.size = Vector2(0.028, 0.028)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = dot
	m.albedo_color = Color(1.0, 0.92, 0.8, 0.85)
	m.backlight_enabled = true
	m.backlight = Color(1, 1, 1)
	quad.material = m
	p.draw_pass_1 = quad
	root.add_child(p)


# --- Pieces ------------------------------------------------------------------

func make_piece(kind: int, variant: int) -> Node3D:
	var tiger := kind == HuntState.HUNTER
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Stone"
	var n := posmod(variant, 4 if tiger else 8)
	mi.mesh = mesh(ART + ("stone/tiger_%d.glb" % n if tiger else "stone/goat_%d.glb" % n))
	mi.material_override = _piece_material(tiger)
	mi.scale = Vector3.ONE * (TIGER_SCALE if tiger else GOAT_SCALE)
	root.add_child(mi)
	root.add_child(contact_shadow(0.3 if tiger else 0.19, 1.1))
	return root


func _piece_material(tiger: bool) -> ShaderMaterial:
	var key := "tiger" if tiger else "goat"
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(ART + "shaders/stone_piece.gdshader")
		if tiger:
			# Dark, water-worn basalt with a satin sheen; two carry a quartz vein.
			m.set_shader_parameter("stone_color", Color(0.12, 0.115, 0.11))
			m.set_shader_parameter("grain_color", Color(0.24, 0.22, 0.2))
			m.set_shader_parameter("roughness_base", 0.4)
		else:
			# Pale quartzite pebbles.
			m.set_shader_parameter("stone_color", Color(0.8, 0.76, 0.68))
			m.set_shader_parameter("grain_color", Color(0.62, 0.56, 0.48))
			m.set_shader_parameter("roughness_base", 0.55)
			m.set_shader_parameter("grain_scale", 80.0)
		_materials[key] = m
	return _materials[key]
