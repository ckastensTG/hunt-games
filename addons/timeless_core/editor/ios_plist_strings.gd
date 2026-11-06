@tool
extends EditorExportPlugin
## iOS exports: the permission prompts' texts in every language the game
## has. iOS shows a usage description (why the app asks to track, to use the
## local network…) from the app's Info.plist, or from the player's language
## folder (<lang>.lproj/InfoPlist.strings) when it has one. Godot writes a
## folder per translation in Project Settings → Localization, with the app
## name only; this adds each prompt text found in the exported Info.plist,
## translated through the project's own translations (the English text is
## the msgid, so the title marks it for translation: TitleConfig.ios_usage).
## A language without a translation keeps the English text.

## The Info.plist keys whose texts are translated.
const KEYS: Array[String] = ["NSUserTrackingUsageDescription", "NSLocalNetworkUsageDescription"]


func _get_name() -> String:
	return "TimelessCoreIOSPlistStrings"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _end_generate_apple_embedded_project(path: String, _will_build_archive: bool) -> void:
	if not _supports_platform(get_export_platform()):
		return
	var name := path.get_file().get_basename()
	var app_dir := path.get_base_dir().path_join(name)
	var plist := app_dir.path_join(name + "-Info.plist")
	if not FileAccess.file_exists(plist):
		push_warning("iOS prompt texts: no Info.plist at %s" % plist)
		return
	var texts := usage_texts(FileAccess.get_file_as_string(plist))
	if texts.is_empty():
		return
	var translations := {}
	for tr_path in ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()):
		var t: Translation = load(tr_path)
		if t:
			translations[t.locale] = t
	var done := 0
	for folder in DirAccess.get_directories_at(app_dir):
		if not folder.ends_with(".lproj"):
			continue
		var t: Translation = translations.get(folder.get_basename())
		if t == null:
			continue
		var file := app_dir.path_join(folder).path_join("InfoPlist.strings")
		var before := FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else ""
		var after := add_strings(before, texts, func(text: String) -> String: return str(t.get_message(text)))
		if after == before:
			continue
		var f := FileAccess.open(file, FileAccess.WRITE)
		if f == null:
			push_error("iOS prompt texts: can't write %s" % file)
			continue
		f.store_string(after)
		f.close()
		done += 1
	print("iOS prompt texts: translated into %d languages" % done)


## The English texts of KEYS found in an Info.plist: {key: text}.
static func usage_texts(plist: String) -> Dictionary:
	var out := {}
	for key in KEYS:
		var re := RegEx.create_from_string("<key>" + key + "</key>\\s*<string>([^<]*)</string>")
		var m := re.search(plist)
		if m:
			out[key] = m.get_string(1).replace("&lt;", "<").replace("&gt;", ">") \
					.replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")
	return out


## A language's InfoPlist.strings with the translated texts added (each key
## once; a text without a translation is left to the Info.plist).
static func add_strings(strings: String, texts: Dictionary, translate: Callable) -> String:
	var out := strings
	for key in texts:
		if out.contains("\n" + key + " =") or out.begins_with(key + " ="):
			continue
		var text: String = translate.call(texts[key])
		if text == "" or text == texts[key]:
			continue
		if out != "" and not out.ends_with("\n"):
			out += "\n"
		out += "%s = \"%s\";\n" % [key, _escape(text)]
	return out


static func _escape(text: String) -> String:
	return text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
