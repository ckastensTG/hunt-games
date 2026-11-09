class_name SeriesTheme
extends RefCounted
## The Timeless Games interface look: dark lacquered panels with a thin brass
## edge, parchment text, Alegreya for display and book text, Alegreya Sans for
## the interface (the series fonts, decided 2026-11-03; ui/fonts/README.md).
## Chinese (Simplified and Traditional), Japanese and Korean fall back to Noto
## Sans SC, TC, JP and KR, subset to the characters the translations use
## (ui/fonts/cjk/), with the current language's font first so shared Han
## characters take its regional forms. Thai falls back to Noto Sans Thai
## (ui/fonts/thai/) and Nepali (Bagh Chal) to Noto Sans Devanagari
## (ui/fonts/devanagari/): whole fonts, since their vowel signs and conjuncts
## come from a few characters, and the files are small.
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
## The CJK, Thai and Devanagari weight that goes with each text role.
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
				# Alegreya's own italic (Medium, like the book text's weight),
				# not the upright font slanted: real italic letterforms.
				_fonts[name] = load(FONTS + "Alegreya-MediumItalic.ttf")
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
		(_fonts[name] as Font).fallbacks = _fallbacks(CJK_WEIGHT[name])
	return _fonts[name]


## Call after changing the language: puts that language's fallback font first.
static func apply_locale() -> void:
	for name in _fonts:
		(_fonts[name] as Font).fallbacks = _fallbacks(CJK_WEIGHT[name])


static func _fallbacks(weight: String) -> Array[Font]:
	var order := ["SC", "TC", "JP", "KR"]
	var lang := L10n.best_locale(TranslationServer.get_locale())
	match lang:
		"zh_TW":
			order = ["TC", "SC", "JP", "KR"]
		"ja":
			order = ["JP", "SC", "TC", "KR"]
		"ko":
			order = ["KR", "SC", "TC", "JP"]
	var out: Array[Font] = []
	for script in order:
		out.append(load(FONTS + "cjk/NotoSans%s-%s.subset.ttf" % [script, weight]))
	# The current language's own script first; the others stay for the
	# language names in the Language menu.
	var thai: Font = load(FONTS + "thai/NotoSansThai-%s.ttf" % weight)
	var devanagari: Font = load(FONTS + "devanagari/NotoSansDevanagari-%s.ttf" % weight)
	for f: Font in [thai, devanagari]:
		out.append(f)
	if lang == "th":
		out.erase(thai)
		out.push_front(thai)
	elif lang == "ne":
		out.erase(devanagari)
		out.push_front(devanagari)
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


## Every text size in the game goes through fs(): the size it was designed
## at plus TEXT_BUMP. Christopher, 2026-11-05: "increase every text in the game
## by two points" (easier to read and to tap on phones).
const TEXT_BUMP := 2
## Large text (Settings; GameText): every size a quarter bigger again.
## Christopher, 2026-11-08: "normal" and "large" with a significant
## difference between the two.
const LARGE_SCALE := 1.25

## Large text is on. Set through set_large() (GameText), which also makes
## theme() build afresh at the new sizes.
static var large := false


static func fs(size: int) -> int:
	var s := size + TEXT_BUMP
	return roundi(s * LARGE_SCALE) if large else s


static func set_large(on: bool) -> void:
	if on == large:
		return
	large = on
	_theme = null


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("ui")
	t.default_font_size = fs(18)

	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("default_color", "RichTextLabel", TEXT)

	for type in ["Button", "OptionButton", "CheckBox"]:
		t.set_font("font", type, font("ui_medium"))
		t.set_font_size("font_size", type, fs(17))
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
	t.set_font_size("font_size", "PopupMenu", fs(17))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.96, 0.88))
	# Roomy rows in drop-down lists, so the right item is easy to tap on a phone.
	t.set_constant("v_separation", "PopupMenu", 22)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 12)

	t.set_stylebox("panel", "TooltipPanel", panel_box(Color(0.09, 0.07, 0.055, 0.97), BRASS_DIM, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", fs(16))

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

	# Sliders (the Sound and Music volumes): a dim rail, brass up to a round
	# parchment knob.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(BRASS_DIM, 0.28)
	track.set_corner_radius_all(4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = BRASS
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := track.duplicate() as StyleBoxFlat
	fill_hi.bg_color = ACCENT
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", _knob(TEXT))
	t.set_icon("grabber_highlight", "HSlider", _knob(Color(1, 0.96, 0.88)))
	t.set_icon("grabber_disabled", "HSlider", _knob(Color(TEXT_DIM, 0.6)))
	_theme = t
	return t


## A round slider knob with a brass rim, drawn with smooth edges.
static func _knob(color: Color, size := 30) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	var r := size / 2.0 - 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var cover := clampf(r + 0.5 - d, 0.0, 1.0)
			if cover <= 0.0:
				continue
			var rim := clampf(d - (r - 2.0), 0.0, 1.0)
			var col := color.lerp(BRASS, rim)
			col.a *= cover
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


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
	l.add_theme_font_size_override("font_size", fs(size))
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
