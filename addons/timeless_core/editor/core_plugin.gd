@tool
extends EditorPlugin
## Timeless Core in the editor: only export steps so far (see
## eos_android_export.gd and admob_ios_spm.gd). Enabled in each title's
## Project Settings > Plugins.

var _eos_android: EditorExportPlugin
var _admob_ios: EditorExportPlugin


func _enter_tree() -> void:
	_eos_android = preload("res://addons/timeless_core/editor/eos_android_export.gd").new()
	add_export_plugin(_eos_android)
	_admob_ios = preload("res://addons/timeless_core/editor/admob_ios_spm.gd").new()
	add_export_plugin(_admob_ios)


func _exit_tree() -> void:
	remove_export_plugin(_eos_android)
	_eos_android = null
	remove_export_plugin(_admob_ios)
	_admob_ios = null
