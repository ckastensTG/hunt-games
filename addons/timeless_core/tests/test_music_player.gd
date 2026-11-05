extends TestCase
## MusicPlayer: every track once before repeats and never twice in a row,
## pauses between tracks, switching sets fades out first, ducking.


func _tracks(n: int) -> Array[AudioStream]:
	var list: Array[AudioStream] = []
	for i in n:
		var w := AudioStreamWAV.new()
		w.data = PackedByteArray([0, 0, 0, 0])
		list.append(w)
	return list


func _player() -> MusicPlayer:
	var m := MusicPlayer.new()
	m.log_plays = true
	return m


## Ends the playing track and waits out the pause.
func _next(m: MusicPlayer) -> void:
	m.track_finished()
	m.step(m.gap_max + 0.1)


func test_shuffle_plays_every_track_without_repeats() -> void:
	var m := _player()
	m.play_set("look", _tracks(3))
	m.step(m.first_gap - 0.1)
	check(m.played.is_empty(), "a short pause before the first track")
	m.step(0.2)
	check_eq(m.state, MusicPlayer.State.PLAYING, "then the first track")
	for i in 29:
		_next(m)
	check_eq(m.played.size(), 30, "one track after another")
	for i in range(1, m.played.size()):
		check(m.played[i] != m.played[i - 1], "never the same track twice in a row")
	for start in range(0, 30, 3):
		var group := {}
		for i in range(start, start + 3):
			group[m.played[i]] = true
		check_eq(group.size(), 3, "each round of three plays every track once")
	m.free()


func test_pause_between_tracks() -> void:
	var m := _player()
	m.play_set("look", _tracks(2))
	m.step(m.first_gap + 0.1)
	m.track_finished()
	check_eq(m.state, MusicPlayer.State.WAITING, "a pause after a track")
	m.step(m.gap_min - 0.1)
	check_eq(m.played.size(), 1, "no new track before the shortest pause")
	m.step(m.gap_max - m.gap_min + 0.2)
	check_eq(m.played.size(), 2, "the next track by the longest pause")
	m.free()


func test_switching_sets_fades_out_first() -> void:
	var m := _player()
	m.play_set("stone", _tracks(3))
	m.step(m.first_gap + 0.1)
	m.step(m.fade_in + 0.1)
	check(is_equal_approx(m.gain(), 1.0), "faded in")
	m.play_set("stone", _tracks(3))
	check_eq(m.state, MusicPlayer.State.PLAYING, "the same set again changes nothing")
	m.play_set("brass", _tracks(3))
	check_eq(m.state, MusicPlayer.State.LEAVING, "another set: the track fades out")
	m.step(m.fade_out / 2.0)
	check(m.gain() > 0.3 and m.gain() < 0.7, "halfway through the fade")
	m.step(m.fade_out / 2.0 + 0.05)
	check_eq(m.state, MusicPlayer.State.WAITING, "faded out, then a short pause")
	m.step(MusicPlayer.SWITCH_GAP + 0.05)
	check(m.played[-1].begins_with("brass#"), "then the new set's first track")
	m.play_set("", [] as Array[AudioStream])
	m.step(m.fade_out + 0.1)
	check_eq(m.state, MusicPlayer.State.IDLE, "no tracks: silence")
	m.free()


func test_duck_under_a_cue() -> void:
	var m := _player()
	m.play_set("look", _tracks(1))
	m.step(m.first_gap + 0.1)
	m.step(m.fade_in + 0.1)
	m.duck(2.0)
	m.step(m.duck_fade + 0.05)
	check(m.gain() < 0.01, "silent under the cue")
	m.step(2.0 - m.duck_fade)
	m.step(m.duck_return / 2.0)
	check(m.gain() > 0.3 and m.gain() < 0.7, "coming back")
	m.step(m.duck_return / 2.0 + 0.1)
	check(is_equal_approx(m.gain(), 1.0), "back to full")
	m.free()


func test_missing_folder_is_silent() -> void:
	var m := _player()
	m.play_folder("res://no/such/music")
	check_eq(m.track_count(), 0, "no tracks")
	check_eq(m.state, MusicPlayer.State.IDLE, "nothing to play")
	m.free()
