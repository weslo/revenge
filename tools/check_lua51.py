"""Flag Lua 5.2+ syntax and library calls that WoW's Lua 5.1 can't run.

luacheck 1.2.0 parses with Lua 5.4, so it accepts `//`, `goto` and bitwise operators.
This scanner strips strings and comments, then looks for those in the remaining code.

Usage: python -I tools/check_lua51.py [paths...]   (default: every .lua under the repo,
excluding docs/ and tools/). Exit code 1 if anything is found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

CHECKS = [
    (re.compile(r'//'), 'integer division `//` (5.3+)'),
    (re.compile(r'\bgoto\b'), '`goto` (5.2+)'),
    (re.compile(r'::[A-Za-z_]\w*::'), 'label `::name::` (5.2+)'),
    (re.compile(r'\bbit32\b'), '`bit32` (5.2; WoW has `bit`)'),
    (re.compile(r'\btable\.(pack|unpack|move)\b'), '`table.pack/unpack/move` (5.2+)'),
    (re.compile(r'\butf8\.'), '`utf8` library (5.3+)'),
    (re.compile(r'<<|>>'), 'bit shift operator (5.3+)'),
    (re.compile(r'(?<![~=<>])&|(?<!~)~(?!=)'), 'bitwise operator `&` or `~` (5.3+)'),
    (re.compile(r'(?<![|])\|(?![|])'), 'bitwise operator `|` (5.3+)'),
]


def strip(source: str) -> str:
    """Replace string and comment contents with spaces, keeping line structure."""
    out, i, n = [], 0, len(source)

    def blank(text: str) -> str:
        return ''.join('\n' if ch == '\n' else ' ' for ch in text)

    while i < n:
        if source.startswith('--', i):
            match = re.match(r'--\[(=*)\[', source[i:])
            if match:
                close = ']' + match.group(1) + ']'
                end = source.find(close, i + len(match.group(0)))
                end = n if end < 0 else end + len(close)
            else:
                end = source.find('\n', i)
                end = n if end < 0 else end
            out.append(blank(source[i:end]))
            i = end
            continue
        match = re.match(r'\[(=*)\[', source[i:])
        if match:
            close = ']' + match.group(1) + ']'
            end = source.find(close, i + len(match.group(0)))
            end = n if end < 0 else end + len(close)
            out.append(blank(source[i:end]))
            i = end
            continue
        ch = source[i]
        if ch in '"\'':
            j = i + 1
            while j < n and source[j] != ch:
                if source[j] == '\\':
                    j += 1
                elif source[j] == '\n':
                    break
                j += 1
            out.append(' ' + blank(source[i + 1:j]) + ' ')
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    paths = [Path(p) for p in sys.argv[1:]] or [
        p for p in root.rglob('*.lua') if not {'docs', 'tools'} & set(p.relative_to(root).parts)
    ]
    problems = 0
    for path in paths:
        code = strip(path.read_text(encoding='utf-8'))
        for number, line in enumerate(code.splitlines(), 1):
            for pattern, message in CHECKS:
                if pattern.search(line):
                    print(f'{path}:{number}: {message}')
                    problems += 1
    print(f'{len(paths)} file(s) checked, {problems} problem(s).')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
