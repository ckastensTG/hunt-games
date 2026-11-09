@tool
extends EditorPlugin
## Timeless Core in the editor: only export steps so far (see
## eos_android_export.gd, admob_ios_spm.gd, ios_plist_strings.gd and
## ios_native_sources.gd).
## Enabled in each title's Project Settings > Plugins.

var _eos_android: EditorExportPlugin
var _admob_ios: EditorExportPlugin
var _ios_strings: EditorExportPlugin
var _ios_sources: EditorExportPlugin


func _enter_tree() -> void:
	_eos_android = preload("res://addons/timeless_core/editor/eos_android_export.gd").new()
	add_export_plugin(_eos_android)
	_admob_ios = preload("res://addons/timeless_core/editor/admob_ios_spm.gd").new()
	add_export_plugin(_admob_ios)
	_ios_strings = preload("res://addons/timeless_core/editor/ios_plist_strings.gd").new()
	add_export_plugin(_ios_strings)
	_ios_sources = preload("res://addons/timeless_core/editor/ios_native_sources.gd").new()
	add_export_plugin(_ios_sources)


func _exit_tree() -> void:
	remove_export_plugin(_eos_android)
	_eos_android = null
	remove_export_plugin(_admob_ios)
	_admob_ios = null
	remove_export_plugin(_ios_strings)
	_ios_strings = null
	remove_export_plugin(_ios_sources)
	_ios_sources = null
