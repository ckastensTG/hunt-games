class_name FrameTimer
extends RefCounted
## Collects frame times over a window, for automatic graphics settings and
## the performance overlay. Frames longer than `hitch` (loading, a shader
## compiling once) are counted apart and kept out of the averages, so a
## one-off stall doesn't read as a slow device.

var hitch := 0.25
var hitches := 0

var _times := PackedFloat32Array()
var _total := 0.0


## Adds one frame's `delta` (seconds).
func add(delta: float) -> void:
	if delta > hitch:
		hitches += 1
		return
	_times.append(delta)
	_total += delta


func clear() -> void:
	_times.clear()
	_total = 0.0
	hitches = 0


func count() -> int:
	return _times.size()


## Seconds of frames collected (hitches left out).
func duration() -> float:
	return _total


func mean_ms() -> float:
	return 0.0 if _times.is_empty() else 1000.0 * _total / _times.size()


## The `p`th percentile frame time (p from 0 to 1) in ms: 0.9 is all but the
## slowest tenth.
func percentile_ms(p: float) -> float:
	if _times.is_empty():
		return 0.0
	var sorted := _times.duplicate()
	sorted.sort()
	return 1000.0 * sorted[clampi(int(round(p * (sorted.size() - 1))), 0, sorted.size() - 1)]


func fps() -> float:
	return 0.0 if _total <= 0.0 else _times.size() / _total
