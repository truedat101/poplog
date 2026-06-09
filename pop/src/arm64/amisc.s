/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Misc assembly routines for AArch64
   Author:  Waldek Hebisch
   AArch64 port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'

vars
    _call_stack_lim, _plog_trail_sp, _plog_trail_lim,
    ;

lconstant macro (
    USP             = "x19",
    PB              = "x20",
    LR              = "x30",
    W0              = "x0",
    W1              = "x1",
    CHAIN_REG       = "x2",
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
    .file   "amisc.s"

;;; Wrapping in POP object
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF
   .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

;;; _popenter: calling (applying) Pop object
#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
.L1.p_key:
    .xword C_LAB(procedure_key)
.L1.i_key:
    .xword C_LAB(integer_key) + _K_APPLY
.L1.d_key:
    .xword C_LAB(weakref decimal_key) + _K_APPLY
    ;;; x0 contains called object
DEF_C_LAB (_popenter)
    adr_l x1, .L1.p_key
    ldr  x1, [x1]
    tst  x0, #1
    b.ne .L2.simple
    ldr  x3, [x0, #_KEY]
    cmp  x1, x3
    b.ne .L2.struct
    ldr  x16, [x0, #_PD_EXECUTE]
    br   x16
    ;;; simple object
.L2.simple:
    str  x0, [USP, #-8]!
    tst  x0, #2
    b.eq .L2.dec
    ;;; integer
    adr_l x0, .L1.i_key
    ldr  x0, [x0]
    ldr  x0, [x0]
    ldr  x0, [x0, #_RF_CONT]
    ldr  x16, [x0, #_PD_EXECUTE]
    br   x16
    ;;; decimal
.L2.dec:
    adr_l x0, .L1.d_key
    ldr  x0, [x0]
    ldr  x0, [x0]
    ldr  x0, [x0, #_RF_CONT]
    ldr  x16, [x0, #_PD_EXECUTE]
    br   x16
    ;;; composite, but not a procedure
.L2.struct:
    str  x0, [USP, #-8]!
    ldr  x0, [x0, #_KEY]
    ldr  x0, [x0, #_K_APPLY]
    ldr  x0, [x0, #_RF_CONT]
    ldr  x16, [x0, #_PD_EXECUTE]
    br   x16

;;; _popuenter: calling (applying) updater of Pop object
;;; x0 contains the object
DEF_C_LAB (_popuenter)
    adr_l x1, .L1.p_key
    ldr  x1, [x1]
    tst  x0, #1
    b.ne .L3.simple
    ldr  x3, [x0, #_KEY]
    cmp  x1, x3
    b.ne .L3.struct
    ;;; fall through

;;; Unchecked entry into updater, assumes object in x0 is a procedure,
;;; but still checks for existence of updater
DEF_C_LAB (_popuncenter)
    mov  x3, x0
    ldr  x0, [x0, #_PD_UPDATER]
    adr_l x1, .L.false
    ldr  x1, [x1]
    cmp  x0, x1
    b.eq .L3.no_updater
    ldr  x16, [x0, #_PD_EXECUTE]
    br   x16
.L3.no_updater:
    str  x3, [USP, #-8]!
    adr_l x16, .L3.nonpd
    ldr  x16, [x16]
    br   x16
#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
.L3.nonpd:
    .xword XC_LAB(-> Sys$-Exec_nonpd)
    ;;; simple object
.L3.simple:
    str  x0, [USP, #-8]!
    tst  x0, #2
    b.eq .L3.dec
    ;;; integer
    adr_l x0, .L1.i_key
    ldr  x0, [x0]
    ldr  x0, [x0]
    b    .L3.call_upd
    ;;; decimal
.L3.dec:
    adr_l x0, .L1.d_key
    ldr  x0, [x0]
    ldr  x0, [x0]
    b    .L3.call_upd
    ;;; composite, but not a procedure
.L3.struct:
    str  x0, [USP, #-8]!
    ldr  x0, [x0, #_KEY]
    ldr  x0, [x0, #_K_APPLY]
.L3.call_upd:
    ldr  x0, [x0, #_RF_CONT]
    ldr  x0, [x0, #_PD_UPDATER]
    adr_l x1, .L.false
    ldr  x1, [x1]
    cmp  x0, x1
    b.eq .L3.call_upd_no_updater
    ldr  x16, [x0, #_PD_EXECUTE]
    br   x16
.L3.call_upd_no_updater:
    adr_l x16, .L3.nonpd
    ldr  x16, [x16]
    br   x16

;;; _erase_sp_1: erase 1 word from call stack, used for error
;;; recovery
DEF_C_LAB (_erase_sp_1)
    add  sp, sp, #8
    ret

DEF_C_LAB (_nextframe)
    ldr  x0, [USP], #8
    ldr  x1, [x0, #_SF_OWNER]
    ldrb w1, [x1, #_PD_FRAME_LEN]
    lsl  x1, x1, #3
    add  x0, x0, x1
    str  x0, [USP, #-8]!
    ret

DEF_C_LAB (_unwind_frame)
    ldrb w0, [PB, #_PD_FRAME_LEN]
    lsl  x0, x0, #3
    add  x0, sp, x0
    ldr  CHAIN_REG, [x0, #-8]
    str  x30, [x0, #-8]
    ldr  x16, [PB, #_PD_EXIT]
    br   x16

DEF_C_LAB (_syschain_caller)
    bl   C_LAB (_unwind_frame)
    ;;; Fall through
DEF_C_LAB (_syschain)
    ldr  x0, [USP], #8
    mov  LR, CHAIN_REG
    b    C_LAB(_popenter)

DEF_C_LAB (_sysncchain_caller)
    bl   C_LAB (_unwind_frame)
    ;;; Fall through
DEF_C_LAB (_sysncchain)
    ldr  x0, [USP], #8
    mov  LR, CHAIN_REG
    ldr  x16, [x0, #_PD_EXECUTE]
    br   x16

DEF_C_LAB (_iscompound)
    ldr  x0, [USP]
    tst  x0, #1
    b.ne .Lcomp_false
    adr_l x0, .L.true
    ldr  x0, [x0]
    str  x0, [USP]
    ret
.Lcomp_false:
    adr_l x0, .L.false
    ldr  x0, [x0]
    str  x0, [USP]
    ret

DEF_C_LAB (_issimple)
    ldr  x0, [USP]
    tst  x0, #1
    b.eq .Lsimp_false
    adr_l x0, .L.true
    ldr  x0, [x0]
    str  x0, [USP]
    ret
.Lsimp_false:
    adr_l x0, .L.false
    ldr  x0, [x0]
    str  x0, [USP]
    ret

DEF_C_LAB (_isinteger)
    ldr  x0, [USP], #8
    tst  x0, #2
    b.eq .Lisint_false
    adr_l x0, .L.true
    ldr  x0, [x0]
    str  x0, [USP, #-8]!
    ret
.Lisint_false:
    adr_l x0, .L.false
    ldr  x0, [x0]
    str  x0, [USP, #-8]!
    ret

DEF_C_LAB (_neg)
    ldr  W0, [USP]
    cmp  W0, #0
    b.ge .Lneg_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lneg_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB (_zero)
    ldr  W0, [USP]
    cmp  W0, #0
    b.ne .Lzero_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lzero_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB (_not)
    adr_l W0, .L.false
    ldr  W0, [W0]
    ldr  W1, [USP]
    cmp  W1, W0
    b.ne .Lnot_done
    adr_l W0, .L.true
    ldr  W0, [W0]
.Lnot_done:
    str  W0, [USP]
    ret

DEF_C_LAB 7 (_eq)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.ne .Leq_ne
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Leq_ne:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 7 (_neq)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.eq .Lneq_eq
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lneq_eq:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 6 (_gr)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.ls .Lgr_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lgr_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 6 (_greq)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.cc .Lgreq_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lgreq_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 6 (_lt)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.cs .Llt_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Llt_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 6 (_lteq)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.hi .Llteq_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Llteq_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 6 (_sgr)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.le .Lsgr_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lsgr_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 6 (_sgreq)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.lt .Lsgreq_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lsgreq_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 6 (_slt)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.ge .Lslt_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lslt_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
.L.false:
    .xword C_LAB(false)
.L.true:
    .xword C_LAB(true)

DEF_C_LAB 6 (_slteq)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    cmp  W1, W0
    b.gt .Lslteq_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lslteq_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB 4 (_bitst)
    ldr  W0, [USP], #8
    ldr  W1, [USP]
    tst  W1, W0
    b.eq .Lbitst_false
    adr_l W0, .L.true
    ldr  W0, [W0]
    str  W0, [USP]
    ret
.Lbitst_false:
    adr_l W0, .L.false
    ldr  W0, [W0]
    str  W0, [USP]
    ret

DEF_C_LAB (_haskey)
    ldr  x0, [USP, #8]
    ldr  x1, [USP], #8
    tst  x0, #1
    b.ne .L6.false
    ldr  x0, [x0, #_KEY]
    cmp  x0, x1
    b.ne .L6.false
    adr_l x0, .L.true
    ldr  x0, [x0]
    str  x0, [USP]
    ret
.L6.false:
    adr_l x0, .L.false
    ldr  x0, [x0]
    str  x0, [USP]
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
.L7.1:
    .xword C_LAB(integer_key)
.L7.2:
    .xword C_LAB(weakref decimal_key)
DEF_C_LAB (_datakey)
    ldr  x0, [USP], #8
    tst  x0, #1
    b.ne .L7.3
    ldr  x0, [x0, #_KEY]
    str  x0, [USP, #-8]!
    ret
.L7.3:
    tst  x0, #2
    b.eq .L7.4
    adr_l x0, .L7.1
    ldr  x0, [x0]
    str  x0, [USP, #-8]!
    ret
.L7.4:
    adr_l x0, .L7.2
    ldr  x0, [x0]
    str  x0, [USP, #-8]!
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
.L8.1:
    .xword I_LAB(Sys$- _free_pairs)
DEF_C_LAB (_conspair)
    adr_l x0, .L8.1
    ldr  x0, [x0]
    ldr  x1, [x0]
    tst  x1, #1
    bne_x XC_LAB(Sys$-Conspair)
    ldr  x2, [x1, #_P_BACK]
    str  x2, [x0]
    ldr  x0, [USP], #8
    str  x0, [x1, #_P_BACK]
    ldr  x0, [USP]
    str  x0, [x1, #_P_FRONT]
    str  x1, [USP]
    ret

DEF_C_LAB (_subss)
    ldr  x0, [USP], #8
    ldr  x1, [USP]
    add  x0, x0, #(_V_BYTES-1)
    asr  x1, x1, #3
    ldrb w0, [x0, x1]
    lsl  x0, x0, #3
    orr  x0, x0, #7
    str  x0, [USP]
    ret

DEF_C_LAB (-> _subss)
DEF_C_LAB (_u_subss)
    ldr  x0, [USP], #8
    ldr  x1, [USP], #8
    ldr  x2, [USP], #8
    add  x0, x0, #(_V_BYTES-1)
    asr  x2, x2, #3
    asr  x1, x1, #3
    strb w2, [x0, x1]
    ret

DEF_C_LAB (_locc)
    ldr  x12, [USP], #8
    ldr  x1, [USP], #8
    ldr  x2, [USP]
    cmp  x1, #0
    b.eq .L10.not_found
    mov  x0, #0
.L10.loop:
    ldrb w3, [x2, x0]
    cmp  x3, x12
    b.eq .L10.found
    add  x0, x0, #1
    cmp  x0, x1
    b.ne .L10.loop
.L10.not_found:
    mov  x0, #-1
.L10.found:
    str  x0, [USP]
    ret

DEF_C_LAB (_skpc)
    ldr  x12, [USP], #8
    ldr  x1, [USP], #8
    ldr  x2, [USP]
    cmp  x1, #0
    b.eq .L19.not_found
    mov  x0, #0
.L19.loop:
    ldrb w3, [x2, x0]
    cmp  x3, x12
    b.ne .L19.found
    add  x0, x0, #1
    cmp  x0, x1
    b.ne .L19.loop
.L19.not_found:
    mov  x0, #-1
.L19.found:
    str  x0, [USP]
    ret

;;; _checkplogall: check prolog trail and then fall into _checkall
DEF_C_LAB (_checkplogall)
    adr_l x0, C_LAB(_special_var_block)
    ldr  x1, [x0, #_SVB_OFFS(_plog_trail_sp)]
    ldr  x2, [x0, #_SVB_OFFS(_plog_trail_lim)]
    cmp  x1, x2
    b.hi C_LAB (_checkall)
    b    XC_LAB(weakref[prologvar_key] Sys$-Plog$-Area_overflow)

DEF_C_LAB (_checkall)
    adr_l x0, C_LAB(_special_var_block)
.L11.do_checkall:
    ldr  x1, [x0, #_SVB_OFFS(_call_stack_lim)]
    cmp  sp, x1
    b.cc .L11.do_call_overflow
.L11.check_user:
    ldr  x1, [x0, #_SVB_OFFS(_userlim)]
    cmp  USP, x1
    b.cc .L11.do_user_overflow
.L11.check_interrupt:
    ldr  x1, [x0, #_SVB_OFFS(_trap)]
    tst  x1, #1
    b.eq .L11.ret
    adr_l x1, I_LAB(_disable)
    ldr  x1, [x1]
    tst  x1, #1
    beq_x XC_LAB(Sys$-Async_raise_signal)
.L11.ret:
    ret

.L11.do_call_overflow:
    adr_l x1, I_LAB(_disable)
    ldr  x1, [x1]
    tst  x1, #2
    beq_x XC_LAB(Sys$-Call_overflow)
    b    .L11.check_user

.L11.do_user_overflow:
    adr_l x1, I_LAB(_disable)
    ldr  x1, [x1]
    tst  x1, #2
    beq_x XC_LAB(Sys$-User_overflow)
    b    .L11.check_interrupt

DEF_C_LAB (_checkinterrupt)
    adr_l x1, I_LAB(_trap)
    ldr  x1, [x1]
    tst  x1, #1
    b.eq .L12.ret
    b    C_LAB (_checkall)
.L12.ret:
    ret

#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
.L11.dummy_procedure_helper:
    .xword XC_LAB(Sys$-dummy_procedure_callback_helper)

EXTERN_NAME(pop_print):
    ;;; Save callee-saved registers: x21, x22 (Pop temps), PB, FP, LR
    stp  x29, x30, [sp, #-48]!
    stp  x21, x22, [sp, #16]
    str  PB, [sp, #32]
    mov  x29, sp

    adr_l PB, .L11.dummy_procedure_helper
    ldr  PB, [PB]
    str  PB, [sp, #-16]!

    str  x0, [USP, #-8]!
    bl   XC_LAB(sys_syspr)

    add  sp, sp, #16
    ldr  PB, [sp, #32]
    ldp  x21, x22, [sp, #16]
    ldp  x29, x30, [sp], #48
    ret

;;; End wrapper: set size
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
