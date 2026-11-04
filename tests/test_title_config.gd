extends TestCase


func test_dev_build_offers_every_rule_set() -> void:
	check_eq(TitleConfig.detect(), TitleConfig.DEV, "no title tag in tests")
	check_eq(TitleConfig.active().rule_sets, HuntRuleSets.ALL, "dev: all rule sets")


func test_bagh_chal_build() -> void:
	var c := TitleConfig.for_id(TitleConfig.BAGH_CHAL)
	check_eq(c.rule_sets, [HuntRuleSets.BAGH_CHAL_STANDARD, HuntRuleSets.BAGH_CHAL_PARLETT], "Standard + Parlett")
	check(c.package.begins_with("com.timegalleon."), "package name")
	for key in ["product_id", "sandbox_id", "deployment_id"]:
		var v: String = c.eos.get(key, "")
		check(v.length() == 32 and v.is_valid_hex_number(), "EOS %s is a 32-digit hex ID" % key)


func test_every_title_rule_set_exists() -> void:
	for title in TitleConfig.TITLES:
		for id in TitleConfig.for_id(title).rule_sets:
			check(HuntRuleSets.ALL.has(id), "%s: %s" % [title, id])


func test_export_presets_match_titles() -> void:
	# Each title preset carries its title tag and the package from TitleConfig.
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg loads")
	var i := 0
	while cfg.has_section("preset.%d" % i):
		var sec := "preset.%d" % i
		var features: String = cfg.get_value(sec, "custom_features", "")
		for title in TitleConfig.TITLES:
			if features.split(",").has("title_" + title):
				var pkg := TitleConfig.for_id(title).package
				var opts := sec + ".options"
				var key := "package/unique_name" if cfg.has_section_key(opts, "package/unique_name") else "application/bundle_identifier"
				check_eq(cfg.get_value(opts, key, ""), pkg, "%s: %s" % [cfg.get_value(sec, "name"), key])
		i += 1
	check(i >= 2, "Android and iOS presets")


func test_network_id_and_rule_set_lookup() -> void:
	check_eq(TitleConfig.for_id(TitleConfig.DEV).network_id(), TitleConfig.BAGH_CHAL, "dev builds meet Bagh Chal builds")
	var bc := TitleConfig.for_id(TitleConfig.BAGH_CHAL)
	check_eq(bc.network_id(), TitleConfig.BAGH_CHAL, "Bagh Chal")
	check(bc.resolve_rule_set(HuntRuleSets.BAGH_CHAL_PARLETT) != null, "Parlett resolves")
	check(bc.resolve_rule_set(HuntRuleSets.ADUGO) == null, "Bagh Chal builds don't take Adugo games")
	check(bc.resolve_rule_set("nonsense") == null, "unknown id")
	var jo := TitleConfig.for_id(TitleConfig.JOGO_DA_ONCA)
	var dogs_first := jo.resolve_rule_set(HuntRuleSets.KOMIKAN + TitleConfig.DOGS_FIRST)
	var puma_first := jo.resolve_rule_set(HuntRuleSets.KOMIKAN)
	check(dogs_first != null and puma_first != null, "both Komikan starts resolve")
	check(dogs_first.fingerprint() != puma_first.fingerprint(), "and differ")
	check(jo.resolve_rule_set(HuntRuleSets.ADUGO + TitleConfig.DOGS_FIRST) == null, "the suffix is Komikan's only")
