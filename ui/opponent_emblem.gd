class_name OpponentEmblem
extends Control
## The emblem of a named AI opponent (HuntOpponents): a line drawing in a
## round brass medallion, drawn in code like SeriesIcon (no image files, crisp
## at any size). Kinds: "kite" (Sanu), "tea" (Maya Didi: a glass of chiya),
## "chisel" (Hari Dai: a carver's mallet and chisel), "topi" (Hajurba: a dhaka
## topi, the Nepali cap). `lit` draws it in the bright accent (the chosen
## opponent); otherwise dimmer.

const KINDS := ["kite", "tea", "chisel", "topi"]

var kind := "topi"
var lit := true


static func make(emblem_kind: String, size := 64.0, on := true) -> OpponentEmblem:
	var e := OpponentEmblem.new()
	e.kind = emblem_kind
	e.lit = on
	e.custom_minimum_size = Vector2(size, size)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return e


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5 - 2.0
	var brass: Color = SeriesTheme.BRASS if lit else SeriesTheme.BRASS_DIM
	var ink: Color = SeriesTheme.ACCENT if lit else SeriesTheme.TEXT_DIM
	draw_circle(c, r, Color(0.13, 0.095, 0.07))
	draw_arc(c, r, 0, TAU, 64, brass, 2.5, true)
	draw_arc(c, r - 5.0, 0, TAU, 64, Color(brass, 0.35), 1.0, true)
	var u := s / 64.0
	var w := 2.4 * u
	match kind:
		"kite":
			var top := c + Vector2(4, -20) * u
			var rt := c + Vector2(17, -4) * u
			var bot := c + Vector2(-2, 14) * u
			var lt := c + Vector2(-14, -8) * u
			draw_polyline(PackedVector2Array([top, rt, bot, lt, top]), ink, w, true)
			draw_line(top, bot, ink, w * 0.6, true)
			draw_line(lt, rt, ink, w * 0.6, true)
			var tail := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				tail.append(bot + Vector2(-6 * t + sin(t * 9.0) * 3.0, 14 * t) * u)
			draw_polyline(tail, ink, w * 0.7, true)
			draw_circle(bot + Vector2(-3, 7) * u, 1.8 * u, ink)
			draw_circle(bot + Vector2(-5, 13) * u, 1.8 * u, ink)
		"tea":
			# A glass of chiya with steam.
			var g := PackedVector2Array([c + Vector2(-11, -4) * u, c + Vector2(-8, 18) * u,
				c + Vector2(8, 18) * u, c + Vector2(11, -4) * u])
			draw_polyline(g, ink, w, true)
			draw_line(c + Vector2(-10, 4) * u, c + Vector2(10, 4) * u, Color(ink, 0.6), w * 0.6, true)
			for dx in [-5.0, 3.0]:
				var st := PackedVector2Array()
				for i in 9:
					var t := i / 8.0
					st.append(c + Vector2(dx + sin(t * 6.0) * 2.6, -9 - 14 * t) * u)
				draw_polyline(st, Color(ink, 0.75), w * 0.6, true)
		"chisel":
			# A carver's mallet over a chisel.
			var a := c + Vector2(-14, 14) * u
			var b := c + Vector2(10, -10) * u
			draw_line(a, b, ink, w, true)
			var blade := PackedVector2Array([b + Vector2(-2.5, -2.5) * u, b + Vector2(5, -9) * u,
				b + Vector2(9, -5) * u, b + Vector2(2.5, 2.5) * u])
			draw_colored_polygon(blade, ink)
			draw_line(c + Vector2(14, 14) * u, c + Vector2(-4, -4) * u, ink, w, true)
			var head := c + Vector2(-8, -8) * u
			var d := Vector2(1, -1).normalized() * 9.0 * u
			var n := Vector2(1, 1).normalized() * 5.0 * u
			draw_colored_polygon(PackedVector2Array([head - d - n, head + d - n, head + d + n, head - d + n]), ink)
		"topi":
			# A dhaka topi: the cap's slanted crown and its woven pattern.
			var outline := PackedVector2Array()
			outline.append(c + Vector2(-19, 11) * u)
			outline.append(c + Vector2(-18, -3) * u)
			for i in 9:
				var t := i / 8.0
				outline.append(c + Vector2(-18 + 35 * t, -3 - 14 * t - sin(t * PI) * 2.0) * u)
			outline.append(c + Vector2(19, 11) * u)
			for i in 9:
				var t := i / 8.0
				outline.append(c + Vector2(19 - 38 * t, 11 + sin(t * PI) * 3.0) * u)
			draw_colored_polygon(outline, Color(ink, 0.16))
			draw_polyline(outline, ink, w, true)
			# The woven pattern: two rows of small diamonds.
			for row in 2:
				for i in 5:
					var x := -13.0 + i * 7.0
					var y := 6.0 - row * 7.0 - (x + 13.0) * 0.28 * row
					var m := c + Vector2(x, y) * u
					draw_polyline(PackedVector2Array([m + Vector2(0, -2.6) * u, m + Vector2(2.6, 0) * u,
						m + Vector2(0, 2.6) * u, m + Vector2(-2.6, 0) * u, m + Vector2(0, -2.6) * u]), Color(ink, 0.85), w * 0.45, true)
