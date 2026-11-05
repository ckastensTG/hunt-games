extends TestCase
## The game's sounds: every look has every piece sound and its music, Bagh
## Chal has its stings, and the Sound and Music settings reach the buses and
## are saved.

const GreyboxScript := preload("res://scenes/greybox/greybox.gd")


func test_every_look_has_every_piece_sound() -> void:
	var dirs: Array[String] = [GreyboxScript.GREYBOX_SOUNDS]
	for st in BaghChalArt.styles():
		check(st.sound_dir != "", "look %s has a sound folder" % st.id)
		dirs.append(st.sound_dir)
	var p := SfxPlayer.new()
	for dir in dirs:
		p.load_events(dir, GreyboxScript.PIECE_SOUNDS)
		for ev in GreyboxScript.PIECE_SOUNDS:
			check(p.take_count(ev) >= 3, "%s: at least 3 takes of %s (got %d)" % [dir, ev, p.take_count(ev)])
	p.load_events(GreyboxScript.TITLE_STINGS["bagh_chal"], GreyboxScript.STINGS)
	for ev in GreyboxScript.STINGS:
		check_eq(p.take_count(ev), 1, "Bagh Chal sting: %s" % ev)
	p.free()


func test_every_look_has_music() -> void:
	for st in BaghChalArt.styles():
		check(st.music_dir != "", "look %s has a music folder" % st.id)
		var m := MusicPlayer.new()
		m.play_folder(st.music_dir)
		check(m.track_count() >= 3, "%s: at least 3 tracks (got %d)" % [st.id, m.track_count()])
		for n in range(1, m.track_count() + 1):
			var t: AudioStream = load("%s/track_%d.ogg" % [st.music_dir, n])
			check(t is AudioStreamOggVorbis, "%s track %d is Ogg Vorbis" % [st.id, n])
			check(not t.loop, "%s track %d plays once (no loop)" % [st.id, n])
			var secs := t.get_length()
			check(secs > 90.0 and secs < 400.0, "%s track %d: %.0f s" % [st.id, n, secs])
		m.free()


func test_new_install_starts_at_half_volume() -> void:
	check_eq(GameSound.DEFAULT_VOLUME[GameSound.SOUND], 0.5, "Sound starts at half")
	check_eq(GameSound.DEFAULT_VOLUME[GameSound.MUSIC], 0.5, "Music starts at half")


func test_settings_reach_the_buses_and_are_saved() -> void:
	var before := {}
	for kind in [GameSound.SOUND, GameSound.MUSIC]:
		before[kind] = [GameSound.is_on(kind), GameSound.volume(kind)]
	GameSound.set_on(GameSound.SOUND, false)
	check(not GameSound.is_on(GameSound.SOUND), "Sound off is saved")
	check(not AudioBuses.is_audible(AudioBuses.SFX), "Sound off mutes the SFX bus")
	check(AudioBuses.is_audible(AudioBuses.MUSIC) == GameSound.is_on(GameSound.MUSIC), "Music untouched")
	GameSound.set_on(GameSound.SOUND, true)
	GameSound.set_volume(GameSound.SOUND, 0.5)
	check_eq(GameSound.volume(GameSound.SOUND), 0.5, "volume saved")
	var i := AudioServer.get_bus_index(AudioBuses.SFX)
	check(absf(AudioServer.get_bus_volume_db(i) - (-12.04)) < 0.05, "half volume on the SFX bus")
	GameSound.set_volume(GameSound.MUSIC, 2.0)
	check_eq(GameSound.volume(GameSound.MUSIC), 1.0, "volume kept within 0..1")
	for kind in before:
		GameSound.set_on(kind, before[kind][0])
		GameSound.set_volume(kind, before[kind][1])
