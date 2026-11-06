#!/usr/bin/env python3
"""Checks the translations against the termbases in locale/termbase/*.csv
(framework §11, bible §7).

Run from the hunt-games root:  python3 tools/l10n/lint_termbase.py [--strict]

Each termbase row gives, per language, the approved word as one or more
stems separated by "|" (a stem matches any inflected form that starts with
it). For every string whose English text uses a term, the translation must
use the approved word.
- Do-not-translate terms (dnt = yes, e.g. the titles) must appear exactly:
  always an error. A language may give its own spelling in its column, used
  instead (Bagh Chal is बाघचाल in Nepali, the game's own script).
- Other terms: a warning, or an error with --strict. Some misses are fine
  (a pronoun instead of the noun), so a human looks at the warnings.
"""
from __future__ import annotations

import csv
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import po  # noqa: E402

LOCALE = pathlib.Path("locale")


def stems(cell: str) -> list[str]:
    return [s.strip().lower() for s in cell.split("|") if s.strip()]


def main() -> int:
    strict = "--strict" in sys.argv
    terms = []
    for path in sorted((LOCALE / "termbase").glob("*.csv")):
        with open(path, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                terms.append(row)
    errors = warnings = 0
    for path in sorted(LOCALE.glob("*.po")):
        header, entries = po.read(path)
        lang = header.get("Language", path.stem)
        for e in entries:
            if not e.translated():
                continue
            src = e.msgid.lower()
            forms = e.msgstr_plural if e.msgid_plural else [e.msgstr]
            for t in terms:
                en = stems(t["en"])
                if not any(re.search(r"(?<!\w)" + re.escape(s), src) for s in en):
                    continue
                want = stems(t.get(lang, ""))
                if not want:
                    continue
                for f in forms:
                    low = f.lower()
                    if t["dnt"].strip() == "yes":
                        exact = (t.get(lang) or "").strip() or t["term"]
                        if exact not in f:
                            print(f"ERROR {path}: \"{exact}\" must stay as it is: {f[:70]!r}")
                            errors += 1
                    elif not any(s in low for s in want):
                        print(f"{'ERROR' if strict else 'warn '} {path}: \"{t['term']}\" should be {'/'.join(want)}: {f[:70]!r}")
                        if strict:
                            errors += 1
                        else:
                            warnings += 1
    print(f"termbase: {errors} errors, {warnings} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
