class_name HuntTutorials
extends RefCounted
## "How to play": a scripted walkthrough per rule set. Each step shows a
## position, highlights points, plays a few moves on the board and explains
## one rule in a sentence or three.
##
## The rules engine plays every scripted move (build() fails on an illegal
## one) and tests/test_tutorials.gd checks each step's outcome, so a
## walkthrough can't teach a rule the game doesn't follow.
##
## Step keys:
##   title, text   English source text, marked with N_() for translation
##   setup         optional: {hunters: [...], prey: [...], reserve, captured,
##                 side: "hunter" | "prey"}, or "start" for the opening
##                 position. Without it the step continues from the last one.
##   marks         optional: [[point, "select" | "step" | "capture" | "note"],
##                 ...], shown before the moves play ("note": look here)
##   moves         optional: [["place", p], ["step", from, to],
##                 ["jump", from, land, land, ...]]
##   outcome       optional: "hunter_win" | "prey_win", checked by the tests
##
## Points are named like the move list: "c3" is column c, row 3 (row 1 on the
## prey's side). Triangle points can also be written T(h, x): h steps below
## the triangle's apex, x across (rules doc §4.2).


static func N_(text: String) -> String:
	return text


## The steps for a rule set, resolved against its board: positions as
## HuntStates (one per step, before its moves) and moves as engine moves.
static func build(rules: HuntRuleSet) -> Array[Dictionary]:
	var script := steps_for(rules.id)
	var out: Array[Dictionary] = []
	var state := HuntState.create(rules)
	for raw in script:
		var step: Dictionary = raw.duplicate(true)
		if raw.has("setup"):
			state = HuntState.create(rules)
			if raw.setup is Dictionary:
				var s: Dictionary = raw.setup
				state.set_position(points(rules.board, s.get("hunters", [])),
					points(rules.board, s.get("prey", [])), s.get("reserve", 0), s.get("captured", 0),
					HuntState.HUNTER if s.get("side", "hunter") == "hunter" else HuntState.PREY)
		step["start"] = state.clone()
		var marks: Array = []
		for m in raw.get("marks", []):
			marks.append([point(rules.board, m[0]), m[1]])
		step["marks"] = marks
		var moves: Array[PackedInt32Array] = []
		for spec in raw.get("moves", []):
			var mv := resolve_move(state, spec)
			if mv.is_empty():
				push_error("Tutorial %s, step \"%s\": %s isn't a legal move" % [rules.id, raw.title, spec])
				break
			state.make(mv)
			moves.append(mv)
		step["moves"] = moves
		step["end"] = state.clone()
		out.append(step)
	return out


## Finds the legal move a spec describes, or an empty array.
static func resolve_move(state: HuntState, spec: Array) -> PackedInt32Array:
	var b := state.board
	var kind: String = spec[0]
	var want := PackedInt32Array()
	for k in range(1, spec.size()):
		want.append(point(b, spec[k]))
	for m in state.legal_moves(false):
		match kind:
			"place":
				if m[0] == HuntState.Kind.PLACE and m[1] == want[0]:
					return m
			"step":
				if m[0] == HuntState.Kind.STEP and m[1] == want[0] and m[2] == want[1]:
					return m
			"jump":
				if m[0] != HuntState.Kind.JUMP or m[1] != want[0] or (m.size() - 2) / 2 != want.size() - 1:
					continue
				var ok := true
				for j in range(1, want.size()):
					if m[1 + j * 2] != want[j]:
						ok = false
						break
				if ok:
					return m
	return PackedInt32Array()


static func points(board: BoardDef, names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in names:
		out.append(point(board, n))
	return out


## "c3" -> the point at column 2, row 2; "T(1.5,-1)" -> Vector2(1, 5.5).
static func point(board: BoardDef, name: String) -> int:
	var pos: Vector2
	if name.begins_with("T("):
		var parts := name.trim_prefix("T(").trim_suffix(")").split(",")
		var h := float(parts[0])
		var x := float(parts[1])
		pos = Vector2(2.0 + x, 4.0 + h)
	else:
		pos = Vector2(name.unicode_at(0) - 97, int(name.substr(1)) - 1)
	var id := board.point_at(pos)
	assert(id >= 0, "no point %s on %s" % [name, board.id])
	return id


static func steps_for(rule_set_id: String) -> Array:
	match rule_set_id:
		HuntRuleSets.BAGH_CHAL_STANDARD:
			return _bagh_chal(false)
		HuntRuleSets.BAGH_CHAL_PARLETT:
			return _bagh_chal(true)
		HuntRuleSets.ADUGO:
			return _adugo()
		HuntRuleSets.KOMIKAN:
			return _komikan()
	return []


# --- Bagh Chal ---------------------------------------------------------------

static func _bagh_chal(parlett: bool) -> Array:
	var corners := ["a1", "e1", "a5", "e5"]
	var steps := [
		{
			"title": N_("Tigers and goats"),
			"text": N_("Four tigers against twenty goats. The tigers start on the corners; the goats start in hand, off the board. The goats move first."),
			"setup": "start",
			"marks": [["a1", "select"], ["e1", "select"], ["a5", "select"], ["e5", "select"]],
		},
		{
			"title": N_("Placing the goats"),
			"text": N_("While goats are left in hand, every goat turn is a placement: one goat onto any empty point. Goats on the board can't move until all twenty are placed. The tigers move in between."),
			"moves": [["place", "c1"], ["step", "a1", "b2"], ["place", "a3"]],
		},
		{
			"title": N_("How a tiger moves"),
			"text": N_("A tiger steps along a line to the next empty point. Diagonals run only through every other point, so some points have eight neighbours and the rest four or fewer."),
			"setup": {"hunters": ["c3", "a5", "e1", "e5"], "prey": ["c1", "a3", "b1"], "reserve": 17, "side": "hunter"},
			"marks": [["c3", "select"], ["b2", "step"], ["c2", "step"], ["d2", "step"], ["b3", "step"],
				["d3", "step"], ["b4", "step"], ["c4", "step"], ["d4", "step"]],
			"moves": [["step", "c3", "d4"]],
		},
		{
			"title": N_("Capturing"),
			"text": N_("A tiger captures by jumping over a goat next to it on a line, onto the empty point just beyond. The goat leaves the board. One goat per jump, and capturing is never compulsory."),
			"setup": {"hunters": ["c3", "a5", "e1", "e5"], "prey": ["c1", "a3", "b1", "c4"], "reserve": 16, "side": "hunter"},
			"marks": [["c3", "select"], ["c5", "capture"]],
			"moves": [["jump", "c3", "c5"]],
		},
		{
			"title": N_("Safety in numbers"),
			"text": N_("A goat with another goat right behind it, or the edge of the board, can't be jumped: the tiger needs an empty point to land on. Goats that stay together are safe."),
			"setup": {"hunters": ["c3", "a5", "e1", "e5"], "prey": ["c1", "a3", "b1", "c4", "c5"], "reserve": 15, "side": "hunter"},
			"marks": [["c3", "select"], ["c4", "note"], ["c5", "note"]],
		},
		{
			"title": N_("Moving the goats"),
			"text": N_("Once all the goats are in play, a goat steps along a line to the next empty point, just as a tiger does. Goats never jump and never capture."),
			"setup": {"hunters": ["b2", "d4", "a5", "e1"],
				"prey": ["a1", "c1", "d1", "a2", "c2", "e2", "a3", "b3", "d3", "a4", "c4", "e4", "b5", "c5", "d5", "e5", "b1"],
				"reserve": 0, "captured": 3, "side": "prey"},
			"marks": [["c2", "select"], ["c3", "step"], ["d2", "step"]],
			"moves": [["step", "c2", "c3"]],
		},
	]
	if parlett:
		steps.append({
			"title": N_("How the tigers win"),
			"text": N_("In Parlett's version the tigers must capture all twenty goats. Everything else is as in the standard game."),
			"setup": {"hunters": ["c3", "a5", "e1", "e5"], "prey": ["c4"], "reserve": 0, "captured": 19, "side": "hunter"},
			"marks": [["c3", "select"], ["c5", "capture"]],
			"moves": [["jump", "c3", "c5"]],
			"outcome": "hunter_win",
		})
	else:
		steps.append({
			"title": N_("How the tigers win"),
			"text": N_("The tigers win by capturing five goats."),
			"setup": {"hunters": ["c3", "a5", "e1", "e5"], "prey": ["c1", "a3", "b1", "c4", "d2", "b4"], "reserve": 10, "captured": 4, "side": "hunter"},
			"marks": [["c3", "select"], ["c5", "capture"]],
			"moves": [["jump", "c3", "c5"]],
			"outcome": "hunter_win",
		})
	steps.append_array([
		{
			"title": N_("How the goats win"),
			"text": N_("The goats win when no tiger can move: every tiger is hemmed in by goats it can't jump."),
			"setup": {"hunters": ["a1", "b1", "a2", "b2"],
				"prey": ["c1", "d1", "a3", "a4", "c2", "d2", "b3", "b4", "c3"], "reserve": 11, "side": "prey"},
			"moves": [["place", "d4"]],
			"outcome": "prey_win",
		},
		{
			# TRANSLATORS: Walkthrough step title: the rules for a drawn game.
			"title": N_("Draws"),
			"text": N_("Once all the goats are placed, no move may bring back a position that has already occurred. The game is a draw if the tigers go 50 moves without capturing, or if every move left would repeat a position."),
			"setup": "start",
			"marks": [["a1", "select"], ["e1", "select"], ["a5", "select"], ["e5", "select"]],
		},
	])
	return steps


# --- Jogo da Onça (Adugo) ----------------------------------------------------

static func _adugo() -> Array:
	return [
		{
			"title": N_("The jaguar and the dogs"),
			"text": N_("One jaguar against fourteen dogs. The jaguar starts in the middle of the board and the dogs fill the far half. The jaguar moves first."),
			"setup": "start",
			"marks": [["c3", "select"]],
		},
		{
			"title": N_("Moving"),
			"text": N_("Each turn, one piece steps along a line to the next empty point, in any direction. The triangle is part of the board, and either side may go in."),
			"marks": [["c3", "select"], ["b4", "step"], ["c4", "step"], ["d4", "step"]],
			"moves": [["step", "c3", "c4"], ["step", "a3", "a4"], ["step", "c4", "c5"]],
		},
		{
			"title": N_("Capturing"),
			"text": N_("The jaguar captures by jumping over a dog next to it on a line, onto the empty point just beyond. The dog leaves the board. Capturing is optional."),
			"setup": {"hunters": ["c3"], "prey": ["a1", "b1", "c1", "d1", "e1", "a2", "b2", "d2", "e2", "c4"], "side": "hunter"},
			"marks": [["c3", "select"], ["c5", "capture"]],
			"moves": [["jump", "c3", "c5"]],
		},
		{
			"title": N_("Chains of captures"),
			"text": N_("After a capture the jaguar may jump again, and again, changing direction as it likes, and it may stop after any jump. No dog can be jumped twice in one turn."),
			"setup": {"hunters": ["a1"], "prey": ["a2", "b3", "c4", "e1", "e2", "d1", "e3"], "side": "hunter"},
			"marks": [["a1", "select"], ["a3", "capture"], ["c3", "capture"], ["c5", "capture"]],
			"moves": [["jump", "a1", "a3", "c3", "c5"]],
		},
		{
			"title": N_("Strength in pairs"),
			"text": N_("Two dogs in a row along a line protect each other: the jaguar has nowhere to land."),
			"setup": {"hunters": ["c3"], "prey": ["a1", "b1", "c1", "d1", "e1", "a2", "b2", "d2", "e2", "c4", "c5"], "side": "hunter"},
			"marks": [["c3", "select"], ["c4", "note"], ["c5", "note"]],
		},
		{
			"title": N_("How the jaguar wins"),
			"text": N_("The jaguar wins by capturing five dogs."),
			"setup": {"hunters": ["c3"], "prey": ["a1", "b1", "c1", "d1", "e1", "a2", "b2", "d2", "c4"], "captured": 4, "side": "hunter"},
			"marks": [["c3", "select"], ["c5", "capture"]],
			"moves": [["jump", "c3", "c5"]],
			"outcome": "hunter_win",
		},
		{
			"title": N_("How the dogs win"),
			"text": N_("The dogs win when the jaguar can't move at all."),
			"setup": {"hunters": ["a1"], "prey": ["a2", "b1", "b2", "a3", "c1", "c4", "d2", "e1", "d4"], "side": "prey"},
			"moves": [["step", "c4", "c3"]],
			"outcome": "prey_win",
		},
		{
			# TRANSLATORS: Walkthrough step title: the rules for a drawn game.
			"title": N_("Draws"),
			"text": N_("If the same position comes up three times, or the jaguar goes 50 moves without capturing, the game is a draw."),
			"setup": "start",
		},
	]


# --- Komikan -----------------------------------------------------------------

static func _komikan() -> Array:
	return [
		{
			"title": N_("The puma and the dogs"),
			# TRANSLATORS: "The tower" is the name of Komikan's triangle in the Spanish sources ("la torre"). Use the ordinary word for tower.
			"text": N_("Komikan is a Mapuche hunting game. The puma starts inside the tower, the triangle, and twelve dogs wait at the far end. The puma moves first."),
			"setup": "start",
			"marks": [["T(1.5,0)", "select"]],
		},
		{
			"title": N_("The puma"),
			"text": N_("The puma steps along any line, in any direction, forward or back."),
			"marks": [["T(1.5,0)", "select"], ["T(1,0)", "step"], ["T(1.5,-1)", "step"], ["T(1.5,1)", "step"], ["T(2,0)", "step"]],
			"moves": [["step", "T(1.5,0)", "T(1,0)"]],
		},
		{
			"title": N_("Moving the dogs"),
			"text": N_("A dog steps the same way: along any line to the next empty point, forward, sideways or back. Only the puma can jump."),
			"setup": {"hunters": ["T(1.5,0)"],
				"prey": ["a1", "b1", "c1", "d1", "e1", "a2", "b2", "d2", "e2", "a3", "e3", "c3"], "side": "prey"},
			"marks": [["c3", "select"], ["c2", "step"], ["b3", "step"], ["d3", "step"], ["b4", "step"], ["c4", "step"], ["d4", "step"]],
			"moves": [["step", "c3", "c2"]],
		},
		{
			"title": N_("Capturing"),
			"text": N_("The puma captures by jumping over a lone dog onto the empty point beyond. It may jump again and again, changing direction, and stop after any jump. Two dogs in a row protect each other."),
			"setup": {"hunters": ["a1"], "prey": ["a2", "b3", "c4", "d2", "e2", "d3", "e3", "d4", "e4", "b5", "d5", "e5"], "side": "hunter"},
			"marks": [["a1", "select"], ["a3", "capture"], ["c3", "capture"]],
			"moves": [["jump", "a1", "a3", "c3"]],
		},
		{
			"title": N_("How the dogs win"),
			"text": N_("The dogs win by hemming the puma in so that it can't move."),
			"setup": {"hunters": ["T(2,-2)"],
				"prey": ["T(1.5,-1.5)", "T(1,-1)", "T(2,0)", "T(1.5,-1)", "a4", "b4", "c4", "d4", "e4", "b5", "d5", "c5"],
				"side": "prey"},
			"moves": [["step", "T(1.5,-1)", "T(2,-1)"]],
			"outcome": "prey_win",
		},
		{
			"title": N_("How the puma wins"),
			"text": N_("The puma wins as soon as it has eaten three dogs."),
			"setup": {"hunters": ["c3"], "prey": ["c4", "a1", "b1", "d1", "e1", "a2", "e2", "b2", "d2", "a3"],
				"captured": 2, "side": "hunter"},
			"marks": [["c3", "select"], ["c5", "capture"]],
			"moves": [["jump", "c3", "c5"]],
			"outcome": "hunter_win",
		},
		{
			# TRANSLATORS: Walkthrough step title: the rules for a drawn game.
			"title": N_("Draws"),
			"text": N_("If the same position comes up three times, or the puma goes 50 moves without capturing, the game is a draw."),
			"setup": "start",
		},
		{
			"title": N_("A reconstruction"),
			# TRANSLATORS: Trapial-Kuzen is the name of a modern Mapuche version of Komikan (Argentina); keep it as is.
			"text": N_("In the accounts written down a century ago, the dogs may only go forward, and then a puma that stays in the tower can never be caught. Here the dogs move and the puma wins as in Trapial-Kuzen, a modern Mapuche version of the game. The tower is ordinary board, and the puma moves first unless you change it in the settings."),
			"setup": "start",
		},
	]
