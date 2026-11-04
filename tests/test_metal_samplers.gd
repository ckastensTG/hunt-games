extends TestCase
## The iPad (Metal) and anisotropic filtering on repeating textures.
##
## Godot 4.7.2 binds 17 texture samplers where Metal allows 16 (the same
## engine issue that tripped Xcode's Metal API Validation). The one left out
## is linear + mipmaps + anisotropic + repeat, and anything that samples with
## it isn't drawn: on 2026-11-04 the stone board, its straw mat and the mat's
## rope vanished on the iPad while everything else showed. Until the engine
## is fixed, anisotropic filtering is only for textures that don't repeat.

const SKIP_DIRS := [".godot", "android", "build", "tests", ".git"]


func test_no_anisotropic_repeat_in_shaders() -> void:
	for path in _files("res://", ["gdshader", "gdshaderinc"]):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.contains("sampler") and line.contains("anisotropic"):
				check(line.contains("repeat_disable"),
					"%s: anisotropic filtering on a repeating texture: %s" % [path, line.strip_edges()])


func test_no_anisotropic_standard_materials() -> void:
	# StandardMaterial3D repeats its textures by default.
	for path in _files("res://", ["gd", "tres", "tscn"]):
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("WITH_MIPMAPS_ANISOTROPIC"),
			"%s: an anisotropic StandardMaterial3D filter (its textures repeat)" % path)


func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := dir.path_join(name)
		if d.current_is_dir():
			if not name in SKIP_DIRS:
				out.append_array(_files(path, exts))
		elif name.get_extension() in exts:
			out.append(path)
		name = d.get_next()
	return out
