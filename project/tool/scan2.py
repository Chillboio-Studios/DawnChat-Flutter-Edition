import json, os, re, sys
LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib', 'src')
ids = set(json.load(open('/tmp/en_msgids.json', encoding='utf-8')))
RX = re.compile(r"^(\s*)(['\"])((?:(?!\2)[^\\$\n]|\\.)*)\2,\s*$")
for root, _, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        p = os.path.join(root, fn)
        lines = open(p, encoding='utf-8').read().split('\n')
        for n, line in enumerate(lines):
            m = RX.match(line)
            if m and m.group(3).replace("\\'", "'") in ids:
                prev = lines[n - 1].strip()[-50:]
                print('%s:%d: %s | %s' % (os.path.basename(p), n + 1, m.group(3)[:36], prev))
