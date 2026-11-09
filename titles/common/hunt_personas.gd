class_name HuntPersonas
extends RefCounted
## The AI levels, weakest first (framework §4.4), and how each one plays: in
## Bagh Chal each level is a person (HuntOpponents: Sanu, Maya Didi, Hari Dai,
## Hajurba) with a style of their own on top of the level's strength.
## tools/persona_ladder.gd measures them.
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

## Each level's style (AIPersona's knobs, set over SPECS). Christopher,
## 2026-11-08: "Have each player play differently."
const STYLES := [
	# Sanu: just learned the game, plays fast and loves the tigers. He takes
	# every capture he's offered and chases threats with his tigers; his goats
	# don't watch for danger and don't know to start on the edges.
	{
		"greedy_captures": true, "think_ms": 250,
		"hunter_style": {"capture": 1.4, "threat_hunter_to_move": 1.5, "hunter_mobility": 0.5},
		"prey_style": {"threat_prey_to_move": 0.4, "prey_edge_in_placement": 0.0},
	},
	# Maya Didi: steady, when she's looking. Small slips less often than a
	# plain Apprentice, and now and then a bigger one, after a longer pause
	# (she was pouring tea).
	{
		"candidate_window": 80, "mistake_rate": 0.15, "lapse_rate": 0.12, "lapse_window": 400,
		"think_ms": 800, "lapse_pause_ms": 1500,
	},
	# Hari Dai: patient, and fond of a trap. His goats squeeze the tigers'
	# room and keep themselves safe; his tigers keep their lines open and set
	# up double threats. He takes his time.
	{
		"think_ms": 1300,
		"hunter_style": {"threat_prey_to_move": 1.8, "hunter_mobility": 1.3},
		"prey_style": {"hunter_blocked": 2.2, "hunter_mobility": 1.6, "threat_prey_to_move": 1.4},
	},
	# Hajurba: the strongest, unhurried, and not the same game twice: among
	# equally good moves he picks a different one from game to game.
	{"vary_ties": true, "think_ms": 1600},
]


## Every level with its style, weakest first.
static func all() -> Array[AIPersona]:
	var out: Array[AIPersona] = []
	for i in SPECS.size():
		out.append(styled(i))
	return out


## Level `i` with its style.
static func styled(i: int) -> AIPersona:
	var p := make(SPECS[i])
	var style: Dictionary = STYLES[i]
	for key in style:
		p.set(key, style[key])
	return p


## Level `i` without a style: the strength alone (tools that need a fixed,
## repeatable opponent: store screenshots, style frames).
static func plain(i: int) -> AIPersona:
	return make(SPECS[i])


static func make(spec: Array) -> AIPersona:
	var p := AIPersona.new()
	p.id = spec[0]
	p.max_depth = spec[1]
	p.time_limit_ms = spec[2]
	p.candidate_window = spec[3]
	p.mistake_rate = spec[4]
	p.temperature = spec[5]
	return p
