class_name SfxPlayer
extends Node
## Plays short sounds by event name ("place", "capture", "win" …) on the SFX
## bus. Each event can have several takes; a take is picked at random (never
## the same one twice in a row) and its pitch and level vary a little, so
## repeated moves don't sound stamped.
##
## Sounds are found by name: `<folder>/<event>_<n>.ogg` (n = 1, 2, …) or
## `<folder>/<event>.ogg`. A missing event is simply silent.

## How many sounds can overlap (a capture rings on under the next move).
const VOICES := 6
const MAX_TAKES := 8

## Random pitch change per play, as a ratio (0.03 = up to 3% up or down).
var pitch_jitter := 0.03
## Random level change per play, in dB.
var volume_jitter_db := 1.0
## Every play, for tests: [event, pitch_scale].
var log_plays := false
var played: Array = []

var _streams := {}      # event -> Array[AudioStream]
var _last := {}         # event -> index of the take played last
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "SfxPlayer"
	_rng.randomize()


func _ready() -> void:
	AudioBuses.ensure()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = AudioBuses.SFX
		add_child(p)
		_voices.append(p)


## Loads `events` from `folder`, replacing what those events had. An empty
## folder clears them.
func load_events(folder: String, events: Array) -> void:
	for event in events:
		var takes: Array[AudioStream] = []
		if folder != "":
			var single := "%s/%s.ogg" % [folder, event]
			if ResourceLoader.exists(single):
				takes.append(load(single))
			for n in range(1, MAX_TAKES + 1):
				var path := "%s/%s_%d.ogg" % [folder, event, n]
				if not ResourceLoader.exists(path):
					break
				takes.append(load(path))
		_streams[event] = takes
		_last.erase(event)


## Adds one take for `event` (tests, or sounds made in code).
func add_take(event: String, stream: AudioStream) -> void:
	if not _streams.has(event):
		_streams[event] = [] as Array[AudioStream]
	_streams[event].append(stream)


func has_event(event: String) -> bool:
	return not _streams.get(event, []).is_empty()


func take_count(event: String) -> int:
	return _streams.get(event, []).size()


## Plays a take of `event`. `pitch` scales the pitch on top of the jitter
## (below 1 for a heavier piece); `volume_db` adds to the level. `vary` false
## plays it exactly as made (music: a detuned sting would sound wrong).
func play(event: String, pitch := 1.0, volume_db := 0.0, vary := true) -> void:
	var takes: Array = _streams.get(event, [])
	if takes.is_empty():
		return
	var i := _rng.randi_range(0, takes.size() - 1)
	if takes.size() > 1 and i == _last.get(event, -1):
		i = (i + 1 + _rng.randi_range(0, takes.size() - 2)) % takes.size()
	_last[event] = i
	var scale := pitch * (1.0 + (_rng.randf_range(-pitch_jitter, pitch_jitter) if vary else 0.0))
	if log_plays:
		played.append([event, scale])
	if _voices.is_empty():
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = takes[i]
	voice.pitch_scale = scale
	voice.volume_db = volume_db + (_rng.randf_range(-volume_jitter_db, volume_jitter_db) if vary else 0.0)
	voice.play()


## The take index played last for `event` (-1 if none), for tests.
func last_take(event: String) -> int:
	return _last.get(event, -1)


func stop_all() -> void:
	for v in _voices:
		v.stop()
		v.stream = null


## Nothing keeps playing once the board is gone (or the game quits).
func _exit_tree() -> void:
	stop_all()
