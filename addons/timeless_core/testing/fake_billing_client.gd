extends Node
## Stands in for the Godot Google Play Billing plugin's BillingClient node
## (addons/GodotGooglePlayBilling/BillingClient.gd) in tests of
## PlayBillingBackend: the same signals and methods it uses. It records the
## calls; the test plays Google Play's side by emitting the signals.

signal connected
signal disconnected
signal connect_error(response_code: int, debug_message: String)
signal query_product_details_response(response: Dictionary)
signal query_purchases_response(response: Dictionary)
signal on_purchase_updated(response: Dictionary)
signal consume_purchase_response(response: Dictionary)
signal acknowledge_purchase_response(response: Dictionary)

var calls: Array[String] = []
var acknowledged: Array[String] = []
## What purchase() answers (the sheet opening, or not).
var purchase_answer := {"response_code": 0, "debug_message": ""}


func count(call_name: String) -> int:
	return calls.count(call_name)


func start_connection() -> void:
	calls.append("start_connection")


func query_product_details(_ids: PackedStringArray, _type: int) -> void:
	calls.append("query_product_details")


func query_purchases(_type: int, _include_suspended := false) -> void:
	calls.append("query_purchases")


func purchase(_product_id: String, _option := "", _offer := "", _personalized := false) -> Dictionary:
	calls.append("purchase")
	return purchase_answer


func acknowledge_purchase(token: String) -> void:
	calls.append("acknowledge_purchase")
	acknowledged.append(token)


## Google Play's answers, as the plugin builds them.
static func details(product_id: String, price: String) -> Dictionary:
	return {"response_code": 0, "debug_message": "", "unfetched_products": [],
		"product_details": [{"product_id": product_id, "title": "Remove ads", "name": "Remove ads",
			"description": "", "product_type": "inapp",
			"one_time_purchase_offer_details_list": [{"formatted_price": price,
				"price_amount_micros": 1990000, "price_currency_code": "USD"}]}]}


static func purchases(product_id: String, state := 1, acknowledged_already := false, code := 0) -> Dictionary:
	var list := []
	if product_id != "":
		list.append({"product_ids": [product_id], "purchase_state": state, "purchase_token": "token-" + product_id,
			"is_acknowledged": acknowledged_already, "order_id": "GPA.1", "quantity": 1})
	return {"response_code": code, "debug_message": "", "purchases": list}
