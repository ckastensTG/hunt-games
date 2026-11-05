extends TestCase
## SfxPlayer: takes picked at random but never twice in a row, small pitch
## variety (none when asked), silent for unknown events, and the buses.


func _player(takes: int) -> SfxPlayer:
	var p := SfxPlayer.new()
	p.log_plays = true
	for i in takes:
		var w := AudioStreamWAV.new()
		w.data = PackedByteArray([0, 0, 0, 0])
		p.add_take("tap", w)
	return p


func test_takes_vary_without_repeating() -> void:
	var p := _player(3)
	var seen := {}
	var last := -1
	for i in 60:
		p.play("tap")
		var take := p.last_take("tap")
		check(take != last, "never the same take twice in a row")
		last = take
		seen[take] = true
	check_eq(seen.size(), 3, "every take gets played")
	p.free()


func test_pitch_varies_a_little_or_not_at_all() -> void:
	var p := _player(2)
	for i in 30:
		p.play("tap", 0.8)
	for entry in p.played:
		check(absf(entry[1] - 0.8) <= 0.8 * p.pitch_jitter + 0.0001, "pitch within the jitter around 0.8")
	p.played.clear()
	p.play("tap", 1.0, 0.0, false)
	check_eq(p.played[0][1], 1.0, "vary off: exact pitch")
	p.free()


func test_unknown_events_are_silent() -> void:
	var p := _player(1)
	p.play("nothing")
	check(p.played.is_empty(), "no take, nothing played")
	p.load_events("res://no/such/folder", ["tap"])
	check(not p.has_event("tap"), "loading from a missing folder clears the event")
	p.free()


func test_buses_and_volume() -> void:
	AudioBuses.ensure()
	AudioBuses.ensure()
	check(AudioServer.get_bus_index(AudioBuses.SFX) != -1, "SFX bus")
	check(AudioServer.get_bus_index(AudioBuses.MUSIC) != -1, "Music bus")
	var count := AudioServer.bus_count
	AudioBuses.ensure()
	check_eq(AudioServer.bus_count, count, "ensure() adds nothing twice")
	var i := AudioServer.get_bus_index(AudioBuses.SFX)
	AudioBuses.apply(AudioBuses.SFX, true, 0.5)
	check(absf(AudioServer.get_bus_volume_db(i) - (-12.04)) < 0.05, "half volume is about -12 dB")
	check(AudioBuses.is_audible(AudioBuses.SFX), "on")
	AudioBuses.apply(AudioBuses.SFX, false, 0.5)
	check(not AudioBuses.is_audible(AudioBuses.SFX), "off mutes")
	AudioBuses.apply(AudioBuses.SFX, true, 0.0)
	check(not AudioBuses.is_audible(AudioBuses.SFX), "zero volume mutes")
	AudioBuses.apply(AudioBuses.SFX, true, 1.0)
	check(absf(AudioServer.get_bus_volume_db(i)) < 0.01, "full volume is 0 dB")
