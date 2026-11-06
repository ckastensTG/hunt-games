class_name GameGraphics
extends RefCounted
## The Graphics setting: Auto (the default), High, Medium or Low, saved per
## device with the other settings (user://settings.cfg).
##
## Auto starts at High and steps down a tier while the game runs under about
## 54 frames per second (greybox.gd, `_auto_graphics`), two tiers when it runs
## under 27 (a slow phone at High: Medium would be too slow as well); the
## tier it settles on is saved, so the next launch starts there. Choosing Auto
## again starts over from High. It never steps back up by itself.
##
## The tiers trade the costliest effects first (measured with
## tools/perf_probe.gd): 4x MSAA, the far depth-of-field blur and full
## resolution 3D. The 3D view can render smaller and be scaled up (FSR 1 on
## desktop; phones use the Mobile renderer, which scales bilinearly); the
## interface always stays sharp.

const AUTO := "auto"
const HIGH := "high"
const MEDIUM := "medium"
const LOW := "low"
const TIERS := [HIGH, MEDIUM, LOW]
const CHOICES := [AUTO, HIGH, MEDIUM, LOW]

const SETTINGS := {
	HIGH: {"msaa": Viewport.MSAA_4X, "scale": 1.0, "dof": true, "glow": true, "particles": 1.0, "shadows": true},
	MEDIUM: {"msaa": Viewport.MSAA_2X, "scale": 0.85, "dof": false, "glow": true, "particles": 0.5, "shadows": true},
	LOW: {"msaa": Viewport.MSAA_2X, "scale": 0.7, "dof": false, "glow": false, "particles": 0.0, "shadows": false,
		"max_pixels": LOW_MAX_PIXELS},
}
## Low draws the 3D at 70%, but never more than this many pixels: about what
## 70% is on a 720x1600 phone (the moto g(20)). A phone GPU's cost follows
## the pixel count, so a 1080x2400 phone (the Redmi Note 10, 2.25x the
## pixels) would otherwise pay twice as much at Low; there Low is about 48%.
const LOW_MAX_PIXELS := 600000
## Never below this, however big the screen.
const MIN_SCALE := 0.4


## The player's choice: AUTO or a tier.
static func choice() -> String:
	var c := str(L10n.load_setting("graphics", AUTO))
	return c if c in CHOICES else AUTO


static func set_choice(c: String) -> void:
	L10n.save_setting("graphics", c if c in CHOICES else AUTO)
	if c == AUTO:
		set_detected("")  # start over from High


## The tier Auto settled on ("" before it has measured).
static func detected() -> String:
	var d := str(L10n.load_setting("graphics_auto", ""))
	return d if d in TIERS else ""


static func set_detected(tier_id: String) -> void:
	L10n.save_setting("graphics_auto", tier_id)


## The tier in use.
static func tier() -> String:
	var c := choice()
	if c != AUTO:
		return c
	var d := detected()
	return d if d != "" else HIGH


## The next tier down, or "" at Low.
static func lower(tier_id: String) -> String:
	var i := TIERS.find(tier_id)
	return TIERS[i + 1] if i >= 0 and i + 1 < TIERS.size() else ""


static func settings(tier_id: String) -> Dictionary:
	return SETTINGS.get(tier_id, SETTINGS[HIGH])


## The 3D render scale for a tier on a window of `size` pixels.
static func render_scale(tier_id: String, size: Vector2i) -> float:
	var s := settings(tier_id)
	var scale: float = s.scale
	var cap: int = s.get("max_pixels", 0)
	var pixels := float(size.x) * float(size.y)
	if cap > 0 and pixels > 0.0:
		scale = minf(scale, sqrt(cap / pixels))
	return clampf(scale, MIN_SCALE, 1.0)


## The name shown in the menu.
static func label(c: String) -> String:
	match c:
		# TRANSLATORS: Graphics setting: the game picks the quality for this device. Keep it short.
		AUTO: return L10n.t("Auto")
		# TRANSLATORS: Graphics setting: the best-looking quality. Keep it short.
		HIGH: return L10n.t("High")
		# TRANSLATORS: Graphics setting: medium quality. Keep it short.
		MEDIUM: return L10n.t("Medium")
		# TRANSLATORS: Graphics setting: the lightest quality, for slower phones. Keep it short.
		LOW: return L10n.t("Low")
	return c


## Auto's measuring: call `step(delta)` every frame. While the choice is Auto
## and the tier isn't Low, it waits `SETTLE` seconds (after start-up or a
## change), averages `WINDOW` seconds of frames (stalls left out) and steps
## the tier down when the average frame is slower than `SLOW_MS` (about 54
## fps), two tiers when slower than `VERY_SLOW_MS`. Returns true when it
## stepped down, so the caller applies the tier.
##
## Measured on a moto g(20) (Mali-G52, 720x1600, perf_test.gd): High 83–99 ms
## a frame, Medium 35–45 ms, Low 25–30 ms. Medium costs about half of High,
## so a High frame over twice `SLOW_MS` means Medium would be slow too.
class Auto:
	const SETTLE := 2.0
	const WINDOW := 4.0
	const SLOW_MS := 18.5
	const VERY_SLOW_MS := 2.0 * SLOW_MS

	var frames := FrameTimer.new()
	var settle := SETTLE

	func step(delta: float) -> bool:
		if GameGraphics.choice() != GameGraphics.AUTO:
			return false
		var now := GameGraphics.tier()
		var next := GameGraphics.lower(now)
		if next == "":
			return false
		if settle > 0.0:
			settle -= delta
			return false
		frames.add(delta)
		if frames.duration() < WINDOW:
			return false
		var mean := frames.mean_ms()
		frames.clear()
		if GameGraphics.detected() == "":
			GameGraphics.set_detected(now)
		if mean <= SLOW_MS:
			return false
		if mean > VERY_SLOW_MS and GameGraphics.lower(next) != "":
			next = GameGraphics.lower(next)
		GameGraphics.set_detected(next)
		settle = SETTLE
		return true

	## Measure afresh (the scene was rebuilt, the app came back, a change).
	func restart() -> void:
		frames.clear()
		settle = SETTLE
