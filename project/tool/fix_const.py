#!/usr/bin/env python3
"""Removes `const` from expressions the analyzer reports as non-constant (after tr() wrapping)."""
import os
import re
import subprocess
import sys

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CONST_CODES = re.compile(r'const|non_constant|invalid_constant')


def lex(src):
    """Returns (opener_stack_at(offset) provider data): list of (open_pos, close_pos, const_pos or None)."""
    spans = []
    stack = []
    i, n = 0, len(src)

    def skip_string(i):
        # i at opening quote; returns index after the string
        raw = i > 0 and src[i - 1] == 'r' and (i < 2 or not src[i - 2].isalnum())
        q = src[i]
        triple = src.startswith(q * 3, i)
        i += 3 if triple else 1
        while i < n:
            c = src[i]
            if c == '\\' and not raw:
                i += 2
                continue
            if triple and src.startswith(q * 3, i):
                return i + 3
            if not triple and c == q:
                return i + 1
            if not triple and c == '\n':
                return i
            if c == '$' and not raw and i + 1 < n and src[i + 1] == '{':
                depth = 0
                while i < n:
                    if src[i] == '{':
                        depth += 1
                    elif src[i] == '}':
                        depth -= 1
                        if depth == 0:
                            i += 1
                            break
                    elif src[i] in '\'"':
                        i = skip_string(i)
                        continue
                    i += 1
                continue
            i += 1
        return i

    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
        elif src.startswith('/*', i):
            j = src.find('*/', i)
            i = n if j < 0 else j + 2
        elif c in '\'"':
            i = skip_string(i)
        elif c in '([{':
            m = re.search(r'\bconst\b[\w\s.<>?,\[\]]*$', src[max(0, i - 200):i])
            cp = None
            if m and '\n\n' not in m.group(0) and ';' not in m.group(0):
                cp = max(0, i - 200) + m.start()
            stack.append((i, cp))
            i += 1
        elif c in ')]}':
            if stack:
                o, cp = stack.pop()
                spans.append((o, i, cp))
            i += 1
        else:
            i += 1
    return spans


def run_analyze():
    p = subprocess.run(['flutter', 'analyze', '--no-pub'], cwd=PROJECT, capture_output=True, text=True)
    errs = []
    for line in (p.stdout + p.stderr).split('\n'):
        m = re.match(r'\s+error • .* • (lib/\S+?):(\d+):(\d+) • (\w+)$', line)
        if m and CONST_CODES.search(m.group(4)):
            errs.append((m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)))
    return errs


def offset(src, line, col):
    pos = 0
    for _ in range(line - 1):
        pos = src.index('\n', pos) + 1
    return pos + col - 1


def main():
    for rnd in range(40):
        errs = run_analyze()
        print('round', rnd, 'const errors', len(errs), file=sys.stderr)
        if not errs:
            return
        by_file = {}
        for f, l, c, code in errs:
            by_file.setdefault(f, []).append((l, c, code))
        changed = False
        for f, items in by_file.items():
            path = os.path.join(PROJECT, f)
            src = open(path, encoding='utf-8').read()
            spans = lex(src)
            removals = set()
            for l, c, code in items:
                off = offset(src, l, c)
                enclosing = [s for s in spans if s[0] < off < s[1] and s[2] is not None]
                if enclosing:
                    inner = max(enclosing, key=lambda s: s[0])  # innermost const expression
                    removals.add(inner[2])
                else:
                    # top-level / field declaration: `const x = ...` -> `final x = ...`
                    ls = src.rfind('\n', 0, off) + 1
                    j = ls
                    while True:
                        k = src.rfind('const ', 0, off)
                        if k >= 0 and src[ls - 400 if ls > 400 else 0:off].count('const ') > 0:
                            removals.add(('final', k))
                        break
            for r in sorted(removals, key=lambda r: r if isinstance(r, int) else r[1], reverse=True):
                if isinstance(r, tuple):
                    k = r[1]
                    src = src[:k] + 'final ' + src[k + 6:]
                else:
                    src = src[:r] + src[r + 5:].lstrip(' ') if src[r + 5:r + 6] == ' ' else src[:r] + src[r + 5:]
                changed = True
            open(path, 'w', encoding='utf-8').write(src)
        if not changed:
            return


if __name__ == '__main__':
    main()
