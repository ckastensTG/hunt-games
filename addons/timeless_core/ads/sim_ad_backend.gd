class_name SimAdBackend
extends AdBackend
## Test builds without AdMob (desktop, the editor): a stand-in screen for
## each ad, clearly labelled as a test, so the placement, the caps and the
## rewards can be tried on the Mac. Never in release builds (AdService only
## picks it in debug builds). Not translated: test builds only.
##
## Tests set `instant` (no screen; the ad closes at once, before show_*()
## returns) and `fill` (false: as if no ad could be loaded).

## Seconds before the interstitial can be closed, and the rewarded video's
## length.
const INTERSTITIAL_S := 1.5
const REWARDED_S := 4.0

var instant := false
## With `instant`: whether the rewarded video counts as watched.
var instant_earn := true
var fill := true
## Ads shown so far (tests).
var interstitials_shown := 0
var rewarded_shown := 0

var _layer: CanvasLayer
var _left := 0.0
var _rewarded := false
var _wait_label: Label
var _done_button: Button


func kind() -> String:
	return "sim"


func interstitial_ready() -> bool:
	return fill


func rewarded_ready() -> bool:
	return fill


func show_interstitial() -> void:
	if not fill:
		interstitial_closed.emit(false)
		return
	interstitials_shown += 1
	if instant:
		interstitial_closed.emit(true)
		return
	_open(false)


func show_rewarded() -> void:
	if not fill:
		rewarded_closed.emit(false, false)
		return
	rewarded_shown += 1
	if instant:
		rewarded_closed.emit(instant_earn, true)
		return
	_open(true)


func _open(rewarded: bool) -> void:
	_rewarded = rewarded
	_left = REWARDED_S if rewarded else INTERSTITIAL_S
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
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	box.add_child(_label("TEST AD", 22, Color(1, 0.8, 0.3)))
	box.add_child(_label("Rewarded video" if rewarded else "Interstitial", 40, Color.WHITE))
	box.add_child(_label("Stands in for an AdMob ad in test builds without AdMob.", 18, Color(0.75, 0.8, 0.85)))
	_wait_label = _label("", 20, Color(0.75, 0.8, 0.85))
	box.add_child(_wait_label)
	_done_button = Button.new()
	_done_button.text = "Collect reward" if rewarded else "Close"
	_done_button.custom_minimum_size = Vector2(0, 60)
	_done_button.disabled = true
	_done_button.pressed.connect(_close.bind(rewarded))
	box.add_child(_done_button)
	if rewarded:
		var skip := Button.new()
		skip.text = "Skip (no reward)"
		skip.flat = true
		skip.custom_minimum_size = Vector2(0, 48)
		skip.pressed.connect(_close.bind(false))
		box.add_child(skip)
	set_process(true)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _process(delta: float) -> void:
	if _layer == null:
		set_process(false)
		return
	_left = maxf(0.0, _left - delta)
	_done_button.disabled = _left > 0.0
	_wait_label.text = ("%d s" % ceili(_left)) if _left > 0.0 else ""


func _close(earned: bool) -> void:
	if _layer:
		_layer.queue_free()
		_layer = null
	if _rewarded:
		rewarded_closed.emit(earned, true)
	else:
		interstitial_closed.emit(true)
