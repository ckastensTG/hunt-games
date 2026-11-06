extends TestCase
## IAPService and its backends: buying, ownership kept across restarts,
## Restore, the backend choice, the test-build stand-in taking over when the
## store has no product, and Google Play and the App Store against stand-ins
## for their plugins (prices, acknowledging, pending payments, cancelling,
## owned at start, refunds).

const SAVE := "user://test_purchases.cfg"
const SIM_STORE := "user://test_iap_store.cfg"
const FAKE_BILLING := "res://addons/timeless_core/testing/fake_billing_client.gd"
const FakeStoreKit := preload("res://addons/timeless_core/testing/fake_storekit.gd")
const PRODUCTS := {"remove_ads": "remove_ads"}


func _clean() -> void:
	for f in [SAVE, SIM_STORE]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _service(kind: String, debug := true) -> IAPService:
	IAPService.backend_override = kind
	var iap := IAPService.new()
	iap.save_path = SAVE
	iap.start({"products": PRODUCTS, "debug": debug})
	IAPService.backend_override = ""
	return iap


func _sim(iap: IAPService) -> SimIapBackend:
	var sim := iap.backend as SimIapBackend
	sim.instant = true
	sim.store_path = SIM_STORE
	return sim


func test_buy_on_the_stand_in_and_keep_it() -> void:
	_clean()
	var iap := _service("sim")
	var sim := _sim(iap)
	iap._on_product_loaded("remove_ads", SimIapBackend.PRICE)
	check_eq(iap.price("remove_ads"), SimIapBackend.PRICE, "the store's price")
	check(iap.can_buy("remove_ads"), "for sale")
	var got := []
	iap.buy("remove_ads", func(r: int) -> void: got.append(r))
	check_eq(got, [IAPService.Result.PURCHASED], "bought")
	check(iap.owns("remove_ads"), "owned")
	check(not iap.can_buy("remove_ads"), "not for sale twice")
	check(not iap.busy, "nothing running")
	iap.free()
	# Next session: still owned, without the store.
	var again := _service("none")
	check(again.owns("remove_ads"), "kept after a restart")
	again.free()
	_clean()


func test_cancel_pending_and_failure_grant_nothing() -> void:
	_clean()
	var iap := _service("sim")
	var sim := _sim(iap)
	iap._on_product_loaded("remove_ads", "US$1.99")
	for r in [IAPService.Result.CANCELLED, IAPService.Result.PENDING, IAPService.Result.FAILED]:
		sim.instant_result = r
		var got := []
		iap.buy("remove_ads", func(x: int) -> void: got.append(x))
		check_eq(got, [r], "result passed on: %s" % IAPService.Result.keys()[r])
		check(not iap.owns("remove_ads"), "nothing granted")
	var none := []
	iap.buy("nothing_like_it", func(x: int) -> void: none.append(x))
	check(not iap.owns("nothing_like_it"), "an unknown product can't be bought")
	iap.free()
	_clean()


func test_restore_and_forget() -> void:
	_clean()
	var iap := _service("sim")
	var sim := _sim(iap)
	iap._on_product_loaded("remove_ads", "US$1.99")
	iap.buy("remove_ads")
	iap.forget_purchases()
	check(not iap.owns("remove_ads"), "test builds can forget a purchase (as a reinstall would)")
	check(sim.bought.has("remove_ads"), "the stand-in store keeps its record")
	iap.restore()
	check(iap.owns("remove_ads"), "restored")
	sim.forget()
	iap.forget_purchases()
	iap.restore()
	check(not iap.owns("remove_ads"), "nothing to restore from a store without it")
	iap.free()
	_clean()


func test_backend_choice() -> void:
	check(not PlayBillingBackend.available(), "no Play Billing plugin here")
	check(not StoreKitBackend.available(), "no StoreKit here")
	check_eq(IAPService.pick_backend({"products": PRODUCTS}), "none", "headless tools and tests: no store")
	check_eq(IAPService.pick_backend({}), "none", "no products: no store")
	var iap := _service("none")
	check(not iap.can_restore(), "nothing to restore from")
	check(not iap.can_buy("remove_ads"), "nothing for sale")
	var got := []
	iap.buy("remove_ads", func(r: int) -> void: got.append(r))
	check(not iap.busy, "not left waiting")
	iap.free()
	_clean()


func test_stand_in_takes_over_in_test_builds_only() -> void:
	for debug in [true, false]:
		_clean()
		var iap := IAPService.new()
		iap.save_path = SAVE
		iap.debug = debug
		iap._setup = {"products": PRODUCTS, "debug": debug}
		var play := PlayBillingBackend.new()
		play.script_path = FAKE_BILLING
		iap.backend = play
		play.store_unavailable.connect(iap._on_store_unavailable)
		iap.add_child(play)
		play.start(PRODUCTS, debug)
		# Play Console has no such product yet.
		play._client.connected.emit()
		play._client.query_product_details_response.emit({"response_code": 0, "debug_message": "",
			"product_details": [], "unfetched_products": [{"product_id": "remove_ads"}]})
		if debug:
			check_eq(iap.backend.kind(), "sim", "test build: the stand-in takes over")
		else:
			check_eq(iap.backend.kind(), "play", "release build: never")
		iap.free()
	_clean()


## Google Play against the stand-in BillingClient.
func _play() -> Array:
	_clean()
	var iap := IAPService.new()
	iap.save_path = SAVE
	var play := PlayBillingBackend.new()
	play.script_path = FAKE_BILLING
	iap.backend = play
	play.product_loaded.connect(iap._on_product_loaded)
	play.owned.connect(iap._grant)
	play.purchase_done.connect(iap._on_purchase_done)
	play.restore_done.connect(iap._on_restore_done)
	iap.add_child(play)
	play.start(PRODUCTS, true)
	return [iap, play, play._client]


func test_google_play() -> void:
	var parts := _play()
	var iap: IAPService = parts[0]
	var play: PlayBillingBackend = parts[1]
	var c: Node = parts[2]
	check_eq(c.count("start_connection"), 1, "connects")
	c.connected.emit()
	check_eq(c.count("query_product_details"), 1, "asks for the price")
	check_eq(c.count("query_purchases"), 1, "and for what's owned")
	c.query_product_details_response.emit(c.details("remove_ads", "R$ 10,90"))
	check_eq(iap.price("remove_ads"), "R$ 10,90", "the price in the player's currency")
	c.query_purchases_response.emit(c.purchases(""))
	check(not iap.owns("remove_ads"), "nothing owned yet")
	# Buying: the sheet, then the update.
	var got := []
	iap.buy("remove_ads", func(r: int) -> void: got.append(r))
	check_eq(c.count("purchase"), 1, "the Play sheet")
	c.on_purchase_updated.emit(c.purchases("remove_ads"))
	check_eq(got, [IAPService.Result.PURCHASED], "bought")
	check(iap.owns("remove_ads"), "owned")
	check_eq(c.acknowledged, ["token-remove_ads"] as Array[String], "acknowledged")
	iap.free()
	_clean()


func test_google_play_cancel_pending_and_owned_at_start() -> void:
	var parts := _play()
	var iap: IAPService = parts[0]
	var c: Node = parts[2]
	c.connected.emit()
	c.query_product_details_response.emit(c.details("remove_ads", "US$1.99"))
	var got := []
	iap.buy("remove_ads", func(r: int) -> void: got.append(r))
	c.on_purchase_updated.emit({"response_code": 1, "debug_message": "", "purchases": []})
	check_eq(got, [IAPService.Result.CANCELLED], "cancelled")
	iap.buy("remove_ads", func(r: int) -> void: got.append(r))
	c.on_purchase_updated.emit(c.purchases("remove_ads", 2))
	check_eq(got[-1], IAPService.Result.PENDING, "pending payment")
	check(not iap.owns("remove_ads"), "not granted while pending")
	check(c.acknowledged.is_empty(), "nothing acknowledged while pending")
	# It goes through later; Google Play sends the update by itself.
	c.on_purchase_updated.emit(c.purchases("remove_ads"))
	check(iap.owns("remove_ads"), "granted when the payment goes through")
	iap.free()
	# Owned already (bought on another phone): found at start, acknowledged
	# only if it wasn't.
	parts = _play()
	iap = parts[0]
	c = parts[2]
	c.connected.emit()
	c.query_purchases_response.emit(c.purchases("remove_ads", 1, true))
	check(iap.owns("remove_ads"), "owned at start")
	check(c.acknowledged.is_empty(), "already acknowledged")
	# Restore asks again.
	var restored := []
	iap.restore(func(r: int) -> void: restored.append(r))
	check_eq(c.count("query_purchases"), 2, "Restore asks Google Play again")
	c.query_purchases_response.emit(c.purchases("remove_ads", 1, true))
	check_eq(restored, [IAPService.Restore.RESTORED], "restored")
	iap.free()
	_clean()


func test_google_play_without_the_product() -> void:
	var parts := _play()
	var iap: IAPService = parts[0]
	var play: PlayBillingBackend = parts[1]
	var c: Node = parts[2]
	var reasons := []
	play.store_unavailable.connect(func(r: String) -> void: reasons.append(r))
	c.connected.emit()
	c.query_product_details_response.emit({"response_code": 0, "debug_message": "", "product_details": [],
		"unfetched_products": [{"product_id": "remove_ads"}]})
	check_eq(reasons.size(), 1, "not set up in Play Console: reported")
	check_eq(iap.price("remove_ads"), "", "no price, so no button")
	iap.free()
	_clean()


## The App Store against the stand-in StoreKitManager.
func test_app_store() -> void:
	_clean()
	var iap := IAPService.new()
	iap.save_path = SAVE
	var sk := StoreKitBackend.new()
	var m := FakeStoreKit.new()
	sk.manager = m
	iap.backend = sk
	sk.product_loaded.connect(iap._on_product_loaded)
	sk.owned.connect(iap._grant)
	sk.purchase_done.connect(iap._on_purchase_done)
	sk.restore_done.connect(iap._on_restore_done)
	iap.add_child(sk)
	sk.start(PRODUCTS, true)
	check_eq(m.calls, ["start", "request_products", "fetch_current_entitlements"] as Array[String],
		"listens, asks for the price and for what's owned")
	m.products_request_completed.emit([FakeStoreKit.FakeProduct.new("remove_ads", "€2,29")], StoreKitBackend.OK)
	check_eq(iap.price("remove_ads"), "€2,29", "the price in the player's currency")
	var got := []
	iap.buy("remove_ads", func(r: int) -> void: got.append(r))
	check_eq(m.bought, ["remove_ads"] as Array[String], "Apple's sheet")
	m.purchase_completed.emit(null, StoreKitBackend.USER_CANCELLED, "")
	check_eq(got, [IAPService.Result.CANCELLED], "cancelled")
	iap.buy("remove_ads", func(r: int) -> void: got.append(r))
	m.purchase_completed.emit(null, StoreKitBackend.PURCHASE_PENDING, "")
	check_eq(got[-1], IAPService.Result.PENDING, "Ask to Buy: pending")
	var t := FakeStoreKit.FakeTransaction.new("remove_ads")
	m.transaction_updated.emit(t)
	check(iap.owns("remove_ads"), "granted when it's approved")
	check(t.finished, "transaction finished")
	iap.free()
	# A refunded purchase isn't granted at start.
	_clean()
	var sk2 := StoreKitBackend.new()
	var m2 := FakeStoreKit.new()
	sk2.manager = m2
	var owned := []
	sk2.owned.connect(func(k: String) -> void: owned.append(k))
	sk2.start(PRODUCTS, true)
	m2.transaction_updated.emit(FakeStoreKit.FakeTransaction.new("remove_ads", 1.0e9))
	check(owned.is_empty(), "refunded: not granted")
	var bought := FakeStoreKit.FakeTransaction.new("remove_ads")
	sk2._buying = "remove_ads"
	var done := []
	sk2.purchase_done.connect(func(k: String, r: int) -> void: done.append(r))
	m2.purchase_completed.emit(bought, StoreKitBackend.OK, "")
	check_eq(done, [IAPService.Result.PURCHASED], "bought")
	check(bought.finished, "finished")
	# Restore: the sync, then the entitlements again.
	var restored := []
	sk2.restore_done.connect(func(r: int) -> void: restored.append(r))
	sk2.restore()
	check_eq(m2.count("restore_purchases"), 1, "AppStore.sync")
	m2.restore_completed.emit(StoreKitBackend.OK, "")
	check_eq(m2.count("fetch_current_entitlements"), 2, "entitlements read again")
	m2.transaction_updated.emit(FakeStoreKit.FakeTransaction.new("remove_ads"))
	sk2._restore_until = 0
	sk2._process(0.0)
	check_eq(restored, [IAPService.Restore.RESTORED], "restored")
	sk2.restore()
	m2.restore_completed.emit(StoreKitBackend.USER_CANCELLED, "")
	check_eq(restored[-1], IAPService.Restore.CANCELLED, "sign-in cancelled")
	sk2.free()
	_clean()
