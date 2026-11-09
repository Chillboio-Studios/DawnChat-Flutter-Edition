import json, os, re, sys
LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib', 'src')
ids = set(json.load(open('/tmp/en_msgids.json', encoding='utf-8')))
LIT = re.compile(r"(?P<pre>.{0,40})(?P<q>['\"])(?P<s>(?:(?!(?P=q))[^\\$\n]|\\.)*)(?P=q)")
for root, _, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        p = os.path.join(root, fn)
        for n, line in enumerate(open(p, encoding='utf-8'), 1):
            for m in LIT.finditer(line):
                s = m.group('s').replace("\\'", "'")
                if s in ids and not m.group('pre').rstrip().endswith('tr(') and not line.lstrip().startswith(('import', 'export', 'part')):
                    print('%s:%d: %s' % (os.path.relpath(p, LIB), n, line.strip()[:110]))
