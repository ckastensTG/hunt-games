class_name HuntRuleSets
extends RefCounted
## The four v1 rule sets (rules doc §6) and their AI evaluation weights.

const BAGH_CHAL_STANDARD := "bagh_chal_standard"
const BAGH_CHAL_PARLETT := "bagh_chal_parlett_1976"
const ADUGO := "jogo_da_onca_adugo"
const KOMIKAN := "jogo_da_onca_komikan"

const ALL := [BAGH_CHAL_STANDARD, BAGH_CHAL_PARLETT, ADUGO, KOMIKAN]


static func by_id(id: String) -> HuntRuleSet:
	match id:
		BAGH_CHAL_STANDARD:
			return bagh_chal_standard()
		BAGH_CHAL_PARLETT:
			return bagh_chal_parlett()
		ADUGO:
			return adugo()
		KOMIKAN:
			return komikan()
	push_error("unknown rule set %s" % id)
	return null


## Bagh Chal, Standard (rules §2.1).
static func bagh_chal_standard() -> HuntRuleSet:
	var board := HuntBoards.alquerque_5x5()
	var r := HuntRuleSet.new()
	r.id = BAGH_CHAL_STANDARD
	r.board = board
	r.hunter_start = _ids(board, [Vector2(0, 0), Vector2(4, 0), Vector2(0, 4), Vector2(4, 4)])
	r.prey_reserve = 20
	r.first_player = HuntRuleSet.PREY
	r.multi_jump = false
	r.capture_target = 5
	r.repetition = HuntRuleSet.Repetition.FORBID
	r.no_capture_limit_plies = 100
	r.prey_stuck_result = HuntRuleSet.StuckResult.DRAW
	r.name_key = "RULESET_BAGH_CHAL_STANDARD"
	r.source_key = "SOURCE_BAGH_CHAL_STANDARD"
	return r


## Bagh Chal, Parlett 1976: tigers must capture all 20 goats (rules §2.2).
static func bagh_chal_parlett() -> HuntRuleSet:
	var r := bagh_chal_standard()
	r.id = BAGH_CHAL_PARLETT
	r.capture_target = 20
	r.name_key = "RULESET_BAGH_CHAL_PARLETT"
	r.source_key = "SOURCE_PARLETT_1976"
	return r


## Jogo da Onça, Adugo (rules §3.2).
static func adugo() -> HuntRuleSet:
	var board := HuntBoards.adugo_31()
	var r := HuntRuleSet.new()
	r.id = ADUGO
	r.board = board
	r.hunter_start = _ids(board, [Vector2(2, 2)])
	var dogs: Array = []
	for y in 2:
		for x in 5:
			dogs.append(Vector2(x, y))
	dogs.append_array([Vector2(0, 2), Vector2(1, 2), Vector2(3, 2), Vector2(4, 2)])
	r.prey_start = _ids(board, dogs)
	r.first_player = HuntRuleSet.HUNTER
	r.multi_jump = true
	r.capture_target = 5
	r.repetition = HuntRuleSet.Repetition.THREEFOLD_DRAW
	r.no_capture_limit_plies = 100
	r.prey_stuck_result = HuntRuleSet.StuckResult.DRAW
	r.name_key = "RULESET_ADUGO"
	r.source_key = "SOURCE_ADUGO"
	return r


## Jogo da Onça, Komikan (rules §4.2): the Mátus board and setup, with the
## movement and win of the modern Mapuche Trapial-Kuzen rules (decided by
## Christopher 2026-11-03): dogs step in any direction and the puma wins at
## three captures. Mátus's forward-only dogs can never trap a puma that stays
## in the tower (tools/komikan_tower/). Draws as in Adugo [ENGINE RULE]. Who
## moves first is an option; the puma moves first by default.
static func komikan(first_player := HuntRuleSet.HUNTER) -> HuntRuleSet:
	var board := HuntBoards.komikan_matus()
	var r := HuntRuleSet.new()
	r.id = KOMIKAN
	r.board = board
	r.hunter_start = _ids(board, [Vector2(2, 5.5)])
	var dogs: Array = []
	for y in 2:
		for x in 5:
			dogs.append(Vector2(x, y))
	dogs.append_array([Vector2(0, 2), Vector2(4, 2)])
	r.prey_start = _ids(board, dogs)
	r.first_player = first_player
	r.multi_jump = true
	r.capture_target = 3
	r.repetition = HuntRuleSet.Repetition.THREEFOLD_DRAW
	r.no_capture_limit_plies = 100
	r.prey_stuck_result = HuntRuleSet.StuckResult.DRAW
	r.name_key = "RULESET_KOMIKAN"
	r.source_key = "SOURCE_KOMIKAN"
	return r


## Starting AI weights per rule set. Tuning happens in self-play.
static func weights_for(rule_set: HuntRuleSet) -> HuntEvalWeights:
	var w := HuntEvalWeights.new()
	match rule_set.id:
		BAGH_CHAL_STANDARD, BAGH_CHAL_PARLETT:
			pass  # defaults were tuned with Bagh Chal in mind
		ADUGO:
			w.prey_edge_in_placement = 0
			w.hunter_blocked = 0  # one jaguar: blocked means lost, handled as terminal
			w.hunter_mobility = 18
		KOMIKAN:
			w.prey_edge_in_placement = 0
			w.hunter_blocked = 0
			w.hunter_mobility = 18
			w.prey_mobility = 12
	return w


static func _ids(board: BoardDef, positions: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in positions:
		var id := board.point_at(p)
		assert(id >= 0, "no point at %s on %s" % [p, board.id])
		out.append(id)
	return out
