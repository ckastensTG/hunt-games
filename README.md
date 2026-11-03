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
| `scenes/greybox/` | The playable greybox: board, pieces and move marks built in code from the board definitions, plus the HUD (`hud.gd`). |
| `ui/` | Series UI: `SeriesTheme` (colors, panels, fonts, built in code) and the proposed fonts (`ui/fonts/README.md`). |
| `titles/common/hunt_art_style.gd` | `HuntArtStyle`, the base for a title's looks (environment, set, pieces). The player picks one under **Look** in the settings. |
| `tests/` | Title tests: board fixtures, rule sets, the Lim & Nievergelt opening result. |
| `titles/bagh_chal/art/` | Bagh Chal looks, listed by `BaghChalArt.styles()`: **Temple brass** (`brass_style.gd`: brass board, cast tiger and goat, dusk courtyard) and **Stone and pebbles** (`stone_style.gd`, `stone/`: chalk-scratched slab, river stones, straw mat in a rest-house). |
| `tools/` | Test runner wrapper, search benchmark, headless smoke test, screenshot and style-frame tools. |
| `tools/art/` | Python generators for the Claude-made art (brass board and pieces, stone set), plus the board geometry they read. |

## Commands

```sh
tools/run_tests.sh                       # core + title tests (headless)
godot --headless --path . -s res://tools/bench_search.gd -- --depth=6
godot --headless --fixed-fps 60 --path . -s res://tools/smoke_greybox.gd
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
  -s res://tools/screenshot.gd -- --out=/tmp/shots
```

Set `GODOT=/path/to/godot` if Godot isn't on your `PATH`.

### Art (Bagh Chal)

```sh
# Style frame + both game views from one fixed position (needs a display):
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
  --rendering-method forward_plus -s res://tools/style_frame.gd -- --out=/tmp/frames [--style=stone]
# Same views on the Mobile and Compatibility renderers:
#   --rendering-method mobile --views=ai,prey   /   --rendering-method gl_compatibility --views=ai
# With the interface: --ui; with move highlights: --ui --select; game-over card: --ui --result

# Regenerate the art (Python 3 with numpy, scipy, scikit-image, trimesh,
# fast-simplification, Pillow):
godot --headless --path . -s res://tools/export_boards.gd   # board geometry -> tools/art/boards.json
python3 tools/art/make_board.py                             # board mesh + engraving textures
python3 tools/art/make_pieces.py [--preview]                # tiger and goat figurines
python3 tools/art/make_stone_set.py [--stones-only]         # stone slab, chalk textures, 4 tiger and 8 goat stones
```

To add a look: subclass `HuntArtStyle`, build the set under the root you are
given (it turns with the board for the prey view), and add it to the title's
`styles()` list.

The generated files (`*.glb`, `board_*.png`) are committed, so nobody needs
Python to open the project. Any of them can be replaced one for one by
outsourced art with the same name, scale (1 unit = one board spacing) and
orientation (figures face -Z, stand on y = 0).

## CI

`.github/workflows/ci.yml` runs the tests on every push. The core submodule
is private, so the workflow needs a `CORE_REPO_TOKEN` secret: a fine-grained
token with read access to `timeless-core`.

Copyright © Time Galleon. All rights reserved.
