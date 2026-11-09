#!/usr/bin/env python3
"""Converts the web client's lingui .po catalogs into compact msgid -> msgstr JSON assets."""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'DawnChat-For-Web', 'packages', 'client', 'components', 'i18n', 'catalogs')
DST = os.path.join(ROOT, 'project', 'assets', 'i18n')

ESC = {'n': '\n', 't': '\t', '"': '"', '\\': '\\', 'r': '\r'}


def unquote(s):
    s = s.strip()
    assert s.startswith('"') and s.endswith('"'), s
    return re.sub(r'\\(.)', lambda m: ESC.get(m.group(1), m.group(1)), s[1:-1])


def parse(path):
    entries = []
    cur = {}
    field = None
    fuzzy = False

    def flush():
        nonlocal cur, fuzzy
        if 'msgid' in cur and 'msgstr' in cur:
            entries.append((cur.get('msgctxt'), cur['msgid'], cur['msgstr'], fuzzy))
        cur = {}
        fuzzy = False

    with open(path, encoding='utf-8') as f:
        for raw in f:
            line = raw.rstrip('\n')
            if not line.strip():
                flush()
                field = None
            elif line.startswith('#~'):
                field = None  # obsolete
            elif line.startswith('#,'):
                fuzzy = 'fuzzy' in line
            elif line.startswith('#'):
                continue
            elif line.startswith('msgctxt '):
                field = 'msgctxt'
                cur[field] = unquote(line[8:])
            elif line.startswith('msgid '):
                if 'msgstr' in cur:
                    flush()
                field = 'msgid'
                cur[field] = unquote(line[6:])
            elif line.startswith('msgstr '):
                field = 'msgstr'
                cur[field] = unquote(line[7:])
            elif line.startswith('"') and field:
                cur[field] += unquote(line)
        flush()
    return entries


def main():
    os.makedirs(DST, exist_ok=True)
    total = 0
    for code in sorted(os.listdir(SRC)):
        po = os.path.join(SRC, code, 'messages.po')
        if not os.path.isfile(po) or code in ('en', 'dev'):
            continue
        out = {}
        for ctx, mid, mstr, fuzzy in parse(po):
            if not mid or not mstr or fuzzy or ctx:
                continue
            if mstr == mid:
                continue
            # rich-text placeholders such as <0/> cannot be rendered in plain strings
            if re.search(r'<\d', mid):
                continue
            out[mid] = mstr
        with open(os.path.join(DST, code + '.json'), 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
        total += os.path.getsize(os.path.join(DST, code + '.json'))
        print(code, len(out), file=sys.stderr)
    print('total bytes', total, file=sys.stderr)

    # English source strings, used by the string-wrapping tool.
    en = {}
    for ctx, mid, mstr, fuzzy in parse(os.path.join(SRC, 'en', 'messages.po')):
        if mid and not ctx:
            en[mid] = mstr or mid
    with open('/tmp/en_msgids.json', 'w', encoding='utf-8') as f:
        json.dump(sorted(en), f, ensure_ascii=False)


if __name__ == '__main__':
    main()
