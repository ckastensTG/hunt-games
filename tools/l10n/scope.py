"""Which strings a title-only language needs.

Most languages cover every string in locale/messages.pot. A title-only
language (L10n.TITLE_LANGUAGES, TitleConfig "languages") is offered by one
title alone, so its .po may leave out the strings only another title shows.
Nepali is Bagh Chal's alone (Christopher, 2026-11-06), so ne.po leaves out
the Jogo da Onça text: Adugo and Komikan's walkthroughs, and the sentences
about the jaguar, the puma and the dogs.

check_po.py allows those to stay untranslated; Godot then shows English,
which only a dev build (every title) can ever reach.
"""
from __future__ import annotations

import pathlib
import re

# language -> the one title that offers it
TITLE_ONLY = {"ne": "bagh_chal"}

TUTORIALS = pathlib.Path("titles/common/hunt_tutorials.gd")
# Sentences that name another title's pieces, people or rule sets...
JOGO_WORDS = re.compile(r"jaguar|puma|\bdogs?\b|adugo|komikan|onça|bororo|mapuche", re.I)
# ...unless they also name Bagh Chal's.
BAGH_CHAL_WORDS = re.compile(r"tiger|goat|bagh chal", re.I)


def _tutorial_ranges() -> dict[str, tuple[int, int]]:
    """Line ranges of the per-rule-set walkthrough functions, e.g.
    {"adugo": (215, 274), "komikan": (275, 335), "bagh_chal": (130, 214)}."""
    lines = TUTORIALS.read_text(encoding="utf-8").split("\n")
    starts = [(i + 1, m.group(1)) for i, line in enumerate(lines)
              if (m := re.match(r"static func _(\w+)\(", line))]
    ranges = {}
    for k, (start, name) in enumerate(starts):
        end = starts[k + 1][0] - 1 if k + 1 < len(starts) else len(lines)
        ranges[name] = (start, end)
    return ranges


_RANGES: dict[str, tuple[int, int]] | None = None


def _walkthrough_of(ref: str) -> str:
    """The rule set whose walkthrough a reference like
    titles/common/hunt_tutorials.gd:219 is in, or ""."""
    global _RANGES
    path, _, line = ref.partition(":")
    if path != str(TUTORIALS) or not line.isdigit():
        return ""
    if _RANGES is None:
        _RANGES = _tutorial_ranges()
    for name, (start, end) in _RANGES.items():
        if start <= int(line) <= end:
            return name
    return ""


def other_title_only(entry, title: str) -> bool:
    """True when only another title shows this string."""
    if title != "bagh_chal":
        raise ValueError(f"no scope rules for {title}")
    walkthroughs = {_walkthrough_of(r) for r in entry.references}
    if walkthroughs and walkthroughs <= {"adugo", "komikan"}:
        return True
    return bool(JOGO_WORDS.search(entry.msgid)) and not BAGH_CHAL_WORDS.search(entry.msgid)


def needed(entry, lang: str) -> bool:
    """Does the language's .po need this string translated?"""
    title = TITLE_ONLY.get(lang)
    return title is None or not other_title_only(entry, title)
