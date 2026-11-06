extends TestCase
## The iOS export step that translates the permission prompts' texts
## (editor/ios_plist_strings.gd): reading them from the Info.plist, adding
## them to a language's InfoPlist.strings once, escaped, and only when
## there's a translation.

const Strings := preload("res://addons/timeless_core/editor/ios_plist_strings.gd")

const PLIST := """<plist version="1.0"><dict>
	<key>CFBundleDisplayName</key>
	<string>$(INFOPLIST_KEY_CFBundleDisplayName)</string>
	<key>NSLocalNetworkUsageDescription</key><string>Find games &amp; friends nearby.</string><key>NSUserTrackingUsageDescription</key><string>Ads keep it free.</string>
</dict></plist>"""

const GODOT_STRINGS := "/* Localized versions of Info.plist keys */\n\nCFBundleDisplayName = \"Bagh Chal\";\n"


func _fr(text: String) -> String:
	return {"Ads keep it free.": "Les \"pubs\" la rendent gratuite.", "Find games & friends nearby.": "Trouver des parties à côté."}.get(text, "")


func test_reads_the_texts() -> void:
	var texts := Strings.usage_texts(PLIST)
	check_eq(texts.get("NSUserTrackingUsageDescription"), "Ads keep it free.", "tracking text")
	check_eq(texts.get("NSLocalNetworkUsageDescription"), "Find games & friends nearby.", "local network text, unescaped")
	check_eq(Strings.usage_texts("<plist></plist>"), {}, "none in a plist without them")


func test_adds_each_translation_once() -> void:
	var texts := Strings.usage_texts(PLIST)
	var out := Strings.add_strings(GODOT_STRINGS, texts, _fr)
	check(out.begins_with(GODOT_STRINGS), "Godot's lines kept")
	check(out.contains("NSUserTrackingUsageDescription = \"Les \\\"pubs\\\" la rendent gratuite.\";\n"), "escaped quotes")
	check(out.contains("NSLocalNetworkUsageDescription = \"Trouver des parties à côté.\";\n"), "second text")
	check_eq(Strings.add_strings(out, texts, _fr), out, "a second export adds nothing")
	var none := Strings.add_strings(GODOT_STRINGS, texts, func(_t: String) -> String: return "")
	check_eq(none, GODOT_STRINGS, "no translation: the Info.plist's English stays")
	var same := Strings.add_strings(GODOT_STRINGS, texts, func(t: String) -> String: return t)
	check_eq(same, GODOT_STRINGS, "an untranslated (English) text isn't repeated")
	check_eq(Strings.add_strings("", {"NSUserTrackingUsageDescription": "Ads keep it free."}, _fr),
		"NSUserTrackingUsageDescription = \"Les \\\"pubs\\\" la rendent gratuite.\";\n", "an empty file gets the line")
