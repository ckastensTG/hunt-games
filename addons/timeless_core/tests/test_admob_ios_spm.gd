extends TestCase
## The iOS export step that adds Google's Mobile Ads Swift package to the
## Xcode project (editor/admob_ios_spm.gd), on a small project file shaped
## like Godot's iOS template.

const Spm := preload("res://addons/timeless_core/editor/admob_ios_spm.gd")

const PROJECT := """// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 54;
	objects = {

/* Begin PBXBuildFile section */
		AAAA00000000000000000001 /* AdmobPlugin.debug.xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = AAAA00000000000000000002 /* AdmobPlugin.debug.xcframework */; };
/* End PBXBuildFile section */

/* Begin PBXFrameworksBuildPhase section */
		D0BCFE3118AEBDA2004A7AAE /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AAAA00000000000000000001 /* AdmobPlugin.debug.xcframework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXNativeTarget section */
		D0BCFE3318AEBDA2004A7AAE /* App */ = {
			isa = PBXNativeTarget;
			buildPhases = (
				D0BCFE3118AEBDA2004A7AAE /* Frameworks */,
			);
			name = App;
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		D0BCFE2C18AEBDA2004A7AAE /* Project object */ = {
			isa = PBXProject;
			targets = (
				D0BCFE3318AEBDA2004A7AAE /* App */,
			);
		};
/* End PBXProject section */
	};
	rootObject = D0BCFE2C18AEBDA2004A7AAE /* Project object */;
}
"""


func test_adds_the_package_once() -> void:
	var out: String = Spm.add_package(PROJECT)
	check(out != PROJECT, "changed")
	check(out.contains("repositoryURL = \"%s\";" % Spm.PACKAGE_URL), "the package's address")
	check(out.contains("minimumVersion = %s;" % Spm.MIN_VERSION), "its version")
	check(out.contains("packageReferences = (\n\t\t\t\t%s" % Spm.PACKAGE_REF), "on the project")
	check(out.contains("packageProductDependencies = (\n\t\t\t\t%s" % Spm.PRODUCT_DEP), "a dependency of the target")
	check(out.contains("files = (\n\t\t\t\t%s /* GoogleMobileAds in Frameworks */," % Spm.BUILD_FILE), "linked")
	check(out.find("XCSwiftPackageProductDependency section") < out.find("\trootObject"), "inside the objects list")
	check_eq(out.count("{"), out.count("}"), "braces balance")
	check_eq(out.count("("), out.count(")"), "lists balance")
	check_eq(Spm.add_package(out), out, "a second run changes nothing")


func test_leaves_other_projects_alone() -> void:
	var without := PROJECT.replace("AdmobPlugin", "OtherPlugin")
	check_eq(Spm.add_package(without), without, "no AdMob plugin in the export")
	var odd := PROJECT.replace("isa = PBXFrameworksBuildPhase;", "isa = Something;")
	check_eq(Spm.add_package(odd), odd, "an unexpected file is left as it is")
