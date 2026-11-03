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
against the AI (four levels), or AI vs AI; "How to play" walks through each
rule set's rules on the board, and the interface is in the 12 launch
languages (Language in the settings).

## Layout

| Path | What it is |
|---|---|
| `titles/common/hunt_boards.gd` | The three boards (Bagh Chal 25 points, Adugo 31, Komikan/Mátus 38), checked by fixture tests. |
| `titles/common/hunt_rule_sets.gd` | The four v1 rule sets (rules doc §6) and starting AI weights. |
| `scenes/greybox/` | The playable greybox: board, pieces and move marks built in code from the board definitions, plus the HUD (`hud.gd`). |
| `ui/` | Series UI: `SeriesTheme` (colors, panels, fonts, built in code), the series fonts and CJK fallbacks (`ui/fonts/README.md`), and `L10n` (language helpers and the player's settings file). |
| `titles/common/hunt_text.gd` | Player-facing sentences that name a side, written out whole per title (no "The %s won" assembled from parts). |
| `titles/common/hunt_tutorials.gd` | "How to play": a scripted walkthrough per rule set; every move is checked by the rules engine (`tests/test_tutorials.gd`). |
| `locale/` | `messages.pot` (the English source strings), one `.po` per language, and the termbases (`locale/termbase/*.csv`). |
| `titles/common/hunt_art_style.gd` | `HuntArtStyle`, the base for a title's looks (environment, set, pieces). The player picks one under **Look** in the settings. |
| `tests/` | Title tests: board fixtures, rule sets, the Lim & Nievergelt opening result. |
| `titles/bagh_chal/art/` | Bagh Chal looks, listed by `BaghChalArt.styles()`: **Temple brass** (`brass_style.gd`: brass board, cast tiger and goat, dusk courtyard) and **Stone and pebbles** (`stone_style.gd`, `stone/`: chalk-scratched slab, river stones, straw mat in a rest-house). |
| `tools/` | Test runner wrapper, search benchmark, AI level ladder, headless smoke test, screenshot and style-frame tools, the Komikan balance test. |
| `tools/komikan_tower/` | A small C program that checks whether forward-only dogs (Komikan's rules until 2026-11-03) can ever trap a puma that stays in the tower (they can't). |
| `tools/l10n/` | Localization tools (Python 3 + fontTools): string extraction, PO merge and checks, termbase lint, glyph check, CJK font subsetting. |
| `tools/art/` | Python generators for the Claude-made art (brass board and pieces, stone set), plus the board geometry they read. |

## Commands

```sh
tools/run_tests.sh                       # core + title tests (headless)
godot --headless --path . -s res://tools/bench_search.gd -- --depth=6
godot --headless --path . -s res://tools/persona_ladder.gd -- --rules=bagh_chal_standard --pairs=adept:master --games=4
godot --headless --fixed-fps 60 --path . -s res://tools/smoke_greybox.gd
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
  -s res://tools/screenshot.gd -- --out=/tmp/shots
```

Set `GODOT=/path/to/godot` if Godot isn't on your `PATH`.

### Localization

All player-facing text is English source text passed through `tr()`,
`L10n.t()` / `L10n.tn()` (plurals) or marked with `N_()`. After changing text:

```sh
python3 tools/l10n/extract_pot.py      # code -> locale/messages.pot
python3 tools/l10n/update_po.py        # merge into every locale/*.po
# translate the new entries, then:
python3 tools/l10n/check_po.py         # complete, placeholders, plural forms
python3 tools/l10n/lint_termbase.py    # approved terms (locale/termbase/*.csv)
python3 tools/l10n/subset_cjk_fonts.py --src=DIR   # if zh/ja/ko text changed
python3 tools/l10n/check_glyphs.py     # the fonts cover every translation
```

Screenshots in another language or with pseudolocalization (30% longer,
accented): `tools/style_frame.gd -- ... --ui --locale=de` or `--pseudo`.
Translations are by Claude (2026-11-03); every language needs a native
speaker's review before release (bible §7), CJK, Russian, Polish and Turkish
first.

### Komikan balance

```sh
godot --headless --path . -s res://tools/komikan_balance.gd -- --games=8 --territory=25 \
  [--variants=shipped,matus,sideways,free,adugo] [--matches=4v4,6v6,d6p2,d6p0,d2p6]
cc -O2 -o /tmp/tower tools/komikan_tower/tower.c && /tmp/tower [--sideways] [--simulate=100000]
```

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
