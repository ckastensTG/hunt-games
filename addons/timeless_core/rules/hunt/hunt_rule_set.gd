class_name HuntRuleSet
extends Resource
## Parameters for one hunt-game variant (Bagh Chal, Adugo, Komikan, ...).
## The fields mirror the rules doc, §6 ("Engine parameters").

enum Repetition {
	NONE,            ## positions may repeat freely
	FORBID,          ## a move may not recreate an earlier position (Bagh Chal)
	THREEFOLD_DRAW,  ## the third occurrence of a position is a draw
}

enum StuckResult {
	DRAW,        ## prey with no legal move: draw (engine rule)
	HUNTER_WIN,  ## prey with no legal move lose (Komikan's forward-only dogs)
}

const HUNTER := 1
const PREY := 2

@export var id: String = ""
@export var version: int = 1
@export var board: BoardDef
## Hunter start points.
@export var hunter_start: PackedInt32Array = PackedInt32Array()
## Prey already on the board at the start.
@export var prey_start: PackedInt32Array = PackedInt32Array()
## Prey waiting to be placed (Bagh Chal's placement phase). Prey on the board
## can't move while any remain in reserve.
@export var prey_reserve: int = 0
@export var first_player: int = PREY
## Hunters may chain jumps (and stop after any jump).
@export var multi_jump: bool = false
@export var forced_capture: bool = false
## Prey may only step to a point of higher rank.
@export var prey_forward_only: bool = false
## With prey_forward_only: prey may also step sideways (to a point of equal
## rank), but never back. One reading of Komikan's "the dogs must always
## advance"; used for balance tests.
@export var prey_sideways: bool = false
@export var capture_target: int = 5
@export var repetition: Repetition = Repetition.NONE
## Draw after this many plies without a capture in the movement phase (0 = off).
@export var no_capture_limit_plies: int = 0
@export var prey_stuck_result: StuckResult = StuckResult.DRAW
## Localization keys.
@export var name_key: String = ""
@export var source_key: String = ""


func prey_total() -> int:
	return prey_start.size() + prey_reserve


## Stable fingerprint of everything that affects play. Goes into saves and the
## LAN handshake so mismatched rules are caught up front.
func fingerprint() -> int:
	var parts: Array = [
		id, version, board.id if board else "", hunter_start, prey_start, prey_reserve,
		first_player, multi_jump, forced_capture, prey_forward_only, prey_sideways, capture_target,
		repetition, no_capture_limit_plies, prey_stuck_result,
	]
	return hash(var_to_str(parts))


func copy_with(overrides: Dictionary) -> HuntRuleSet:
	var r: HuntRuleSet = duplicate()
	for key in overrides:
		r.set(key, overrides[key])
	return r
