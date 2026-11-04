class_name SeriesIcon
extends Control
## Small line icons drawn in code in the series brass, so they stay crisp at
## any size and need no image files: "globe" (language), "menu" (the in-game
## menu button) and "undo".

var kind := "globe"
var color := SeriesTheme.BRASS
var line := 1.6


static func make(icon_kind: String, size := 22.0, tint := SeriesTheme.BRASS) -> SeriesIcon:
	var icon := SeriesIcon.new()
	icon.kind = icon_kind
	icon.color = tint
	icon.custom_minimum_size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.line = maxf(1.2, size / 14.0)
	return icon


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var r := s / 2.0 - line
	match kind:
		"globe":
			# Outline, equator, two parallels and two meridians.
			draw_arc(c, r, 0.0, TAU, 48, color, line, true)
			draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), color, line, true)
			for y in [-0.5, 0.5]:
				var half := r * sqrt(1.0 - y * y)
				draw_line(c + Vector2(-half, y * r), c + Vector2(half, y * r), color, line * 0.8, true)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r), color, line * 0.8, true)
			_ellipse(c, r * 0.48, r, color, line * 0.8)
		"menu":
			var w := r * 1.5
			for y in [-0.55, 0.0, 0.55]:
				draw_line(c + Vector2(-w / 2.0, y * r), c + Vector2(w / 2.0, y * r), color, line * 1.3, true)
		"undo":
			# A counter-clockwise arc with an arrowhead at its start.
			draw_arc(c + Vector2(0, r * 0.15), r * 0.72, deg_to_rad(200), deg_to_rad(400), 32, color, line * 1.2, true)
			var tip := c + Vector2(0, r * 0.15) + Vector2.from_angle(deg_to_rad(200)) * r * 0.72
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.32, -r * 0.05), tip + Vector2(r * 0.12, -r * 0.42),
				tip + Vector2(r * 0.2, r * 0.18)]), color)


func _ellipse(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)
