class_name SeriesTheme
extends RefCounted
## The Timeless Games interface look: dark lacquered panels with a thin brass
## edge, parchment text, Alegreya for display and book text, Alegreya Sans for
## the interface (the series fonts, decided 2026-11-03; ui/fonts/README.md).
## Chinese, Japanese and Korean fall back to Noto Sans SC, JP and KR, subset
## to the characters the translations use (ui/fonts/cjk/), with the current
## language's font first so shared Han characters take its regional forms.
## Built in code so it stays in step with the palette below; later it moves
## to timeless-core's shell (framework §7).

const PANEL := Color(0.07, 0.055, 0.045, 0.86)
const PANEL_SOFT := Color(0.07, 0.055, 0.045, 0.6)
const BRASS := Color(0.8, 0.62, 0.34)
const BRASS_DIM := Color(0.8, 0.62, 0.34, 0.45)
const TEXT := Color(0.95, 0.9, 0.8)
const TEXT_DIM := Color(0.76, 0.7, 0.6)
const ACCENT := Color(0.96, 0.76, 0.42)
const BUTTON := Color(0.16, 0.12, 0.09, 0.92)
const BUTTON_HOVER := Color(0.24, 0.18, 0.12, 0.95)
const BUTTON_PRESSED := Color(0.11, 0.08, 0.06, 0.95)

const FONTS := "res://ui/fonts/"
## The CJK weight that goes with each text role.
const CJK_WEIGHT := {
	"display": "Medium", "book": "Regular", "book_italic": "Regular",
	"ui": "Regular", "ui_medium": "Medium", "ui_bold": "Bold", "code": "Bold",
}

static var _theme: Theme
static var _fonts := {}


static func font(name: String) -> Font:
	if not _fonts.has(name):
		match name:
			"display":
				_fonts[name] = load(FONTS + "AlegreyaSC-Medium.ttf")
			"book":
				var v := FontVariation.new()
				v.base_font = load(FONTS + "Alegreya-Variable.ttf")
				v.variation_opentype = {"wght": 500}
				_fonts[name] = v
			"book_italic":
				var v := FontVariation.new()
				v.base_font = load(FONTS + "Alegreya-Variable.ttf")
				v.variation_opentype = {"wght": 450}
				v.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.18, 1), Vector2.ZERO)
				_fonts[name] = v
			"ui":
				_fonts[name] = load(FONTS + "AlegreyaSans-Regular.ttf")
			"ui_medium":
				_fonts[name] = load(FONTS + "AlegreyaSans-Medium.ttf")
			"ui_bold":
				_fonts[name] = load(FONTS + "AlegreyaSans-Bold.ttf")
			"code":
				# Join codes and clocks: lining, even-width figures, so 0 never
				# reads as o (Alegreya's default figures are old-style).
				var v := FontVariation.new()
				v.base_font = load(FONTS + "AlegreyaSans-Bold.ttf")
				v.opentype_features = {"lnum": 1, "tnum": 1}
				_fonts[name] = v
		(_fonts[name] as Font).fallbacks = _cjk_fallbacks(CJK_WEIGHT[name])
	return _fonts[name]


## Call after changing the language: puts that language's CJK font first.
static func apply_locale() -> void:
	for name in _fonts:
		(_fonts[name] as Font).fallbacks = _cjk_fallbacks(CJK_WEIGHT[name])


static func _cjk_fallbacks(weight: String) -> Array[Font]:
	var order := ["SC", "JP", "KR"]
	match TranslationServer.get_locale().substr(0, 2):
		"ja":
			order = ["JP", "SC", "KR"]
		"ko":
			order = ["KR", "SC", "JP"]
	var out: Array[Font] = []
	for script in order:
		out.append(load(FONTS + "cjk/NotoSans%s-%s.subset.ttf" % [script, weight]))
	return out


static func panel_box(bg := PANEL, border := BRASS_DIM, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.anti_aliasing = true
	return s


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(7)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 7
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("ui")
	t.default_font_size = 18

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("default_color", "RichTextLabel", TEXT)

	for type in ["Button", "OptionButton", "CheckBox"]:
		t.set_font("font", type, font("ui_medium"))
		t.set_font_size("font_size", type, 17)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1, 0.96, 0.88))
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.45))
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _button_box(BUTTON, BRASS_DIM))
		t.set_stylebox("hover", type, _button_box(BUTTON_HOVER, BRASS))
		t.set_stylebox("pressed", type, _button_box(BUTTON_PRESSED, ACCENT))
		t.set_stylebox("disabled", type, _button_box(Color(BUTTON, 0.5), Color(BRASS_DIM, 0.2)))
		var focus := _button_box(Color(0, 0, 0, 0), ACCENT)
		focus.draw_center = false
		t.set_stylebox("focus", type, focus)
	t.set_color("icon_normal_color", "OptionButton", BRASS)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", empty)

	var popup := panel_box(Color(0.09, 0.07, 0.055, 0.97), BRASS_DIM, 8)
	popup.content_margin_top = 6
	popup.content_margin_bottom = 6
	popup.content_margin_left = 6
	popup.content_margin_right = 6
	t.set_stylebox("panel", "PopupMenu", popup)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.32, 0.23, 0.13, 0.9)
	hover.set_corner_radius_all(5)
	t.set_stylebox("hover", "PopupMenu", hover)
	t.set_font("font", "PopupMenu", font("ui"))
	t.set_font_size("font_size", "PopupMenu", 17)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.96, 0.88))
	t.set_constant("v_separation", "PopupMenu", 10)

	t.set_stylebox("panel", "TooltipPanel", panel_box(Color(0.09, 0.07, 0.055, 0.97), BRASS_DIM, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	var sep := StyleBoxLine.new()
	sep.color = BRASS_DIM
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)

	# Scroll bars (long texts such as Game origins): a thin brass rail.
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(BRASS_DIM, 0.18)
	rail.set_corner_radius_all(3)
	rail.content_margin_left = 3
	rail.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", rail)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var g := StyleBoxFlat.new()
		g.bg_color = BRASS_DIM if st == "grabber" else BRASS
		g.set_corner_radius_all(3)
		t.set_stylebox(st, "VScrollBar", g)
	_theme = t
	return t


## A label in one of the series' text roles.
static func label(text: String, role := "body", size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	match role:
		"display":
			l.add_theme_font_override("font", font("display"))
		"book":
			l.add_theme_font_override("font", font("book"))
		"italic":
			l.add_theme_font_override("font", font("book_italic"))
		"caps":
			l.add_theme_font_override("font", font("display"))
			l.uppercase = false
		"medium":
			l.add_theme_font_override("font", font("ui_medium"))
		"bold":
			l.add_theme_font_override("font", font("ui_bold"))
		"code":
			l.add_theme_font_override("font", font("code"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A small round piece token for the interface (tiger amber, goat pale).
static func token(color: Color, diameter := 14, filled := true) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	var s := StyleBoxFlat.new()
	s.bg_color = color if filled else Color(0, 0, 0, 0)
	s.border_color = color
	s.set_border_width_all(0 if filled else 1)
	s.set_corner_radius_all(diameter)
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
