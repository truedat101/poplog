/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Assembly routines supporting process switching for AArch64
   Author:  Waldek Hebisch
   AArch64 port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'
#_INCLUDE 'process.ph'

lconstant macro (

    USP                     = "x19",
    PB                      = "x20",
    SP                      = "sp",

    _PD_EXECUTE             = @@PD_EXECUTE,
    _PD_EXIT                = @@PD_EXIT,
    _PD_FLAGS               = @@PD_FLAGS,
    _PD_FRAME_LEN           = @@PD_FRAME_LEN,
    _PD_NLOCALS             = @@PD_NLOCALS,
    _PD_NUM_STK_VARS        = @@PD_NUM_STK_VARS,
    _PD_REGMASK             = @@PD_REGMASK,
    _PD_TABLE               = @@PD_TABLE,
    _PS_CALLSTACK_LIM       = @@PS_CALLSTACK_LIM,
    _PS_CALLSTACK_PARTIAL   = @@PS_CALLSTACK_PARTIAL,
    _PS_FLAGS               = @@PS_FLAGS,
    _PS_PARTIAL_RETURN      = @@PS_PARTIAL_RETURN,
    _PS_STATE               = @@PS_STATE,

    BRANCH_std              = '4',
);

lconstant macro MOVFL   = "ldrb";

>_#

    .arch armv8-a
    .file   "aprocess.s"
    .text

    /* Swap out (suspend) process
    */
DEF_C_LAB (_swap_out_callstack)
    ;;; load process from user stack
    ldr  x0, [USP]
    ldr  x3, [x0, #_PS_CALLSTACK_LIM]
    str  x3, [x0, #_PS_CALLSTACK_PARTIAL]
    b so_test_finished

so_loop:
    ;;; make lr relative
    sub   x30, x30, PB

    ;;; If needed run dlocal expressions
    ldrb w1, [PB, #_PD_FLAGS]
    tst  w1, #_:M_PD_PROC_DLEXPR_CODE
    b.ne so_do_dlexpr

so_cont:
    ;;; Continue swap out after running dlocal expressions
    ;;; Stack pointer here still points to the stack frame

    MOVFL w1, [PB, #_PD_FRAME_LEN]
    ;;; Frame length is in words; shift left by 3 for 8-byte words
    sub   x3, x3, x1, lsl #3
    str   x3, [x0, #_PS_CALLSTACK_PARTIAL]

    str   x30, [x3], #8
    str   PB,  [x3], #8
    add   SP, SP, #16

    ;;; Save on-stack lvars into the process record

    MOVFL w0, [PB, #_PD_NUM_STK_VARS]
    cbz   w0, do_save_dl
l_save_loop:
    ldr   x12, [SP], #8
    str   x12, [x3], #8
    subs  w0, w0, #1
    b.ne  l_save_loop
do_save_dl:
    ;;; Save dynamic locals

    ;;;   test if any

    MOVFL w0, [PB, #_PD_NLOCALS]
    cbz   w0, perm_reg_save

    ;;; Compute pointer to end of PD_TABLE array
    ;;; Each entry is 8 bytes (pointer-sized)
    add   x2, PB, x0, lsl #3
    add   x2, x2, #(_PD_TABLE - 8)

dl_save_loop:
    ;;;      save idval in process record and restore previous from stack

    ldr   x1,  [x2], #-8
    ldr   x12, [x1]
    str   x12, [x3], #8
    ldr   x12, [SP], #8
    str   x12, [x1]

    subs  w0, w0, #1
    b.ne  dl_save_loop

perm_reg_save:
    ;;; Save permanent registers to process struct, restore
    ;;; previous values from stack frame
    ;;; Bit positions in _PD_REGMASK:
    ;;;   bit 9 = x25, bit 8 = x24, bit 7 = x23,
    ;;;   bit 6 = x22, bit 4 = x21

    ldrh  w0, [PB, #_PD_REGMASK]

    ;;; bit 9 -> x25
    tst   w0, #512
    b.eq  1f
    str   x25, [x3], #8
    ldr   x25, [SP], #8
1:
    ;;; bit 8 -> x24
    tst   w0, #256
    b.eq  2f
    str   x24, [x3], #8
    ldr   x24, [SP], #8
2:
    ;;; bit 7 -> x23
    tst   w0, #128
    b.eq  3f
    str   x23, [x3], #8
    ldr   x23, [SP], #8
3:
    ;;; bit 6 -> x22
    tst   w0, #64
    b.eq  4f
    str   x22, [x3], #8
    ldr   x22, [SP], #8
4:
    ;;; bit 5 currently not needed
    ;;; tst   w0, #32
    ;;; b.eq  5f
    ;;; str   ..., [x3], #8
    ;;; ldr   ..., [SP], #8
    ;;; 5:

    ;;; bit 4 -> x21
    tst   w0, #16
    b.eq  6f
    str   x21, [x3], #8
    ldr   x21, [SP], #8
6:
    ;;; Restore LR and PB from the caller's stack frame
    ldr   x30, [SP], #8
    ldr   PB,  [SP]

so_test_finished:
    ldr   x0, [USP]
    ldr   x1, [x0, #_PS_STATE]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    cmp   x3, x1
    b.hi  so_loop

    ;;; Finished, save flags and chain to procedure on user stack
    add   USP, USP, #8
    mov   x1, #0
    str   x1, [x0, #_PS_CALLSTACK_PARTIAL]
    strh  w1, [x0, #_PS_FLAGS]
    ldr   x0, [USP], #8
    ldr   x16, [x0, #_PD_EXECUTE]
    br    x16

so_do_dlexpr:
    str   x30, [x0, #_PS_PARTIAL_RETURN]
    ;;; Jump to suspend code
    ldr   x16, [PB, #_PD_EXIT]
    sub   x16, x16, #(BRANCH_std << 1)
    br    x16

DEF_C_LAB (_swap_out_continue)
    ldr   x0, [USP]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    ldr   x30, [x0, #_PS_PARTIAL_RETURN]
    b so_cont

    ;;; Swap in (resume) process
DEF_C_LAB (_swap_in_callstack)
    ;;; load process from user stack
    ldr   x0, [USP]
    ldr   x3, [x0, #_PS_STATE]
    str   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    b si_test_finished

si_loop:
    str   x30, [SP, #-16]!
    ldr   PB,  [x3, #8]
    MOVFL w1, [PB, #_PD_FRAME_LEN]
    ;;; Advance x3 by frame_len words (8 bytes each)
    add   x3, x3, x1, lsl #3
    str   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    sub   x3, x3, #8

    ;;; Restore registers from process record and store values
    ;;; to stack

    ldrh  w0, [PB, #_PD_REGMASK]

    ;;; bit 4 -> x21
    tst   w0, #16
    b.eq  1f
    str   x21, [SP, #-16]!
    ldr   x21, [x3], #-8
1:
    ;;; bit 5 currently not needed
    ;;; tst   w0, #32
    ;;; b.eq  2f
    ;;; str   ..., [SP, #-16]!
    ;;; ldr   ..., [x3], #-8
    ;;; 2:

    ;;; bit 6 -> x22
    tst   w0, #64
    b.eq  3f
    str   x22, [SP, #-16]!
    ldr   x22, [x3], #-8
3:
    ;;; bit 7 -> x23
    tst   w0, #128
    b.eq  4f
    str   x23, [SP, #-16]!
    ldr   x23, [x3], #-8
4:
    ;;; bit 8 -> x24
    tst   w0, #256
    b.eq  5f
    str   x24, [SP, #-16]!
    ldr   x24, [x3], #-8
5:
    ;;; bit 9 -> x25
    tst   w0, #512
    b.eq  6f
    str   x25, [SP, #-16]!
    ldr   x25, [x3], #-8
6:
    ;;; Restore dynamic locals

    ;;;   test if any

    MOVFL w0, [PB, #_PD_NLOCALS]
    cbz   w0, do_restore_lvars

    add   x2, PB, #_PD_TABLE

dl_restore_loop:
    ;;;      save idval in stack and restore previous from process record
    ldr   x1,  [x2], #8
    ldr   x12, [x1]
    str   x12, [SP, #-16]!
    ldr   x12, [x3], #-8
    str   x12, [x1]

    subs  w0, w0, #1
    b.ne  dl_restore_loop

do_restore_lvars:
    ;;; Restore on-stack lvars from the process record
    MOVFL w0, [PB, #_PD_NUM_STK_VARS]
    cbz   w0, si_lvars_done
l_restore_loop:
    ldr   x12, [x3], #-8
    str   x12, [SP, #-16]!
    subs  w0, w0, #1
    b.ne  l_restore_loop

si_lvars_done:
    str   PB, [SP, #-16]!
    ldr   x30, [x3, #-8]

    ldr   x0, [USP]

    ;;; If needed run dlocal expressions
    ldrb  w1, [PB, #_PD_FLAGS]
    tst   w1, #_:M_PD_PROC_DLEXPR_CODE
    b.ne  si_do_dlexpr

si_cont:
    add   x30, x30, PB

si_test_finished:
    ldr   x0, [USP]
    ldr   x1, [x0, #_PS_CALLSTACK_LIM]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    cmp   x3, x1
    b.lo  si_loop
    ;;; Finished, chain to procedure on user stack
    add   USP, USP, #8
    mov   x1, #0
    str   x1, [x0, #_PS_CALLSTACK_PARTIAL]
    ldr   x0, [USP], #8
    ldr   x16, [x0, #_PD_EXECUTE]
    br    x16

si_do_dlexpr:
    str   x30, [x0, #_PS_PARTIAL_RETURN]
    ;;; Jump to resume code
    ldr   x16, [PB, #_PD_EXIT]
    sub   x16, x16, #BRANCH_std
    br    x16


    ;;; Continue swap in after running procedure init code
DEF_C_LAB (_swap_in_continue)
    ldr   x0, [USP]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    ldr   x30, [x0, #_PS_PARTIAL_RETURN]
    b si_cont

    .align 3
usrhi_lab:
    .xword I_LAB(_userhi)
DEF_C_LAB (_ussave)
    b C_LAB (_ussave)

DEF_C_LAB (_usrestore)
    ldr   x0, [USP, #8]
    ldr   x1, [USP], #16
    cbz   x0, usr_done
    adrp  x2, I_LAB(_userhi)
    add   x2, x2, :lo12:I_LAB(_userhi)
    mov   x3, USP
    ldr   x2, [x2]
    sub   USP, USP, x0
    cmp   x2, x3
    mov   x0, USP
    b.eq  usr_loop2
usr_loop1:
    ldr   x12, [x3], #8
    str   x12, [x0], #8
    cmp   x3, x2
    b.ne  usr_loop1
usr_loop2:
    ldr   x12, [x1], #8
    str   x12, [x0], #8
    cmp   x0, x2
    b.ne  usr_loop2
usr_done:
    ret

DEF_C_LAB (_userasund)
    b C_LAB (_userasund)
