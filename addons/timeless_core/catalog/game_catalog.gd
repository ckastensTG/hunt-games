class_name GameCatalog
extends Node
## "Other Timeless Games" (playbook Phase 9): the series' game list and its
## cards, one per app, made by instance() and kept under the scene tree's
## root as "GameCatalog", like AdService. The title starts it once
## (TitleConfig.catalog_setup()); the main menu asks refresh_if_due() each
## time it shows, and the pop-up reads games() and card().
##
## Where the list comes from:
##   - the build ships games.json and each game's English card as they were
##     at export (`bundled_dir`: games.json and cards/<id>/en.webp);
##   - at most once a day, from the main menu and in the background, it reads
##     the list from apps.timegalleon.com/games/v1/ and keeps it in
##     user://catalog/ for offline use (after a failed try, again in an hour);
##     the newer of the kept and the shipped list (by its "updated" date) is
##     the one used;
##   - then the cards in the player's language, for the games on this store
##     (cards/<id>/<locale>.webp), kept in user://catalog/cards/ until the
##     game's "rev" changes.
## Nothing is sent but the requests themselves, and nothing else is stored.
## The list is checked by GameList; the store pages are opened by StoreLinks
## from the IDs, never from an address in the file. The list may be 64 KB, a
## card 300 KB and 2048 × 1024 pixels at most.
##
## Tools, tests and headless runs never use the network (`offline`, or a
## script as the main loop); tests give their own `fetcher`.

## The list or a card arrived.
signal changed

const NODE_NAME := "GameCatalog"
const BASE_URL := "https://apps.timegalleon.com/games/v1/"
const LIST_FILE := "games.json"
const CACHE_DIR := "user://catalog"
const REFRESH_SECONDS := 86400
const RETRY_SECONDS := 3600
const MAX_LIST_BYTES := 64 * 1024
const MAX_CARD_BYTES := 300 * 1024
const MAX_CARD_SIZE := Vector2i(2048, 1024)
const TIMEOUT_SECONDS := 20.0

## Tools and tests: never read from the network.
static var offline := false
static var _instance: GameCatalog

var base_url := BASE_URL
## res:// folder with the list and English cards shipped with the build.
var bundled_dir := ""
var cache_dir := CACHE_DIR
## The series line shown ("timeless"; Galleon Boards: "boards").
var line := "timeless"
## "google_play" or "app_store": the store this copy came from.
var store := ""
## The checked list in use (GameList entries).
var entries: Array = []
## When the list was last read from the site, and last tried (Unix seconds).
var last_success := 0
var last_attempt := 0
## Seconds since 1970 (tests set their own).
var clock := func() -> int: return int(Time.get_unix_time_from_system())
## How a download is made: fetcher.call(url, max_bytes, done), and later
## done.call(ok: bool, body: PackedByteArray). Empty: HTTPRequest. Tests
## give their own, which also lets them past the network check.
var fetcher := Callable()

var _started := false
var _http: HTTPRequest
var _queue: Array = []
var _busy := false
var _textures := {}
## Each game's card rev in the list shipped with the build: its English card
## is in the build, so it isn't downloaded.
var _shipped_revs := {}


static func instance() -> GameCatalog:
	if is_instance_valid(_instance):
		return _instance
	_instance = GameCatalog.new()
	_instance.name = NODE_NAME
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.add_child.call_deferred(_instance)
	return _instance


## The store this build sells on: Google Play on Android, the App Store on
## iPhone and iPad; Google Play's web pages elsewhere (desktop tests).
static func store_for_platform() -> String:
	return "app_store" if OS.get_name() == "iOS" else "google_play"


## Whether this run may read from the network: not in tools or tests (a
## script runs the main loop), not headless, not `offline`.
static func network_allowed() -> bool:
	if offline or DisplayServer.get_name() == "headless":
		return false
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() == null


## `setup`: {bundled_dir, line, store (optional), base_url and cache_dir
## (tests)}. Once. Reads the kept and the shipped list; no network.
func start(setup: Dictionary) -> void:
	if _started:
		return
	_started = true
	base_url = str(setup.get("base_url", BASE_URL))
	bundled_dir = str(setup.get("bundled_dir", ""))
	cache_dir = str(setup.get("cache_dir", CACHE_DIR))
	line = str(setup.get("line", "timeless"))
	store = str(setup.get("store", store_for_platform()))
	_load_state()
	_load_list()


## The games on this store with `status` ("available" or "coming_soon"), in
## the list's order, the game itself included.
func games(status: String) -> Array:
	return GameList.on_store(entries, store, status, line)


## The card for `entry` in `locale` (Godot's code), else its English card
## (kept, or shipped with the build); null when there's none.
func card(entry: Dictionary, locale: String) -> Texture2D:
	var want := GameList.card_locale(entry, locale)
	var rev := int(entry.card.rev)
	if rev > 0:
		for l in ([want, "en"] if want != "en" else ["en"]):
			if l == "":
				continue
			var tex := _texture(card_path(entry.id, rev, l))
			if tex:
				return tex
	return _shipped_card(entry.id)


## The English card shipped with the build, or null.
func _shipped_card(id: String) -> Texture2D:
	if bundled_dir == "":
		return null
	return _texture(bundled_dir.path_join("cards").path_join(id).path_join("en.webp"))


## Opens the game's store page (StoreLinks); false when nothing opened.
func open_store(entry: Dictionary) -> bool:
	return StoreLinks.open(entry, store)


## From the main menu: reads the list if the last read is a day old (an hour
## after a failed try), in the background.
func refresh_if_due() -> void:
	if not _started or not _net_ok() or _has_queued("list"):
		return
	var now: int = clock.call()
	if last_success > 0 and now >= last_success and now - last_success < REFRESH_SECONDS:
		return
	if last_attempt > 0 and now >= last_attempt and now - last_attempt < RETRY_SECONDS:
		return
	last_attempt = now
	_save_state()
	_enqueue({"kind": "list", "url": base_url + LIST_FILE, "max": MAX_LIST_BYTES})


## Fetches the cards in `locale` not kept yet, for the games on this store
## (the pop-up asks when it opens; the list's arrival asks too).
func fetch_cards(locale: String) -> void:
	if not _started or not _net_ok():
		return
	for status in GameList.STATUSES:
		for e in games(status):
			var l := GameList.card_locale(e, locale)
			var rev := int(e.card.rev)
			if l == "" or rev <= 0 or FileAccess.file_exists(card_path(e.id, rev, l)):
				continue
			if l == "en" and int(_shipped_revs.get(e.id, -1)) == rev and _shipped_card(e.id) != null:
				continue
			if _has_queued("card", card_path(e.id, rev, l)):
				continue
			_enqueue({"kind": "card", "url": card_url(e.id, l), "max": MAX_CARD_BYTES,
				"path": card_path(e.id, rev, l), "id": e.id, "locale": l})


## Where a game's card is on the site: built from the checked id and locale.
func card_url(id: String, locale: String) -> String:
	return base_url + "cards/%s/%s.webp" % [id, locale]


## Where a game's card is kept on the device.
func card_path(id: String, rev: int, locale: String) -> String:
	return cache_dir.path_join("cards").path_join("%s-%d-%s.webp" % [id, rev, locale])


# --- The list ------------------------------------------------------------------

func _load_list() -> void:
	var kept := _read_text(cache_dir.path_join(LIST_FILE))
	var shipped := _read_text(bundled_dir.path_join(LIST_FILE)) if bundled_dir != "" else ""
	for e in GameList.parse(shipped):
		_shipped_revs[e.id] = int(e.card.rev)
	# The newer one by date; the kept one when they're the same.
	var first := kept
	var second := shipped
	if GameList.updated(shipped) > GameList.updated(kept):
		first = shipped
		second = kept
	entries = GameList.parse(first)
	if entries.is_empty():
		entries = GameList.parse(second)


func _on_list(ok: bool, body: PackedByteArray) -> void:
	if not ok or body.size() > MAX_LIST_BYTES:
		return
	var text := body.get_string_from_utf8()
	var parsed := GameList.parse(text)
	if parsed.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var f := FileAccess.open(cache_dir.path_join(LIST_FILE), FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	entries = parsed
	last_success = clock.call()
	_save_state()
	changed.emit()
	fetch_cards(TranslationServer.get_locale())


# --- Cards ---------------------------------------------------------------------

func _on_card(job: Dictionary, ok: bool, body: PackedByteArray) -> void:
	if not ok or body.size() > MAX_CARD_BYTES:
		return
	var img := image_from_webp(body)
	if img == null:
		return
	var dir := cache_dir.path_join("cards")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(job.path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(body)
	f.close()
	# The same card of an older rev goes.
	var keep := str(job.path).get_file()
	for fname in DirAccess.get_files_at(dir):
		if fname != keep and fname.begins_with(str(job.id) + "-") and fname.ends_with("-%s.webp" % job.locale):
			DirAccess.remove_absolute(dir.path_join(fname))
	changed.emit()


## A card's picture from WebP bytes, checked; null when it isn't one or it's
## too big.
static func image_from_webp(bytes: PackedByteArray) -> Image:
	if bytes.is_empty() or bytes.size() > MAX_CARD_BYTES:
		return null
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		return null
	var size := img.get_size()
	if size.x <= 0 or size.y <= 0 or size.x > MAX_CARD_SIZE.x or size.y > MAX_CARD_SIZE.y:
		return null
	return img


func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := image_from_webp(FileAccess.get_file_as_bytes(path))
		if img:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	if tex:
		_textures[path] = tex
	return tex


# --- Downloads -----------------------------------------------------------------

func _net_ok() -> bool:
	return fetcher.is_valid() or network_allowed()


func _has_queued(kind: String, path := "") -> bool:
	for j in _queue:
		if j.kind == kind and (path == "" or j.get("path", "") == path):
			return true
	return false


func _enqueue(job: Dictionary) -> void:
	_queue.append(job)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var job: Dictionary = _queue[0]
	var done := func(ok: bool, body: PackedByteArray) -> void:
		_queue.erase(job)
		if job.kind == "list":
			_on_list(ok, body)
		else:
			_on_card(job, ok, body)
		_next()
	if fetcher.is_valid():
		fetcher.call(job.url, job.max, done)
	else:
		_http_get(job.url, job.max, done)


func _http_get(url: String, max_bytes: int, done: Callable) -> void:
	# At start the main menu asks before this node is in the tree (it's added
	# at the end of the frame): the request waits for it.
	if not is_inside_tree():
		tree_entered.connect(func() -> void: _http_get(url, max_bytes, done), CONNECT_ONE_SHOT)
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = TIMEOUT_SECONDS
		_http.use_threads = true
		add_child(_http)
	_http.body_size_limit = max_bytes
	var on_done := func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		done.call(result == HTTPRequest.RESULT_SUCCESS and code == 200, body)
	_http.request_completed.connect(on_done, CONNECT_ONE_SHOT)
	if _http.request(url) != OK:
		_http.request_completed.disconnect(on_done)
		done.call_deferred(false, PackedByteArray())


# --- Kept state ----------------------------------------------------------------

func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(cache_dir.path_join("state.cfg")) == OK:
		last_success = int(cfg.get_value("list", "last_success", 0))
		last_attempt = int(cfg.get_value("list", "last_attempt", 0))


func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var cfg := ConfigFile.new()
	cfg.set_value("list", "last_success", last_success)
	cfg.set_value("list", "last_attempt", last_attempt)
	cfg.save(cache_dir.path_join("state.cfg"))


static func _read_text(path: String) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
