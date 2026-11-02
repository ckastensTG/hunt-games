extends TestCase
## AI regression from Lim & Nievergelt, "Computing Tigers and Goats" (2004):
## the goats lose a goat within 10 plies unless their first goat goes on the
## middle point of an edge.
##
## Search setup: capture target = 1 and an all-zero evaluation, so the score
## is either a proven capture or 0. After the goats' first placement (ply 1),
## a depth-9 search covers plies 2-10.
##
## A proof search, but fast enough (~2-3 s) to run on every commit.

const REPRESENTATIVES := {
	"center c3": Vector2(2, 2),
	"diagonal neighbour of center b2": Vector2(1, 1),
	"orthogonal neighbour of center c2": Vector2(2, 1),
	"edge next to a corner b1": Vector2(1, 0),
	"middle of an edge c1": Vector2(2, 0),
}


func test_only_the_edge_middle_opening_is_safe() -> void:
	var rules := HuntRuleSets.bagh_chal_standard().copy_with({"capture_target": 1})
	var zero := HuntEvalWeights.new()
	for prop in ["capture", "hunter_mobility", "hunter_blocked", "threat_hunter_to_move",
			"threat_prey_to_move", "prey_edge_in_placement", "prey_mobility"]:
		zero.set(prop, 0)
	for label in REPRESENTATIVES:
		var s := HuntState.create(rules)
		s.make(PackedInt32Array([HuntState.Kind.PLACE, s.board.point_at(REPRESENTATIVES[label])]))
		var search := HuntSearcher.new(HuntEvaluator.new(zero))
		search.max_depth = 9
		search.run(s)
		var forced := search.is_decisive(search.best_score) and search.best_score > 0
		var expect_forced: bool = label != "middle of an edge c1"
		print("         %s: depth %d, %d nodes, %d ms, forced capture: %s" % [
			label, search.completed_depth, search.nodes, search.elapsed_ms(), forced])
		check_eq(forced, expect_forced, label)
