class_name GameSound
extends RefCounted
## The player's sound settings: Sound (pieces and stings) and Music, each on
## or off with a volume, saved per device with the other settings
## (user://settings.cfg). On iPhone and iPad the game also stays quiet when the
## silent switch is on: the audio session is Godot's default, Ambient.

const SOUND := "sound"
const MUSIC := "music"
## A new install starts both at half volume (Christopher, 2026-11-05).
const DEFAULT_VOLUME := {SOUND: 0.5, MUSIC: 0.5}


static func apply_saved() -> void:
	for kind in [SOUND, MUSIC]:
		_apply(kind)


static func is_on(kind: String) -> bool:
	return bool(L10n.load_setting(kind + "_on", true))


static func volume(kind: String) -> float:
	return clampf(float(L10n.load_setting(kind + "_volume", DEFAULT_VOLUME[kind])), 0.0, 1.0)


static func set_on(kind: String, on: bool) -> void:
	L10n.save_setting(kind + "_on", on)
	_apply(kind)


static func set_volume(kind: String, value: float) -> void:
	L10n.save_setting(kind + "_volume", clampf(value, 0.0, 1.0))
	_apply(kind)


static func bus(kind: String) -> StringName:
	return AudioBuses.MUSIC if kind == MUSIC else AudioBuses.SFX


static func _apply(kind: String) -> void:
	AudioBuses.apply(bus(kind), is_on(kind), volume(kind))
