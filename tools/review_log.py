"""Reads Revenge's diagnostic log and saved data, to review a few days of play.

Usage: python -I tools/review_log.py [PATH] [--since YYYY-MM-DD] [--kinds death,in,...] [--summary]

PATH is a RevengeTracker.lua saved-variables file, or a folder to look under. Without
one, it looks in the usual WoW: Forever install for
_forever_/WTF/Account/*/SavedVariables/RevengeTracker.lua. For each file it prints:
  - the log in local time, a rule before each session (not with --summary);
  - which checks have evidence (V-003 to V-019), with counts and the newest line;
  - what's stored: deaths by source, Wanted marks, the log's span;
  - Bugsy's errors that mention Revenge, when Bugsy's saved file is beside it.
The game writes saved variables at logout and /reload. This only reads them, and parses
them as data: nothing in them is ever run.
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from collections import Counter
from pathlib import Path

DEFAULT_ROOT = Path(r"C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account")

# --------------------------------------------------------------------------------------
# Saved variables: a small Lua table reader (strings, numbers, booleans, nil, tables)
# --------------------------------------------------------------------------------------
_TOKEN = re.compile(r"""
    (?P<space>\s+|--[^\n]*)
  | (?P<str>"(?:\\.|\\\n|[^"\\])*")
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|inf|nan))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,;])
""", re.X)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
            "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class ParseError(ValueError):
    pass


def _unescape(body: str) -> str:
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = body[i + 1] if i + 1 < len(body) else ""
        if nxt.isdigit():
            digits = re.match(r"\d{1,3}", body[i + 1:]).group(0)
            out.append(chr(int(digits)))
            i += 1 + len(digits)
        else:
            out.append(_ESCAPES.get(nxt, nxt))
            i += 2
    return "".join(out)


def _tokens(text: str):
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise ParseError(f"unexpected {text[pos:pos + 20]!r} at {pos}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "space":
            continue
        yield kind, m.group(kind)
    yield "end", ""


class _Parser:
    def __init__(self, text: str):
        self.tokens = _tokens(text)
        self.kind, self.value = next(self.tokens)

    def take(self, kind=None, value=None):
        if (kind and self.kind != kind) or (value is not None and self.value != value):
            raise ParseError(f"expected {value or kind}, got {self.value!r}")
        token = (self.kind, self.value)
        self.kind, self.value = next(self.tokens)
        return token

    def value_(self):
        kind, value = self.kind, self.value
        if kind == "str":
            self.take()
            return _unescape(value[1:-1])
        if kind == "num":
            self.take()
            if value.lstrip("-").lower() in ("inf", "nan"):
                return float(value)
            if value.lower().lstrip("-").startswith("0x"):
                return int(value, 16)
            number = float(value)
            return int(number) if number.is_integer() and "." not in value and "e" not in value.lower() else number
        if kind == "name" and value in ("true", "false", "nil"):
            self.take()
            return {"true": True, "false": False, "nil": None}[value]
        if kind == "punct" and value == "{":
            return self.table()
        raise ParseError(f"unexpected {value!r}")

    def table(self):
        self.take("punct", "{")
        out, index = {}, 1
        while not (self.kind == "punct" and self.value == "}"):
            if self.kind == "punct" and self.value == "[":
                self.take()
                key = self.value_()
                self.take("punct", "]")
                self.take("punct", "=")
                out[key] = self.value_()
            elif self.kind == "name" and self.value not in ("true", "false", "nil"):
                key = self.take()[1]
                self.take("punct", "=")
                out[key] = self.value_()
            else:
                value = self.value_()
                if value is not None:
                    out[index] = value
                index += 1
            if self.kind == "punct" and self.value in (",", ";"):
                self.take()
        self.take("punct", "}")
        return out

    def file(self):
        names = {}
        while self.kind != "end":
            name = self.take("name")[1]
            self.take("punct", "=")
            names[name] = self.value_()
        return names


def parse_saved_variables(text: str) -> dict:
    """The top-level names a saved-variables file assigns, as Python values (tables are dicts)."""
    return _Parser(text).file()


def as_list(table) -> list:
    """A Lua array (a dict keyed 1..n) as a list, in order."""
    if not isinstance(table, dict):
        return []
    return [table[i] for i in range(1, len(table) + 1) if i in table]


# --------------------------------------------------------------------------------------
# The log
# --------------------------------------------------------------------------------------
_LINE = re.compile(r"^(\d+) (\S+) (.*)$", re.S)


def log_lines(db: dict) -> list[tuple[int, str, str]]:
    """The log's lines as (server time, kind, text)."""
    out = []
    for line in as_list(db.get("log")):
        m = _LINE.match(line) if isinstance(line, str) else None
        if m:
            out.append((int(m.group(1)), m.group(2), m.group(3)))
    return out


def _has(*parts):
    return lambda t: any(p in t for p in parts)


# Which lines are evidence for which check (docs/plans/revenge/IMPLEMENTATION-MATRIX.md).
CHECKS = [
    ("V-003", "your open-world deaths recorded", "death", lambda t: t.startswith("recorded")),
    ("V-003", "deaths not recorded, and why", "death", lambda t: t.startswith("not recorded")),
    ("V-004", "tooltips showing Revenge's lines", "tooltip", lambda t: True),
    ("V-006", "your own data sent to the guild", "out", lambda t: "queued to" in t and "guild" in t),
    ("V-006", "guildmates' Revenge data received", "in", lambda t: " by guild" in t and ("death" in t or "Wanted" in t)
     and "dropped" not in t),
    ("V-006", "catch-up: hellos and answers", None, lambda t: "hello" in t),
    ("V-007", "friends found running Revenge", "friends", lambda t: True),
    ("V-007", "friends' data received", "in", lambda t: ("(whisper)" in t or "(Battle.net)" in t) and "dropped" not in t
     and "hello" not in t),
    ("V-008", "friend or guildmate killed alerts", "alert", lambda t: t.startswith("killed")),
    ("V-009", "nameplate skulls", "skull", lambda t: True),
    ("V-010", "killer nearby alerts", "alert", lambda t: t.startswith("nearby")),
    ("V-011", "map pins shown", "pins", lambda t: True),
    ("V-011", "kills dismissed from the map", "list", lambda t: t.startswith("dismissed")),
    ("V-013", "alerts shown as a popup", "alert", lambda t: "(popup" in t),
    ("V-015", "Revenge Book reports", "others", _has("Revenge Book ", "revengebook ")),
    ("V-016", "Grudgekeeper reports", "others", _has("Grudgekeeper ", "grudgekeeper ")),
    ("V-017", "HeadHunter reports", "others", _has("HeadHunter ", "headhunter ")),
    ("V-018", "Kill on Sight's list", "others", _has("Kill on Sight", "killonsight ")),
    ("V-019", "the module, breakers and summaries", "others", _has("module", "paused", "last 10 minutes")),
    ("-", "messages turned away", "in", lambda t: t.startswith("dropped")),
    ("-", "messages the game refused or that never went", "out", _has("refused", "dropped")),
    ("-", "errors Revenge caught", "error", lambda t: True),
]


def evidence(lines) -> list[tuple[str, str, int, tuple | None]]:
    """For each check: (id, what, how many lines, the newest line or None)."""
    out = []
    for check, what, kind, test in CHECKS:
        found = [line for line in lines if (kind is None or line[1] == kind) and test(line[2])]
        out.append((check, what, len(found), found[-1] if found else None))
    return out


def _when(at: int) -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(at))


# --------------------------------------------------------------------------------------
# Saved data and Bugsy
# --------------------------------------------------------------------------------------
def stored_summary(db: dict) -> list[str]:
    kills = [k for k in (db.get("kills") or {}).values() if isinstance(k, dict)]
    marks = [m for m in (db.get("wanted") or {}).values() if isinstance(m, dict)]
    by_source = Counter("+".join(sorted(k.get("sources") or {})) or "?" for k in kills)
    mark_sources = Counter("+".join(sorted(m.get("sources") or {})) or "?" for m in marks)
    settings = db.get("settings") or {}
    out = [f"deaths stored: {len(kills)} ({sum(1 for k in kills if k.get('own'))} from Revenge itself)"]
    out += [f"  from {source}: {n}" for source, n in sorted(by_source.items())]
    out.append(f"Wanted marks stored: {len(marks)}")
    out += [f"  from {source}: {n}" for source, n in sorted(mark_sources.items())]
    out.append(f"diagnostic log: {'on' if settings.get('diagnosticLog') else 'off'}")
    return out


def bugsy_errors(folder: Path) -> list[str]:
    """Bugsy's saved errors whose text mentions Revenge, one line each."""
    path = folder / "!Bugsy.lua"
    if not path.exists():
        return ["(no !Bugsy.lua here)"]
    text = path.read_text(encoding="utf-8", errors="replace")
    try:
        data = parse_saved_variables(text)
    except ParseError:
        n = text.count("RevengeTracker")
        return [f"(couldn't read !Bugsy.lua; it mentions RevengeTracker {n} times)"]
    found = []

    def walk(value):
        if isinstance(value, dict):
            message = value.get("message")
            if isinstance(message, str) and "RevengeTracker" in repr(value):
                found.append(" ".join(message.split())[:200])
                return
            for item in value.values():
                walk(item)

    walk(data)
    return found or ["none mention Revenge"]


# --------------------------------------------------------------------------------------
def find_files(path: Path | None) -> list[Path]:
    if path and path.is_file():
        return [path]
    root = path or DEFAULT_ROOT
    return sorted(root.glob("**/SavedVariables/RevengeTracker.lua")) or sorted(root.glob("**/RevengeTracker.lua"))


def review(path: Path, since: float | None = None, kinds: set[str] | None = None, summary: bool = False) -> str:
    data = parse_saved_variables(path.read_text(encoding="utf-8", errors="replace"))
    db = data.get("RevengeTrackerDB") or {}
    lines = [line for line in log_lines(db) if since is None or line[0] >= since]
    out = [f"== {path}", ""]
    if not summary:
        shown = [line for line in lines if not kinds or line[1] in kinds]
        for at, kind, text in shown:
            if kind == "session" and text.startswith("Revenge "):
                out.append("-" * 72)
            out.append(f"{_when(at)}  {kind:<8} {text}")
        out.append("")
    if lines:
        out.append(f"log: {len(lines)} lines, {_when(lines[0][0])} to {_when(lines[-1][0])}; by kind: "
                   + ", ".join(f"{k} {n}" for k, n in Counter(line[1] for line in lines).most_common()))
    else:
        out.append("log: no lines (is it on? /revenge log on, then play and /reload or log out)")
    out += ["", "checks:"]
    for check, what, n, newest in evidence(lines):
        out.append(f"  {check:<6} {what}: {n}")
        if newest:
            out.append(f"         newest: {_when(newest[0])}  {newest[1]} {newest[2][:150]}")
    out += ["", *stored_summary(db), "", "Bugsy, errors mentioning Revenge:"]
    out += [f"  {line}" for line in bugsy_errors(path.parent)]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("path", nargs="?", type=Path)
    parser.add_argument("--since", help="only lines from this local date on (YYYY-MM-DD)")
    parser.add_argument("--kinds", help="only these kinds in the listing, comma-separated")
    parser.add_argument("--summary", action="store_true", help="the checks and counts, without the listing")
    args = parser.parse_args(argv)
    since = time.mktime(time.strptime(args.since, "%Y-%m-%d")) if args.since else None
    kinds = set(args.kinds.split(",")) if args.kinds else None
    files = find_files(args.path)
    if not files:
        print(f"No RevengeTracker.lua found under {args.path or DEFAULT_ROOT}", file=sys.stderr)
        return 1
    for path in files:
        print(review(path, since, kinds, args.summary))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
