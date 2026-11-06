#!/usr/bin/env python3
"""Checks the translations in locale/*.po against locale/messages.pot.

Run from the hunt-games root:  python3 tools/l10n/check_po.py [--allow-missing]

Errors (exit 1):
- a string from the template is missing or untranslated (unless --allow-missing)
- a translation's placeholders (%d, %s) differ from the source text's
- a plural entry has the wrong number of forms for the language
- a translation is the English source text unchanged (only checked for
  real sentences: names such as "Bagh Chal · Parlett 1976" may stay)

A title-only language (scope.py: Nepali, Bagh Chal's alone) may leave out
the strings only another title shows.
"""
from __future__ import annotations

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import po  # noqa: E402
import scope  # noqa: E402

LOCALE = pathlib.Path("locale")
PH = re.compile(r"%[-+ 0#]*\d*(?:\.\d+)?[dsf%]")


def placeholders(s: str) -> list[str]:
    return [p for p in PH.findall(s) if p != "%%"]


def main() -> int:
    allow_missing = "--allow-missing" in sys.argv
    _, template = po.read(LOCALE / "messages.pot")
    keys = {t.key for t in template}
    errors, warnings = 0, 0
    for path in sorted(LOCALE.glob("*.po")):
        header, entries = po.read(path)
        nplurals = int(re.search(r"nplurals=(\d+)", header.get("Plural-Forms", "")).group(1))
        have = {e.key: e for e in entries}
        lang = header.get("Language", path.stem)
        needed = {t.key for t in template if scope.needed(t, lang)}
        missing = [k for k in needed if k not in have or not have[k].translated()]
        problems = []
        for e in entries:
            if e.key not in keys:
                problems.append(f"not in the template (run update_po.py): {e.msgid[:60]!r}")
                continue
            if not e.translated():
                continue
            want = placeholders(e.msgid)
            forms = e.msgstr_plural if e.msgid_plural else [e.msgstr]
            if e.msgid_plural and len(forms) != nplurals:
                problems.append(f"{len(forms)} plural forms, the language has {nplurals}: {e.msgid[:60]!r}")
            for f in forms:
                if placeholders(f) != want:
                    problems.append(f"placeholders {placeholders(f)} != {want}: {e.msgid[:60]!r}")
            if len(re.findall(r"\b[a-z]{3,}\b", e.msgid)) >= 3 and e.msgid in forms:
                problems.append(f"left in English: {e.msgid[:60]!r}")
        if missing and not allow_missing:
            problems.append(f"{len(missing)} strings untranslated")
        elif missing:
            warnings += 1
            print(f"{path}: {len(missing)} strings untranslated (allowed)")
        for p in problems:
            print(f"{path}: {p}")
        errors += len(problems)
        if not problems:
            left_out = len(keys) - len(needed)
            print(f"{path}: ok ({len(entries)} strings" + (f", {left_out} for other titles left out)" if left_out else ")"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
