/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Miscellaneous assembler routines for RISC-V (rv64gc, LP64D)
   Author:  Waldek Hebisch
   AArch64 port by truedat101
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'

vars
    _call_stack_lim, _plog_trail_sp, _plog_trail_lim,
    ;

lconstant macro (
    USP             = "x9",      ;;; s1 (matches genproc R10)
    PB              = "x18",     ;;; s2 (matches genproc R11)
    LR              = "ra",      ;;; x1
    W0              = "x10",     ;;; a0 (64-bit despite the name)
    W1              = "x11",     ;;; a1
    CHAIN_REG       = "x12",     ;;; a2 (matches genproc R2)
    _K_APPLY        = @@K_APPLY,
    _KEY            = @@KEY,
    _P_BACK         = @@P_BACK,
    _P_FRONT        = @@P_FRONT,
    _PD_EXECUTE     = @@PD_EXECUTE,
    _PD_EXIT        = @@PD_EXIT,
    _PD_FRAME_LEN   = @@PD_FRAME_LEN,
    _PD_UPDATER     = @@PD_UPDATER,
    _RF_CONT        = @@RF_CONT,
    _SF_OWNER       = @@SF_OWNER,
    _V_BYTES        = @@V_BYTES,

);

section $-Sys;

constant
        procedure (Async_raise_signal, Call_overflow, Conspair,
                   Plog$-Area_overflow, User_overflow,
                   dummy_procedure_callback_helper),
;

endsection;

>_#

    .option arch, rv64gc
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    ;;; RISC-V conditional branches reach only +-4 KB, so a branch to a (far)
    ;;; external symbol inverts the test and reaches it with `tail` (+-2 GB).
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
    .file   "amisc.s"

;;; Wrapping in POP object
	.text
   .quad  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

;;; _popenter: calling (applying) a Pop object.  Object in a0 (= genproc WK_REG).
;;; Indirect-branch target loaded into t5 (= genproc R16); x16/x3 scratch -> t5/a3.
	.balign 8
.L1.p_key:
    .quad C_LAB(procedure_key)
.L1.i_key:
    .quad C_LAB(integer_key) + _K_APPLY
.L1.d_key:
    .quad C_LAB(weakref decimal_key) + _K_APPLY
DEF_C_LAB (_popenter)
    adr_l a1, .L1.p_key
    ld   a1, 0(a1)
    andi t0, a0, 1
    bnez t0, .L2.simple
    ld   a3, _KEY(a0)
    bne  a1, a3, .L2.struct
    ld   t5, _PD_EXECUTE(a0)
    jr   t5
.L2.simple:
    addi USP, USP, -8
    sd   a0, 0(USP)
    andi t0, a0, 2
    beqz t0, .L2.dec
    adr_l a0, .L1.i_key
    ld   a0, 0(a0)
    ld   a0, 0(a0)
    ld   a0, _RF_CONT(a0)
    ld   t5, _PD_EXECUTE(a0)
    jr   t5
.L2.dec:
    adr_l a0, .L1.d_key
    ld   a0, 0(a0)
    ld   a0, 0(a0)
    ld   a0, _RF_CONT(a0)
    ld   t5, _PD_EXECUTE(a0)
    jr   t5
.L2.struct:
    addi USP, USP, -8
    sd   a0, 0(USP)
    ld   a0, _KEY(a0)
    ld   a0, _K_APPLY(a0)
    ld   a0, _RF_CONT(a0)
    ld   t5, _PD_EXECUTE(a0)
    jr   t5

;;; _popuenter: applying the updater of a Pop object (object in a0)
DEF_C_LAB (_popuenter)
    adr_l a1, .L1.p_key
    ld   a1, 0(a1)
    andi t0, a0, 1
    bnez t0, .L3.simple
    ld   a3, _KEY(a0)
    bne  a1, a3, .L3.struct
    ;;; fall through

;;; _popuncenter: unchecked updater entry (a0 assumed a procedure)
DEF_C_LAB (_popuncenter)
    mv   a3, a0
    ld   a0, _PD_UPDATER(a0)
    adr_l a1, .L.false
    ld   a1, 0(a1)
    beq  a0, a1, .L3.no_updater
    ld   t5, _PD_EXECUTE(a0)
    jr   t5
.L3.no_updater:
    addi USP, USP, -8
    sd   a3, 0(USP)
    adr_l t5, .L3.nonpd
    ld   t5, 0(t5)
    jr   t5
	.balign 8
.L3.nonpd:
    .quad XC_LAB(-> Sys$-Exec_nonpd)
.L3.simple:
    addi USP, USP, -8
    sd   a0, 0(USP)
    andi t0, a0, 2
    beqz t0, .L3.dec
    adr_l a0, .L1.i_key
    ld   a0, 0(a0)
    ld   a0, 0(a0)
    j    .L3.call_upd
.L3.dec:
    adr_l a0, .L1.d_key
    ld   a0, 0(a0)
    ld   a0, 0(a0)
    j    .L3.call_upd
.L3.struct:
    addi USP, USP, -8
    sd   a0, 0(USP)
    ld   a0, _KEY(a0)
    ld   a0, _K_APPLY(a0)
.L3.call_upd:
    ld   a0, _RF_CONT(a0)
    ld   a0, _PD_UPDATER(a0)
    adr_l a1, .L.false
    ld   a1, 0(a1)
    beq  a0, a1, .L3.call_upd_no_updater
    ld   t5, _PD_EXECUTE(a0)
    jr   t5
.L3.call_upd_no_updater:
    adr_l t5, .L3.nonpd
    ld   t5, 0(t5)
    jr   t5

;;; _erase_sp_1: erase 1 word from the call stack
DEF_C_LAB (_erase_sp_1)
    addi sp, sp, 8
    ret

DEF_C_LAB (_nextframe)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, _SF_OWNER(a0)
    lbu  a1, _PD_FRAME_LEN(a1)
    slli a1, a1, 3
    add  a0, a0, a1
    addi USP, USP, -8
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_unwind_frame)
    lbu  a0, _PD_FRAME_LEN(PB)
    slli a0, a0, 3
    add  a0, sp, a0
    ld   CHAIN_REG, -8(a0)
    sd   ra, -8(a0)
    ld   t5, _PD_EXIT(PB)
    jr   t5

DEF_C_LAB (_syschain_caller)
    call C_LAB (_unwind_frame)
    ;;; Fall through
DEF_C_LAB (_syschain)
    ld   a0, 0(USP)
    addi USP, USP, 8
    mv   LR, CHAIN_REG
    j    C_LAB(_popenter)

DEF_C_LAB (_sysncchain_caller)
    call C_LAB (_unwind_frame)
    ;;; Fall through
DEF_C_LAB (_sysncchain)
    ld   a0, 0(USP)
    addi USP, USP, 8
    mv   LR, CHAIN_REG
    ld   t5, _PD_EXECUTE(a0)
    jr   t5

DEF_C_LAB (_iscompound)
    ld   a0, 0(USP)
    andi t0, a0, 1
    bnez t0, .Lcomp_false
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lcomp_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_issimple)
    ld   a0, 0(USP)
    andi t0, a0, 1
    beqz t0, .Lsimp_false
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lsimp_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_isinteger)
    ld   a0, 0(USP)
    addi USP, USP, 8
    andi t0, a0, 2
    beqz t0, .Lisint_false
    adr_l a0, .L.true
    ld   a0, 0(a0)
    addi USP, USP, -8
    sd   a0, 0(USP)
    ret
.Lisint_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    addi USP, USP, -8
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_neg)
    ld   a0, 0(USP)
    bgez a0, .Lneg_false
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lneg_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_zero)
    ld   a0, 0(USP)
    bnez a0, .Lzero_false
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lzero_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_not)
    adr_l a0, .L.false
    ld   a0, 0(a0)
    ld   a1, 0(USP)
    bne  a1, a0, .Lnot_done
    adr_l a0, .L.true
    ld   a0, 0(a0)
.Lnot_done:
    sd   a0, 0(USP)
    ret

DEF_C_LAB 7 (_eq)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    bne  a1, a0, .Leq_ne
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Leq_ne:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 7 (_neq)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    beq  a1, a0, .Lneq_eq
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lneq_eq:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 6 (_gr)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    bgeu a0, a1, .Lgr_false       ;;; b.ls: a1 <= a0 unsigned
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lgr_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 6 (_greq)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    bltu a1, a0, .Lgreq_false     ;;; b.cc: a1 < a0 unsigned
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lgreq_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 6 (_lt)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    bgeu a1, a0, .Llt_false       ;;; b.cs: a1 >= a0 unsigned
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Llt_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 6 (_lteq)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    bltu a0, a1, .Llteq_false     ;;; b.hi: a1 > a0 unsigned
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Llteq_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 6 (_sgr)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    bge  a0, a1, .Lsgr_false      ;;; b.le: a1 <= a0 signed
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lsgr_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 6 (_sgreq)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    blt  a1, a0, .Lsgreq_false    ;;; b.lt: a1 < a0 signed
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lsgreq_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 6 (_slt)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    bge  a1, a0, .Lslt_false      ;;; b.ge: a1 >= a0 signed
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lslt_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

	.balign 8
.L.false:
    .quad C_LAB(false)
.L.true:
    .quad C_LAB(true)

DEF_C_LAB 6 (_slteq)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    blt  a0, a1, .Lslteq_false    ;;; b.gt: a1 > a0 signed
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lslteq_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB 4 (_bitst)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    and  t0, a1, a0
    beqz t0, .Lbitst_false
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.Lbitst_false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_haskey)
    ld   a0, 8(USP)
    ld   a1, 0(USP)
    addi USP, USP, 8
    andi t0, a0, 1
    bnez t0, .L6.false
    ld   a0, _KEY(a0)
    bne  a0, a1, .L6.false
    adr_l a0, .L.true
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret
.L6.false:
    adr_l a0, .L.false
    ld   a0, 0(a0)
    sd   a0, 0(USP)
    ret

	.balign 8
.L7.1:
    .quad C_LAB(integer_key)
.L7.2:
    .quad C_LAB(weakref decimal_key)
DEF_C_LAB (_datakey)
    ld   a0, 0(USP)
    addi USP, USP, 8
    andi t0, a0, 1
    bnez t0, .L7.3
    ld   a0, _KEY(a0)
    addi USP, USP, -8
    sd   a0, 0(USP)
    ret
.L7.3:
    andi t0, a0, 2
    beqz t0, .L7.4
    adr_l a0, .L7.1
    ld   a0, 0(a0)
    addi USP, USP, -8
    sd   a0, 0(USP)
    ret
.L7.4:
    adr_l a0, .L7.2
    ld   a0, 0(a0)
    addi USP, USP, -8
    sd   a0, 0(USP)
    ret

	.balign 8
.L8.1:
    .quad I_LAB(Sys$- _free_pairs)
DEF_C_LAB (_conspair)
    adr_l a0, .L8.1
    ld   a0, 0(a0)
    ld   a1, 0(a0)
    andi t0, a1, 1
    bnez_x t0, XC_LAB(Sys$-Conspair)
    ld   a2, _P_BACK(a1)
    sd   a2, 0(a0)
    ld   a0, 0(USP)
    addi USP, USP, 8
    sd   a0, _P_BACK(a1)
    ld   a0, 0(USP)
    sd   a0, _P_FRONT(a1)
    sd   a1, 0(USP)
    ret

DEF_C_LAB (_subss)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    addi a0, a0, (_V_BYTES-1)
    srai a1, a1, 3
    add  t0, a0, a1
    lbu  a0, 0(t0)
    slli a0, a0, 3
    ori  a0, a0, 7
    sd   a0, 0(USP)
    ret

DEF_C_LAB (-> _subss)
DEF_C_LAB (_u_subss)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    addi USP, USP, 8
    ld   a2, 0(USP)
    addi USP, USP, 8
    addi a0, a0, (_V_BYTES-1)
    srai a2, a2, 3
    srai a1, a1, 3
    add  t0, a0, a1
    sb   a2, 0(t0)
    ret

DEF_C_LAB (_locc)
    ld   t1, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    addi USP, USP, 8
    ld   a2, 0(USP)
    beqz a1, .L10.not_found
    li   a0, 0
.L10.loop:
    add  t0, a2, a0
    lbu  a3, 0(t0)
    beq  a3, t1, .L10.found
    addi a0, a0, 1
    bne  a0, a1, .L10.loop
.L10.not_found:
    li   a0, -1
.L10.found:
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_skpc)
    ld   t1, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)
    addi USP, USP, 8
    ld   a2, 0(USP)
    beqz a1, .L19.not_found
    li   a0, 0
.L19.loop:
    add  t0, a2, a0
    lbu  a3, 0(t0)
    bne  a3, t1, .L19.found
    addi a0, a0, 1
    bne  a0, a1, .L19.loop
.L19.not_found:
    li   a0, -1
.L19.found:
    sd   a0, 0(USP)
    ret

;;; _checkplogall: check the prolog trail, then fall into _checkall
DEF_C_LAB (_checkplogall)
    adr_l a0, C_LAB(_special_var_block)
    ld   a1, _SVB_OFFS(_plog_trail_sp)(a0)
    ld   a2, _SVB_OFFS(_plog_trail_lim)(a0)
    bgtu a1, a2, C_LAB (_checkall)
    tail XC_LAB(weakref[prologvar_key] Sys$-Plog$-Area_overflow)

DEF_C_LAB (_checkall)
    adr_l a0, C_LAB(_special_var_block)
.L11.do_checkall:
    ld   a1, _SVB_OFFS(_call_stack_lim)(a0)
    bltu sp, a1, .L11.do_call_overflow
.L11.check_user:
    ld   a1, _SVB_OFFS(_userlim)(a0)
    bltu USP, a1, .L11.do_user_overflow
.L11.check_interrupt:
    ld   a1, _SVB_OFFS(_trap)(a0)
    andi t0, a1, 1
    beqz t0, .L11.ret
    adr_l a1, I_LAB(_disable)
    ld   a1, 0(a1)
    andi t0, a1, 1
    beqz_x t0, XC_LAB(Sys$-Async_raise_signal)
.L11.ret:
    ret

.L11.do_call_overflow:
    adr_l a1, I_LAB(_disable)
    ld   a1, 0(a1)
    andi t0, a1, 2
    beqz_x t0, XC_LAB(Sys$-Call_overflow)
    j    .L11.check_user

.L11.do_user_overflow:
    adr_l a1, I_LAB(_disable)
    ld   a1, 0(a1)
    andi t0, a1, 2
    beqz_x t0, XC_LAB(Sys$-User_overflow)
    j    .L11.check_interrupt

DEF_C_LAB (_checkinterrupt)
    adr_l a1, I_LAB(_trap)
    ld   a1, 0(a1)
    andi t0, a1, 1
    beqz t0, .L12.ret
    j    C_LAB (_checkall)
.L12.ret:
    ret

	.balign 8
.L11.dummy_procedure_helper:
    .quad XC_LAB(Sys$-dummy_procedure_callback_helper)

EXTERN_NAME(pop_print):
    ;;; Save ra, fp, PB and the Pop register-locals x19/x20.  48-byte frame.
    addi sp, sp, -48
    sd   x8,  0(sp)           ;;; fp (= arm64 x29 slot)
    sd   ra,  8(sp)           ;;; lr
    sd   x19, 16(sp)          ;;; was x21
    sd   x20, 24(sp)          ;;; was x22
    sd   PB,  32(sp)
    mv   x8, sp

    adr_l PB, .L11.dummy_procedure_helper
    ld   PB, 0(PB)
    addi sp, sp, -16
    sd   PB, 0(sp)

    addi USP, USP, -8
    sd   a0, 0(USP)
    call XC_LAB(sys_syspr)

    addi sp, sp, 16
    ld   PB,  32(sp)
    ld   x20, 24(sp)
    ld   x19, 16(sp)
    ld   ra,  8(sp)
    ld   x8,  0(sp)
    addi sp, sp, 48
    ret

;;; End wrapper: set size
	.text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
