class_name StoreKitBackend
extends IapBackend
## The App Store through StoreKit 2, from Godot Apple Plugins (Miguel de
## Icaza / Xogot, MIT; addons/GodotApplePluginsStoreKit and its runtime,
## a GDExtension that loads by itself). Its StoreKitManager is made through
## ClassDB, so the core still loads without the plugin. iPhone and iPad
## only: the plugin also runs in the macOS editor, where we don't sell.
##
##   start: listen for transactions, ask for the products (their prices)
##          and for the current entitlements (what the player owns: a new
##          device, a reinstall, Family Sharing).
##   buy:   Apple's purchase sheet. Each verified transaction is finished
##          once granted. Ask to Buy and some payment methods end as PENDING
##          and arrive later as a transaction update.
##   restore: AppStore.sync (Apple asks the player to sign in), then the
##          entitlements are read again; RESTORED when something is owned.

const CLASS := "StoreKitManager"
## StoreKitManager.StoreKitStatus
const OK := 0
const INVALID_PRODUCT := 1
const CANCELLED := 2
const UNVERIFIED_TRANSACTION := 3
const USER_CANCELLED := 4
const PURCHASE_PENDING := 5
## How long Restore waits for the entitlements to arrive after the sync.
const RESTORE_WAIT_MS := 2_000

## Tests set a stand-in (testing/fake_storekit.gd); otherwise made in start().
var manager: Object = null
var _products := {}  # key -> StoreProduct
var _buying := ""
var _restore_until := -1
var _restored_any := false


static func available() -> bool:
	return OS.has_feature("ios") and ClassDB.class_exists(CLASS)


func kind() -> String:
	return "storekit"


func start(product_ids: Dictionary, debug_build: bool) -> void:
	super(product_ids, debug_build)
	if manager == null:
		manager = ClassDB.instantiate(CLASS)
	manager.products_request_completed.connect(_on_products)
	manager.purchase_completed.connect(_on_purchase_completed)
	manager.restore_completed.connect(_on_restore_completed)
	manager.transaction_updated.connect(_on_transaction)
	manager.unverified_transaction_updated.connect(func(t: Object, error: int) -> void:
		_log("unverified transaction for %s (error %d), not granted" % [t.product_id if t else "?", error]))
	manager.start()
	var ids := PackedStringArray()
	for k in products:
		ids.append(str(products[k]))
	manager.request_products(ids)
	manager.fetch_current_entitlements()


func _process(_delta: float) -> void:
	if _restore_until != -1 and Time.get_ticks_msec() >= _restore_until:
		_restore_until = -1
		restore_done.emit(IAPService.Restore.RESTORED if _restored_any else IAPService.Restore.NOTHING)


func _on_products(list: Array, status: int) -> void:
	if status != OK:
		_log("products request failed (status %d)" % status)
	for p in list:
		if p == null:
			continue
		var key := key_for(str(p.product_id))
		if key == "":
			continue
		_products[key] = p
		product_loaded.emit(key, str(p.display_price))
	for k in products:
		if not _products.has(k):
			store_unavailable.emit("%s isn't set up in App Store Connect" % products[k])
			return


## Entitlements at start, after Restore, and purchases that complete
## outside the sheet (Ask to Buy, pending payments, another device).
func _on_transaction(t: Object) -> void:
	if t == null:
		return
	var key := key_for(str(t.product_id))
	if key == "":
		return
	if float(t.revocation_date) > 0.0:
		_log("%s was refunded or revoked" % key)
		return
	owned.emit(key)
	if _restore_until != -1:
		_restored_any = true
	t.finish()


func _on_purchase_completed(t: Object, status: int, message: String) -> void:
	var key := _buying
	_buying = ""
	if status == OK and t != null:
		var bought := key_for(str(t.product_id))
		if bought != "":
			owned.emit(bought)
			key = bought if key == "" else key
		t.finish()
	if key == "":
		return
	match status:
		OK:
			purchase_done.emit(key, IAPService.Result.PURCHASED if t != null else IAPService.Result.FAILED)
		USER_CANCELLED, CANCELLED:
			purchase_done.emit(key, IAPService.Result.CANCELLED)
		PURCHASE_PENDING:
			purchase_done.emit(key, IAPService.Result.PENDING)
		_:
			_log("purchase failed (status %d): %s" % [status, message])
			purchase_done.emit(key, IAPService.Result.FAILED)


func buy(key: String) -> void:
	var p: Object = _products.get(key)
	if p == null:
		purchase_done.emit.call_deferred(key, IAPService.Result.UNAVAILABLE)
		return
	_buying = key
	manager.purchase(p)


func restore() -> void:
	_restored_any = false
	manager.restore_purchases()


func _on_restore_completed(status: int, message: String) -> void:
	if status != OK:
		_log("restore failed (status %d): %s" % [status, message])
		restore_done.emit(IAPService.Restore.CANCELLED if status in [USER_CANCELLED, CANCELLED] else IAPService.Restore.FAILED)
		return
	# The entitlements come back as transaction updates.
	_restore_until = Time.get_ticks_msec() + RESTORE_WAIT_MS
	manager.fetch_current_entitlements()
