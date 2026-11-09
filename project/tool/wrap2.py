#!/usr/bin/env python3
"""Wraps UI string literals that match a catalog msgid with tr(). Idempotent. Usage: wrap2.py [--dry]"""
import json
import os
import re
import sys

LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib', 'src'))
I18N = os.path.join(LIB, 'core', 'i18n.dart')
msgids = set(json.load(open('/tmp/en_msgids.json', encoding='utf-8')))
dry = '--dry' in sys.argv

# Wording used by this app that the web client words differently.
ALIAS = {
    'Delete account': 'Delete Account', 'Admin panel': 'Admin Panel', 'Custom Status': 'Custom status',
    'Set custom status': 'Custom status', 'All messages': 'All Messages', 'Mentions only': 'Mentions Only',
    'Channel settings': 'Channel Settings', 'Group name': 'Group Name', 'Channel name': 'Channel Name',
    'Channel description': 'Channel Description', 'Create webhook': 'Create Webhook',
    'Webhook name': 'Webhook Name', 'Server name': 'Server Name', 'Server description': 'Server Description',
    'Create role': 'Create Role', 'Role name': 'Role Name', 'New password': 'New Password',
    'Display name': 'Display Name', 'Log out all other sessions': 'Log out of all other sessions',
    'Create a bot': 'Create Bot', 'Delete bot': 'Delete Bot', 'Add Friend': 'Add friend',
    'Would you like to create a group or a server?': 'Would you like to create a new group or server?',
    'No KLIPY GIFs found': 'No GIFs found',
}

CTX = (
    r"(?:\bText\(\s*"
    r"|\b(?:title|label|labelText|hintText|hint|tooltip|message|description|subtitle|helperText|header|"
    r"placeholder|confirmLabel|cancelLabel|actionLabel|emptyText|semanticLabel|buttonText|okText|"
    r"confirmText|cancelText|submitLabel|heading|caption|body|action)\s*:\s*"
    r"|\bMenuItem\.\w+\(\s*"
    r"|\b(?:DlgAction|_LinkButton|SectionTitle|FlowTitle|FlowSubtitle)\(\s*"
    r"|\bshowSnack\(\s*\w+\s*,\s*)"
)
LIT = r"(?P<q>['\"])(?P<s>(?:(?!(?P=q))[^\\$\n]|\\.)*)(?P=q)"
RX = re.compile(r"(?P<ctx>" + CTX + r")" + LIT)
STANDALONE = re.compile(r"^(?P<ctx>\s*)" + LIT + r"(?P<tail>,\s*)$", re.M)
UNESC = re.compile(r"\\(.)")


def unescape(s):
    return UNESC.sub(lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)


def rel_import(path):
    return "import '%s';" % os.path.relpath(I18N, os.path.dirname(path)).replace(os.sep, '/')


def resolve(val):
    if val in msgids:
        return val
    return ALIAS.get(val)


def add_import(out, path):
    imp = rel_import(path)
    if imp in out:
        return out
    lines = out.split('\n')
    last = -1
    for i, l in enumerate(lines):
        if l.startswith('import ') or l.startswith('export '):
            j = i
            while not lines[j].rstrip().endswith(';'):
                j += 1
            last = j
    lines.insert(last + 1, imp)
    return '\n'.join(lines)


hits = 0
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
            mid = resolve(unescape(raw))
            if mid is None:
                return m.group(0)
            hits += 1
            esc = mid.replace("\\", "\\\\").replace("'", "\\'") if m.group('q') == "'" else mid
            return m.group('ctx') + "tr(" + m.group('q') + esc + m.group('q') + ")"

        def sub2(m):
            global hits
            mid = resolve(unescape(m.group('s')))
            if mid is None:
                return m.group(0)
            hits += 1
            esc = mid.replace("'", "\\'") if m.group('q') == "'" else mid
            return m.group('ctx') + "tr(" + m.group('q') + esc + m.group('q') + ")" + m.group('tail')

        out = STANDALONE.sub(sub2, RX.sub(sub, src))
        if out != src and not dry:
            open(path, 'w', encoding='utf-8').write(add_import(out, path))

print('wrapped', hits, file=sys.stderr)
