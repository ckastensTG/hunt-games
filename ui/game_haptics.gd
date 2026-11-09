class_name GameHaptics
extends RefCounted
## Light vibrations on the board (Christopher, 2026-11-08: "A light
## vibration on a move, a capture and the end of a game, with an on/off
## switch"). On phones only: iPads have no vibration motor, desktops none
## either. On by default; Settings → Vibration turns it off, saved per device
## (user://settings.cfg). Android needs the VIBRATE permission (both Android
## presets); iPhone uses Core Haptics through Godot.

const SETTING := "haptics_on"
const MOVE := "move"
const CAPTURE := "capture"
const END := "end"
## [milliseconds, strength 0..1] per event: a tap for a move, a firmer one
## for a capture, a longer one at the end of a game. Not shorter than about
## 25 ms: the small motors in budget phones don't get going in less (on the
## moto g20 a 12 ms move pulse wasn't felt at all; Christopher's device test,
## 2026-11-08).
const PULSES := {MOVE: [28, 0.55], CAPTURE: [50, 0.85], END: [90, 1.0]}

## Tests and tools: when set, pulses are recorded here instead of vibrating,
## and the switch shows as on any platform.
static var recorder: Variant = null
static var _on := -1


static func available() -> bool:
	if recorder != null:
		return true
	if OS.get_name() == "Android":
		return true
	return OS.get_name() == "iOS" and not OS.get_model_name().begins_with("iPad")


static func is_on() -> bool:
	if _on < 0:
		_on = 1 if bool(L10n.load_setting(SETTING, true)) else 0
	return _on == 1


static func set_on(on: bool) -> void:
	_on = 1 if on else 0
	L10n.save_setting(SETTING, on)


static func pulse(kind: String) -> void:
	if not PULSES.has(kind) or not available() or not is_on():
		return
	if recorder != null:
		(recorder as Array).append(kind)
		return
	Input.vibrate_handheld(PULSES[kind][0], PULSES[kind][1])
