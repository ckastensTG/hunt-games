#!/usr/bin/env python3
"""Checks that the fonts can draw every translated string (framework §11).

Run from the hunt-games root:  python3 tools/l10n/check_glyphs.py

For each locale/<lang>.po, every character of every translation must be in
each interface font (Alegreya SC, Alegreya, Alegreya Sans) or, for Chinese,
Japanese and Korean, in that language's Noto subset (ui/fonts/cjk/). Run
tools/l10n/subset_cjk_fonts.py when a CJK translation adds characters.
Also checks the language names shown in the Language menu.
"""
from __future__ import annotations

import pathlib
import re
import sys

from fontTools.ttLib import TTFont

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import po  # noqa: E402

FONTS = pathlib.Path("ui/fonts")
LATIN = ["AlegreyaSC-Medium.ttf", "Alegreya-Variable.ttf", "AlegreyaSans-Regular.ttf",
         "AlegreyaSans-Medium.ttf", "AlegreyaSans-Bold.ttf"]
CJK = {"zh_CN": "SC", "ja": "JP", "ko": "KR"}
IGNORE = set("\n\t")


def cmap(path: pathlib.Path) -> set[int]:
    return set(TTFont(path).getBestCmap().keys())


def main() -> int:
    latin = {name: cmap(FONTS / name) for name in LATIN}
    cjk = {}
    for script in CJK.values():
        cover = set()
        for f in (FONTS / "cjk").glob(f"NotoSans{script}-*.subset.ttf"):
            cover |= cmap(f)
        cjk[script] = cover
    errors = 0
    texts = {}
    for path in sorted(pathlib.Path("locale").glob("*.po")):
        header, entries = po.read(path)
        lang = header.get("Language", path.stem)
        texts[lang] = "".join("".join(e.msgstr_plural if e.msgid_plural else [e.msgstr]) for e in entries)
    names = re.findall(r'\["\w+", "([^"]+)"\]', pathlib.Path("ui/l10n.gd").read_text(encoding="utf-8"))
    texts["(language menu)"] = "".join(names)
    for lang, text in texts.items():
        extra = set()
        if lang in CJK:
            extra = cjk[CJK[lang]]
        elif lang == "(language menu)":
            extra = set().union(*cjk.values())
        missing = {}
        for ch in set(text) - IGNORE:
            for name, cover in latin.items():
                if ord(ch) not in cover and ord(ch) not in extra:
                    missing.setdefault(name, set()).add(ch)
        for name, chars in missing.items():
            print(f"{lang}: {name} lacks {''.join(sorted(chars))!r}")
            errors += 1
        if not missing:
            print(f"{lang}: ok ({len(set(text))} characters)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
