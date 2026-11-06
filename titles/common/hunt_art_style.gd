class_name HuntArtStyle
extends RefCounted
## One look for a hunt-game title: the environment, camera depth of field, the
## set around the board, and the pieces. A title can offer several (Bagh Chal
## has "Temple brass" and "Stone and pebbles"); the player picks one in the
## settings. Styles only ever build nodes for the view: the rules never see
## them (framework §2, presentation layer).
##
## Scale everywhere: 1 unit = the spacing between two board points (about
## 6 cm). The playing surface is y = 0; pieces stand on it and face -Z.

## Stable id, saved in settings.
var id := ""
## English name for the style menu (shown through tr()).
var display_name := ""
## One-line description for the style menu (shown through tr()).
var description := ""
## The folder with this look's piece sounds (place, slide, set, land,
## capture; tools/audio/make_sounds.py). Empty: the greybox's wooden ones.
var sound_dir := ""
## The folder with this look's music (track_1.ogg, track_2.ogg …;
## tools/audio/make_music.py), played in turn by MusicPlayer. Empty: none.
var music_dir := ""
## Distance hint for the game camera (the greybox frames 5.4 by default).
var camera_extent := 5.7
## Depth of field: where the game camera starts blurring the surroundings.
var far_blur_from := 11.0
## The cinematic camera for style frames, menus and trailers: from, look-at.
var hero_from := Vector3(5.2, 1.5, 6.0)
var hero_to := Vector3(0.3, 0.7, -0.9)
## Colors for the move highlights on this style's board.
var mark_select := Color(1.0, 0.78, 0.35)
var mark_step := Color(0.55, 0.95, 0.65)
var mark_capture := Color(1.0, 0.38, 0.22)
var mark_last := Color(0.5, 0.7, 1.0)
## Draw the highlights as opaque ink instead of added light: for pale boards,
## where light does not show against the wood.
var mark_ink := false

var _meshes := {}
var _materials := {}
var _environment: Environment


## The world environment for this look. `extras` turns on the Steam-only
## effects (volumetric light, SSAO); the core look must hold without them
## (bible §6, §4.1). Built once and reused.
func environment(extras: bool) -> Environment:
	if _environment == null:
		_environment = _make_environment(extras)
	return _environment


func camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = far_blur_from
	ca.dof_blur_far_transition = 9.0
	ca.dof_blur_amount = 0.12
	return ca


## Builds the board and everything around it under `root` (which the game
## turns with the board, so the prey view sees the room from the other side).
func build_set(_root: Node3D, _extras: bool) -> void:
	pass


## A piece. `variant` lets a style vary its pieces (one pebble is never quite
## like the next); the same variant always gives the same piece.
func make_piece(_kind: int, _variant: int) -> Node3D:
	return Node3D.new()


## How awake the board is, 0..1 (art direction A: the lines glow once play
## starts).
func set_awaken(_value: float) -> void:
	pass


func _make_environment(_extras: bool) -> Environment:
	return Environment.new()


# --- Helpers for styles ------------------------------------------------------

## Meta key: the lowest Graphics tier a node shows at (greybox
## `_apply_graphics`).
const GRAPHICS_MIN := "graphics_min"


## Hides a node at the Low tier. For lights and reflections a phone pays for
## on every pixel but the picture hardly misses (checked in renders; measured
## on a moto g(20), round 22: Brass's distant lamps and sky fill, Modern's
## reflection probe and bounce light). The node must be visible as built.
static func hide_at_low(node: Node3D) -> void:
	node.set_meta(GRAPHICS_MIN, "medium")


func is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## The first mesh in an imported scene (.glb), cached.
func mesh(path: String) -> Mesh:
	if not _meshes.has(path):
		var scene: Node = (load(path) as PackedScene).instantiate()
		var found: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		_meshes[path] = found.mesh
		scene.free()
	return _meshes[path]


func box(root: Node3D, name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = mat
	root.add_child(mi)
	return mi


func plain(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## A turned shape: `profile` (x = radius, y = height), from the axis at the
## bottom outward and up, swept round the y axis. A hollow shape (a cup) goes
## up the outside, over the rim and down the inside. Normals follow the
## profile, so a corner needs two points close together to stay crisp.
static func lathe(profile: PackedVector2Array, segments := 32) -> ArrayMesh:
	var n := profile.size()
	var normals2: Array[Vector2] = []
	for i in n:
		var a := profile[maxi(i - 1, 0)]
		var b := profile[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		normals2.append(Vector2(t.y, -t.x))
	var length := 0.0
	var vs := PackedFloat32Array([0.0])
	for i in range(1, n):
		length += profile[i].distance_to(profile[i - 1])
		vs.append(length)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for s in segments + 1:
		var ang := TAU * s / segments
		var c := cos(ang)
		var sn := sin(ang)
		for i in n:
			var p := profile[i]
			verts.append(Vector3(p.x * c, p.y, p.x * sn))
			var nn := normals2[i]
			norms.append(Vector3(nn.x * c, nn.y, nn.x * sn).normalized())
			uvs.append(Vector2(float(s) / segments, vs[i] / maxf(length, 0.001)))
	var idx := PackedInt32Array()
	for s in segments:
		for i in n - 1:
			var a := s * n + i
			var b := a + 1
			var c2 := a + n
			var d := c2 + 1
			# Godot's front faces wind clockwise: keep each triangle facing
			# the way its normals point.
			for tri in [[a, b, c2], [b, d, c2]]:
				var e1 := verts[tri[1]] - verts[tri[0]]
				var e2 := verts[tri[2]] - verts[tri[0]]
				var avg := norms[tri[0]] + norms[tri[1]] + norms[tri[2]]
				if e1.cross(e2).dot(avg) > 0.0:
					tri = [tri[0], tri[2], tri[1]]
				idx.append_array(PackedInt32Array(tri))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A mesh instance placed in `root` (set dressing).
func prop(root: Node3D, name: String, m: Mesh, at: Vector3, mat: Material, yaw_deg := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = m
	mi.position = at
	mi.rotation_degrees.y = yaw_deg
	mi.material_override = mat
	root.add_child(mi)
	return mi


## An empty clay cup standing at `at`, on the vessel shader:
##   "kulhad"  the unglazed, slightly flared tea cup of Nepal and India
##   "bowl"    a small glazed tea bowl on a foot ring
## `colors` overrides the shader's defaults (e.g. {"glaze": Color(...)}).
func clay_cup(root: Node3D, at: Vector3, kind := "kulhad", colors := {}) -> MeshInstance3D:
	var key := "cup_" + kind
	if not _meshes.has(key):
		_meshes[key] = lathe(_cup_outline(kind), 48)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://titles/common/shaders/vessel.gdshader")
	var outline := _cup_outline(kind)
	var top := 0.0
	for pt in outline:
		top = maxf(top, pt.y)
	mat.set_shader_parameter("height", top)
	if kind == "bowl":
		mat.set_shader_parameter("glazed", 1.0)
		mat.set_shader_parameter("glaze_line", 0.16)
		mat.set_shader_parameter("clay", Color(0.72, 0.6, 0.47))
		mat.set_shader_parameter("clay_dark", Color(0.55, 0.43, 0.32))
		mat.set_shader_parameter("throw_rings", 0.35)
	for k in colors:
		mat.set_shader_parameter(k, colors[k])
	var cup := prop(root, "Cup", _meshes[key], at, mat)
	return cup


static func _cup_outline(kind: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if kind == "bowl":
		# Foot ring, a rounded belly, a rim rolled thin, the inside down to a
		# shallow well.
		pts.append_array([Vector2(0, 0.022), Vector2(0.12, 0.022), Vector2(0.135, 0.004),
			Vector2(0.15, 0.0), Vector2(0.172, 0.0), Vector2(0.182, 0.02), Vector2(0.2, 0.045),
			Vector2(0.255, 0.1), Vector2(0.3, 0.18), Vector2(0.33, 0.27), Vector2(0.345, 0.36)])
		pts.append_array(_rim(Vector2(0.345, 0.4), 0.014))
		pts.append_array([Vector2(0.312, 0.34), Vector2(0.295, 0.25), Vector2(0.262, 0.16),
			Vector2(0.21, 0.095), Vector2(0.14, 0.06), Vector2(0.06, 0.05), Vector2(0, 0.048)])
	else:
		# A string-cut base, thin walls swelling a little as they flare, a
		# thin rim.
		pts.append_array([Vector2(0, 0.0), Vector2(0.2, 0.0), Vector2(0.222, 0.006),
			Vector2(0.232, 0.024), Vector2(0.246, 0.08), Vector2(0.27, 0.2), Vector2(0.294, 0.33),
			Vector2(0.313, 0.46), Vector2(0.326, 0.56), Vector2(0.332, 0.6)])
		pts.append_array(_rim(Vector2(0.334, 0.62), 0.011))
		pts.append_array([Vector2(0.308, 0.58), Vector2(0.302, 0.54), Vector2(0.29, 0.44),
			Vector2(0.272, 0.32), Vector2(0.25, 0.19), Vector2(0.232, 0.1), Vector2(0.2, 0.066),
			Vector2(0.09, 0.058), Vector2(0, 0.056)])
	return pts


## A rim rolled over the top: from the outside at `outer_top` (x = outer
## radius, y = height of the lip) round to the inside, radius `r`.
static func _rim(outer_top: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := Vector2(outer_top.x - r, outer_top.y - r)
	for k in 7:
		var a := PI * float(k) / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## A closed hardback lying flat, its spine along z at -x: two cover boards, a
## rounded spine and the page block set in from the edges. `size`: width
## (spine to fore-edge), thickness, height (head to tail).
func book(root: Node3D, at: Vector3, size: Vector3, cover: Color, yaw_deg := 0.0, foil := false) -> Node3D:
	var b := Node3D.new()
	b.name = "Book"
	b.position = at
	b.rotation_degrees.y = yaw_deg
	root.add_child(b)
	var board := 0.022
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = cover
	cloth.roughness = 0.78
	cloth.rim_enabled = true            # the soft sheen of bookcloth at grazing angles
	cloth.rim = 0.35
	cloth.rim_tint = 0.6
	cloth.normal_enabled = true
	cloth.normal_texture = _linen_normal()
	cloth.normal_scale = 0.35
	cloth.uv1_triplanar = true
	cloth.uv1_scale = Vector3(5, 5, 5)
	box(b, "BackBoard", Vector3(size.x, board, size.z), Vector3(0, board / 2, 0), cloth)
	box(b, "FrontBoard", Vector3(size.x, board, size.z), Vector3(0, size.y - board / 2, 0), cloth)
	var spine_mesh := CylinderMesh.new()
	spine_mesh.top_radius = size.y / 2
	spine_mesh.bottom_radius = size.y / 2
	spine_mesh.height = size.z
	spine_mesh.radial_segments = 20
	var spine := prop(b, "Spine", spine_mesh, Vector3(-size.x / 2 + 0.02, size.y / 2, 0), cloth)
	spine.rotation_degrees.x = 90
	spine.scale = Vector3(0.45, 1.0, 1.0)
	var pages := ShaderMaterial.new()
	pages.shader = preload("res://titles/common/shaders/book_pages.gdshader")
	var block := Vector3(size.x - 0.05, size.y - board * 2, size.z - 0.07)
	pages.set_shader_parameter("thickness", block.y)
	box(b, "Pages", block, Vector3(-0.005, size.y / 2, 0), pages)
	if foil:
		box(b, "Foil", Vector3(size.x * 0.5, 0.004, size.z * 0.08), Vector3(0.05, size.y + 0.002, -size.z * 0.28),
			plain(Color(0.83, 0.66, 0.36), 0.32, 1.0))
	return b


func _linen_normal() -> Texture2D:
	if not _materials.has("linen"):
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.18
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 4.0
		tex.noise = noise
		_materials["linen"] = tex
	return _materials["linen"]


## Wood grain from stretched noise (triplanar, so any box works).
func wood(dark: Color, light: Color) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, light)
	tex.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.04, 0.6, 0.04)
	m.roughness = 0.55
	return m


## A soft dark disc under a piece, so it sits on the board even without a
## shadow-casting light (Compatibility tier) and at a distance.
func contact_shadow(radius: float, strength := 1.0) -> MeshInstance3D:
	var blob := MeshInstance3D.new()
	blob.name = "ContactShadow"
	var quad := PlaneMesh.new()
	quad.size = Vector2(radius * 2, radius * 2)
	blob.mesh = quad
	blob.position.y = 0.002
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var key := "contact_%.2f" % strength
	if not _materials.has(key):
		var tex := GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.55 * strength), Color(0, 0, 0, 0.35 * strength), Color(0, 0, 0, 0)])
		tex.gradient = g
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = tex
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_materials[key] = m
	blob.material_override = _materials[key]
	return blob
