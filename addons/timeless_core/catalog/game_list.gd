class_name GameList
extends RefCounted
## The series' game list for "Other Timeless Games" (playbook Phase 9): read
## and checked here, so nothing in it is trusted as it comes.
##
## The file (games.json, on apps.timegalleon.com/games/v1/ and shipped with
## each build) looks like this; the order of "games" is the display order:
##
##   {"version": 1, "updated": "2026-11-11", "games": [
##     {"id": "bagh_chal", "line": "timeless", "name": "Bagh Chal",
##      "google_play": {"status": "available", "package": "com.timegalleon.baghchal"},
##      "app_store": {"status": "available", "apple_id": "6830657856"},
##      "card": {"rev": 1, "locales": ["en", "pt_BR", ...]}}, ...]}
##
## A store left out means the game isn't on that store. "status" is
## "available" or "coming_soon"; an available game needs its store ID (the
## package name, or the App Store's Apple ID: digits only). The file never
## gives an address: the store links are built from the IDs (StoreLinks), and
## each card's address from the game's id, the locale and nothing else
## (cards/<id>/<locale>.webp under the list's folder; Timeless Games' cards
## are 1024 × 250 bands of each game's Google Play feature graphic). "rev" goes up when a
## game's cards change, so devices fetch them again. "name" is the Latin
## name, shown only when no card can be had.
##
## Anything that doesn't fit is left out (a bad game, a bad store entry, a
## bad locale); a file that isn't a list at all gives none.

const VERSION := 1
const STORES := ["google_play", "app_store"]
const STATUSES := ["available", "coming_soon"]
const LINES := ["timeless", "boards"]
## The most games read from one file.
const MAX_GAMES := 100


## The checked games of a list's text, in its order; [] when it isn't one.
static func parse(text: String) -> Array:
	var data = _json(text)
	if not data is Dictionary:
		return []
	if int(data.get("version", 0)) != VERSION:
		return []
	var games = data.get("games")
	if not games is Array:
		return []
	var out := []
	var seen := {}
	for g in games:
		if out.size() >= MAX_GAMES:
			break
		var e := _entry(g)
		if e.is_empty() or seen.has(e.id):
			continue
		seen[e.id] = true
		out.append(e)
	return out


## The list's "updated" date (YYYY-MM-DD), "" when it has none: the newer of
## the copy on the device and the one shipped with the build is used.
static func updated(text: String) -> String:
	var data = _json(text)
	if not data is Dictionary:
		return ""
	var d := str(data.get("updated", ""))
	return d if _matches(d, "^\\d{4}-\\d{2}-\\d{2}\\z") else ""


## The games on `store` with `status`, of one line, in the list's order.
static func on_store(entries: Array, store: String, status: String, line := "timeless") -> Array:
	var out := []
	for e in entries:
		if e.line != line or not e.stores.has(store):
			continue
		if e.stores[store].status == status:
			out.append(e)
	return out


## The card locale to show for `locale` (Godot's code, e.g. "pt_BR"): the
## same, else the same language, else English; "" when the game has no card.
static func card_locale(entry: Dictionary, locale: String) -> String:
	var have: PackedStringArray = entry.card.locales
	if have.has(locale):
		return locale
	var lang := locale.split("_")[0]
	for l in have:
		if l.split("_")[0] == lang:
			return l
	return "en" if have.has("en") else ""


static func valid_id(id: String) -> bool:
	return _matches(id, "^[a-z][a-z0-9_]{1,39}\\z")


## An Android package name: lowercase segments joined by dots (at least two).
static func valid_package(package: String) -> bool:
	return package.length() <= 100 and _matches(package, "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+\\z")


## An App Store Apple ID: digits only.
static func valid_apple_id(apple_id: String) -> bool:
	return _matches(apple_id, "^[1-9][0-9]{5,11}\\z")


## A card locale: Godot's codes ("en", "pt_BR", "zh_TW").
static func valid_locale(locale: String) -> bool:
	return _matches(locale, "^[a-z]{2,3}(_[A-Z]{2})?\\z")


static func _entry(g) -> Dictionary:
	if not g is Dictionary:
		return {}
	var id := str(g.get("id", ""))
	var line := str(g.get("line", ""))
	if not valid_id(id) or not line in LINES:
		return {}
	var e := {"id": id, "line": line, "name": _name(g.get("name", "")), "stores": {}, "card": {"rev": 0, "locales": PackedStringArray()}}
	for store in STORES:
		var s := _store(store, g.get(store))
		if not s.is_empty():
			e.stores[store] = s
	if e.stores.is_empty():
		return {}
	var card = g.get("card")
	if card is Dictionary:
		var r = card.get("rev", 0)
		var rev := int(r) if (r is int or r is float) else 0
		var locales := PackedStringArray()
		var list = card.get("locales")
		if list is Array:
			for l in list:
				if l is String and valid_locale(l) and not locales.has(l):
					locales.append(l)
		if rev > 0 and not locales.is_empty():
			e.card = {"rev": rev, "locales": locales}
	return e


static func _store(store: String, s) -> Dictionary:
	if not s is Dictionary:
		return {}
	var status := str(s.get("status", ""))
	if not status in STATUSES:
		return {}
	var out := {"status": status}
	if store == "google_play":
		var package := str(s.get("package", ""))
		if valid_package(package):
			out.package = package
		elif status == "available":
			return {}
	else:
		var apple_id = s.get("apple_id", "")
		var text := str(apple_id) if apple_id is String else ""
		if valid_apple_id(text):
			out.apple_id = text
		elif status == "available":
			return {}
	return out


## Printable Latin text, at most 40 characters; "" otherwise.
static func _name(n) -> String:
	if not n is String:
		return ""
	var s: String = n.strip_edges()
	if s.length() > 40 or not _matches(s, "^[\\p{Latin}\\p{M}0-9 '’\\-–:.&]+\\z"):
		return ""
	return s


## The parsed text, or null (quietly: a missing or broken list isn't an error).
static func _json(text: String) -> Variant:
	if text.strip_edges() == "":
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _matches(text: String, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	return re.search(text) != null
