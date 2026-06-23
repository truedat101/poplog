/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Prolog support assembly routines for AArch64
   Author:  Waldek Hebisch
   AArch64 port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'

constant procedure (
    $-Sys$-Plog$-Assign_pair, Sys$-Plog$-New_var,
    ),
;

vars
    _plog_contn_sp, _plog_contn_top,  _plog_next_var, _plog_save_contn_sp,
     _plog_trail_barrier, _plog_trail_sp,
     ;

lconstant macro (
    USP   = "x19",
    PB    = "x20",
    _KEY            = @@KEY,
    _PGT_FUNCTOR    = @@PGT_FUNCTOR,
    _PGT_LENGTH     = @@PGT_LENGTH,
    _PGV_CONT       = @@PGV_CONT,
    _PGV_SIZE       = @@(struct PLOGVAR)++,
    _P_BACK         = @@P_BACK,
    _P_FRONT        = @@P_FRONT,
    _SF_PLGSV_NEXT_VAR  = @@SF_PLGSV_NEXT_VAR,
    _SF_PLGSV_CONTN_TOP = @@SF_PLGSV_CONTN_TOP,
    _SF_PLGSV_TRAIL_SP  = @@SF_PLGSV_TRAIL_SP,
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
    .file   "aprolog.s"
#_IF DEF UNIX_MACHO
	.section	__POPSEED,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF

;;; Wrapping in POP object
#_IF DEF UNIX_MACHO
	.section	__POPSEED,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF
   .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
.L11.special:
    .xword C_LAB(_special_var_block)

DEF_C_LAB (_prolog_save_check)
    ldr  x0, .L11.special
    ldr  x1, [x0, #_SVB_OFFS(_plog_next_var)]
    str  x1, [sp, #_SF_PLGSV_NEXT_VAR]
    ldr  x1, [x0, #_SVB_OFFS(_plog_trail_sp)]
    ldr  x2, [x0, #_SVB_OFFS(_plog_trail_barrier)]
    sub  x1, x1, x2
    str  x1, [sp, #_SF_PLGSV_TRAIL_SP]

    ldr  x1, [x0, #_SVB_OFFS(_plog_contn_sp)]
    str  x1, [x0, #_SVB_OFFS(_plog_save_contn_sp)]
    ldr  x1, [x0, #_SVB_OFFS(_plog_contn_top)]
    str  x1, [sp, #_SF_PLGSV_CONTN_TOP]

    ;;; Check for overflow etc.
    b C_LAB (_checkplogall)

DEF_C_LAB (_prolog_restore)
    ldr  x0, .L11.special
    ldr  x1, [sp, #_SF_PLGSV_NEXT_VAR]
    str  x1, [x0, #_SVB_OFFS(_plog_next_var)]
    ldr  x1, [x0, #_SVB_OFFS(_plog_save_contn_sp)]
    str  x1, [x0, #_SVB_OFFS(_plog_contn_sp)]
    ldr  x1, [sp, #_SF_PLGSV_CONTN_TOP]
    str  x1, [x0, #_SVB_OFFS(_plog_contn_top)]

    ldr  x2, [x0, #_SVB_OFFS(_plog_trail_barrier)]
    ldr  x1, [sp, #_SF_PLGSV_TRAIL_SP]
    add  x1, x1, x2
    ldr  x2, [x0, #_SVB_OFFS(_plog_trail_sp)]
    cmp  x1, x2
    b.eq trail.done
    str  x1, [x0, #_SVB_OFFS(_plog_trail_sp)]
trail.loop:
    ldr  x3, [x1], #8
    str  x3, [x3, #_PGV_CONT]
    cmp  x1, x2
    b.ne trail.loop
trail.done:
    ret

DEF_C_LAB (_prolog_unify_atom)
deref.loop3:
    tst  x0, #1
    b.ne notvar.ret
    ldr  x3, [x0, #_KEY]
    ldr  x9, plog.var_key
    cmp  x3, x9
    b.ne notvar.ret
    mov  x9, x0
    ldr  x0, [x0, #_PGV_CONT]
    cmp  x0, x9
    b.ne deref.loop3
    ;;; Unbound variable: assign atom and trail
    str  x1, [x0, #_PGV_CONT]
    ldr  x2, plog_trail_sp.lab
    ldr  x3, [x2]
    str  x0, [x3], #8
    str  x3, [x2]
    ;;; Flags are still set to EQ (from cmp x0, x9 which was equal)
    ret
notvar.ret:
    cmp  x0, x1
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
plog.pair_key:
    .xword C_LAB(pair_key)

DEF_C_LAB (_prolog_pair_switch)
deref.loop2:
    tst  x0, #1
    b.ne fail.ret
    ldr  x3, [x0, #_KEY]
    ldr  x9, plog.var_key
    cmp  x3, x9
    b.ne deref.notvar2
    mov  x9, x0
    ldr  x0, [x0, #_PGV_CONT]
    cmp  x0, x9
    b.ne deref.loop2
    ;;; Unbound variable: push onto user stack
    str  x0, [USP, #-8]!
    ;;; set flags: x0 is nonzero so we get HI (unsigned higher)
    cmp  x0, #0
    ret
deref.notvar2:
    ldr  x9, plog.pair_key
    cmp  x3, x9
    b.ne fail.ret
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
plog.term_key:
    .xword C_LAB(prologterm_key)

DEF_C_LAB (_prolog_term_switch)
deref.loop1:
    tst  x0, #1
    b.ne fail.ret
    ldr  x3, [x0, #_KEY]
    ldr  x9, plog.var_key
    cmp  x3, x9
    b.ne deref.notvar
    mov  x9, x0
    ldr  x0, [x0, #_PGV_CONT]
    cmp  x0, x9
    b.ne deref.loop1
    ;;; Unbound variable: push onto user stack
    str  x0, [USP, #-8]!
    ;;; set flags: x0 is nonzero so we get HI (unsigned higher)
    cmp  x0, #0
    ret
deref.notvar:
    ldr  x9, plog.term_key
    cmp  x3, x9
    b.ne fail.ret
    ldr  x3, [x0, #_PGT_FUNCTOR]
    cmp  x1, x3
    b.ne fail.ret
    ldr  x3, [x0, #_PGT_LENGTH]
    asr  x4, x2, #2
    cmp  x3, x4
    b.eq term.match
    b    fail.ret
term.match:
    ret
fail.ret:
    ;;; set flags to CC (unsigned lower): compare 0 < 1
    mov  x3, #0
    cmp  x3, #1
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
plog_trail_sp.lab:
    .xword I_LAB(_plog_trail_sp)

DEF_C_LAB (_prolog_assign)
    ldr  x0, [USP, #8]
    ldr  x1, [USP], #16
    str  x1, [x0, #_PGV_CONT]
    ;;; Put var on trail
    ldr  x2, plog_trail_sp.lab
    ldr  x3, [x2]
    str  x0, [x3], #8
    str  x3, [x2]
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
free_pairs.lab:
    .xword I_LAB(Sys$- _free_pairs)

DEF_C_LAB (_prolog_assign_pair)
    ldr  x1, free_pairs.lab
    ldr  x0, [x1]
    tst  x0, #1
    bne_x XC_LAB(Sys$-Plog$-Assign_pair)
    ldr  x2, [x0, #_P_BACK]
    str  x2, [x1]
    ldr  x2, [USP, #16]
    ldr  x1, [USP, #8]
    ldr  x3, [USP], #24
    str  x3, [x0, #_P_BACK]
    str  x1, [x0, #_P_FRONT]
    str  x0, [x2, #_PGV_CONT]
    ;;; Put var on trail
    ldr  x0, plog_trail_sp.lab
    ldr  x3, [x0]
    str  x2, [x3], #8
    str  x3, [x0]
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
plog.var_key:
    .xword C_LAB(prologvar_key)

DEF_C_LAB (_prolog_deref)
    ldr  x0, [USP]
deref.loop:
    tst  x0, #1
    b.ne deref.ret
    ldr  x1, [x0, #_KEY]
    ldr  x2, plog.var_key
    cmp  x1, x2
    b.ne deref.ret
    mov  x3, x0
    ldr  x0, [x0, #_PGV_CONT]
    cmp  x0, x3
    b.ne deref.loop
deref.ret:
    str  x0, [USP]
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
ref_key.lab:
    .xword C_LAB(ref_key)

next_var.lab:
    .xword I_LAB(_plog_next_var)

DEF_C_LAB (_prolog_newvar)
    ldr  x1, next_var.lab
    ldr  x0, [x1]
    ldr  x2, ref_key.lab
    ldr  x3, [x0, #_KEY]
    cmp  x2, x3
    beq_x XC_LAB(Sys$-Plog$-New_var)
    str  x0, [x0, #_PGV_CONT]
    str  x0, [USP, #-8]!
    add  x0, x0, #_PGV_SIZE
    str  x0, [x1]
    ret

    .align  3

;;; End wrapper: set size
#_IF DEF UNIX_MACHO
	.section	__POPSEED,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
