#!/usr/bin/env python3
"""Display-site tr() wrapping for data-driven static labels."""
import os
import sys

LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'lib', 'src', 'ui'))

# (file, old, new, expected_count)
EDITS = [
    ('settings/channel_settings.dart', 'title: Text(p.$2),', 'title: Text(tr(p.$2)),', 1),
    ('settings/channel_settings.dart', 'child: Text(p.$2)', 'child: Text(tr(p.$2))', 1),
    ('settings/channel_settings.dart', 'title: Text(p.$1),', 'title: Text(tr(p.$1)),', 1),
    ('settings/channel_settings.dart', "isServer ? 'Delete Channel' : 'Delete / Leave'", "tr(isServer ? 'Delete Channel' : 'Delete / Leave')", 1),
    ('settings/server_settings.dart', 'title: Text(e.$2),', 'title: Text(tr(e.$2)),', 1),
    ('settings/server_settings.dart', 'child: Text(e.$2)', 'child: Text(tr(e.$2))', 1),
    ('settings/settings_pages.dart', 'title: Text(title),', 'title: Text(tr(title)),', 3),
    ('settings/settings_pages.dart', 'title: Text(t),', 'title: Text(tr(t)),', 2),
    ('settings/settings_pages.dart', 'description: Text(d),', 'description: Text(tr(d)),', 1),
    ('settings/settings_pages.dart', 'description: Text(desc),', 'description: Text(tr(desc)),', 1),
    ('settings/settings_pages.dart', 'label: Text(i.$1)', 'label: Text(tr(i.$1))', 1),
    ('interface/sidebars.dart', 'title: Text(label),', 'title: Text(tr(label)),', 1),
    ('interface/server_rail.dart', "Text(label, style: const TextStyle(fontSize: 14))", "Text(tr(label), style: const TextStyle(fontSize: 14))", 1),
    ('menus/user_menu.dart', 'Text(widget.label, style: const TextStyle(fontSize: 12', 'Text(tr(widget.label), style: const TextStyle(fontSize: 12', 1),
    ('menus/user_menu.dart', 'Text(widget.label, style: const TextStyle(fontSize: 14', 'Text(tr(widget.label), style: const TextStyle(fontSize: 14', 1),
    ('auth/flows.dart', '          Text(label),', '          Text(tr(label)),', 1),
    ('auth/flows.dart', 'label: Text(m)', 'label: Text(tr(m))', 1),
    ('profile/profile.dart', 'Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500', 'Text(tr(title), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500', 1),
    ('messaging/markdown_view.dart', 'Flexible(child: Text(label, overflow: TextOverflow.ellipsis))', 'Flexible(child: Text(tr(label), overflow: TextOverflow.ellipsis))', 1),
    ('channel/message_list.dart', 'children: [Expanded(child: Text(label)), Text(action), trailing]', 'children: [Expanded(child: Text(tr(label))), Text(tr(action)), trailing]', 1),
]

bad = 0
for f, old, new, count in EDITS:
    p = os.path.join(LIB, f)
    s = open(p, encoding='utf-8').read()
    n = s.count(old)
    if n != count:
        print('MISMATCH', f, repr(old), 'found', n, 'expected', count, file=sys.stderr)
        bad += 1
        continue
    s = s.replace(old, new)
    imp = "import '%s';" % os.path.relpath(os.path.join(LIB, '..', 'core', 'i18n.dart'), os.path.dirname(p))
    if imp not in s:
        lines = s.split('\n')
        last = -1
        for i, l in enumerate(lines):
            if l.startswith('import '):
                j = i
                while not lines[j].rstrip().endswith(';'):
                    j += 1
                last = j
        lines.insert(last + 1, imp)
        s = '\n'.join(lines)
    open(p, 'w', encoding='utf-8').write(s)
print('done, mismatches:', bad, file=sys.stderr)
