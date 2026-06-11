#!/usr/bin/env python3
# Mechanical Mach-O port of the hand-written arm64 runtime .s files.
# The only ELF-isms in these files are `.arch armv8-a` and `:lo12:`.
#   * `adrp R, X`              -> `adr_l R, X`      (full address into R)
#   * `add  R, R, :lo12:X`     -> removed           (adr_l already added the lo12)
#   * `[R, #:lo12:X]`/`[R,:lo12:X]` -> `[R]`        (R already holds &X)
#   * `.arch armv8-a`          -> OS-gated macro block defining `adr_l`
# adr_l expands per-OS; the ELF path is identical to the original instructions.
# Order matters: rewrite adrp/add/ldr FIRST, then insert the macro block LAST
# (via a function-replacement, so re doesn't eat the doubled backslashes).
import re, sys

MACRO_BLOCK = r"""#_IF DEF UNIX_MACHO
    ;;; Mach-O PC-relative address load (backslashes doubled: popc escapes .s).
    .macro adr_l reg, sym
    adrp \\reg, \\sym@PAGE
    add  \\reg, \\reg, \\sym@PAGEOFF
    .endm
    ;;; Mach-O: a conditional branch may NOT target an external symbol; invert
    ;;; the test and reach it with an unconditional b (which may be external).
    .macro beq_x t
    b.ne 8f
    b \\t
8:
    .endm
    .macro bne_x t
    b.eq 8f
    b \\t
8:
    .endm
#_ELSE
    .arch armv8-a
    .macro adr_l reg, sym
    adrp \\reg, \\sym
    add  \\reg, \\reg, :lo12:\\sym
    .endm
    .macro beq_x t
    b.eq \\t
    .endm
    .macro bne_x t
    b.ne \\t
    .endm
#_ENDIF"""

for path in sys.argv[1:]:
    src = open(path).read()
    # C: drop the redundant `add R, R, :lo12:...` line (R must repeat)
    src, nc = re.subn(r'(?m)^[ \t]*add[ \t]+(\w+)[ \t]*,[ \t]*\1[ \t]*,[ \t]*:lo12:[^\n]*\n', '', src)
    # B: adrp -> adr_l (mnemonic only)
    src, nb = re.subn(r'(?m)^([ \t]*)adrp\b', r'\1adr_l', src)
    # D: [R, #:lo12:X] -> [R]
    src, nd = re.subn(r'\[(\w+)[ \t]*,[ \t]*#?:lo12:[^\]]+\]', r'[\1]', src)
    # E: conditional branch to an external (XC_LAB) -> beq_x/bne_x macro
    src, ne1 = re.subn(r'(?m)^([ \t]*)b\.eq\b([ \t]+XC_LAB)', r'\1beq_x\2', src)
    src, ne2 = re.subn(r'(?m)^([ \t]*)b\.ne\b([ \t]+XC_LAB)', r'\1bne_x\2', src)
    # A (LAST): .arch armv8-a -> macro block; function repl => no escape munging
    src, na = re.subn(r'(?m)^[ \t]*\.arch[ \t]+armv8-a[ \t]*$', lambda m: MACRO_BLOCK, src)
    open(path, 'w').write(src)
    residual = src.count(':lo12:') - (1 if na else 0)   # 1 legit :lo12: in ELF macro branch
    print(f"  {path.split('/')[-1]:12s} arch={na} adrp->adr_l={nb} add-dropped={nc} ldoff-stripped={nd} bcond_ext={ne1+ne2}  residual:lo12:={residual}")
