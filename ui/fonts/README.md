# Fonts

The series typography (framework §11; decided by Christopher 2026-11-03):

| File | Use |
|---|---|
| `AlegreyaSC-Medium.ttf` | Display: titles, banners, panel headings (small caps) |
| `Alegreya-Variable.ttf` | Book text: rule names, walkthrough text, game-over lines |
| `Alegreya-MediumItalic.ttf` | Book italics: notes, the rule set under a title, book titles in Game origins' sources (Alegreya's real italic, weight 500; added 2026-11-08, from the `@expo-google-fonts/alegreya` npm package, v0.4.2: Alegreya 2.009, the same version as the upright files, with the same 1,254 characters) |
| `AlegreyaSans-Regular/Medium/Bold.ttf` | Interface: labels, buttons, menus |
| `cjk/NotoSans{SC,TC,JP,KR}-{Regular,Medium,Bold}.subset.ttf` | Fallback for Simplified and Traditional Chinese, Japanese and Korean |
| `thai/NotoSansThai-{Regular,Medium,Bold}.ttf` | Fallback for Thai |
| `devanagari/NotoSansDevanagari-{Regular,Medium,Bold}.ttf` | Fallback for Nepali (Bagh Chal only) |

Alegreya and Alegreya Sans (Huerta Tipográfica) cover Latin Extended and
Cyrillic: 10 of the 15 launch languages (EN, PT-BR, ES, FR, DE, IT, RU, PL,
TR, ID). Downloaded from github.com/google/fonts on 2026-11-03.

**Chinese, Japanese, Korean.** Noto Sans SC, TC (Traditional Chinese, added
2026-11-06), JP and KR (Adobe/Google, the
CJK companions of the Noto family, chosen for legibility at small sizes and
their weight range). Each language gets its own font so that characters
shared between the languages take that language's regional forms.
`SeriesTheme` puts the current language's font first in every text role's
fallback list (display → Medium, body → Regular, buttons → Medium, bold →
Bold). The full fonts are ~6–10 MB each, so the game ships subsets that hold
only the characters the translations use (about 400 per language, ~150 KB
per file), made by `tools/l10n/subset_cjk_fonts.py` from the static fonts in
the `@expo-google-fonts/noto-sans-{sc,tc,jp,kr}` npm packages (rebuilt from
v0.4.4 on 2026-11-06). Every subset also holds the four CJK language names,
so the Language menu shows them in any language. Rebuild them whenever the
Chinese, Japanese or Korean text changes;
`tools/l10n/check_glyphs.py` (also in CI) fails if a character is missing.
Godot's system-font fallback stays on as a last resort.

**Thai.** Noto Sans Thai (the Noto Project), added 2026-11-06 with the Thai
translation. Same family as the other fallbacks, so the weights match, and
`SeriesTheme` puts it first while the game is in Thai. Whole fonts, not
subsets: each file is about 47 KB, and Thai's vowel and tone marks stack
from a few characters. From the `@expo-google-fonts/noto-sans-thai` npm
package (v0.4.2). Thai has no spaces between words; Godot breaks lines with
its own dictionary (the text-server data the project includes:
`internationalization/locale/include_text_server_data`).

**Nepali (Devanagari).** Noto Sans Devanagari (the Noto Project), added
2026-11-06 when Bagh Chal got Nepali (Christopher). It's the Devanagari
member of the same family as the CJK fallbacks, so the weights match:
`SeriesTheme` uses Regular, Medium and Bold for the same text roles, and
puts it first in the fallback list while the game is in Nepali. These are
the **whole fonts**, not subsets: Devanagari draws many conjunct letters
from a few characters, and each file is only ~210 KB. From the
`@expo-google-fonts/noto-sans-devanagari` npm package (v0.4.2, font
version 2.007). `tools/l10n/check_glyphs.py` checks Nepali against them.
Godot's text server shapes Devanagari (conjuncts, vowel signs, halant).

All of these are under the SIL Open Font License 1.1 (`OFL-*.txt`,
`cjk/OFL-NotoSansCJK.txt`, `thai/OFL-NotoSansThai.txt`,
`devanagari/OFL-NotoSansDevanagari.txt`): free to use and embed in commercial games;
the fonts themselves may not be sold on their own.
