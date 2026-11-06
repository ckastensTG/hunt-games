class_name SimIapBackend
extends IapBackend
## Test builds without a store (desktop, the editor, or a phone whose store
## doesn't have the product yet): a stand-in purchase sheet, clearly
## labelled as a test, so the purchase, the thank-you and Restore can be
## tried. Nothing is charged. Never in release builds (IAPService only picks
## it in debug builds). Not translated: test builds only.
##
## What was "bought" here is kept in user://iap_test_store.cfg, as a store
## would, so Restore finds it again after IAPService forgets it.
##
## Tests set `instant` (no sheet: the purchase ends before buy() returns,
## with `instant_result`).

const PRICE := "US$1.99 (test)"
const STORE_PATH := "user://iap_test_store.cfg"

var instant := false
var instant_result := IAPService.Result.PURCHASED
var store_path := STORE_PATH
## What the stand-in store remembers as bought.
var bought := {}

var _layer: CanvasLayer
var _key := ""


func kind() -> String:
	return "sim"


func start(product_ids: Dictionary, debug_build: bool) -> void:
	super(product_ids, debug_build)
	var cfg := ConfigFile.new()
	if cfg.load(store_path) == OK and cfg.has_section("bought"):
		for k in cfg.get_section_keys("bought"):
			bought[k] = true
	for k in products:
		product_loaded.emit.call_deferred(k, PRICE)


func buy(key: String) -> void:
	_key = key
	if instant:
		_finish(instant_result)
		return
	_open()


func restore() -> void:
	var any := false
	for k in bought:
		if products.has(k):
			any = true
			owned.emit(k)
	restore_done.emit.call_deferred(IAPService.Restore.RESTORED if any else IAPService.Restore.NOTHING)


func forget() -> void:
	bought.clear()
	_save()


func _finish(result: int) -> void:
	if _layer:
		_layer.queue_free()
		_layer = null
	if result == IAPService.Result.PURCHASED:
		bought[_key] = true
		_save()
	purchase_done.emit(_key, result)


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in bought:
		cfg.set_value("bought", k, true)
	cfg.save(store_path)


func _open() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.07, 0.1, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	box.add_child(_label("TEST PURCHASE", 22, Color(1, 0.8, 0.3)))
	box.add_child(_label(_key.replace("_", " ").capitalize(), 40, Color.WHITE))
	box.add_child(_label(PRICE, 24, Color.WHITE))
	box.add_child(_label("Stands in for Google Play or the App Store in test builds. Nothing is charged.", 18, Color(0.75, 0.8, 0.85)))
	for choice in [["Buy (test)", IAPService.Result.PURCHASED], ["Payment pending (test)", IAPService.Result.PENDING],
			["Payment fails (test)", IAPService.Result.FAILED], ["Cancel", IAPService.Result.CANCELLED]]:
		var b := Button.new()
		b.text = choice[0]
		b.custom_minimum_size = Vector2(0, 56)
		b.flat = choice[1] != IAPService.Result.PURCHASED
		b.pressed.connect(_finish.bind(choice[1]))
		box.add_child(b)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
