class_name HuntEvalWeights
extends Resource
## Tunable weights for HuntEvaluator. Each title ships its own resource.
## Scores are from the hunter's point of view; the evaluator flips the sign
## when the prey side is to move.

## Per prey captured.
@export var capture: int = 1000
## Per available hunter move (step or jump).
@export var hunter_mobility: int = 10
## Per hunter with no move at all (Bagh Chal: one blocked tiger is progress).
@export var hunter_blocked: int = 120
## Per prey that a hunter could jump right now, when the hunter is to move.
@export var threat_hunter_to_move: int = 350
## Same, when the prey side is to move and can still defend.
@export var threat_prey_to_move: int = 90
## Per prey on an edge point while prey remain in reserve (Lim & Nievergelt:
## goats should stay on the border during placement). Counts for the prey.
@export var prey_edge_in_placement: int = 30
## Per prey move available. Matters for forward-only prey (Komikan), whose
## moves run out.
@export var prey_mobility: int = 3
## Per empty point the hunters can reach by steps without passing a prey
## (their territory). Trapping games: the prey win by shrinking it. 0 = off.
@export var hunter_territory: int = 0
## Per prey the hunters could jump from a point they can reach by steps
## (their territory, or where they stand), the point beyond it being empty:
## gaps in the prey's wall. Trapping games: the prey advance as a solid
## front. Counts for the hunter. 0 = off.
@export var prey_exposed: int = 0
## When the prey side is to move and the hunters threaten two or more prey
## at once (one move rarely saves both). Counts for the hunter. 0 = off.
@export var double_threat: int = 0
## Score positions relative to the rule set's starting position, so an even
## game scores about 0 and the side that is ahead is the one scoring above it.
## Needed with contempt (AIPersona.contempt): otherwise the terms that always
## favour the hunter (mobility, territory) make every draw look good to the
## prey. Off = scores as they come.
@export var centered := false
