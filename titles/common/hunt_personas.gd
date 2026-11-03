class_name HuntPersonas
extends RefCounted
## The AI levels offered in the greybox, weakest first (framework §4.4). The
## named characters will replace these; tools/persona_ladder.gd measures them.
##
## Each level: search depth, time limit per move (0 = none), and the mistake
## model (AIPersona): how far below the best a move may score, how often the
## level picks among those moves, and how evenly.

const NOVICE := 0
const APPRENTICE := 1
const ADEPT := 2
const MASTER := 3

const SPECS := [
	# id, max_depth, time_limit_ms, candidate_window, mistake_rate, temperature
	["novice", 2, 0, 400, 0.6, 120.0],
	["apprentice", 3, 0, 200, 0.35, 80.0],
	["adept", 5, 1500, 80, 0.15, 40.0],
	["master", 8, 2500, 0, 0.0, 1.0],
]


static func all() -> Array[AIPersona]:
	var out: Array[AIPersona] = []
	for spec in SPECS:
		out.append(make(spec))
	return out


static func make(spec: Array) -> AIPersona:
	var p := AIPersona.new()
	p.id = spec[0]
	p.max_depth = spec[1]
	p.time_limit_ms = spec[2]
	p.candidate_window = spec[3]
	p.mistake_rate = spec[4]
	p.temperature = spec[5]
	return p
