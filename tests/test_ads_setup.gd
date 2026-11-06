extends TestCase
## Bagh Chal's ad setup: the App IDs the AdMob plugin writes into the Android
## manifest and the iOS Info.plist match TitleConfig, the iOS preset has the
## tracking prompt's text once, debug builds use Google's demo units, and the
## free look is one of the title's looks.

const ANDROID_EXPORT := "res://addons/AdmobPlugin/android_export.cfg"
const IOS_EXPORT := "res://addons/AdmobPlugin/ios_export.cfg"
const PRESETS := "res://export_presets.cfg"
const IOSPlistStrings := preload("res://addons/timeless_core/editor/ios_plist_strings.gd")


func test_android_manifest_app_id_matches_title_config() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load(ANDROID_EXPORT), OK, "android_export.cfg reads")
	var app_id := TitleConfig.for_id(TitleConfig.BAGH_CHAL).admob_app_id("android")
	check(app_id.begins_with("ca-app-pub-8333290579862415~"), "Bagh Chal's Android App ID")
	check_eq(cfg.get_value("General", "is_real", false), true, "the real App ID in every build")
	check_eq(cfg.get_value("Release", "app_id", ""), app_id, "release App ID")
	check_eq(cfg.get_value("Debug", "app_id", ""), app_id, "debug App ID (unused while is_real)")


func test_ios_info_plist_app_id_and_tracking_text() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load(IOS_EXPORT), OK, "ios_export.cfg reads")
	var app_id := TitleConfig.for_id(TitleConfig.BAGH_CHAL).admob_app_id("ios")
	check(app_id.begins_with("ca-app-pub-8333290579862415~"), "Bagh Chal's iOS App ID")
	check_eq(cfg.get_value("General", "is_real", false), true, "the real App ID in every build")
	check_eq(cfg.get_value("Release", "app_id", ""), app_id, "release App ID")
	check_eq(cfg.get_value("Debug", "app_id", ""), app_id, "debug App ID (unused while is_real)")
	check_eq(cfg.get_value("ATT", "att_enabled", true), false, "the plugin doesn't add the tracking text a second time")
	# The tracking prompt's text is in the iOS preset, exactly once.
	var presets := ConfigFile.new()
	check_eq(presets.load(PRESETS), OK, "export_presets.cfg reads")
	var found := 0
	for section in presets.get_sections():
		if section.ends_with(".options") and presets.get_value(section.trim_suffix(".options"), "platform", "") == "iOS":
			var plist := str(presets.get_value(section, "application/additional_plist_content", ""))
			found += 1
			check_eq(plist.count("<key>NSUserTrackingUsageDescription</key>"), 1, "%s: the tracking prompt's text" % section)
			# The prompts' English texts are TitleConfig's, so the export step
			# finds their translations (editor/ios_plist_strings.gd).
			var texts := IOSPlistStrings.usage_texts(plist)
			var usage := TitleConfig.ios_usage(TitleConfig.BAGH_CHAL)
			for key in usage:
				check_eq(texts.get(key, ""), usage[key], "%s: %s matches TitleConfig" % [section, key])
	check(found >= 1, "an iOS preset")


## Every translation has the prompts' texts, so iOS shows them in the
## player's language.
func test_ios_prompt_texts_are_translated() -> void:
	var usage := TitleConfig.ios_usage(TitleConfig.BAGH_CHAL)
	check_eq(usage.size(), 2, "tracking and local network")
	for tr_path in ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()):
		var t: Translation = load(tr_path)
		for key in usage:
			var text := str(t.get_message(usage[key]))
			check(text != "" and text != usage[key], "%s: %s translated" % [t.locale, key])


func test_debug_builds_use_demo_units() -> void:
	var c := TitleConfig.for_id(TitleConfig.BAGH_CHAL)
	for platform in ["android", "ios"]:
		for kind in ["interstitial", "rewarded"]:
			var demo := c.ad_unit(kind, platform, true)
			check(demo.begins_with("ca-app-pub-3940256099942544/"), "%s %s: Google's demo unit" % [platform, kind])
			check(c.ad_unit(kind, platform, false).begins_with("ca-app-pub-8333290579862415/"),
				"%s %s: our unit in release" % [platform, kind])
	var setup := c.ad_setup()
	check_eq(setup.debug, OS.is_debug_build(), "debug flag")


func test_free_look_is_a_bagh_chal_look() -> void:
	var free := TitleConfig.free_look(TitleConfig.BAGH_CHAL)
	check_eq(free, "brass", "Temple brass is free")
	var ids := BaghChalArt.styles().map(func(s: HuntArtStyle) -> String: return s.id)
	check(ids.has(free), "a real look")
	check_eq(TitleConfig.free_look(TitleConfig.JOGO_DA_ONCA), "", "Jogo da Onça: one look, nothing locked")
