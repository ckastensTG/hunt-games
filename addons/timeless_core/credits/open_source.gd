class_name OpenSource
extends RefCounted
## The open-source notices a Timeless Games app has to carry: Godot Engine's
## MIT notice ("Complying with licenses" in Godot's documentation) with the
## third-party code inside the engine (FreeType, ENet and Mbed TLS among
## them), the plugins and SDKs the core builds on, and whatever the title adds
## (its fonts). The title's Credits screen lists entries(); each opens text().
##
## Godot's part is read from the running engine (Engine.get_copyright_info(),
## Engine.get_license_info()), so it always matches the engine in the build.
## Licence texts come from the engine too: "Expat" is the MIT licence,
## "Apache-2.0", "OFL-1.1" and the rest are the standard texts.
##
## An entry: {id, name, copyright: [lines], license: key of
## Engine.get_license_info() (or ""), about: an optional line shown before
## the licence, notice: an optional res:// JSON file {"text": …} shown in
## full after it}.

const GODOT := "godot"
## The licences' names, shown above their texts (the engine's texts start
## without one).
const LICENSE_NAMES := {
	"Expat": "MIT License",
	"Apache-2.0": "Apache License, Version 2.0",
	"OFL-1.1": "SIL Open Font License, Version 1.1",
	"BSD-3-clause": "BSD 3-Clause License",
	"Zlib": "zlib License",
}

## What the core's code ships with (keep in step with the plugins in the
## project and the core's README).
const CORE := [
	{"id": "eos_sdk", "name": "Epic Online Services SDK",
		"copyright": ["Copyright Epic Games, Inc."], "license": "",
		"about": "Used under the Epic Online Services SDK license. It includes the following third-party software:",
		"notice": "res://addons/timeless_core/credits/eos_sdk_notices.json"},
	{"id": "eosg", "name": "Epic Online Services for Godot (EOSG)",
		"copyright": ["Copyright (c) 2022 Delano Lourenco"], "license": "Expat"},
	{"id": "admob_plugin", "name": "Godot AdMob Plugin",
		"copyright": ["Copyright (c) 2024-present Cengiz"], "license": "Expat"},
	{"id": "play_billing_plugin", "name": "Godot Google Play Billing",
		"copyright": ["Copyright (c) Godot Engine contributors"], "license": "Expat"},
	{"id": "play_games_plugin", "name": "Google Play Games Services for Godot",
		"copyright": ["Copyright (c) 2023 Jacob Ibáñez Sánchez"], "license": "Expat"},
	{"id": "apple_plugins", "name": "Godot Apple Plugins and SwiftGodot",
		"copyright": ["Copyright (c) Miguel de Icaza and contributors"], "license": "Expat"},
	{"id": "androidx", "name": "AndroidX (AppCompat, Lifecycle)",
		"copyright": ["Copyright The Android Open Source Project"], "license": "Apache-2.0"},
	{"id": "gson", "name": "Gson",
		"copyright": ["Copyright 2008 Google LLC"], "license": "Apache-2.0"},
	{"id": "google_sdks", "name": "Google Mobile Ads SDK, User Messaging Platform, Google Play services, Google Play Games Services and Google Play Billing Library",
		"copyright": ["Copyright Google LLC"], "license": "",
		"about": "Used under Google's terms for these SDKs."},
]


## Godot first, then the core's entries, then the title's.
static func entries(extra: Array = []) -> Array:
	var out: Array = [{"id": GODOT, "name": "Godot Engine",
		"copyright": ["Copyright (c) 2014-present Godot Engine contributors", "Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur"],
		"license": "Expat"}]
	out.append_array(CORE)
	out.append_array(extra)
	return out


static func find(id: String, extra: Array = []) -> Dictionary:
	for e in entries(extra):
		if e.id == id:
			return e
	return {}


## The full text for one entry: its copyright lines and licence, and for
## Godot every component inside the engine with the texts of their licences.
static func text(entry: Dictionary) -> String:
	if entry.get("id", "") == GODOT:
		return godot_text()
	var parts: PackedStringArray = []
	parts.append("\n".join(PackedStringArray(entry.get("copyright", []))))
	if str(entry.get("about", "")) != "":
		parts.append(str(entry.about))
	var license := str(entry.get("license", ""))
	if license != "":
		parts.append("License: %s" % LICENSE_NAMES.get(license, license))
		parts.append(license_text(license))
	var notice := str(entry.get("notice", ""))
	if notice != "":
		parts.append(notice_text(notice))
	return "\n\n".join(parts)


## Godot's own notice, then each third-party component compiled into the
## engine (name, files, copyright, licence) and the licences' texts.
static func godot_text() -> String:
	var parts: PackedStringArray = []
	parts.append("This game uses Godot Engine, available under the following license:")
	parts.append(Engine.get_license_text().strip_edges())
	parts.append("Godot Engine includes the following third-party components:")
	var used := {}
	for c in Engine.get_copyright_info():
		if str(c.name) == "Godot Engine":
			continue
		var lines: PackedStringArray = [str(c.name)]
		for p in c.parts:
			for line in p.get("copyright", []):
				lines.append("  © " + str(line))
			lines.append("  License: " + str(p.license))
			for key in licence_keys(str(p.license)):
				used[key] = true
		parts.append("\n".join(lines))
	var info := Engine.get_license_info()
	var keys := used.keys()
	keys.sort()
	for key in keys:
		if info.has(key):
			parts.append("— %s —\n\n%s" % [key, str(info[key]).strip_edges()])
	return "\n\n".join(parts)


## "BSD-3-clause and Expat" or "Unlicense or Expat" -> each key.
static func licence_keys(expr: String) -> Array:
	var out := []
	for word in expr.replace("(", " ").replace(")", " ").split(" ", false):
		if word != "and" and word != "or":
			out.append(word)
	return out


static func license_text(key: String) -> String:
	var info := Engine.get_license_info()
	return str(info.get(key, key)).strip_edges()


static func notice_text(path: String) -> String:
	if not ResourceLoader.exists(path):
		return ""
	var res := load(path)
	if res is JSON:
		return str((res as JSON).data.get("text", "")).strip_edges()
	return ""
