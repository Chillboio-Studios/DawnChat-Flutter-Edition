#!/usr/bin/env python3
"""Wraps UI string literals that exactly match a catalog msgid with tr(). Usage: wrap_strings.py [--dry]"""
import json
import os
import re
import sys

LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib', 'src'))
I18N = os.path.join(LIB, 'core', 'i18n.dart')
msgids = set(json.load(open('/tmp/en_msgids.json', encoding='utf-8')))
dry = '--dry' in sys.argv

CTX = (
    r"(?:\bText\(\s*"
    r"|\b(?:title|label|labelText|hintText|hint|tooltip|message|description|subtitle|helperText|header|"
    r"placeholder|confirmLabel|cancelLabel|actionLabel|emptyText|semanticLabel|buttonText|okText|"
    r"confirmText|cancelText|submitLabel|heading|caption|body)\s*:\s*"
    r"|\bMenuItem\.\w+\(\s*"
    r"|\bshowSnack\(\s*\w+\s*,\s*)"
)
LIT = r"(?P<q>['\"])(?P<s>(?:(?!(?P=q))[^\\$\n]|\\.)*)(?P=q)"
RX = re.compile(r"(?P<ctx>" + CTX + r")" + LIT)

UNESC = re.compile(r"\\(.)")


def unescape(s):
    return UNESC.sub(lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)


def rel_import(path):
    r = os.path.relpath(I18N, os.path.dirname(path))
    return "import '%s';" % r.replace(os.sep, '/')


hits = 0
misses = {}
for root, _, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root, fn)
        if path == I18N:
            continue
        src = open(path, encoding='utf-8').read()

        def sub(m):
            global hits
            raw = m.group('s')
            val = unescape(raw)
            if val in msgids:
                hits += 1
                return m.group('ctx') + "tr(" + m.group('q') + raw + m.group('q') + ")"
            if re.search(r'[A-Za-z]{3}', val):
                misses.setdefault(val, []).append(os.path.relpath(path, LIB))
            return m.group(0)

        out = RX.sub(sub, src)
        if out != src and not dry:
            imp = rel_import(path)
            if imp not in out:
                # insert after the last import line
                lines = out.split('\n')
                idx = max((i for i, l in enumerate(lines) if l.startswith('import ')), default=-1)
                lines.insert(idx + 1, imp)
                out = '\n'.join(lines)
            open(path, 'w', encoding='utf-8').write(out)

print('wrapped', hits, file=sys.stderr)
json.dump(misses, open('/tmp/misses.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print('unmatched candidates', len(misses), file=sys.stderr)
