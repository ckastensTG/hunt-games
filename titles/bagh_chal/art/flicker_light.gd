extends OmniLight3D
## A butter-lamp light: energy and position wobble like a small flame.

@export var base_energy := 1.0
@export var seed := 0.0

var _t := 0.0
var _origin := Vector3.ZERO


func _ready() -> void:
	_origin = position
	_t = seed * 17.0


func _process(delta: float) -> void:
	_t += delta * 7.0
	var f := 0.82 + 0.1 * sin(_t) + 0.06 * sin(_t * 2.3 + 1.0) + 0.04 * sin(_t * 5.1)
	light_energy = base_energy * f
	position = _origin + Vector3(sin(_t * 0.9) * 0.02, 0.0, cos(_t * 1.3) * 0.02)
