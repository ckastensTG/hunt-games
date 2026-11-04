@tool
extends EditorPlugin
## Timeless Core in the editor: only export steps so far (see
## eos_android_export.gd). Enabled in each title's Project Settings > Plugins.

var _eos_android: EditorExportPlugin


func _enter_tree() -> void:
	_eos_android = preload("res://addons/timeless_core/editor/eos_android_export.gd").new()
	add_export_plugin(_eos_android)


func _exit_tree() -> void:
	remove_export_plugin(_eos_android)
	_eos_android = null
