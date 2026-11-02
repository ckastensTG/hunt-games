# hunt-games

Godot project for the first **Timeless Games** production: **Bagh Chal**
(Nepal) and **Jogo da Onça** (Brazil, Bororo), with the Komikan (Mapuche)
variation. Both titles build from this one project through per-title
export presets (feature tags `title_bagh_chal` / `title_jogo_da_onca`).

The series framework lives in the `timeless-core` repo, included as a git
submodule at `addons/timeless_core/`.

Design docs ("Ancient games series" project): the series bible, the kickoff
brief, the rules lock (`claude/games/bagh-chal-jogo-da-onca-rules.md`) and the
framework architecture.

## Getting started

```sh
git clone --recurse-submodules <repo-url>
# or, after a plain clone:
git submodule update --init
```

Open the folder in **Godot 4.7.2**. The main scene is the greybox
(`scenes/greybox/greybox.tscn`): every v1 rule set, hotseat, either side
against the AI (four levels), or AI vs AI.

## Layout

| Path | What it is |
|---|---|
| `titles/common/hunt_boards.gd` | The three boards (Bagh Chal 25 points, Adugo 31, Komikan/Mátus 38), checked by fixture tests. |
| `titles/common/hunt_rule_sets.gd` | The four v1 rule sets (rules doc §6) and starting AI weights. |
| `scenes/greybox/` | Placeholder 3D board, built in code from the board definitions. |
| `tests/` | Title tests: board fixtures, rule sets, the Lim & Nievergelt opening result. |
| `tools/` | Test runner wrapper, search benchmark, headless smoke test, screenshot tool. |

## Commands

```sh
tools/run_tests.sh                       # core + title tests (headless)
godot --headless --path . -s res://tools/bench_search.gd -- --depth=6
godot --headless --fixed-fps 60 --path . -s res://tools/smoke_greybox.gd
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
  -s res://tools/screenshot.gd -- --out=/tmp/shots
```

Set `GODOT=/path/to/godot` if Godot isn't on your `PATH`.

## CI

`.github/workflows/ci.yml` runs the tests on every push. The core submodule
is private, so the workflow needs a `CORE_REPO_TOKEN` secret: a fine-grained
token with read access to `timeless-core`.

Copyright © Time Galleon. All rights reserved.
