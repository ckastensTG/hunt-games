class_name BaghChalBrassStyle
extends HuntArtStyle
## Bagh Chal, "Temple brass" style: an engraved brass board with cast
## tigers and goats, on a low wooden table in a temple courtyard at dusk.
## Art direction A ("Living Artifact": one warm key light against darkness,
## the board awakening) with touches of B (lamps, prayer-flag shadows, dust in
## the light, the courtyard soft at the edges of the frame).
##
## Scale: 1 unit = the spacing between board points, about 6 cm. The board is
## 5.4 units (about 32 cm), the table top sits just under y = 0 and the
## courtyard floor is about 35 cm lower.
##
## Everything is built under one root, which the game turns with the board.
## The prey view therefore sees the same room from the other side of the table.
##
## Generated assets (replaceable one for one by outsourced art):
##   pieces/tiger.glb, pieces/goat.glb   tools/art/make_pieces.py
##   board/board.glb + board_*.png        tools/art/make_board.py

const ART := "res://titles/bagh_chal/art/"
const FLOOR_Y := -6.0
const TABLE_HALF := 4.3
## Piece sizes relative to the modeled figures (tools/art/make_pieces.py).
const TIGER_SCALE := 1.2
const GOAT_SCALE := 1.25

## Tigers in deep brass, goats in pale white bronze: they must differ in
## value as well as shape, for colorblind players and small phone screens.
const BRASS := Color(0.80, 0.60, 0.30)
const TIGER_BRASS := Color(0.74, 0.55, 0.28)
const WHITE_BRONZE := Color(0.82, 0.81, 0.78)

var board_material: ShaderMaterial


func _init() -> void:
	id = "brass"
	display_name = L10n.N_("Temple brass")
	description = L10n.N_("An engraved brass board and cast figures, at dusk in a temple courtyard.")
	camera_extent = 5.7
	far_blur_from = 11.0


# --- Environment -------------------------------------------------------------

## The courtyard at dusk. `extras` turns on the Steam-only effects (volumetric
## light, SSAO); the core look must hold without them (bible §6, §4.1).
func _make_environment(extras: bool) -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.07, 0.16)
	sky_mat.sky_horizon_color = Color(0.66, 0.34, 0.27)
	sky_mat.sky_curve = 0.09
	sky_mat.ground_horizon_color = Color(0.16, 0.1, 0.08)
	sky_mat.ground_bottom_color = Color(0.03, 0.025, 0.02)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 0.8
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.34, 0.52)
	env.ambient_light_energy = 0.16
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.04
	if extras:
		env.ssao_enabled = true
		env.ssao_radius = 0.6
		env.ssao_intensity = 1.4
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = Color(0.85, 0.8, 0.72)
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.25
	return env


# --- The set -----------------------------------------------------------------

func build_set(root: Node3D, extras: bool) -> void:
	_add_board(root)
	_add_table(root)
	_add_courtyard(root)
	_add_lights(root, extras)
	# Lamps at the middle of the left and right edges: at the frame's edge in
	# both the AI view and the prey view (the set turns with the board).
	_add_lamp(root, Vector3(TABLE_HALF - 0.7, -0.11, -0.9), 0.0, true)
	_add_lamp(root, Vector3(-(TABLE_HALF - 0.7), -0.11, 0.9), 1.0, true)
	_add_prayer_flags(root)
	_add_dust(root)


func set_awaken(value: float) -> void:
	if board_material:
		board_material.set_shader_parameter("awaken", value)


func _add_board(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Board"
	mi.mesh = mesh(ART + "board/board.glb")
	if board_material == null:
		board_material = ShaderMaterial.new()
		board_material.shader = load(ART + "shaders/board_brass.gdshader")
		board_material.set_shader_parameter("albedo_tex", load(ART + "board/board_albedo.png"))
		board_material.set_shader_parameter("orm_tex", load(ART + "board/board_orm.png"))
		board_material.set_shader_parameter("normal_tex", load(ART + "board/board_normal.png"))
		board_material.set_shader_parameter("glow_tex", load(ART + "board/board_glow.png"))
	board_material.set_shader_parameter("glow_energy", 2.2)
	mi.material_override = board_material
	root.add_child(mi)


func _add_table(root: Node3D) -> void:
	var wood := wood(Color(0.16, 0.075, 0.04), Color(0.27, 0.13, 0.065))
	var t := TABLE_HALF
	box(root, "TableTop", Vector3(t * 2, 0.5, t * 2), Vector3(0, -0.11 - 0.25, 0), wood)
	box(root, "TableMolding", Vector3(t * 2 + 0.3, 0.25, t * 2 + 0.3), Vector3(0, -0.11 - 0.62, 0), wood)
	box(root, "TableApron", Vector3(t * 2 - 0.4, 1.6, t * 2 - 0.4), Vector3(0, -0.11 - 1.5, 0), wood)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var h := -0.11 - 2.3 - FLOOR_Y
			box(root, "Leg", Vector3(0.8, h, 0.8), Vector3(sx * (t - 0.6), FLOOR_Y + h / 2, sz * (t - 0.6)), wood)


func _add_courtyard(root: Node3D) -> void:
	# Brick floor.
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mi.mesh = plane
	floor_mi.position.y = FLOOR_Y
	var brick := ShaderMaterial.new()
	brick.shader = load(ART + "shaders/courtyard_brick.gdshader")
	brick.set_shader_parameter("brick_width", 1.1)
	floor_mi.material_override = brick
	root.add_child(floor_mi)
	var stone := plain(Color(0.36, 0.3, 0.25), 0.9)
	var brick_wall := plain(Color(0.36, 0.16, 0.09), 0.92)
	var dark_wood := wood(Color(0.09, 0.05, 0.03), Color(0.17, 0.09, 0.05))
	# Side A (behind the board in the AI view): two low plinth steps lined
	# with butter lamps, the courtyard beyond, and the tiered temple roofs
	# against the dusk sky (seen from low angles: the hero shot, menus).
	# The lamp ledge stands about as high as the table, so its flames show just
	# beyond the board's far edge from low angles.
	for k in 2:
		var z := -11.0 - k * 3.5
		var h := 5.0 + k * 1.6
		box(root, "Step", Vector3(70, h, 3.5), Vector3(-6.0, FLOOR_Y + h / 2, z - 1.75), stone if k == 0 else brick_wall)
	for i in 13:
		var x := -28.0 + i * 4.4
		_add_lamp(root, Vector3(x, FLOOR_Y + 5.0, -11.9), float(i) + 2.0, i % 4 == 1)
	var silhouette := plain(Color(0.025, 0.02, 0.018), 0.95)
	box(root, "FarWall", Vector3(160, 6.5, 2.0), Vector3(0, FLOOR_Y + 3.25, -62), brick_wall)
	box(root, "TempleBase", Vector3(30, 9, 26), Vector3(-34, FLOOR_Y + 4.5, -112), silhouette)
	for k in 3:
		var w := 38.0 - k * 9.5
		box(root, "Roof", Vector3(w, 1.4, w * 0.9), Vector3(-34, FLOOR_Y + 13.0 + k * 6.5, -112), silhouette)
		box(root, "RoofWall", Vector3(w * 0.55, 5.6, w * 0.5), Vector3(-34, FLOOR_Y + 10.2 + k * 6.5, -112), silhouette)
	box(root, "Finial", Vector3(1.2, 4.0, 1.2), Vector3(-34, FLOOR_Y + 28.5, -112), silhouette)
	# Side B (behind the board in the prey view): a carved wooden window in a
	# brick wall, with a lamp niche.
	box(root, "WallB", Vector3(120, 60, 2.0), Vector3(0, FLOOR_Y + 30.0, 24.0), brick_wall)
	box(root, "Plinth", Vector3(120, 4.0, 5.0), Vector3(0, FLOOR_Y + 2.0, 21.5), stone)
	var frame_c := Vector3(0, FLOOR_Y + 17.0, 22.8)
	box(root, "WindowFrame", Vector3(18.0, 13.0, 0.8), frame_c, dark_wood)
	for i in 9:
		box(root, "Lattice", Vector3(0.35, 11.0, 0.5), frame_c + Vector3(-7.0 + i * 1.75, 0, -0.5), dark_wood)
	for j in 6:
		box(root, "Lattice", Vector3(16.0, 0.35, 0.5), frame_c + Vector3(0, -5.0 + j * 2.0, -0.5), dark_wood)
	for i in 7:
		_add_lamp(root, Vector3(-15.0 + i * 5.0, FLOOR_Y + 4.0, 20.5), float(i) + 20.0, i == 3)
	# Side walls, so the space reads as an enclosed courtyard.
	for sx in [-1, 1]:
		box(root, "WallSide", Vector3(2.0, 6.5, 120), Vector3(sx * 52.0, FLOOR_Y + 3.25, -5.0), brick_wall)


func _add_lights(root: Node3D, extras: bool) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "TableReflections"
	probe.size = Vector3(30, 14, 30)
	probe.position = Vector3(0, 1.0, 0)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 1.0
	root.add_child(probe)
	# The key: the last warm light of the day, falling as a pool on the table.
	# It comes from the side, square to the camera, so the AI view and the prey
	# view (the far side of the table) get the same light, mirrored.
	var key := SpotLight3D.new()
	key.name = "Key"
	key.position = Vector3(20.0, 30.0, 0.0)
	key.look_at_from_position(key.position, Vector3(0, 0, 0), Vector3.UP)
	key.light_color = Color(1.0, 0.74, 0.46)
	key.light_energy = 4.2
	# Godot fades a light toward its range, so keep the range well past the
	# table (about 36 units away) or the pool dims.
	key.spot_range = 90.0
	key.spot_attenuation = 0.0
	key.spot_angle = 6.2
	key.spot_angle_attenuation = 2.2
	# Compatibility (low-end fallback): the key's shadow pass striped the board
	# in our software-GL test renders, so that tier goes without it and the
	# pieces keep their contact shadows (make_piece) for grounding.
	# TODO(M1): re-check on a real low-end Android device.
	key.shadow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	key.shadow_blur = 1.5
	key.shadow_bias = 0.06
	key.shadow_normal_bias = 1.5
	key.light_size = 0.35 if extras else 0.0
	key.light_volumetric_fog_energy = 2.5
	root.add_child(key)
	# The lamp row on the temple steps: a low warm glow from side A that puts a
	# rim on the pieces and a sheen on the brass at grazing angles.
	var glow := SpotLight3D.new()
	glow.name = "LampRowGlow"
	glow.position = Vector3(0.0, 1.0, -11.5)
	glow.look_at_from_position(glow.position, Vector3(0, 0, 0), Vector3.UP)
	glow.light_color = Color(1.0, 0.6, 0.3)
	glow.light_energy = 1.2
	glow.spot_range = 22.0
	glow.spot_angle = 22.0
	glow.spot_attenuation = 0.6
	glow.shadow_enabled = false
	glow.light_volumetric_fog_energy = 0.0
	root.add_child(glow)
	# A weak cool fill from the dusk sky, so the shadows aren't black.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-60, 150, 0)
	fill.light_color = Color(0.45, 0.55, 0.9)
	fill.light_energy = 0.07
	fill.light_volumetric_fog_energy = 0.0
	root.add_child(fill)


func _add_lamp(root: Node3D, at: Vector3, seed: float, with_light: bool) -> void:
	var lamp := Node3D.new()
	lamp.name = "ButterLamp"
	lamp.position = at
	lamp.scale = Vector3.ONE * 0.75
	var brass := plain(BRASS, 0.32, 1.0)
	var foot := MeshInstance3D.new()
	var foot_mesh := CylinderMesh.new()
	foot_mesh.top_radius = 0.22
	foot_mesh.bottom_radius = 0.42
	foot_mesh.height = 0.18
	foot.mesh = foot_mesh
	foot.position.y = 0.09
	foot.material_override = brass
	lamp.add_child(foot)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.14
	stem_mesh.bottom_radius = 0.18
	stem_mesh.height = 0.5
	stem.mesh = stem_mesh
	stem.position.y = 0.43
	stem.material_override = brass
	lamp.add_child(stem)
	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.55
	bowl_mesh.bottom_radius = 0.22
	bowl_mesh.height = 0.36
	bowl.mesh = bowl_mesh
	bowl.position.y = 0.86
	bowl.material_override = brass
	lamp.add_child(bowl)
	var ghee := MeshInstance3D.new()
	var ghee_mesh := CylinderMesh.new()
	ghee_mesh.top_radius = 0.5
	ghee_mesh.bottom_radius = 0.5
	ghee_mesh.height = 0.02
	ghee.mesh = ghee_mesh
	ghee.position.y = 1.0
	ghee.material_override = plain(Color(0.42, 0.33, 0.2), 0.25, 0.0)
	lamp.add_child(ghee)
	var flame := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.46)
	quad.center_offset = Vector3(0, 0.23, 0)
	flame.mesh = quad
	flame.position.y = 1.0
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fm := ShaderMaterial.new()
	fm.shader = load(ART + "shaders/lamp_flame.gdshader")
	fm.set_shader_parameter("seed", seed)
	flame.material_override = fm
	lamp.add_child(flame)
	if with_light:
		var light := OmniLight3D.new()
		light.set_script(load(ART + "flicker_light.gd"))
		light.set("base_energy", 1.0)
		light.set("seed", seed)
		light.light_color = Color(1.0, 0.62, 0.3)
		light.omni_range = 7.0
		light.omni_attenuation = 1.6
		light.position.y = 1.35
		light.shadow_enabled = false
		light.light_volumetric_fog_energy = 0.3
		lamp.add_child(light)
	root.add_child(lamp)


func _add_prayer_flags(root: Node3D) -> void:
	# A string of plain flags between the key light and the table. Shadow-only:
	# the player sees moving shadows across one corner of the board and table.
	var colors := [Color(0.1, 0.25, 0.7), Color(0.9, 0.9, 0.85), Color(0.75, 0.1, 0.08),
		Color(0.1, 0.5, 0.2), Color(0.9, 0.75, 0.1)]
	var mat := ShaderMaterial.new()
	mat.shader = load(ART + "shaders/prayer_flag.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 6
	var w := 0.42
	var h := 0.55
	for i in count:
		var x0 := -1.8 + i * 0.6
		var sag := -0.3 * (1.0 - pow((x0 + w / 2) / 2.1, 2.0))
		st.set_color(colors[i % colors.size()])
		for v in [[0.0, 0.0], [w, 0.0], [w, 1.0], [0.0, 0.0], [w, 1.0], [0.0, 1.0]]:
			st.set_uv(Vector2(v[0] / w, v[1]))
			st.add_vertex(Vector3(x0 + v[0], sag - v[1] * h, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "PrayerFlags"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# Halfway along the key light's path to the board's right edge, so the
	# shadows cross the rim and the outer column, not the middle of the board.
	mi.position = Vector3(11.6, 15.0, -0.6)
	mi.rotation_degrees = Vector3(0, 90.0, 0)
	root.add_child(mi)


func _add_dust(root: Node3D) -> void:
	# Lit, not glowing: the motes only show where the key light catches them.
	var p := GPUParticles3D.new()
	p.name = "DustMotes"
	p.amount = 160
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.position = Vector3(1.5, 4.0, -0.5)
	p.visibility_aabb = AABB(Vector3(-10, -8, -10), Vector3(20, 18, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.5, 3.6, 3.5)
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
	m.albedo_color = Color(1.0, 0.9, 0.75, 0.9)
	m.emission_enabled = true
	m.emission = Color(0.0, 0.0, 0.0)
	m.backlight_enabled = true
	m.backlight = Color(1, 1, 1)
	m.disable_receive_shadows = false
	quad.material = m
	p.draw_pass_1 = quad
	root.add_child(p)


# --- Pieces ------------------------------------------------------------------

func make_piece(kind: int, _variant: int) -> Node3D:
	var tiger := kind == HuntState.HUNTER
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Figure"
	mi.mesh = mesh(ART + ("pieces/tiger.glb" if tiger else "pieces/goat.glb"))
	mi.material_override = _piece_material(tiger)
	mi.scale = Vector3.ONE * (TIGER_SCALE if tiger else GOAT_SCALE)
	root.add_child(mi)
	root.add_child(contact_shadow((0.205 * TIGER_SCALE if tiger else 0.158 * GOAT_SCALE) * 1.6))
	return root


func _piece_material(tiger: bool) -> ShaderMaterial:
	var key := "tiger" if tiger else "goat"
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(ART + "shaders/piece_brass.gdshader")
		if tiger:
			m.set_shader_parameter("metal_color", TIGER_BRASS)
			m.set_shader_parameter("stripes", 1.0)
		else:
			m.set_shader_parameter("metal_color", WHITE_BRONZE)
			m.set_shader_parameter("patina_color", Color(0.17, 0.15, 0.12))
			m.set_shader_parameter("polish_roughness", 0.3)
		_materials[key] = m
	return _materials[key]
