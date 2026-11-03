#!/usr/bin/env python3
"""Merges locale/messages.pot into every locale/<lang>.po (like msgmerge).

Run from the hunt-games root after tools/l10n/extract_pot.py:
    python3 tools/l10n/update_po.py

Keeps every existing translation whose source text is unchanged, adds new
strings untranslated, and drops strings the code no longer uses (listed so a
translation isn't lost by accident when a string is only reworded). Then run
tools/l10n/check_po.py to see what still needs translating.
"""
from __future__ import annotations

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import po  # noqa: E402

LOCALE = pathlib.Path("locale")


def main() -> None:
    _, template = po.read(LOCALE / "messages.pot")
    for path in sorted(LOCALE.glob("*.po")):
        header, entries = po.read(path)
        nplurals = int(re.search(r"nplurals=(\d+)", header.get("Plural-Forms", "nplurals=2")).group(1))
        old = {e.key: e for e in entries}
        merged, added = [], 0
        for t in template:
            e = po.Entry(msgid=t.msgid, msgctxt=t.msgctxt, msgid_plural=t.msgid_plural,
                         comments=list(t.comments), references=list(t.references), flags=list(t.flags))
            prev = old.pop(t.key, None)
            if prev is not None:
                e.msgstr = prev.msgstr
                e.msgstr_plural = prev.msgstr_plural
            else:
                added += 1
                if t.msgid_plural:
                    e.msgstr_plural = [""] * nplurals
            merged.append(e)
        po.write(path, header, merged)
        print(f"{path}: {len(merged)} strings, {added} new, {len(old)} dropped")
        for e in old.values():
            print(f"    dropped: {e.msgid[:70]!r}")


if __name__ == "__main__":
    main()
