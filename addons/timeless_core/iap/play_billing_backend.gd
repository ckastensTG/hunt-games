class_name PlayBillingBackend
extends IapBackend
## Google Play Billing through the Godot Foundation's plugin (Godot Google
## Play Billing 3.3.0, Play Billing Library 9.1; addons/GodotGooglePlayBilling,
## enabled in Project Settings → Plugins, Gradle builds). Its BillingClient
## node is loaded by path, so the core still loads without the plugin.
##
##   start: connect; then ask for the products (their prices) and for what
##          the player already owns (Google Play's way of restoring: a new
##          phone, a reinstall). Reconnects after a drop, and asks for owned
##          purchases again when the app comes back (a pending payment may
##          have gone through meanwhile).
##   buy:   the Play purchase sheet. A purchase is acknowledged once granted
##          (Google refunds unacknowledged purchases after 3 days). A
##          pending payment (cash, some local methods) ends as PENDING and is
##          granted when it goes through.

const SCRIPT_PATH := "res://addons/GodotGooglePlayBilling/BillingClient.gd"
const SINGLETON := "GodotGooglePlayBilling"
const RECONNECT_MS := 30_000

## BillingClient.BillingResponseCode
const OK := 0
const USER_CANCELED := 1
const SERVICE_UNAVAILABLE := 2
const BILLING_UNAVAILABLE := 3
const ITEM_UNAVAILABLE := 4
const DEVELOPER_ERROR := 5
const ITEM_ALREADY_OWNED := 7
## BillingClient.PurchaseState
const PURCHASED := 1
const PENDING := 2
## BillingClient.ProductType.INAPP
const INAPP := 0

## Tests swap in testing/fake_billing_client.gd.
var script_path := SCRIPT_PATH
var _client: Node = null
var _connected := false
var _reconnect_at := -1
var _buying := ""
var _restoring := false


static func available() -> bool:
	return Engine.has_singleton(SINGLETON) and ResourceLoader.exists(SCRIPT_PATH)


func kind() -> String:
	return "play"


func start(product_ids: Dictionary, debug_build: bool) -> void:
	super(product_ids, debug_build)
	var script: Script = load(script_path)
	_client = script.new()
	_client.name = "BillingClient"
	_client.connected.connect(_on_connected)
	_client.disconnected.connect(func() -> void:
		_log("disconnected")
		_connected = false
		_reconnect_at = Time.get_ticks_msec() + RECONNECT_MS)
	_client.connect_error.connect(func(code: int, message: String) -> void:
		_log("can't connect (%d): %s" % [code, message])
		_connected = false
		if code == BILLING_UNAVAILABLE:
			store_unavailable.emit("billing unavailable on this device")
		_reconnect_at = Time.get_ticks_msec() + RECONNECT_MS)
	_client.query_product_details_response.connect(_on_product_details)
	_client.query_purchases_response.connect(_on_purchases)
	_client.on_purchase_updated.connect(_on_purchase_updated)
	_client.acknowledge_purchase_response.connect(func(r: Dictionary) -> void:
		_log("acknowledged: %d %s" % [int(r.get("response_code", -99)), str(r.get("debug_message", ""))]))
	add_child(_client)
	_client.start_connection()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _connected:
		_client.query_purchases(INAPP)


func _process(_delta: float) -> void:
	if _client and not _connected and _reconnect_at != -1 and Time.get_ticks_msec() >= _reconnect_at:
		_reconnect_at = -1
		_client.start_connection()


func _on_connected() -> void:
	_connected = true
	_reconnect_at = -1
	_log("connected")
	var ids := PackedStringArray()
	for k in products:
		ids.append(str(products[k]))
	_client.query_product_details(ids, INAPP)
	_client.query_purchases(INAPP)


func _on_product_details(r: Dictionary) -> void:
	var code := int(r.get("response_code", -99))
	if code != OK:
		_log("product details failed (%d): %s" % [code, str(r.get("debug_message", ""))])
		if code in [BILLING_UNAVAILABLE, DEVELOPER_ERROR, ITEM_UNAVAILABLE]:
			store_unavailable.emit("product details: %d" % code)
		return
	var found := {}
	for d in r.get("product_details", []):
		var key := key_for(str(d.get("product_id", "")))
		if key == "":
			continue
		var offers: Array = d.get("one_time_purchase_offer_details_list", [])
		var price := str(offers[0].get("formatted_price", "")) if offers.size() > 0 else ""
		found[key] = true
		product_loaded.emit(key, price)
	for k in products:
		if not found.has(k):
			store_unavailable.emit("%s isn't set up in Play Console" % products[k])
			return


## Owned purchases: at start, after a resume, and for Restore.
func _on_purchases(r: Dictionary) -> void:
	var code := int(r.get("response_code", -99))
	var any := false
	if code == OK:
		for p in r.get("purchases", []):
			if _handle(p) == PURCHASED:
				any = true
	else:
		_log("owned purchases failed (%d): %s" % [code, str(r.get("debug_message", ""))])
	if _restoring:
		_restoring = false
		if code != OK:
			restore_done.emit(IAPService.Restore.FAILED)
		else:
			restore_done.emit(IAPService.Restore.RESTORED if any else IAPService.Restore.NOTHING)


## A purchase from the sheet, or one that changed later (a pending payment
## that went through).
func _on_purchase_updated(r: Dictionary) -> void:
	var code := int(r.get("response_code", -99))
	var state := -1
	if code == OK:
		for p in r.get("purchases", []):
			var s := _handle(p)
			if s == PURCHASED or state == -1:
				state = s
	if _buying == "":
		return
	var key := _buying
	_buying = ""
	match code:
		OK:
			if state == PURCHASED:
				purchase_done.emit(key, IAPService.Result.PURCHASED)
			elif state == PENDING:
				purchase_done.emit(key, IAPService.Result.PENDING)
			else:
				purchase_done.emit(key, IAPService.Result.FAILED)
		USER_CANCELED:
			purchase_done.emit(key, IAPService.Result.CANCELLED)
		ITEM_ALREADY_OWNED:
			# Bought on another phone or before a reinstall: it's theirs.
			owned.emit(key)
			purchase_done.emit(key, IAPService.Result.PURCHASED)
		_:
			_log("purchase failed (%d): %s" % [code, str(r.get("debug_message", ""))])
			purchase_done.emit(key, IAPService.Result.FAILED)


## Grants and acknowledges a purchased product; returns its purchase state.
func _handle(p: Dictionary) -> int:
	var state := int(p.get("purchase_state", 0))
	if state != PURCHASED:
		return state
	for id in p.get("product_ids", []):
		var key := key_for(str(id))
		if key != "":
			owned.emit(key)
	if not bool(p.get("is_acknowledged", false)):
		_client.acknowledge_purchase(str(p.get("purchase_token", "")))
	return state


func buy(key: String) -> void:
	if not _connected or not products.has(key):
		purchase_done.emit.call_deferred(key, IAPService.Result.UNAVAILABLE)
		if not _connected:
			_client.start_connection()
		return
	var r: Dictionary = _client.purchase(str(products[key]))
	var code := int(r.get("response_code", OK))
	if code == OK:
		_buying = key  # on_purchase_updated ends it
		return
	_log("purchase sheet failed (%d): %s" % [code, str(r.get("debug_message", ""))])
	if code == ITEM_ALREADY_OWNED:
		owned.emit(key)
		purchase_done.emit.call_deferred(key, IAPService.Result.PURCHASED)
	else:
		purchase_done.emit.call_deferred(key,
				IAPService.Result.CANCELLED if code == USER_CANCELED else IAPService.Result.FAILED)


func restore() -> void:
	if not _connected:
		restore_done.emit.call_deferred(IAPService.Restore.UNAVAILABLE)
		_client.start_connection()
		return
	_restoring = true
	_client.query_purchases(INAPP)
