# timeless-core

Shared framework for **Timeless Games by Time Galleon**: the rules engine,
AI, test runner and (later) presentation, shell and platform services that
every title builds on.

This repo is a Godot 4 addon. Game projects include it as a git submodule at
`addons/timeless_core/`. Design: `claude/framework-architecture.md` in the
"Ancient games series" project.

## Contents

| Path | What it is |
|---|---|
| `rules/board_def.gd`, `rules/board_builder.gd` | Boards as points and polylines. Adjacency and jumps come from the lines, never from coordinates. |
| `rules/hunt/` | Hunt-game family (Bagh Chal, Adugo, Komikan, ...): `HuntRuleSet`, `HuntState` (move generation, make/unmake, repetition, terminal rules), Zobrist hashing, `HuntEvaluator`. |
| `ai/hunt_searcher.gd` | Alpha-beta with iterative deepening, transposition table and capture quiescence. Explicit stack: `step(nodes)` pauses and resumes. |
| `ai/ai_persona.gd` | Named opponents: search limits plus plausible (seeded) mistakes. |
| `testing/` | Headless test runner and `TestCase` base class. |
| `tests/` | Core unit tests. |

## Requirements

Godot **4.7.2** (pinned for the series until M2; see the architecture doc).

## Running the tests

From a game project that includes this addon:

```sh
godot --headless --path . --import
godot --headless --path . -s res://addons/timeless_core/testing/test_runner.gd -- \
  --dir=res://addons/timeless_core/tests
```

CI does the same in a throwaway host project (`.github/workflows/ci.yml`).

Copyright © Time Galleon. All rights reserved.
