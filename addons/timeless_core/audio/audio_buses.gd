class_name AudioBuses
extends RefCounted
## The game's audio buses: "SFX" (pieces, stings, interface) and "Music",
## both into Master, so each has its own switch and volume in the settings.
## Made in code at start-up (no bus layout file to keep in step).

const SFX := &"SFX"
const MUSIC := &"Music"


## Adds the buses if they aren't there yet. Safe to call more than once.
static func ensure() -> void:
	for bus in [SFX, MUSIC]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, &"Master")


## `volume` from 0 to 1 as the slider shows it; `on` false mutes the bus.
## The slider follows loudness rather than amplitude (volume², so halfway is
## about -12 dB), and 0 is silence.
static func apply(bus: StringName, on: bool, volume: float) -> void:
	ensure()
	var i := AudioServer.get_bus_index(bus)
	var v := clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_mute(i, not on or v <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v * v, 0.0001)))


static func is_audible(bus: StringName) -> bool:
	var i := AudioServer.get_bus_index(bus)
	return i != -1 and not AudioServer.is_bus_mute(i)
