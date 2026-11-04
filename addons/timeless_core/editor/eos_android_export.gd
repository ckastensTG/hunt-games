@tool
extends EditorExportPlugin
## Puts the EOS SDK's Java half into Android builds (Gradle build only) when
## the EOSG plugin is installed in the title: the EOS library (.aar) and the
## AndroidX libraries it uses. The EOSG instructions edit the Android
## template's build.gradle and GodotApp.java by hand instead; this way the
## template stays stock, and EOSGApi starts the Java half at run time.
##
## EOS's sign-in screen for Epic accounts is left out: we only use the
## anonymous device login, and the screen would need the client ID baked
## into the build as a URL scheme.

const AAR := "res://addons/epic-online-services-godot/bin/android/eossdk-StaticSTDC-release.aar"
const DEPENDENCIES := [
	"androidx.appcompat:appcompat:1.5.1",
	"androidx.constraintlayout:constraintlayout:2.1.4",
	"androidx.security:security-crypto:1.0.0",
	"androidx.browser:browser:1.4.0",
	"androidx.webkit:webkit:1.7.0",
]


func _get_name() -> String:
	return "TimelessCoreEOSAndroid"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid and FileAccess.file_exists(AAR)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray([AAR])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray(DEPENDENCIES)


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return '<activity android:name="com.epicgames.mobile.eossdk.EOSAuthHandlerActivity" tools:node="remove" />\n'
