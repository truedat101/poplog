/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Lisp support assembly routines for AArch64
*/

#_<

#_INCLUDE 'declare.ph'

lconstant macro (

        ;;; User stack pointer

        USP     = "x19",
);

>_#

#_IF DEF UNIX_MACHO
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
#_ENDIF
    .file "alisp.s"
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
#_ELSE
	.text
#_ENDIF

;;; Wrapping in POP object
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
#_ELSE
	.text
#_ENDIF
   .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

L0._userhi:
    .xword I_LAB(_userhi)
nil.lab:
    .xword C_LAB(nil)

DEF_C_LAB (_setstklen)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #16
    add   x2, x2, x3
    sub   x2, x2, #6
    ;;; (nresults + saved_len) are POPINTS (scale 4/item); subtracting the two
    ;;; tags (#6) leaves 4*(items).  Stack items are 8 bytes on LP64, so double
    ;;; to get the byte offset 8*(items).  The ARM32 original omitted this (its
    ;;; items were 4 bytes); the matching inline I_SETSTACKLENGTH in ass.p
    ;;; already doubles.  Without it _setstklen set USP at half the distance,
    ;;; misaligning the user stack by 4 and underflowing -- the "Ste: stack
    ;;; empty" that blocked all Lisp eval (lisp_apply's nresults protocol).
    add   x2, x2, x2
    adr_l  x3, L0._userhi
    ldr   x3, [x3]
    ldr   x3, [x3]
    sub   x2, x3, x2
    cmp   USP, x2
    b.ne  1f
    ret
1:
    ;;; fall through
DEF_C_LAB (_setstklen_diff)
    ;;; if too short set and return
    cmp   USP, x2
    b.cs  2f
    mov   USP, x2
    ret
2:
    adr_l  x3, nil.lab
    ldr   x3, [x3]
str.loop:
    str   x3, [USP, #-8]!
    cmp   USP, x2
    b.ne  str.loop
    ret

;;; End wrapper: set size
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
#_ELSE
	.text
#_ENDIF
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
