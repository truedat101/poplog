#!/usr/bin/env python3
# Route the hand-written arm64 .s `.text` directives into __DATA,__popseed on
# Mach-O (so their objmod headers / procedure-record .quad pointer fields are
# dyld-rebasable, not text-relocs), gated by popc #_IF. ELF keeps `.text`.
import re, sys
BLOCK = "#_IF DEF UNIX_MACHO\n\t.section\t__DATA,__popseed\n#_ELSE\n\t.text\n#_ENDIF"
for path in sys.argv[1:]:
    src = open(path).read()
    src, n = re.subn(r'(?m)^[ \t]*\.text[ \t]*$', lambda m: BLOCK, src)
    open(path, 'w').write(src)
    print(f"  {path.split('/')[-1]:12s} {n} .text -> __popseed")
