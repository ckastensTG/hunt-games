extends RefCounted
## Stands in for Godot Apple Plugins' StoreKitManager in tests of
## StoreKitBackend: the same signals and methods it uses. It records the
## calls; the test plays the App Store's side by emitting the signals.

signal products_request_completed(products: Array, status: int)
signal purchase_completed(transaction: Object, status: int, error_message: String)
signal restore_completed(status: int, error_message: String)
signal transaction_updated(transaction: Object)
signal unverified_transaction_updated(transaction: Object, verification_error: int)


class FakeProduct:
	extends RefCounted
	var product_id := ""
	var display_price := ""
	func _init(id: String, price: String) -> void:
		product_id = id
		display_price = price


class FakeTransaction:
	extends RefCounted
	var product_id := ""
	var revocation_date := 0.0
	var finished := false
	func _init(id: String, revoked := 0.0) -> void:
		product_id = id
		revocation_date = revoked
	func finish() -> void:
		finished = true


var calls: Array[String] = []
var bought: Array[String] = []


func count(call_name: String) -> int:
	return calls.count(call_name)


func start() -> void:
	calls.append("start")


func request_products(_ids: PackedStringArray) -> void:
	calls.append("request_products")


func fetch_current_entitlements() -> void:
	calls.append("fetch_current_entitlements")


func purchase(product: Object) -> void:
	calls.append("purchase")
	bought.append(product.product_id)


func restore_purchases() -> void:
	calls.append("restore_purchases")
