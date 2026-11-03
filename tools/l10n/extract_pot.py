#!/usr/bin/env python3
"""Collects the game's translatable strings into locale/messages.pot.

Run from the hunt-games root:  python3 tools/l10n/extract_pot.py [--check]

--check doesn't write anything: it fails if the strings in the code differ
from locale/messages.pot (file:line references aside), for CI.

It scans every .gd file (except addons/) for string literals passed to:
  tr("…"[, "context"])            tr_n("…", "…", n[, "context"])
  L10n.t("…"[, "context"])        L10n.tn("…", "…", n[, "context"])
  N_("…") / L10n.N_("…")          strings shown later through t()
  TranslationServer.translate("…"[, "context"])

A comment line "# TRANSLATORS: …" just above a call is passed on to the
translators. Then run tools/l10n/update_po.py to merge the template into
each language's .po file.
"""
from __future__ import annotations

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import po  # noqa: E402

ROOT = pathlib.Path(".")
CALLS = {
    # name: (number of message strings, index of the optional context argument)
    "tr": (1, 1), "L10n.t": (1, 1), "TranslationServer.translate": (1, 1),
    "tr_n": (2, 3), "L10n.tn": (2, 3), "TranslationServer.translate_plural": (2, 3),
    "N_": (1, None), "L10n.N_": (1, None),
}
CALL_RE = re.compile(r"(?<![\w.])(L10n\.tn|L10n\.t|L10n\.N_|TranslationServer\.translate_plural|"
                     r"TranslationServer\.translate|tr_n|tr|N_)\(")


def parse_args(src: str, i: int):
    """Parses call arguments starting after '('. Returns a list where string
    literals are str and anything else is None, plus the end index."""
    args, depth, cur_is_str, cur, j = [], 0, None, [], i
    while j < len(src):
        c = src[j]
        if c == '"':
            k = j + 1
            buf = []
            while src[k] != '"':
                if src[k] == "\\":
                    buf.append({"n": "\n", "t": "\t"}.get(src[k + 1], src[k + 1]))
                    k += 2
                else:
                    buf.append(src[k])
                    k += 1
            if depth == 0 and cur_is_str is None and not "".join(cur).strip():
                cur_is_str = "".join(buf)
            else:
                cur_is_str = False
            j = k + 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                args.append(cur_is_str if isinstance(cur_is_str, str) and not "".join(cur).strip() else None)
                return args, j
            depth -= 1
        elif c == "," and depth == 0:
            args.append(cur_is_str if isinstance(cur_is_str, str) and not "".join(cur).strip() else None)
            cur_is_str, cur = None, []
            j += 1
            continue
        elif not c.isspace() and cur_is_str is None:
            cur.append(c)
        elif not c.isspace() and isinstance(cur_is_str, str):
            cur_is_str = False   # a literal followed by more code: an expression
        j += 1
    return args, j


def main() -> None:
    entries: dict = {}
    order = []
    for path in sorted(ROOT.rglob("*.gd")):
        rel = path.as_posix()
        if rel.startswith("addons/") or "/." in rel:
            continue
        src = path.read_text(encoding="utf-8")
        lines = src.split("\n")
        for m in CALL_RE.finditer(src):
            line_start = src.rfind("\n", 0, m.start()) + 1
            if src[line_start:m.start()].lstrip().startswith("#"):
                continue   # in a comment
            name = m.group(1)
            nmsg, ctx_idx = CALLS[name]
            args, _ = parse_args(src, m.end())
            msgs = args[:nmsg]
            if len(msgs) < nmsg or any(not isinstance(a, str) for a in msgs):
                continue   # not a literal: translated elsewhere (marked with N_)
            ctx = ""
            if ctx_idx is not None and len(args) > ctx_idx and isinstance(args[ctx_idx], str):
                ctx = args[ctx_idx]
            line_no = src.count("\n", 0, m.start()) + 1
            note = []
            k = line_no - 2
            while k >= 0 and lines[k].strip().startswith("#"):
                t = lines[k].strip().lstrip("#").strip()
                if t.startswith("TRANSLATORS:"):
                    note.insert(0, t[len("TRANSLATORS:"):].strip())
                k -= 1
            key = (ctx, msgs[0])
            if key not in entries:
                entries[key] = po.Entry(msgid=msgs[0], msgctxt=ctx,
                                        msgid_plural=msgs[1] if nmsg == 2 else "")
                order.append(key)
            e = entries[key]
            e.references.append(f"{rel}:{line_no}")
            for n in note:
                if n not in e.comments:
                    e.comments.append(n)
            if "%" in msgs[0] and "c-format" not in e.flags:
                e.flags.append("c-format")
    header = {
        "Project-Id-Version": "Timeless Games: hunt-games",
        "MIME-Version": "1.0",
        "Content-Type": "text/plain; charset=UTF-8",
        "Content-Transfer-Encoding": "8bit",
    }
    out = ROOT / "locale" / "messages.pot"
    if "--check" in sys.argv:
        _, committed = po.read(out)
        have = {(e.msgctxt, e.msgid, e.msgid_plural) for e in committed}
        want = {(entries[k].msgctxt, entries[k].msgid, entries[k].msgid_plural) for k in order}
        for m in sorted(want - have):
            print(f"new in the code: {m[1][:70]!r}")
        for m in sorted(have - want):
            print(f"gone from the code: {m[1][:70]!r}")
        if want != have:
            sys.exit("locale/messages.pot is out of date: run tools/l10n/extract_pot.py, then update_po.py")
        print(f"locale/messages.pot: up to date ({len(order)} messages)")
        return
    out.parent.mkdir(exist_ok=True)
    po.write(out, header, [entries[k] for k in order])
    print(f"locale/messages.pot: {len(order)} messages")


if __name__ == "__main__":
    main()
