class_name IAPService
extends Node
## Every in-app purchase goes through here (bible §3.1: one "Remove ads",
## US$1.99, with restore): one per app, made by instance() and kept under
## the scene tree's root as "Purchases", like AdService. The title starts it
## once with its products (TitleConfig.iap_setup()) and turns what the player
## owns into the extras (Bagh Chal: remove_ads -> AdService.set_ads_removed).
##
## What the title calls:
##   price(key)          the store's price text ("US$1.99"), "" until the
##                       store has answered; offer the purchase only then
##   can_buy(key)        the store knows the product and nothing is running
##   buy(key, then)      the store's purchase sheet; `then` gets a Result
##   owns(key)           bought (kept in user://purchases.cfg, so it holds
##                       offline and after a restart)
##   can_restore()       a store is there ("Restore purchases": App Store
##                       review asks for it; Google Play restores by itself at
##                       start, the button just asks again)
##   restore(then)       `then` gets a Restore
##
## Test builds: when the store has no such product yet (not set up in Play
## Console / App Store Connect, or billing missing on the device), a
## labelled stand-in takes over (SimIapBackend), so the flow can be tried.
## Release builds never do that.

enum Result { PURCHASED, PENDING, CANCELLED, FAILED, UNAVAILABLE }
enum Restore { RESTORED, NOTHING, CANCELLED, FAILED, UNAVAILABLE }

## Prices, ownership or the backend changed.
signal changed

const NODE_NAME := "Purchases"
const SAVE_PATH := "user://purchases.cfg"

## Tests and tools: "none", "sim", "play" or "storekit" instead of the
## platform's choice.
static var backend_override := ""
static var _instance: IAPService

var backend: IapBackend
## key -> price text from the store.
var prices := {}
## key -> true, kept in save_path.
var owned := {}
## A purchase or restore is running.
var busy := false
var save_path := SAVE_PATH
var debug := false

var _setup := {}
var _buy_then := Callable()
var _restore_then := Callable()


static func instance() -> IAPService:
	if is_instance_valid(_instance):
		return _instance
	_instance = IAPService.new()
	_instance.name = NODE_NAME
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.add_child.call_deferred(_instance)
	return _instance


## `setup`: {products: {key: store product ID}, debug: bool}. Once.
func start(setup: Dictionary) -> void:
	if backend:
		return
	_setup = setup
	debug = bool(setup.get("debug", false))
	_load()
	_use(pick_backend(setup))


## The store where its plugin runs; the labelled stand-in in other test
## builds with a screen; otherwise none.
static func pick_backend(setup: Dictionary) -> String:
	if backend_override != "":
		return backend_override
	if (setup.get("products", {}) as Dictionary).is_empty():
		return "none"
	if PlayBillingBackend.available():
		return "play"
	if StoreKitBackend.available():
		return "storekit"
	if OS.is_debug_build() and DisplayServer.get_name() != "headless":
		return "sim"
	return "none"


func _use(kind: String) -> void:
	if backend:
		backend.queue_free()
		prices.clear()
	match kind:
		"play":
			backend = PlayBillingBackend.new()
		"storekit":
			backend = StoreKitBackend.new()
		"sim":
			backend = SimIapBackend.new()
		_:
			backend = IapBackend.new()
	backend.name = "Backend"
	backend.product_loaded.connect(_on_product_loaded)
	backend.owned.connect(_grant)
	backend.purchase_done.connect(_on_purchase_done)
	backend.restore_done.connect(_on_restore_done)
	backend.store_unavailable.connect(_on_store_unavailable)
	add_child(backend)
	backend.start(_setup.get("products", {}), debug)
	changed.emit()


func price(key: String) -> String:
	return str(prices.get(key, ""))


func owns(key: String) -> bool:
	return owned.has(key)


func can_buy(key: String) -> bool:
	return prices.has(key) and not busy and not owns(key)


func can_restore() -> bool:
	return backend != null and backend.kind() != "none" and not busy


## The store's purchase sheet for `key`; `then(result)` once it's over.
func buy(key: String, then := Callable()) -> void:
	if not can_buy(key):
		if then.is_valid():
			then.call_deferred(Result.UNAVAILABLE)
		return
	busy = true
	_buy_then = then
	changed.emit()
	_log("buying %s" % key)
	backend.buy(key)


func restore(then := Callable()) -> void:
	if not can_restore():
		if then.is_valid():
			then.call_deferred(Restore.UNAVAILABLE)
		return
	busy = true
	_restore_then = then
	changed.emit()
	_log("restoring")
	backend.restore()


func _on_product_loaded(key: String, price_text: String) -> void:
	if key == "" or price_text == "":
		return
	prices[key] = price_text
	_log("%s costs %s" % [key, price_text])
	changed.emit()


func _grant(key: String) -> void:
	if key == "" or owns(key):
		return
	owned[key] = true
	_save()
	_log("%s owned" % key)
	changed.emit()


func _on_purchase_done(key: String, result: int) -> void:
	busy = false
	if result == Result.PURCHASED:
		_grant(key)
	_log("purchase of %s: %s" % [key, Result.keys()[result]])
	changed.emit()
	var then := _buy_then
	_buy_then = Callable()
	if then.is_valid():
		then.call(result)


func _on_restore_done(result: int) -> void:
	busy = false
	_log("restore: %s" % Restore.keys()[result])
	changed.emit()
	var then := _restore_then
	_restore_then = Callable()
	if then.is_valid():
		then.call(result)


func _on_store_unavailable(reason: String) -> void:
	_log("store unavailable: %s" % reason)
	if debug and not busy and backend.kind() in ["play", "storekit"]:
		_log("test build: the test purchase stand-in takes over")
		_use("sim")


## Test builds: forget what this install owns, as a reinstall would, to
## try Restore (the store, and the stand-in, keep their record) or the
## purchase again. (On Google Play a test purchase can be refunded in Play
## Console; App Store sandbox purchases are cleared in Settings on the
## device.)
func forget_purchases() -> void:
	owned.clear()
	_save()
	changed.emit()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		for k in cfg.get_section_keys("owned") if cfg.has_section("owned") else PackedStringArray():
			if bool(cfg.get_value("owned", k, false)):
				owned[k] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in owned:
		cfg.set_value("owned", k, true)
	cfg.save(save_path)


func _log(text: String) -> void:
	if debug:
		print("[iap] " + text)
