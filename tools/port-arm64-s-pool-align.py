#!/usr/bin/env python3
# 8-align each literal/key pool START in the hand-written arm64 .s on Mach-O.
# A pool start = a label line whose NEXT meaningful line is a data directive
# (.xword/.quad/...) and whose PREVIOUS meaningful line is NOT data (so it's a
# fresh data block after code). Aligning there pads only between code and the
# pool (harmless), never mid-pool. Gated by popc #_IF; ELF byte-identical.
import re, sys
DATA = re.compile(r'^\s*\.(xword|quad|long|word|short|byte|8byte|4byte)\b')
LABEL = re.compile(r'^\s*[.A-Za-z_][\w.$]*:\s*$')
def meaningful(lines, i, step):
    i += step
    while 0 <= i < len(lines):
        s = lines[i].strip()
        if s and not s.startswith(';;;'):
            return lines[i]
        i += step
    return ''
GATE = ['#_IF DEF UNIX_MACHO', '\t.p2align\t3', '#_ENDIF']
for path in sys.argv[1:]:
    lines = open(path).read().split('\n')
    out, n = [], 0
    for i, ln in enumerate(lines):
        if LABEL.match(ln) and DATA.match(meaningful(lines, i, +1)) \
                and not DATA.match(meaningful(lines, i, -1)):
            out += GATE; n += 1
        out.append(ln)
    open(path, 'w').write('\n'.join(out))
    print(f"  {path.split('/')[-1]:12s} aligned {n} pool starts")
