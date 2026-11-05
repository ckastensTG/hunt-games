class_name SeriesSwitch
extends Button
## An on/off switch in the series look: a brass-edged pill whose knob sits
## right (lit) when on. Drawn in code, so it stays sharp at any screen size
## and needs no words (Sound and Music in the in-game menu).

const W := 60.0
const H := 32.0

var _box_on: StyleBoxFlat
var _box_off: StyleBoxFlat


func _init() -> void:
	toggle_mode = true
	flat = true
	custom_minimum_size = Vector2(W + 8, H + 12)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_box_on = _box(Color(0.5, 0.35, 0.15, 0.95), SeriesTheme.ACCENT)
	_box_off = _box(SeriesTheme.BUTTON, SeriesTheme.BRASS_DIM)
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _draw() -> void:
	var r := Rect2((size - Vector2(W, H)) / 2.0, Vector2(W, H))
	draw_style_box(_box_on if button_pressed else _box_off, r)
	var radius := H / 2.0 - 5.0
	var x := r.end.x - H / 2.0 if button_pressed else r.position.x + H / 2.0
	var knob := SeriesTheme.TEXT if button_pressed else SeriesTheme.TEXT_DIM
	draw_circle(Vector2(x, r.get_center().y), radius, knob, true, -1.0, true)
	if has_focus():
		var ring := _box(Color(0, 0, 0, 0), SeriesTheme.ACCENT)
		ring.draw_center = false
		ring.expand_margin_left = 3
		ring.expand_margin_right = 3
		ring.expand_margin_top = 3
		ring.expand_margin_bottom = 3
		draw_style_box(ring, r)


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(H / 2.0))
	s.anti_aliasing = true
	return s
