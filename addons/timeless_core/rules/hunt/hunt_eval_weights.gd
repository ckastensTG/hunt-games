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
