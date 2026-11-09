extends TestCase
## The iOS export step that adds the core's native files to the Xcode
## project (editor/ios_native_sources.gd), on a small project file shaped
## like Godot 4.7's iOS template (the app's group path is quoted there), and
## the share sheet's address (ShareSheet).

const Sources := preload("res://addons/timeless_core/editor/ios_native_sources.gd")

const PROJECT := """// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 54;
	objects = {

/* Begin PBXBuildFile section */
		1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */ = {isa = PBXBuildFile; fileRef = 1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		1F1575711F582BE20003B888 /* dylibs */ = {isa = PBXFileReference; lastKnownFileType = folder; name = dylibs; path = BaghChal/dylibs; sourceTree = "<group>"; };
		1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; path = dummy.cpp; sourceTree = "<group>"; };
		D0BCFE7718AEBFEB004A7AAE /* BaghChal.pck */ = {isa = PBXFileReference; lastKnownFileType = file; path = BaghChal.pck; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		D0BCFE2B18AEBDA2004A7AAE = {
			isa = PBXGroup;
			children = (
				1F1575711F582BE20003B888 /* dylibs */,
				D0BCFE7718AEBFEB004A7AAE /* BaghChal.pck */,
				D0BCFE4118AEBDA2004A7AAE /* BaghChal */,
			);
			sourceTree = "<group>";
		};
		D0BCFE4118AEBDA2004A7AAE /* BaghChal */ = {
			isa = PBXGroup;
			children = (
				1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,
			);
			path = "BaghChal";
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXSourcesBuildPhase section */
		D0BCFE3018AEBDA2004A7AAE /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */
	};
	rootObject = D0BCFE2C18AEBDA2004A7AAE /* Project object */;
}
"""


func test_adds_a_source_file_once() -> void:
	var out: String = Sources.add_source(PROJECT, "BaghChal", "TimelessShare.m")
	var ids: PackedStringArray = Sources.ids_for("TimelessShare.m")
	check(out != PROJECT, "changed")
	check_eq(ids[0].length(), 24, "a 24-digit ID")
	check(out.contains("%s /* TimelessShare.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = TimelessShare.m;" % ids[0]), "a file reference")
	check(out.contains("%s /* TimelessShare.m in Sources */ = {isa = PBXBuildFile; fileRef = %s" % [ids[1], ids[0]]), "a build file")
	var group := out.find("path = \"BaghChal\";\n")
	check(out.rfind("%s /* TimelessShare.m */," % ids[0], group) > out.rfind("children = (", group), "in the app's group")
	check(out.contains("files = (\n\t\t\t\t%s /* TimelessShare.m in Sources */," % ids[1]), "compiled in Sources")
	check(out.find("BaghChal.pck */,") < out.find("D0BCFE4118AEBDA2004A7AAE /* BaghChal */,"), "the main group unchanged")
	check_eq(out.count("{"), out.count("}"), "braces balance")
	check_eq(out.count("("), out.count(")"), "lists balance")
	check_eq(Sources.add_source(out, "BaghChal", "TimelessShare.m"), out, "a second run changes nothing")
	var two: String = Sources.add_source(out, "BaghChal", "Other.mm")
	check(two.contains("lastKnownFileType = sourcecode.cpp.objcpp; path = Other.mm;"), "a second file, Objective-C++")
	check(Sources.ids_for("Other.mm")[0] != ids[0], "with its own IDs")


func test_bare_group_path() -> void:
	# Xcode itself writes the group's path without quotes.
	var bare := PROJECT.replace("path = \"BaghChal\";", "path = BaghChal;")
	var out: String = Sources.add_source(bare, "BaghChal", "TimelessShare.m")
	var ref: String = Sources.ids_for("TimelessShare.m")[0]
	check_eq(out.count(ref), 3, "added with a bare path too")
	check(out.rfind("%s /* TimelessShare.m */," % ref, out.find("path = BaghChal;\n")) > out.find("D0BCFE4118AEBDA2004A7AAE /* BaghChal */ = {"), "in the app's group")


func test_leaves_odd_projects_alone() -> void:
	check_eq(Sources.add_source(PROJECT, "Other", "TimelessShare.m"), PROJECT, "no group for that app")
	var odd := PROJECT.replace("isa = PBXSourcesBuildPhase;", "isa = Something;")
	check_eq(Sources.add_source(odd, "BaghChal", "TimelessShare.m"), odd, "no Sources phase")


func test_the_core_ships_the_share_file() -> void:
	var files: PackedStringArray = Sources.sources()
	check(files.has("res://addons/timeless_core/platform/ios/TimelessShare.m"), "TimelessShare.m is found")
	var text := FileAccess.get_file_as_string("res://addons/timeless_core/platform/ios/TimelessShare.m")
	check(text.contains("@\"%s\"" % ShareSheet.IOS_SCHEME), "it answers the share sheet's scheme")
	check(text.contains("tg_canOpenURL:") and text.contains("tg_openURL:options:completionHandler:"), "both of Godot's calls")


func test_share_sheet_address() -> void:
	check_eq(ShareSheet.ios_url("Code TG-7K4Q & more"), "timelessshare:?text=Code%20TG-7K4Q%20%26%20more", "percent-encoded")
	check(ShareSheet.ios_url("Jogue comigo! Código: TG-7K4Q").begins_with("timelessshare:?text=Jogue%20comigo%21%20C%C3%B3digo"), "UTF-8")
	# Headless Linux: no share sheet; the menu copies instead.
	check(not ShareSheet.available(), "none here")
	check(not ShareSheet.share("hello"), "share() says so")
