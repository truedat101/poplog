#!/usr/bin/env python3
# Wrap bare C-function bl/b targets in EXTERN_NAME() so they get the Mach-O
# leading underscore (ELF output is unchanged: EXTERN_NAME(x) -> x on ELF).
# These are direct calls to C runtime / libc routines written ELF-style (no _).
import re, sys
FUNCS = (r'do_bgi_(?:add|sub|negate|negate_no_ov|lshift|rshiftl|mult|mult_add|'
         r'sub_mult|div)|do_quotient_estimate(?:_init)?|copy_external_arguments|'
         r'memcmp|memmove|memset')
pat = re.compile(r'(?m)^([ \t]*)(bl|b)[ \t]+(' + FUNCS + r')[ \t]*$')
for path in sys.argv[1:]:
    src = open(path).read()
    src, n = pat.subn(r'\1\2 EXTERN_NAME(\3)', src)
    open(path, 'w').write(src)
    print(f"  {path.split('/')[-1]:12s} wrapped {n} bare C-function refs")
