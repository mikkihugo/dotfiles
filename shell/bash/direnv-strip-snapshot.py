#!/usr/bin/env python3
"""Strip DIRENV_DIFF / DIRENV_WATCHES from a direnv `export bash` dump.

direnv emits one semicolon-joined line of `export NAME=$'…';` assignments.
Line-oriented filters either drop the whole dump or change nothing. This
scanner removes only those two assignments and keeps the rest byte-for-byte.
"""

from __future__ import annotations

import sys

DROP = frozenset({"DIRENV_DIFF", "DIRENV_WATCHES"})


def _skip_ansi_c(s: str, i: int) -> int:
    # i points at the opening quote of $'…'
    i += 1
    n = len(s)
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == "'":
            return i + 1
        i += 1
    return n


def _skip_single(s: str, i: int) -> int:
    i += 1
    n = len(s)
    while i < n and s[i] != "'":
        i += 1
    return min(i + 1, n)


def _skip_double(s: str, i: int) -> int:
    i += 1
    n = len(s)
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == '"':
            return i + 1
        i += 1
    return n


def _skip_value(s: str, i: int) -> int:
    n = len(s)
    if s.startswith("$'", i):
        return _skip_ansi_c(s, i + 1)
    if i < n and s[i] == "'":
        return _skip_single(s, i)
    if i < n and s[i] == '"':
        return _skip_double(s, i)
    while i < n and s[i] not in ";\n":
        i += 1
    return i


def _ident_end(s: str, i: int) -> int:
    n = len(s)
    while i < n and (s[i].isalnum() or s[i] == "_"):
        i += 1
    return i


def strip_dump(s: str) -> str:
    out: list[str] = []
    i = 0
    n = len(s)
    while i < n:
        while i < n and s[i] in " \t\r":
            i += 1
        if i >= n:
            break
        if s.startswith("#", i):
            j = s.find("\n", i)
            if j == -1:
                out.append(s[i:])
                break
            out.append(s[i : j + 1])
            i = j + 1
            continue
        if s[i] == "\n":
            out.append("\n")
            i += 1
            continue
        if not s.startswith("export ", i) and not s.startswith("unset ", i):
            j = s.find(";", i)
            if j == -1:
                out.append(s[i:])
                break
            out.append(s[i : j + 1])
            i = j + 1
            continue
        start = i
        if s.startswith("unset ", i):
            i += 6
            names: list[str] = []
            while i < n and s[i] not in ";\n":
                while i < n and s[i] in " \t":
                    i += 1
                if i >= n or s[i] in ";\n":
                    break
                j = _ident_end(s, i)
                if j == i:
                    break
                names.append(s[i:j])
                i = j
            if i < n and s[i] == ";":
                i += 1
            keep = [name for name in names if name not in DROP]
            if not keep:
                continue
            if keep != names:
                out.append("unset " + " ".join(keep) + ";")
                continue
            out.append(s[start:i])
            continue
        i += 7
        name = None
        if i < n and (s[i].isalpha() or s[i] == "_"):
            j = _ident_end(s, i)
            name = s[i:j]
            i = j
            if i < n and s[i] == "=":
                i += 1
                i = _skip_value(s, i)
        elif s.startswith("$'", i):
            name_end = _skip_ansi_c(s, i + 1)
            if name_end > i + 2:
                name = s[i + 2 : name_end - 1]
            i = name_end
            if i < n and s[i] == "=":
                i += 1
                i = _skip_value(s, i)
        else:
            j = s.find(";", start)
            if j == -1:
                out.append(s[start:])
                break
            out.append(s[start : j + 1])
            i = j + 1
            continue
        if i < n and s[i] == ";":
            i += 1
        if name in DROP:
            continue
        out.append(s[start:i])
    return "".join(out)


def main() -> int:
    sys.stdout.write(strip_dump(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
