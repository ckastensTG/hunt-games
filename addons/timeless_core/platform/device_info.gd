class_name DeviceInfo
extends RefCounted
## Facts about the device that Godot doesn't give directly.
##
## Android's API level: OS.get_version() is no good for this, because on many
## phones it returns the maker's own build version (a moto g(20) on Android 11
## gave "30.66-3"; Samsung, Xiaomi and others have their own), not "11".
## The level comes from Build.VERSION.SDK_INT through Godot's Java wrapper,
## or from `getprop ro.build.version.sdk`.

static var _api_level := -2


## The Android API level (30 = Android 11, 37 = Android 17); -1 on other
## platforms, 0 when it can't be found.
static func android_api_level() -> int:
	if _api_level != -2:
		return _api_level
	_api_level = -1
	if OS.get_name() != "Android":
		return _api_level
	_api_level = _from_java()
	if _api_level <= 0:
		_api_level = _from_getprop()
	return _api_level


## "Android 11 (API 30)" style text for test reports.
static func describe() -> String:
	var api := android_api_level()
	if api < 0:
		return "%s %s" % [OS.get_name(), OS.get_version()]
	return "Android %s (API %d) · build %s" % [_release(), api, OS.get_version()]


static func _from_java() -> int:
	var version = JavaClassWrapper.wrap("android.os.Build$VERSION")
	if version == null:
		return 0
	var sdk = version.get("SDK_INT")
	return sdk if sdk is int else 0


static func _from_getprop() -> int:
	return _getprop("ro.build.version.sdk").to_int()


static func _release() -> String:
	var r := _getprop("ro.build.version.release")
	return r if r != "" else "?"


static func _getprop(key: String) -> String:
	var out: Array = []
	if OS.execute("getprop", [key], out) != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()
