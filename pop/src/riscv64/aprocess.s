/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Process (call-stack) swap for RISC-V (rv64gc, LP64D)
   AArch64 port by truedat101
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'
#_INCLUDE 'process.ph'

lconstant macro (

    USP                     = "x9",      ;;; s1 (matches genproc R10)
    PB                      = "x18",     ;;; s2 (matches genproc R11)
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

>_#

    .option arch, rv64gc
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    .file   "aprocess.s"
	.text

;;; Register remap: arm64 scratch x0-x8/x12/x16/x30 -> RISC-V a0-a7 / s8(carried
;;; resume) / t1 / t5(indirect branch) / ra; x9-as-scratch -> t0 (x9 is USP).
;;; The Pop register-locals x19-x23 (saved/restored below) keep their numbers.
;;; PD_REGMASK bits: x19=bit0, x20=bit1, x21=bit2, x22=bit3, x23=bit4 (genproc
;;; M_CREATE_SF), NOT arm64's bits 4/6/7/8/9.  PS_FLAGS is vestigial (zeroed).

    /* --- Swap out (suspend) the live call stack into the process record ---
       sp points at the frame base: [sp+0]=SF_OWNER(PB), [sp+8+i*8]=SF_LOCALS,
       [sp+(flen-1)*8]=SF_RETURN_ADDR.  flen even -> whole 16-byte units. */
DEF_C_LAB (_swap_out_callstack)
    ld    a0, 0(USP)                    ;;; process record
    ld    a3, _PS_CALLSTACK_LIM(a0)     ;;; record write ptr (fills downward)
    sd    a3, _PS_CALLSTACK_PARTIAL(a0)
    j     so_test_finished

so_loop:
    ld    PB, 0(SP)                     ;;; PB = SF_OWNER of current frame
    sub   ra, ra, PB                    ;;; make resume address relative

    lbu   a1, _PD_FLAGS(PB)
    andi  t0, a1, _:M_PD_PROC_DLEXPR_CODE
    bnez  t0, so_do_dlexpr

so_cont:
    lbu   a6, _PD_FRAME_LEN(PB)         ;;; flen (word count, byte field)
    slli  t0, a6, 3
    sub   a3, a3, t0                    ;;; reserve this frame's record slot
    sd    a3, _PS_CALLSTACK_PARTIAL(a0)
    sd    ra, 0(a3)                     ;;; relative return address
    sd    PB, 8(a3)                     ;;; owner
    addi  a3, a3, 16

    addi  a4, SP, 8                     ;;; a4 -> SF_LOCALS[0] (frame read cursor)

    ;;; on-stack lvars: frame -> record
    lbu   a5, _PD_NUM_STK_VARS(PB)
    beqz  a5, so_save_dl
so_lv_loop:
    ld    t1, 0(a4)
    addi  a4, a4, 8
    sd    t1, 0(a3)
    addi  a3, a3, 8
    addiw a5, a5, -1
    bnez  a5, so_lv_loop

so_save_dl:
    ;;; dynamic locals: current idval -> record, frame's saved-old -> ident
    lbu   a5, _PD_NLOCALS(PB)
    beqz  a5, so_save_regs
    addi  a2, PB, _PD_TABLE
so_dl_loop:
    ld    a1, 0(a2)                     ;;; identifier (PD_TABLE forward)
    addi  a2, a2, 8
    ld    t1, 0(a1)                     ;;; current idval
    sd    t1, 0(a3)                     ;;;   -> record
    addi  a3, a3, 8
    ld    t1, 0(a4)                     ;;; saved-old from frame slot
    addi  a4, a4, 8
    sd    t1, 0(a1)                     ;;;   -> identifier
    addiw a5, a5, -1
    bnez  a5, so_dl_loop

so_save_regs:
    ;;; register locals x19..x23 (ascending; PD_REGMASK bits 0..4): current value
    ;;; -> record, frame's saved value -> register.
    lhu   a5, _PD_REGMASK(PB)
    andi  t0, a5, 1                     ;;; bit0 -> x19
    beqz  t0, 1f
    sd    x19, 0(a3)
    addi  a3, a3, 8
    ld    x19, 0(a4)
    addi  a4, a4, 8
1:
    andi  t0, a5, 2                     ;;; bit1 -> x20
    beqz  t0, 2f
    sd    x20, 0(a3)
    addi  a3, a3, 8
    ld    x20, 0(a4)
    addi  a4, a4, 8
2:
    andi  t0, a5, 4                     ;;; bit2 -> x21
    beqz  t0, 3f
    sd    x21, 0(a3)
    addi  a3, a3, 8
    ld    x21, 0(a4)
    addi  a4, a4, 8
3:
    andi  t0, a5, 8                     ;;; bit3 -> x22
    beqz  t0, 4f
    sd    x22, 0(a3)
    addi  a3, a3, 8
    ld    x22, 0(a4)
    addi  a4, a4, 8
4:
    andi  t0, a5, 16                    ;;; bit4 -> x23
    beqz  t0, 5f
    sd    x23, 0(a3)
    addi  a3, a3, 8
    ld    x23, 0(a4)
    addi  a4, a4, 8
5:
    ;;; advance sp past the whole (16-aligned) frame; next resume addr from
    ;;; this frame's SF_RETURN_ADDR (now at sp-8).
    slli  t0, a6, 3
    add   SP, SP, t0
    ld    ra, -8(SP)

so_test_finished:
    ld    a0, 0(USP)
    ld    a1, _PS_STATE(a0)
    ld    a3, _PS_CALLSTACK_PARTIAL(a0)
    bgtu  a3, a1, so_loop

    ;;; Finished.  Restore the resuming frame's PB from its SF_OWNER at [sp+0].
    ld    PB, 0(SP)

    ;;; save flags (zeroed) and chain to the procedure on the user stack
    addi  USP, USP, 8
    li    a1, 0
    sd    a1, _PS_CALLSTACK_PARTIAL(a0)
    sh    a1, _PS_FLAGS(a0)
    ld    a0, 0(USP)
    addi  USP, USP, 8
    ld    t5, _PD_EXECUTE(a0)
    jr    t5

so_do_dlexpr:
    sd    ra, _PS_PARTIAL_RETURN(a0)
    ;;; Jump to the suspend code (sp at frame base, frame intact)
    ld    t5, _PD_EXIT(PB)
    addi  t5, t5, -(BRANCH_std << 1)
    jr    t5

DEF_C_LAB (_swap_out_continue)
    ld    a0, 0(USP)
    ld    a3, _PS_CALLSTACK_PARTIAL(a0)
    ld    ra, _PS_PARTIAL_RETURN(a0)
    j     so_cont

    /* --- Swap in (resume) a saved call stack, rebuilding frames on sp ---
       Frames from PS_STATE (outermost) upward; outermost lands deepest. */
DEF_C_LAB (_swap_in_callstack)
    mv    s8, ra                        ;;; carried resume addr (arm64 x8)
    ld    a0, 0(USP)                    ;;; process record
    ld    a3, _PS_STATE(a0)             ;;; record read ptr (outermost first)
    sd    a3, _PS_CALLSTACK_PARTIAL(a0)
    j     si_test_finished

si_loop:
    ld    ra, 0(a3)                     ;;; this frame's saved RESUME addr (relative)
    ld    PB, 8(a3)                     ;;; owner (record [+8])
    lbu   a6, _PD_FRAME_LEN(PB)         ;;; flen
    slli  t0, a6, 3
    sub   SP, SP, t0                    ;;; allocate the whole frame (16-aligned)
    sd    PB, 0(SP)                     ;;; SF_OWNER at [sp+0]
    ;;; SF_RETURN_ADDR (where THIS frame returns) = next-outer frame's resume
    ;;; addr, carried in s8 (shifted by one vs the saved RESUME slots).
    addi  t0, a6, -1
    slli  t0, t0, 3
    add   t0, SP, t0
    sd    s8, 0(t0)
    add   s8, ra, PB                    ;;; s8 = THIS frame's resume (absolute)
    addi  a4, SP, 8                     ;;; frame write cursor -> SF_LOCALS[0]
    addi  a2, a3, 16                    ;;; record read cursor -> lvars

    ;;; on-stack lvars: record -> frame
    lbu   a5, _PD_NUM_STK_VARS(PB)
    beqz  a5, si_restore_dl
si_lv_loop:
    ld    t1, 0(a2)
    addi  a2, a2, 8
    sd    t1, 0(a4)
    addi  a4, a4, 8
    addiw a5, a5, -1
    bnez  a5, si_lv_loop

si_restore_dl:
    ;;; dynamic locals: current idval -> frame slot, record value -> ident
    lbu   a5, _PD_NLOCALS(PB)
    beqz  a5, si_restore_regs
    addi  a7, PB, _PD_TABLE
si_dl_loop:
    ld    a1, 0(a7)                     ;;; identifier (PD_TABLE forward)
    addi  a7, a7, 8
    ld    t1, 0(a1)                     ;;; current idval
    sd    t1, 0(a4)                     ;;;   -> frame slot
    addi  a4, a4, 8
    ld    t1, 0(a2)                     ;;; saved value from record
    addi  a2, a2, 8
    sd    t1, 0(a1)                     ;;;   -> identifier
    addiw a5, a5, -1
    bnez  a5, si_dl_loop

si_restore_regs:
    ;;; register locals x19..x23 (ascending; bits 0..4): current reg -> frame
    ;;; slot, record value -> register.
    lhu   a5, _PD_REGMASK(PB)
    andi  t0, a5, 1                     ;;; bit0 -> x19
    beqz  t0, 1f
    sd    x19, 0(a4)
    addi  a4, a4, 8
    ld    x19, 0(a2)
    addi  a2, a2, 8
1:
    andi  t0, a5, 2                     ;;; bit1 -> x20
    beqz  t0, 2f
    sd    x20, 0(a4)
    addi  a4, a4, 8
    ld    x20, 0(a2)
    addi  a2, a2, 8
2:
    andi  t0, a5, 4                     ;;; bit2 -> x21
    beqz  t0, 3f
    sd    x21, 0(a4)
    addi  a4, a4, 8
    ld    x21, 0(a2)
    addi  a2, a2, 8
3:
    andi  t0, a5, 8                     ;;; bit3 -> x22
    beqz  t0, 4f
    sd    x22, 0(a4)
    addi  a4, a4, 8
    ld    x22, 0(a2)
    addi  a2, a2, 8
4:
    andi  t0, a5, 16                    ;;; bit4 -> x23
    beqz  t0, 5f
    sd    x23, 0(a4)
    addi  a4, a4, 8
    ld    x23, 0(a2)
    addi  a2, a2, 8
5:
    ;;; advance record ptr to the next frame
    slli  t0, a6, 3
    add   a3, a3, t0
    sd    a3, _PS_CALLSTACK_PARTIAL(a0)

    ;;; run resume dlexpr code if present (s8 = carried resume addr)
    lbu   a1, _PD_FLAGS(PB)
    andi  t0, a1, _:M_PD_PROC_DLEXPR_CODE
    bnez  t0, si_do_dlexpr

si_test_finished:
    ld    a0, 0(USP)
    ld    a1, _PS_CALLSTACK_LIM(a0)
    ld    a3, _PS_CALLSTACK_PARTIAL(a0)
    bltu  a3, a1, si_loop
    ;;; Finished: s8 = innermost frame's resume addr -> LR, then chain.
    mv    ra, s8
    addi  USP, USP, 8
    li    a1, 0
    sd    a1, _PS_CALLSTACK_PARTIAL(a0)
    ld    a0, 0(USP)
    addi  USP, USP, 8
    ld    t5, _PD_EXECUTE(a0)
    jr    t5

si_do_dlexpr:
    sd    s8, _PS_PARTIAL_RETURN(a0)    ;;; preserve carried resume across dlexpr
    ;;; Jump to the resume code (sp at frame base, frame intact)
    ld    t5, _PD_EXIT(PB)
    addi  t5, t5, -BRANCH_std
    jr    t5

    ;;; Continue swap in after running procedure init code
DEF_C_LAB (_swap_in_continue)
    ld    a0, 0(USP)
    ld    a3, _PS_CALLSTACK_PARTIAL(a0)
    ld    s8, _PS_PARTIAL_RETURN(a0)
    j     si_test_finished

    .align 3
	.balign 8
usrhi_lab:
    .quad I_LAB(_userhi)
    ;;; _USSAVE: _ussave(_BYTE_LENGTH, _DST_ADDR)
    ;;;
    ;;; Swap out the DEEPEST _BYTE_LENGTH bytes of the user stack (the
    ;;; block next to _userhi, i.e. everything UNDER the retained top
    ;;; words) into the save area at _DST_ADDR ascending (so _usrestore
    ;;; reads the record back verbatim), then shift the retained top up
    ;;; against _userhi and pop the freed space.  Same algorithm as the
    ;;; arm64/x86-64 versions.  Until 2026-08 this was a tail-to-self
    ;;; placeholder from the port skeleton -- coroutines spun forever.
DEF_C_LAB (_ussave)
    ld    a1, 8(USP)                    ;;; a1 = byte length
    ld    a0, 0(USP)                    ;;; a0 = destination
    addi  USP, USP, 16
    beqz  a1, uss_done
    adr_l a2, I_LAB(_userhi)
    ld    a2, 0(a2)                     ;;; a2 = _userhi (stack base end)
    sub   a3, a2, a1                    ;;; a3 = start of block to save
uss_save:
    ld    t1, 0(a3)                     ;;; copy block -> save area, ascending
    addi  a3, a3, 8
    sd    t1, 0(a0)
    addi  a0, a0, 8
    bne   a3, a2, uss_save
    sub   a3, a2, a1                    ;;; a3 = shift source end (exclusive)
uss_shift:
    beq   a3, USP, uss_set              ;;; move retained top up by length,
    addi  a3, a3, -8                    ;;; copying high-to-low (overlap safe)
    addi  a2, a2, -8
    ld    t1, 0(a3)
    sd    t1, 0(a2)
    j     uss_shift
uss_set:
    mv    USP, a2                       ;;; = old USP + length
uss_done:
    ret

DEF_C_LAB (_usrestore)
    ld    a0, 8(USP)
    ld    a1, 0(USP)
    addi  USP, USP, 16
    beqz  a0, usr_done
    adr_l a2, I_LAB(_userhi)
    mv    a3, USP
    ld    a2, 0(a2)
    sub   USP, USP, a0
    mv    a0, USP
    beq   a2, a3, usr_loop2
usr_loop1:
    ld    t1, 0(a3)
    addi  a3, a3, 8
    sd    t1, 0(a0)
    addi  a0, a0, 8
    bne   a3, a2, usr_loop1
usr_loop2:
    ld    t1, 0(a1)
    addi  a1, a1, 8
    sd    t1, 0(a0)
    addi  a0, a0, 8
    bne   a0, a2, usr_loop2
usr_done:
    ret

    ;;; _USERASUND: _userasund(_BYTE_LENGTH)
    ;;; Erase the deepest _BYTE_LENGTH bytes (the block _ussave saves)
    ;;; without saving them.  Was also a tail-to-self placeholder.
DEF_C_LAB (_userasund)
    ld    a1, 0(USP)                    ;;; a1 = byte length
    addi  USP, USP, 8
    beqz  a1, uer_done
    adr_l a2, I_LAB(_userhi)
    ld    a2, 0(a2)                     ;;; a2 = _userhi
    sub   a3, a2, a1                    ;;; a3 = shift source end (exclusive)
uer_shift:
    beq   a3, USP, uer_set
    addi  a3, a3, -8
    addi  a2, a2, -8
    ld    t1, 0(a3)
    sd    t1, 0(a2)
    j     uer_shift
uer_set:
    mv    USP, a2
uer_done:
    ret
