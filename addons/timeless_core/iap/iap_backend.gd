class_name IapBackend
extends Node
## Where purchases go. IAPService picks one when it starts:
##   PlayBillingBackend  Google Play (Android, the Godot Google Play Billing
##                       plugin);
##   StoreKitBackend     the App Store (iPhone and iPad, Godot Apple Plugins'
##                       StoreKit 2);
##   SimIapBackend       test builds without a store: a labelled stand-in;
##   IapBackend          this one: no store (desktop, Steam, tools).
## Products are known by a key (e.g. "remove_ads") and a store product ID.
## Every buy() ends with exactly one purchase_done, every restore() with
## exactly one restore_done.

## A product's price, in the store's currency and format ("US$1.99").
signal product_loaded(key: String, price: String)
## The player owns the product: just bought, restored, found at start, or a
## pending payment that went through later.
signal owned(key: String)
## IAPService.Result.
signal purchase_done(key: String, result: int)
## IAPService.Restore.
signal restore_done(result: int)
## The store can't sell anything here (no billing, product not set up).
signal store_unavailable(reason: String)

## key -> store product ID.
var products := {}
var debug := false


## "none", "sim", "play" or "storekit".
func kind() -> String:
	return "none"


func start(product_ids: Dictionary, debug_build: bool) -> void:
	products = product_ids
	debug = debug_build


func buy(key: String) -> void:
	purchase_done.emit.call_deferred(key, IAPService.Result.UNAVAILABLE)


func restore() -> void:
	restore_done.emit.call_deferred(IAPService.Restore.UNAVAILABLE)


func key_for(product_id: String) -> String:
	for k in products:
		if str(products[k]) == product_id:
			return k
	return ""


func _log(text: String) -> void:
	if debug:
		print("[iap] " + text)
