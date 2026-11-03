"""Minimal gettext PO reading and writing for the localization tools.

No third-party packages: PO is a small text format, and the tools only need
msgctxt, msgid, msgid_plural, msgstr / msgstr[n], translator comments (#.),
references (#:) and flags (#,).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class Entry:
    msgid: str
    msgctxt: str = ""
    msgid_plural: str = ""
    msgstr: str = ""
    msgstr_plural: list[str] = field(default_factory=list)
    comments: list[str] = field(default_factory=list)     # "#." extracted comments
    references: list[str] = field(default_factory=list)   # "#:" file:line
    flags: list[str] = field(default_factory=list)        # "#," e.g. fuzzy

    @property
    def key(self) -> tuple[str, str]:
        return (self.msgctxt, self.msgid)

    def translated(self) -> bool:
        if self.msgid_plural:
            return bool(self.msgstr_plural) and all(s != "" for s in self.msgstr_plural)
        return self.msgstr != ""


def _unquote(s: str) -> str:
    s = s.strip()
    assert s.startswith('"') and s.endswith('"'), s
    body = s[1:-1]
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def read(path) -> tuple[dict, list[Entry]]:
    """Returns (header fields, entries). The header entry (msgid "") is parsed
    into a dict and not included in the entries."""
    entries: list[Entry] = []
    cur: dict = {}
    last = None

    def flush():
        nonlocal cur, last
        if "msgid" in cur:
            e = Entry(msgid=cur["msgid"], msgctxt=cur.get("msgctxt", ""),
                      msgid_plural=cur.get("msgid_plural", ""), msgstr=cur.get("msgstr", ""),
                      comments=cur.get("comments", []), references=cur.get("references", []),
                      flags=cur.get("flags", []))
            plurals = cur.get("plural", {})
            e.msgstr_plural = [plurals[k] for k in sorted(plurals)]
            entries.append(e)
        cur = {}
        last = None

    for raw in open(path, encoding="utf-8").read().splitlines():
        line = raw.rstrip()
        if not line:
            flush()
            continue
        if line.startswith("#~"):
            continue
        if line.startswith("#."):
            if "msgid" in cur:
                flush()
            cur.setdefault("comments", []).append(line[2:].strip())
            continue
        if line.startswith("#:"):
            if "msgid" in cur:
                flush()
            cur.setdefault("references", []).extend(line[2:].split())
            continue
        if line.startswith("#,"):
            if "msgid" in cur:
                flush()
            cur.setdefault("flags", []).extend(f.strip() for f in line[2:].split(","))
            continue
        if line.startswith("#"):
            continue
        m = re.match(r'^(msgctxt|msgid_plural|msgid|msgstr\[(\d+)\]|msgstr)\s+(".*")$', line)
        if m:
            kw, idx, val = m.group(1), m.group(2), _unquote(m.group(3))
            if kw == "msgid" and "msgid" in cur:
                flush()
            if kw.startswith("msgstr["):
                cur.setdefault("plural", {})[int(idx)] = val
                last = ("plural", int(idx))
            else:
                cur[kw] = val
                last = kw
            continue
        if line.startswith('"') and last is not None:
            val = _unquote(line)
            if isinstance(last, tuple):
                cur["plural"][last[1]] += val
            else:
                cur[last] += val
    flush()
    header = {}
    body = []
    for e in entries:
        if e.msgid == "" and not e.msgctxt:
            for hl in e.msgstr.split("\n"):
                if ":" in hl:
                    k, v = hl.split(":", 1)
                    header[k.strip()] = v.strip()
        else:
            body.append(e)
    return header, body


def write(path, header: dict, entries: list[Entry]) -> None:
    out = ['msgid ""', 'msgstr ""']
    for k, v in header.items():
        out.append(_quote(f"{k}: {v}\n"))
    out.append("")
    for e in entries:
        for c in e.comments:
            out.append(f"#. {c}")
        if e.references:
            out.append("#: " + " ".join(e.references))
        if e.flags:
            out.append("#, " + ", ".join(e.flags))
        if e.msgctxt:
            out.append(f"msgctxt {_quote(e.msgctxt)}")
        out.append(f"msgid {_quote(e.msgid)}")
        if e.msgid_plural:
            out.append(f"msgid_plural {_quote(e.msgid_plural)}")
            plurals = e.msgstr_plural or ["", ""]
            for i, s in enumerate(plurals):
                out.append(f"msgstr[{i}] {_quote(s)}")
        else:
            out.append(f"msgstr {_quote(e.msgstr)}")
        out.append("")
    open(path, "w", encoding="utf-8").write("\n".join(out))
