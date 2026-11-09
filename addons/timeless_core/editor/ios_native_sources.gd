@tool
extends EditorExportPlugin
## iOS exports: copies the core's small native files (platform/ios/*.m)
## into the exported Xcode project and adds them to the app target, so Xcode
## compiles them with the rest of the app. Nothing is built ahead of time and
## no plugin is installed. Today: TimelessShare.m, the share sheet
## (platform/share_sheet.gd).
##
## Godot writes the project with a group for the app's own files (path =
## <name>, holding dummy.cpp and friends) and one Sources build phase; each
## file gets a file reference in that group and a build file in that phase.
## Object IDs are fixed per file name, so a re-export writes the same project,
## and a file already there isn't added twice.

const SOURCE_DIR := "res://addons/timeless_core/platform/ios"


func _get_name() -> String:
	return "TimelessCoreIOSNativeSources"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _end_generate_apple_embedded_project(path: String, _will_build_archive: bool) -> void:
	if not _supports_platform(get_export_platform()):
		return
	var name := path.get_file().get_basename()
	var app_dir := path.get_base_dir().path_join(name)
	var file := path.get_base_dir().path_join(name + ".xcodeproj").path_join("project.pbxproj")
	if not FileAccess.file_exists(file) or not DirAccess.dir_exists_absolute(app_dir):
		push_warning("iOS native files: no Xcode project at %s" % file)
		return
	var text := FileAccess.get_file_as_string(file)
	var out := text
	var added: PackedStringArray = []
	for source in sources():
		var dest := app_dir.path_join(source.get_file())
		var copy := FileAccess.open(dest, FileAccess.WRITE)
		if copy == null:
			push_error("iOS native files: can't write %s" % dest)
			return
		copy.store_string(FileAccess.get_file_as_string(source))
		copy.close()
		var next := add_source(out, name, source.get_file())
		if next == out and not out.contains(source.get_file()):
			push_error("iOS native files: couldn't add %s to the Xcode project" % source.get_file())
			return
		out = next
		added.append(source.get_file())
	if out != text:
		var f := FileAccess.open(file, FileAccess.WRITE)
		if f == null:
			push_error("iOS native files: can't write %s" % file)
			return
		f.store_string(out)
		f.close()
	if not added.is_empty():
		print("iOS native files: %s in the Xcode project" % ", ".join(added))


## The core's native files for iOS (res:// paths).
static func sources() -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(SOURCE_DIR):
		if f.get_extension() in ["m", "mm"]:
			out.append(SOURCE_DIR.path_join(f))
	out.sort()
	return out


## Two object IDs (24 hex digits) for a file: its file reference and its
## build file. Fixed for a name, distinct from Godot's and the AdMob step's.
static func ids_for(file_name: String) -> PackedStringArray:
	var h := file_name.md5_text().to_upper().substr(0, 14)
	return PackedStringArray(["5A6D0C" + h + "0001", "5A6D0C" + h + "0002"])


## The project file with `file_name` (already copied into the app's folder)
## in the app's group and its Sources phase. Unchanged when it's already
## there or when the file doesn't look as expected.
static func add_source(text: String, app_name: String, file_name: String) -> String:
	var ids := ids_for(file_name)
	var ref := ids[0]
	var build := ids[1]
	if text.contains(ref):
		return text
	var kind := "sourcecode.c.objc" if file_name.get_extension() == "m" else "sourcecode.cpp.objcpp"
	var t := text
	# The build file and the file reference.
	t = _insert_after(t, "/* Begin PBXBuildFile section */\n",
		"\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % [build, file_name, ref, file_name])
	t = _insert_after(t, "/* Begin PBXFileReference section */\n",
		"\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; };\n"
			% [ref, file_name, kind, file_name])
	# In the app's group: the group whose path is the app's folder. Godot's
	# template writes it quoted (path = "BaghChal";); Xcode writes it bare.
	var group_path := t.find("\t\t\tpath = \"%s\";\n" % app_name)
	if group_path < 0:
		group_path = t.find("\t\t\tpath = %s;\n" % app_name)
	var children := t.rfind("children = (\n", group_path) if group_path >= 0 else -1
	if children < 0 or t.rfind("isa = PBXGroup;", group_path) < 0 or t.rfind("isa = PBXGroup;", group_path) > children:
		return text
	t = t.insert(children + "children = (\n".length(), "\t\t\t\t%s /* %s */,\n" % [ref, file_name])
	# In the Sources phase.
	var phase := t.find("isa = PBXSourcesBuildPhase;")
	var files := t.find("files = (\n", phase) if phase >= 0 else -1
	if files < 0:
		return text
	t = t.insert(files + "files = (\n".length(), "\t\t\t\t%s /* %s in Sources */,\n" % [build, file_name])
	# Every step found its place, or nothing changes.
	if t.count(ref) != 3 or t.count(build) != 2:
		return text
	return t


static func _insert_after(text: String, marker: String, insert: String) -> String:
	var at := text.find(marker)
	if at < 0:
		return text
	return text.insert(at + marker.length(), insert)
