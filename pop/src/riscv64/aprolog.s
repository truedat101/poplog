/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Prolog support assembly routines for RISC-V (rv64gc, LP64D)
   Author:  Waldek Hebisch
   AArch64 port by truedat101
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
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
    USP   = "x9",      ;;; s1 (matches genproc R10)
    PB    = "x18",     ;;; s2 (matches genproc R11)
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

    .option arch, rv64gc
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    ;;; Far conditional branch to an external symbol (RISC-V cond branches reach
    ;;; only +-4KB): invert and reach it with `tail`.
    .macro beqz_x rs, t
    bnez \\rs, 88f
    tail \\t
88:
    .endm
    .macro bnez_x rs, t
    beqz \\rs, 88f
    tail \\t
88:
    .endm
    .file   "aprolog.s"

;;; The _prolog_* "switch" primitives return their three-way result in a0
;;; (RISC-V has no condition flags): the ass.p I_PLOG_* handlers test it.
;;;   _prolog_unify_atom: a0 = 0 if unified, non-zero if not.
;;;   _prolog_term_switch / _prolog_pair_switch: a0 = +1 (unbound var, pushed on
;;;     the user stack), 0 (matched term/pair), -1 (mismatch).
;;; The term comes in a0, the functor/atom in a1, the arity (term_switch) in a2.

;;; Wrapping in POP object
	.text
   .quad  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

	.balign 8
.L11.special:
    .quad C_LAB(_special_var_block)

DEF_C_LAB (_prolog_save_check)
    ld   t0, .L11.special
    ld   t1, _SVB_OFFS(_plog_next_var)(t0)
    sd   t1, _SF_PLGSV_NEXT_VAR(sp)
    ld   t1, _SVB_OFFS(_plog_trail_sp)(t0)
    ld   t2, _SVB_OFFS(_plog_trail_barrier)(t0)
    sub  t1, t1, t2
    sd   t1, _SF_PLGSV_TRAIL_SP(sp)
    ld   t1, _SVB_OFFS(_plog_contn_sp)(t0)
    sd   t1, _SVB_OFFS(_plog_save_contn_sp)(t0)
    ld   t1, _SVB_OFFS(_plog_contn_top)(t0)
    sd   t1, _SF_PLGSV_CONTN_TOP(sp)
    ;;; Check for overflow etc.
    tail C_LAB (_checkplogall)

DEF_C_LAB (_prolog_restore)
    ld   t0, .L11.special
    ld   t1, _SF_PLGSV_NEXT_VAR(sp)
    sd   t1, _SVB_OFFS(_plog_next_var)(t0)
    ld   t1, _SVB_OFFS(_plog_save_contn_sp)(t0)
    sd   t1, _SVB_OFFS(_plog_contn_sp)(t0)
    ld   t1, _SF_PLGSV_CONTN_TOP(sp)
    sd   t1, _SVB_OFFS(_plog_contn_top)(t0)
    ld   t2, _SVB_OFFS(_plog_trail_barrier)(t0)
    ld   t1, _SF_PLGSV_TRAIL_SP(sp)
    add  t1, t1, t2
    ld   t2, _SVB_OFFS(_plog_trail_sp)(t0)
    beq  t1, t2, trail.done
    sd   t1, _SVB_OFFS(_plog_trail_sp)(t0)
trail.loop:
    ld   t3, 0(t1)
    addi t1, t1, 8
    sd   t3, _PGV_CONT(t3)
    bne  t1, t2, trail.loop
trail.done:
    ret

DEF_C_LAB (_prolog_unify_atom)
deref.loop3:
    andi t0, a0, 1
    bnez t0, notvar.ret
    ld   t2, _KEY(a0)
    ld   t1, plog.var_key
    bne  t2, t1, notvar.ret
    mv   t1, a0
    ld   a0, _PGV_CONT(a0)
    bne  a0, t1, deref.loop3
    ;;; Unbound variable: assign the atom and trail.  Result: unified (a0=0).
    sd   a1, _PGV_CONT(a0)
    ld   t3, plog_trail_sp.lab
    ld   t2, 0(t3)
    sd   a0, 0(t2)
    addi t2, t2, 8
    sd   t2, 0(t3)
    li   a0, 0
    ret
notvar.ret:
    ;;; deref'd term in a0, atom in a1: a0 = 0 if equal (unified), else non-zero
    sub  a0, a0, a1
    ret

	.balign 8
plog.pair_key:
    .quad C_LAB(pair_key)

DEF_C_LAB (_prolog_pair_switch)
deref.loop2:
    andi t0, a0, 1
    bnez t0, fail.ret
    ld   t2, _KEY(a0)
    ld   t1, plog.var_key
    bne  t2, t1, deref.notvar2
    mv   t1, a0
    ld   a0, _PGV_CONT(a0)
    bne  a0, t1, deref.loop2
    ;;; Unbound variable: push it, return a0 = 0 (var).
    addi USP, USP, -8
    sd   a0, 0(USP)
    li   a0, 0
    ret
deref.notvar2:
    ld   t1, plog.pair_key
    bne  t2, t1, fail.ret
    ;;; matched pair: leave a0 = the derefed pair (a positive pointer) so the
    ;;; following field-extraction can read its components.
    ret

	.balign 8
plog.term_key:
    .quad C_LAB(prologterm_key)

DEF_C_LAB (_prolog_term_switch)
deref.loop1:
    andi t0, a0, 1
    bnez t0, fail.ret
    ld   t2, _KEY(a0)
    ld   t1, plog.var_key
    bne  t2, t1, deref.notvar
    mv   t1, a0
    ld   a0, _PGV_CONT(a0)
    bne  a0, t1, deref.loop1
    ;;; Unbound variable: push it, return a0 = 0 (var).
    addi USP, USP, -8
    sd   a0, 0(USP)
    li   a0, 0
    ret
deref.notvar:
    ld   t1, plog.term_key
    bne  t2, t1, fail.ret
    ld   t2, _PGT_FUNCTOR(a0)
    bne  a1, t2, fail.ret
    ld   t2, _PGT_LENGTH(a0)
    srai t4, a2, 2                ;;; integer arity from the popint
    bne  t2, t4, fail.ret
    ;;; matched term: leave a0 = the derefed term (a positive pointer) so the
    ;;; following field-extraction can read its arguments.
    ret
fail.ret:
    li   a0, -1                   ;;; mismatch (shared by pair_switch + term_switch)
    ret

	.balign 8
plog_trail_sp.lab:
    .quad I_LAB(_plog_trail_sp)

DEF_C_LAB (_prolog_assign)
    ld   a0, 8(USP)
    ld   a1, 0(USP)
    addi USP, USP, 16
    sd   a1, _PGV_CONT(a0)
    ;;; Put the var on the trail
    ld   t3, plog_trail_sp.lab
    ld   t2, 0(t3)
    sd   a0, 0(t2)
    addi t2, t2, 8
    sd   t2, 0(t3)
    ret

	.balign 8
free_pairs.lab:
    .quad I_LAB(Sys$- _free_pairs)

DEF_C_LAB (_prolog_assign_pair)
    ld   a1, free_pairs.lab
    ld   a0, 0(a1)
    andi t0, a0, 1
    bnez_x t0, XC_LAB(Sys$-Plog$-Assign_pair)
    ld   t3, _P_BACK(a0)
    sd   t3, 0(a1)
    ld   t3, 16(USP)             ;;; the var
    ld   a1, 8(USP)              ;;; front
    ld   t4, 0(USP)              ;;; back
    addi USP, USP, 24
    sd   t4, _P_BACK(a0)
    sd   a1, _P_FRONT(a0)
    sd   a0, _PGV_CONT(t3)
    ;;; Put the var on the trail
    ld   a0, plog_trail_sp.lab
    ld   t4, 0(a0)
    sd   t3, 0(t4)
    addi t4, t4, 8
    sd   t4, 0(a0)
    ret

	.balign 8
plog.var_key:
    .quad C_LAB(prologvar_key)

DEF_C_LAB (_prolog_deref)
    ld   a0, 0(USP)
deref.loop:
    andi t0, a0, 1
    bnez t0, deref.ret
    ld   a1, _KEY(a0)
    ld   t3, plog.var_key
    bne  a1, t3, deref.ret
    mv   t4, a0
    ld   a0, _PGV_CONT(a0)
    bne  a0, t4, deref.loop
deref.ret:
    sd   a0, 0(USP)
    ret

	.balign 8
ref_key.lab:
    .quad C_LAB(ref_key)
next_var.lab:
    .quad I_LAB(_plog_next_var)

DEF_C_LAB (_prolog_newvar)
    ld   a1, next_var.lab
    ld   a0, 0(a1)
    ld   t3, ref_key.lab
    ld   t4, _KEY(a0)
    sub  t0, t3, t4
    beqz_x t0, XC_LAB(Sys$-Plog$-New_var)
    sd   a0, _PGV_CONT(a0)
    addi USP, USP, -8
    sd   a0, 0(USP)
    addi a0, a0, _PGV_SIZE
    sd   a0, 0(a1)
    ret

    .align  3

;;; End wrapper: set size
	.text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
