class_name AIDriver
extends RefCounted
## Runs one AI move on a worker thread (framework §4.2): start() searches a
## copy of the position, poll() hands back the move once it's ready, cancel()
## stops it (undo, resign, leaving the game).

var _task := -1
var _cancel := false
var _result := PackedInt32Array()


func start(state: HuntState, persona: AIPersona, evaluator: HuntEvaluator, seed_value: int) -> void:
	cancel()
	_cancel = false
	_result = PackedInt32Array()
	var snapshot := state.clone()
	_task = WorkerThreadPool.add_task(_work.bind(persona, evaluator, snapshot, seed_value), false, "AI move")


func is_thinking() -> bool:
	return _task >= 0


## The chosen move once the search is done, else an empty array.
func poll() -> PackedInt32Array:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return PackedInt32Array()
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if _cancel:
		return PackedInt32Array()
	return _result


func cancel() -> void:
	if _task >= 0:
		_cancel = true
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_cancel = false


## Blocking version, for tools and tests.
static func choose_now(state: HuntState, persona: AIPersona, evaluator: HuntEvaluator, seed_value: int) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return persona.choose(state.clone(), evaluator, rng)


func _work(persona: AIPersona, evaluator: HuntEvaluator, snapshot: HuntState, seed_value: int) -> void:
	var search := persona.make_searcher(evaluator)
	search.begin(snapshot)
	while not search.step(4000):
		if _cancel:
			search.cancel()
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_result = persona.pick(search, rng)
