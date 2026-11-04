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
