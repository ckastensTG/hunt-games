# Fonts

The series typography (framework §11; decided by Christopher 2026-11-03):

| File | Use |
|---|---|
| `AlegreyaSC-Medium.ttf` | Display: titles, banners, panel headings (small caps) |
| `Alegreya-Variable.ttf` | Book text: rule names, walkthrough text, game-over lines |
| `AlegreyaSans-Regular/Medium/Bold.ttf` | Interface: labels, buttons, menus |
| `cjk/NotoSans{SC,JP,KR}-{Regular,Medium,Bold}.subset.ttf` | Fallback for Simplified Chinese, Japanese and Korean |

Alegreya and Alegreya Sans (Huerta Tipográfica) cover Latin Extended and
Cyrillic: 9 of the 12 launch languages (EN, PT-BR, ES, FR, DE, IT, RU, PL,
TR). Downloaded from github.com/google/fonts on 2026-11-03.

**Chinese, Japanese, Korean.** Noto Sans SC, JP and KR (Adobe/Google, the
CJK companions of the Noto family, chosen for legibility at small sizes and
their weight range). Each language gets its own font so that characters
shared between the languages take that language's regional forms.
`SeriesTheme` puts the current language's font first in every text role's
fallback list (display → Medium, body → Regular, buttons → Medium, bold →
Bold). The full fonts are ~6–10 MB each, so the game ships subsets that hold
only the characters the translations use (about 400 per language, ~150 KB
per file), made by `tools/l10n/subset_cjk_fonts.py` from the static fonts in
the `@expo-google-fonts/noto-sans-{sc,jp,kr}` npm packages. Rebuild them
whenever the Chinese, Japanese or Korean text changes;
`tools/l10n/check_glyphs.py` (also in CI) fails if a character is missing.
Godot's system-font fallback stays on as a last resort.

All of these are under the SIL Open Font License 1.1 (`OFL-*.txt`,
`cjk/OFL-NotoSansCJK.txt`): free to use and embed in commercial games;
the fonts themselves may not be sold on their own.
