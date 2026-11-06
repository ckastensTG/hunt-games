class_name SeriesIcon
extends Control
## Small line icons drawn in code in the series brass, so they stay crisp at
## any size and need no image files: "globe" (language), "menu" (the in-game
## menu button), "undo" and "lock" (a look that needs a video first).
## texture() renders one into an image, for controls that take a texture
## (an OptionButton's items).

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
		"lock":
			# A padlock: the shackle's arch over a solid body with a keyhole.
			var top := c + Vector2(0, -r * 0.1)
			draw_arc(top, r * 0.42, PI, TAU, 24, color, line * 1.3, true)
			for x in [-0.42, 0.42]:
				draw_line(top + Vector2(x * r, 0), top + Vector2(x * r, r * 0.25), color, line * 1.3, true)
			draw_rect(Rect2(c + Vector2(-r * 0.7, r * 0.05), Vector2(r * 1.4, r * 0.9)), color)
			draw_circle(c + Vector2(0, r * 0.42), r * 0.14, Color(0, 0, 0, 0.55))


## An icon as a texture (size × size pixels), drawn with smooth edges.
## Only "lock" so far.
static func texture(icon_kind: String, size := 22, tint := SeriesTheme.BRASS) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(size)
			var d := _lock_distance(p) if icon_kind == "lock" else 1.0
			var a := clampf(0.5 - d * size, 0.0, 1.0)
			img.set_pixel(x, y, Color(tint, tint.a * a))
	return ImageTexture.create_from_image(img)


## Signed distance (in icon widths) to a padlock in the unit square:
## negative inside.
static func _lock_distance(p: Vector2) -> float:
	# Body: a rounded box, with a round keyhole cut out.
	var q := (p - Vector2(0.5, 0.7)).abs() - Vector2(0.32, 0.22) + Vector2(0.06, 0.06)
	var body := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 0.06
	body = maxf(body, 0.065 - p.distance_to(Vector2(0.5, 0.68)))
	# Shackle: an arch of radius 0.2 over the body, 0.08 thick.
	var c := Vector2(0.5, 0.36)
	var arch: float
	if p.y <= c.y:
		arch = absf(p.distance_to(c) - 0.2)
	else:
		arch = minf(Vector2(absf(p.x - 0.3), maxf(0.0, p.y - 0.5)).length(),
			Vector2(absf(p.x - 0.7), maxf(0.0, p.y - 0.5)).length())
	arch -= 0.045
	return minf(body, arch)


func _ellipse(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)
