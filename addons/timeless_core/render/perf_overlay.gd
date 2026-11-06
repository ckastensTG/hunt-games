class_name PerfOverlay
extends CanvasLayer
## A small frame-rate readout for testing on devices, in any build. Hidden
## until toggled: F3 on a keyboard, or a three-finger tap on a touch screen.
## Shows frames per second, the average and slowest frame times over the
## last second, the GPU and CPU render times and the draw calls, plus a line
## from the game (`info`, e.g. the graphics tier).

## Returns extra text for the last line (or "").
var info: Callable

var _label := Label.new()
var _frames := FrameTimer.new()
var _touches := {}
var _shown := false


func _init() -> void:
	name = "PerfOverlay"
	layer = 120
	_frames.hitch = 10.0  # show stalls here; they matter when testing
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)


func is_shown() -> bool:
	return _shown


func toggle() -> void:
	_shown = not _shown
	_label.visible = _shown
	_frames.clear()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), _shown)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
			if _touches.size() == 3:
				toggle()
		else:
			_touches.erase(event.index)


func _process(delta: float) -> void:
	if not _shown:
		return
	_frames.add(delta)
	if _frames.duration() < 1.0:
		return
	var vp := get_viewport().get_viewport_rid()
	var R := RenderingServer
	var text := "%.0f fps   avg %.1f ms   slowest %.1f ms\nGPU %.1f ms   CPU %.1f ms   %d draw calls" % [
		_frames.fps(), _frames.mean_ms(), _frames.percentile_ms(1.0),
		R.viewport_get_measured_render_time_gpu(vp), R.viewport_get_measured_render_time_cpu(vp),
		R.viewport_get_render_info(vp, R.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, R.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		+ R.viewport_get_render_info(vp, R.VIEWPORT_RENDER_INFO_TYPE_SHADOW, R.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)]
	if _frames.hitches > 0:
		text += "   %d stalls" % _frames.hitches
	if info.is_valid():
		var extra: String = info.call()
		if extra != "":
			text += "\n" + extra
	_label.text = text
	_frames.clear()
