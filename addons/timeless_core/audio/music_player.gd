class_name MusicPlayer
extends Node
## Background music on the Music bus. Plays a set of tracks one after another
## in a shuffled order (every track once before any repeats, never the same
## track twice in a row), with a pause between tracks. Switching to another
## set (another look) fades the current track out and starts the new set;
## duck() fades the music out under a short cue (an end-of-game sting) and
## brings it back. The music pauses while the Music bus is muted.
##
## Tracks are found by name: `<folder>/track_<n>.ogg` (n = 1, 2, …). They
## play once each (no looping), so a track's own ending is heard.

const MAX_TRACKS := 16
## Between switching sets: the old track has faded out, the new one waits this long.
const SWITCH_GAP := 1.0

enum State { IDLE, WAITING, PLAYING, LEAVING }

## Silence before the first track, in seconds.
var first_gap := 1.5
## Silence between tracks, picked at random in this range.
var gap_min := 6.0
var gap_max := 14.0
## Fades, in seconds: in at the start of a track, out when the set changes,
## down under a cue and back up after it.
var fade_in := 0.5
var fade_out := 1.5
var duck_fade := 0.4
var duck_return := 3.0
## Every track started, as "<set>#<n>", for tests.
var log_plays := false
var played: Array[String] = []

var state := State.IDLE

var _set_id := ""
var _tracks: Array[AudioStream] = []
var _bag: Array[int] = []
var _current := -1
var _last := -1
var _wait := 0.0
var _level := 0.0     # the track's fade, 0..1
var _duck := 1.0      # the duck, 0..1
var _duck_hold := 0.0
var _player := AudioStreamPlayer.new()
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "MusicPlayer"
	_rng.randomize()
	_player.finished.connect(track_finished)
	add_child(_player)


func _ready() -> void:
	AudioBuses.ensure()
	_player.bus = AudioBuses.MUSIC


func _process(delta: float) -> void:
	step(delta)


## Plays the tracks in `folder` (`track_1.ogg`, `track_2.ogg` …). The same
## folder again changes nothing; "" or a folder without tracks fades out.
func play_folder(folder: String) -> void:
	if folder == _set_id:
		return
	var list: Array[AudioStream] = []
	if folder != "":
		for n in range(1, MAX_TRACKS + 1):
			var path := "%s/track_%d.ogg" % [folder, n]
			if not ResourceLoader.exists(path):
				break
			list.append(load(path))
	play_set(folder, list)


## Plays `tracks` as the set called `id` (tests, or music made in code).
func play_set(id: String, tracks: Array[AudioStream]) -> void:
	if id == _set_id:
		return
	_set_id = id
	_tracks = tracks
	for t in _tracks:
		if t is AudioStreamOggVorbis:
			t.loop = false
	_bag.clear()
	_last = -1
	match state:
		State.PLAYING:
			state = State.LEAVING
		State.LEAVING:
			pass
		State.IDLE:
			if not _tracks.is_empty():
				state = State.WAITING
				_wait = first_gap
		State.WAITING:
			if _tracks.is_empty():
				state = State.IDLE
			else:
				_wait = minf(_wait, SWITCH_GAP)


## Fades the music out for `seconds` (a sting plays over the silence), then
## brings it back.
func duck(seconds: float) -> void:
	_duck_hold = maxf(_duck_hold, seconds)


func stop() -> void:
	_player.stop()
	_player.stream = null
	_current = -1
	_level = 0.0
	state = State.IDLE if _tracks.is_empty() else State.WAITING
	_wait = gap_max


func set_id() -> String:
	return _set_id


func track_count() -> int:
	return _tracks.size()


## The track playing (0-based), or -1.
func current_track() -> int:
	return _current if state == State.PLAYING or state == State.LEAVING else -1


## True while the music is held down under a cue.
func is_ducked() -> bool:
	return _duck_hold > 0.0


## The music's own gain, 0..1 (fades and duck; the bus volume comes on top).
func gain() -> float:
	return _level * _duck


## Called when a track has played to its end (the player's `finished`).
func track_finished() -> void:
	if state == State.PLAYING:
		state = State.WAITING
		_wait = _rng.randf_range(gap_min, gap_max)
		_current = -1


## Advances fades and pauses by `delta` seconds (called every frame).
func step(delta: float) -> void:
	if _duck_hold > 0.0:
		_duck_hold -= delta
		_duck = maxf(0.0, _duck - delta / duck_fade)
	else:
		_duck = minf(1.0, _duck + delta / duck_return)
	match state:
		State.WAITING:
			_wait -= delta
			if _wait <= 0.0:
				_start_next()
		State.PLAYING:
			_level = minf(1.0, _level + delta / fade_in)
		State.LEAVING:
			_level = maxf(0.0, _level - delta / fade_out)
			if _level <= 0.0:
				_player.stop()
				_current = -1
				if _tracks.is_empty():
					state = State.IDLE
				else:
					state = State.WAITING
					_wait = SWITCH_GAP
	_player.volume_db = linear_to_db(maxf(gain(), 0.0001))
	var audible := AudioBuses.is_audible(AudioBuses.MUSIC)
	if _player.stream_paused == audible:
		_player.stream_paused = not audible


func _start_next() -> void:
	if _tracks.is_empty():
		state = State.IDLE
		return
	if _bag.is_empty():
		for i in _tracks.size():
			_bag.append(i)
		for i in range(_bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var t := _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = t
		if _bag.size() > 1 and _bag[0] == _last:
			var t := _bag[0]
			_bag[0] = _bag[_bag.size() - 1]
			_bag[_bag.size() - 1] = t
	_current = _bag.pop_front()
	_last = _current
	_level = 0.0
	state = State.PLAYING
	if log_plays:
		played.append("%s#%d" % [_set_id, _current + 1])
	_player.stream = _tracks[_current]
	if _player.is_inside_tree():
		_player.play()


## Nothing keeps playing once the scene is gone (or the game quits).
func _exit_tree() -> void:
	_player.stop()
	_player.stream = null
