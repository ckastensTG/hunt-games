extends TestCase
## DeviceInfo: the Android API level, never the maker's version string.


func test_not_android() -> void:
	if OS.get_name() == "Android":
		check(DeviceInfo.android_api_level() >= 23, "a real API level on Android")
		return
	check_eq(DeviceInfo.android_api_level(), -1, "-1 off Android")
	check(DeviceInfo.describe().begins_with(OS.get_name()), "describes the platform")


func test_cached() -> void:
	var a := DeviceInfo.android_api_level()
	check_eq(DeviceInfo.android_api_level(), a, "same answer twice")
