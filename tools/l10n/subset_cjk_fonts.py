#!/usr/bin/env python3
"""Builds the Chinese, Japanese and Korean fallback fonts in ui/fonts/cjk/:
Noto Sans SC, TC, JP and KR (SIL OFL), cut down to the characters the game's
translations use, so they cost a few hundred KB instead of ~35 MB.
(Thai and Devanagari ship as whole fonts: they're small.)

    python3 tools/l10n/subset_cjk_fonts.py --src=DIR

DIR holds the full static fonts, named as in the @expo-google-fonts npm
packages (NotoSansSC_400Regular.ttf, ..._500Medium.ttf, ..._700Bold.ttf, and
the same for TC, JP and KR). Any copy of Noto Sans SC/TC/JP/KR works if
renamed. Get them with:  npm pack @expo-google-fonts/noto-sans-sc  (and -tc,
-jp, -kr)

Run it again whenever the zh_CN, zh_TW, ja or ko translations change: the
glyph check (tools/l10n/check_glyphs.py) fails when a translated character
is missing from these files. Every subset also carries the four CJK language
names from the Language menu, so they show in every language.
"""
from __future__ import annotations

import pathlib
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import po  # noqa: E402

OUT = pathlib.Path("ui/fonts/cjk")
SCRIPTS = {"SC": "zh_CN", "TC": "zh_TW", "JP": "ja", "KR": "ko"}
WEIGHTS = {"Regular": "400Regular", "Medium": "500Medium", "Bold": "700Bold"}
# Always in: ASCII, the Language menu's names, and punctuation the
# translations or the interface use.
EXTRA = (" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
         "简体中文繁體中文日本語한국어·…‹›—–“”‘’、。，：；！？（）「」『』《》〈〉・ー〜％")


def language_chars(code: str) -> set[str]:
    _, entries = po.read(pathlib.Path("locale") / f"{code}.po")
    chars = set()
    for e in entries:
        for s in (e.msgstr_plural if e.msgid_plural else [e.msgstr]):
            chars.update(s)
    return chars


def main() -> None:
    src = None
    for arg in sys.argv[1:]:
        if arg.startswith("--src="):
            src = pathlib.Path(arg[6:])
    if src is None:
        sys.exit(__doc__)
    OUT.mkdir(parents=True, exist_ok=True)
    for script, lang in SCRIPTS.items():
        chars = language_chars(lang) | set(EXTRA)
        chars = {c for c in chars if not c.isspace() or c == " "}
        for weight, tag in WEIGHTS.items():
            path = src / f"NotoSans{script}_{tag}.ttf"
            font = TTFont(path)
            options = subset.Options()
            options.layout_features = ["*"]
            options.name_IDs = ["*"]
            options.name_languages = ["*"]
            options.hinting = False
            options.notdef_outline = True
            sub = subset.Subsetter(options)
            sub.populate(text="".join(sorted(chars)))
            sub.subset(font)
            out = OUT / f"NotoSans{script}-{weight}.subset.ttf"
            font.save(out)
            print(f"{out}: {len(chars)} characters, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
