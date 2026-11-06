@tool
extends EditorExportPlugin
## iOS exports with the AdMob plugin: adds Google's Mobile Ads Swift package
## (GoogleMobileAds) to the exported Xcode project, so the plugin's library
## links. The AdMob plugin tries to do this itself with Ruby's xcodeproj gem,
## which macOS's own Ruby doesn't have: its step fails ("cannot load such
## file -- xcodeproj", seen 2026-11-06) and the build stops with undefined
## GAD* symbols. This edits project.pbxproj directly instead, so nothing has
## to be installed on the Mac. Xcode fetches the package when it builds.
## Same package and version as the plugin (AdmobPlugin.gd SPM_DEPENDENCIES).
## The plugin's own step still logs its Ruby error; it's harmless.

const PACKAGE_URL := "https://github.com/googleads/swift-package-manager-google-mobile-ads.git"
const PACKAGE_NAME := "swift-package-manager-google-mobile-ads"
const MIN_VERSION := "12.14.0"
const PRODUCT := "GoogleMobileAds"
## Object IDs in the project file (24 hex digits), fixed so a re-export
## writes the same file.
const PACKAGE_REF := "5A6D0B000000000000000001"
const PRODUCT_DEP := "5A6D0B000000000000000002"
const BUILD_FILE := "5A6D0B000000000000000003"


func _get_name() -> String:
	return "TimelessCoreAdmobIOS"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _end_generate_apple_embedded_project(path: String, _will_build_archive: bool) -> void:
	if not _supports_platform(get_export_platform()):
		return
	var file := path.get_base_dir().path_join(path.get_file().get_basename() + ".xcodeproj").path_join("project.pbxproj")
	if not FileAccess.file_exists(file):
		push_warning("AdMob iOS: no Xcode project at %s" % file)
		return
	var text := FileAccess.get_file_as_string(file)
	var out := add_package(text)
	if out == text:
		return
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		push_error("AdMob iOS: can't write %s" % file)
		return
	f.store_string(out)
	f.close()
	print("AdMob iOS: added the %s Swift package (%s or later) to %s" % [PRODUCT, MIN_VERSION, file.get_base_dir().get_file()])


## The project file with the package added: a package reference on the
## project, the product as a dependency of the app target and linked in its
## Frameworks phase. Unchanged when the AdMob plugin isn't in the export, when
## the package is already there, or when the file doesn't look as expected.
static func add_package(text: String) -> String:
	if text.contains(PACKAGE_URL) or not text.contains("AdmobPlugin"):
		return text
	var t := text
	# The build file that links the product.
	t = _insert_after(t, "/* Begin PBXBuildFile section */\n",
		"\t\t%s /* %s in Frameworks */ = {isa = PBXBuildFile; productRef = %s /* %s */; };\n"
			% [BUILD_FILE, PRODUCT, PRODUCT_DEP, PRODUCT])
	# Linked in the app's Frameworks phase.
	var phase := t.find("isa = PBXFrameworksBuildPhase;")
	var files := t.find("files = (\n", phase) if phase >= 0 else -1
	if files < 0:
		return text
	files += "files = (\n".length()
	t = t.insert(files, "\t\t\t\t%s /* %s in Frameworks */,\n" % [BUILD_FILE, PRODUCT])
	# The app target depends on the product.
	t = _insert_after(t, "isa = PBXNativeTarget;\n",
		"\t\t\tpackageProductDependencies = (\n\t\t\t\t%s /* %s */,\n\t\t\t);\n" % [PRODUCT_DEP, PRODUCT])
	# The project knows the package.
	t = _insert_after(t, "isa = PBXProject;\n",
		"\t\t\tpackageReferences = (\n\t\t\t\t%s /* XCRemoteSwiftPackageReference \"%s\" */,\n\t\t\t);\n"
			% [PACKAGE_REF, PACKAGE_NAME])
	# The two objects, at the end of the objects list.
	var sections := ""
	sections += "\n/* Begin XCRemoteSwiftPackageReference section */\n"
	sections += "\t\t%s /* XCRemoteSwiftPackageReference \"%s\" */ = {\n" % [PACKAGE_REF, PACKAGE_NAME]
	sections += "\t\t\tisa = XCRemoteSwiftPackageReference;\n"
	sections += "\t\t\trepositoryURL = \"%s\";\n" % PACKAGE_URL
	sections += "\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = %s;\n\t\t\t};\n" % MIN_VERSION
	sections += "\t\t};\n"
	sections += "/* End XCRemoteSwiftPackageReference section */\n"
	sections += "\n/* Begin XCSwiftPackageProductDependency section */\n"
	sections += "\t\t%s /* %s */ = {\n" % [PRODUCT_DEP, PRODUCT]
	sections += "\t\t\tisa = XCSwiftPackageProductDependency;\n"
	sections += "\t\t\tpackage = %s /* XCRemoteSwiftPackageReference \"%s\" */;\n" % [PACKAGE_REF, PACKAGE_NAME]
	sections += "\t\t\tproductName = %s;\n" % PRODUCT
	sections += "\t\t};\n"
	sections += "/* End XCSwiftPackageProductDependency section */\n"
	var end := t.rfind("\t};\n\trootObject")
	if end < 0:
		return text
	t = t.insert(end, sections)
	# Every step found its place, or nothing changes.
	if t.count(BUILD_FILE) != 2 or t.count(PRODUCT_DEP) != 3 or t.count(PACKAGE_REF) != 3:
		return text
	return t


static func _insert_after(text: String, marker: String, insert: String) -> String:
	var at := text.find(marker)
	if at < 0:
		return text
	return text.insert(at + marker.length(), insert)
