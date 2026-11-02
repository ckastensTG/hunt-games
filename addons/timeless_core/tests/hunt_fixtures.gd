class_name HuntFixtures
extends RefCounted
## Small builders shared by the core tests. Positions are Vector2(x = column, y = row).

static var _alq: BoardDef


static func alquerque() -> BoardDef:
	if _alq == null:
		var b := BoardBuilder.new("test_alquerque_5x5")
		b.add_alquerque(5, 5)
		_alq = b.finish()
	return _alq


static func rules(board: BoardDef, hunters: Array, prey: Array, opts := {}) -> HuntRuleSet:
	var r := HuntRuleSet.new()
	r.id = "test"
	r.board = board
	var hs := PackedInt32Array()
	for p in hunters:
		hs.append(board.point_at(p))
	var ps := PackedInt32Array()
	for p in prey:
		ps.append(board.point_at(p))
	r.hunter_start = hs
	r.prey_start = ps
	r.prey_reserve = 0
	r.first_player = HuntRuleSet.HUNTER
	r.capture_target = 99
	for k in opts:
		r.set(k, opts[k])
	return r


static func state(board: BoardDef, hunters: Array, prey: Array, opts := {}) -> HuntState:
	return HuntState.create(rules(board, hunters, prey, opts))


## Bagh-Chal-like setup on the test board.
static func tigers_and_goats(opts := {}) -> HuntRuleSet:
	var base := {
		"prey_reserve": 20, "first_player": HuntRuleSet.PREY, "capture_target": 5,
		"repetition": HuntRuleSet.Repetition.FORBID, "no_capture_limit_plies": 100,
	}
	base.merge(opts, true)
	return rules(alquerque(), [Vector2(0, 0), Vector2(4, 0), Vector2(0, 4), Vector2(4, 4)], [], base)


static func move(s: HuntState, kind: int, pts: Array) -> PackedInt32Array:
	var m := PackedInt32Array([kind])
	for p in pts:
		m.append(s.board.point_at(p))
	return m
