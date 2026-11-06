extends TestCase
## The Graphics setting: choices saved, the tier in use, and Auto stepping
## down on a slow device but not on a fast one.


var _before := []


func _save() -> void:
	_before = [GameGraphics.choice(), GameGraphics.detected()]


func _restore() -> void:
	L10n.save_setting("graphics", _before[0])
	GameGraphics.set_detected(_before[1])


func test_choices_and_tiers() -> void:
	_save()
	GameGraphics.set_choice(GameGraphics.MEDIUM)
	check_eq(GameGraphics.choice(), GameGraphics.MEDIUM, "a fixed choice is saved")
	check_eq(GameGraphics.tier(), GameGraphics.MEDIUM, "and used")
	GameGraphics.set_choice("ultra")
	check_eq(GameGraphics.choice(), GameGraphics.AUTO, "unknown choices fall back to Auto")
	check_eq(GameGraphics.tier(), GameGraphics.HIGH, "Auto starts at High")
	GameGraphics.set_detected(GameGraphics.LOW)
	check_eq(GameGraphics.tier(), GameGraphics.LOW, "then uses what it measured")
	GameGraphics.set_choice(GameGraphics.AUTO)
	check_eq(GameGraphics.tier(), GameGraphics.HIGH, "choosing Auto again starts over")
	check_eq(GameGraphics.lower(GameGraphics.HIGH), GameGraphics.MEDIUM, "High → Medium")
	check_eq(GameGraphics.lower(GameGraphics.LOW), "", "nothing below Low")
	for t in GameGraphics.TIERS:
		var s := GameGraphics.settings(t)
		check(s.has_all(["msaa", "scale", "dof", "glow", "particles", "shadows"]), "%s sets everything" % t)
	check(GameGraphics.settings(GameGraphics.LOW).scale < GameGraphics.settings(GameGraphics.MEDIUM).scale, "Low renders smaller than Medium")
	_restore()


func _run(auto: GameGraphics.Auto, frame: float, seconds: float) -> int:
	var steps := 0
	var t := 0.0
	while t < seconds:
		if auto.step(frame):
			steps += 1
		t += frame
	return steps


func test_auto_steps_down_on_a_slow_device() -> void:
	_save()
	GameGraphics.set_choice(GameGraphics.AUTO)
	var auto := GameGraphics.Auto.new()
	check_eq(_run(auto, 1.0 / 30.0, GameGraphics.Auto.SETTLE + GameGraphics.Auto.WINDOW + 0.2), 1, "30 fps: one step")
	check_eq(GameGraphics.tier(), GameGraphics.MEDIUM, "down to Medium")
	_run(auto, 1.0 / 30.0, 20.0)
	check_eq(GameGraphics.tier(), GameGraphics.LOW, "still slow: Low")
	check_eq(_run(auto, 1.0 / 30.0, 20.0), 0, "and no further")
	GameGraphics.set_choice(GameGraphics.AUTO)
	auto = GameGraphics.Auto.new()
	check_eq(_run(auto, 1.0 / 60.0, 30.0), 0, "60 fps: stays")
	check_eq(GameGraphics.detected(), GameGraphics.HIGH, "and remembers High")
	auto.restart()
	var steps := 0
	for i in 400:
		if auto.step(0.6 if i % 20 == 0 else 1.0 / 60.0):  # stalls now and then
			steps += 1
	check_eq(steps, 0, "a few stalls don't count as slow")
	GameGraphics.set_choice(GameGraphics.HIGH)
	auto = GameGraphics.Auto.new()
	check_eq(_run(auto, 1.0 / 20.0, 30.0), 0, "a fixed choice is never changed")
	_restore()


func test_auto_skips_medium_on_a_very_slow_device() -> void:
	_save()
	GameGraphics.set_choice(GameGraphics.AUTO)
	var auto := GameGraphics.Auto.new()
	# The moto g(20) at High: about 10 fps.
	check_eq(_run(auto, 0.1, GameGraphics.Auto.SETTLE + GameGraphics.Auto.WINDOW + 0.2), 1, "10 fps: one step")
	check_eq(GameGraphics.tier(), GameGraphics.LOW, "straight to Low")
	GameGraphics.set_choice(GameGraphics.AUTO)
	GameGraphics.set_detected(GameGraphics.MEDIUM)
	auto = GameGraphics.Auto.new()
	_run(auto, 0.1, GameGraphics.Auto.SETTLE + GameGraphics.Auto.WINDOW + 0.2)
	check_eq(GameGraphics.tier(), GameGraphics.LOW, "from Medium, Low is as far as it goes")
	_restore()


## The looks mark the lights and reflections they drop at Low
## (HuntArtStyle.hide_at_low): Brass its four courtyard lamps and sky fill,
## Modern its reflection probe and bounce light. Stone needs none.
func test_looks_mark_what_goes_at_low() -> void:
	var want := {"brass": 5, "modern": 2, "stone": 0}
	for style: HuntArtStyle in BaghChalArt.styles():
		var root := Node3D.new()
		style.build_set(root, false)
		var marked: Array = root.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n.has_meta(HuntArtStyle.GRAPHICS_MIN))
		check_eq(marked.size(), want.get(style.id, -1), "%s marks %d nodes" % [style.id, want.get(style.id, -1)])
		for n: Node3D in marked:
			check(n is Light3D or n is ReflectionProbe, "%s: %s is a light or probe" % [style.id, n.name])
			check(n.visible, "%s: %s is built visible" % [style.id, n.name])
		root.free()


## Low's 3D size is capped by pixel count, so a bigger phone screen doesn't
## make Low cost more.
func test_low_render_scale_follows_the_pixel_count() -> void:
	var moto := Vector2i(720, 1600)
	var redmi := Vector2i(1080, 2400)
	check(absf(GameGraphics.render_scale(GameGraphics.LOW, moto) - 0.7) < 0.001, "720x1600 keeps 70%")
	var r := GameGraphics.render_scale(GameGraphics.LOW, redmi)
	check(absf(r - sqrt(600000.0 / (1080.0 * 2400.0))) < 0.001, "1080x2400 at about 48%% (%.3f)" % r)
	check(absf(GameGraphics.render_scale(GameGraphics.LOW, Vector2i(2400, 1080)) - r) < 0.001, "the same turned sideways")
	check_eq(GameGraphics.render_scale(GameGraphics.LOW, Vector2i(3840, 2160)), GameGraphics.MIN_SCALE, "never below the minimum")
	check_eq(GameGraphics.render_scale(GameGraphics.HIGH, redmi), 1.0, "High is full size")
	check(absf(GameGraphics.render_scale(GameGraphics.MEDIUM, redmi) - 0.85) < 0.001, "Medium isn't capped")
