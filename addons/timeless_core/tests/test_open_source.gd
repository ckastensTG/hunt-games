extends TestCase
## OpenSource: the notices the Credits screen shows. Godot's MIT notice with
## the engine's third-party components (FreeType, ENet and Mbed TLS must be
## credited, Godot's "Complying with licenses"), every licence resolving to
## its text, and the Epic Online Services SDK's notices loading.


func test_godot_notice_and_its_components() -> void:
	var t := OpenSource.godot_text()
	check(t.begins_with("This game uses Godot Engine, available under the following license:"), "Godot's wording first")
	check(t.contains("Copyright (c) 2014-present Godot Engine contributors"), "Godot's copyright")
	check(t.contains("Permission is hereby granted, free of charge"), "the MIT text")
	for name in ["The FreeType Project", "ENet", "Mbed TLS"]:
		check(t.contains(name), "%s credited" % name)
	check(t.contains("— FTL —"), "FreeType's licence text")
	check(t.contains("— Apache-2.0 —"), "Mbed TLS's licence text")


func test_every_entry_resolves() -> void:
	var info := Engine.get_license_info()
	for e in OpenSource.entries():
		check(str(e.name) != "", "named")
		check(not (e.copyright as Array).is_empty(), "%s has a copyright line" % e.id)
		var lic := str(e.get("license", ""))
		check(lic == "" or info.has(lic), "%s: licence %s is one of the engine's texts" % [e.id, lic])
		check(OpenSource.text(e).length() > 20, "%s has text" % e.id)
	check_eq(OpenSource.entries()[0].id, OpenSource.GODOT, "Godot first")


func test_eos_sdk_notices_load() -> void:
	var e := OpenSource.find("eos_sdk")
	var t := OpenSource.text(e)
	check(t.contains("Copyright Epic Games, Inc."), "Epic's line")
	check(t.contains("CityHash") and t.contains("libcurl") and t.contains("OpenSSL"), "the SDK's third-party notices")
	check(not t.contains("\r"), "plain line ends")


func test_title_entries_follow() -> void:
	var extra := [{"id": "font", "name": "A Font", "copyright": ["Copyright 2011 Someone"], "license": "OFL-1.1"}]
	var all := OpenSource.entries(extra)
	check_eq(all[all.size() - 1].id, "font", "the title's last")
	check(OpenSource.text(OpenSource.find("font", extra)).contains("License: SIL Open Font License, Version 1.1") and OpenSource.text(OpenSource.find("font", extra)).contains("PREAMBLE"), "OFL name and text")
	check_eq(OpenSource.licence_keys("Unlicense or Expat"), ["Unlicense", "Expat"])
	check_eq(OpenSource.licence_keys("BSD-3-clause and IJG"), ["BSD-3-clause", "IJG"])
