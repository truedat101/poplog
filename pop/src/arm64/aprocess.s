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

    /* --- Swap out (suspend) the live call stack into the process record ---

       Frames live on the hardware sp, which AArch64 requires to be 16-byte
       aligned at EVERY sp-based access.  Per the arm64 frame contract
       (ass.p I_CREATE_SF / genproc.p M_CREATE_SF) sp points at the frame base:
         [sp + 0]          = SF_OWNER (PB)
         [sp + 8 + i*8]    = SF_LOCALS[i]: on-stack lvars (Nstkvars), then
                             dynamic-local saved-old idvals (Nlocals), then
                             register-local saved values (Nreg)
         [sp + (flen-1)*8] = SF_RETURN_ADDR (LR)
       flen = Nstkvars + Nlocals + Nreg + 2 and is always even, so each frame
       is a whole number of 16-byte units.  We read each frame via a cursor
       register (x4) plus fixed sp offsets and advance sp only by the WHOLE
       frame (flen*8) -- never the 8-byte-at-a-time pops that would leave sp
       8-misaligned and raise a SIGBUS.

       Record format (written here, read back verbatim by _swap_in_callstack),
       one block per frame filled upward from x3:
         [+0]  relative return address (LR - PB)
         [+8]  owner (PB)
         [+16] on-stack lvar values         (Nstkvars)
         [..]  dynamic-local current idvals  (Nlocals, PD_TABLE order)
         [..]  register-local current values (Nreg, x21..x25 order)

       On entry x30 = resume address into the immediate caller and PB = that
       caller's PB (the first frame); later frames take the resume address from
       the frame just consumed (its SF_RETURN_ADDR) and PB from the next
       frame's SF_OWNER.
    */
DEF_C_LAB (_swap_out_callstack)
    ldr   x0, [USP]                     ;;; process record
    ldr   x3, [x0, #_PS_CALLSTACK_LIM]  ;;; record write ptr (fills downward)
    str   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    b     so_test_finished

so_loop:
    ldr   PB, [SP]                      ;;; PB = SF_OWNER of current frame
    sub   x30, x30, PB                  ;;; make resume address relative

    ldrb  w1, [PB, #_PD_FLAGS]
    tst   w1, #_:M_PD_PROC_DLEXPR_CODE
    b.ne  so_do_dlexpr

so_cont:
    MOVFL w6, [PB, #_PD_FRAME_LEN]      ;;; flen (words; byte field)
    sub   x3, x3, x6, lsl #3            ;;; reserve this frame's slot in record
    str   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    str   x30, [x3, #0]                 ;;; relative return address
    str   PB,  [x3, #8]                 ;;; owner
    add   x3, x3, #16

    add   x4, SP, #8                    ;;; x4 -> SF_LOCALS[0] (frame read cursor)

    ;;; on-stack lvars: frame -> record
    MOVFL w5, [PB, #_PD_NUM_STK_VARS]
    cbz   w5, so_save_dl
so_lv_loop:
    ldr   x12, [x4], #8
    str   x12, [x3], #8
    subs  w5, w5, #1
    b.ne  so_lv_loop

so_save_dl:
    ;;; dynamic locals: current idval -> record, frame's saved-old -> ident
    MOVFL w5, [PB, #_PD_NLOCALS]
    cbz   w5, so_save_regs
    add   x2, PB, #_PD_TABLE
so_dl_loop:
    ldr   x1,  [x2], #8                 ;;; identifier (PD_TABLE forward)
    ldr   x12, [x1]                     ;;; current idval
    str   x12, [x3], #8                 ;;;   -> record
    ldr   x12, [x4], #8                 ;;; saved-old value from frame slot
    str   x12, [x1]                     ;;;   -> identifier
    subs  w5, w5, #1
    b.ne  so_dl_loop

so_save_regs:
    ;;; register locals x21..x25 (PD_REGMASK remap: x21=bit4, x22=bit6,
    ;;; x23=bit7, x24=bit8, x25=bit9 -- see genproc.p M_CREATE_SF).  Save the
    ;;; current value into the record, restore the frame's saved value into the
    ;;; register.  Ascending order matches the frame reg-slot order + cursor.
    ldrh  w5, [PB, #_PD_REGMASK]
    tst   w5, #16                       ;;; bit 4 -> x21
    b.eq  1f
    str   x21, [x3], #8
    ldr   x21, [x4], #8
1:
    tst   w5, #64                       ;;; bit 6 -> x22
    b.eq  2f
    str   x22, [x3], #8
    ldr   x22, [x4], #8
2:
    tst   w5, #128                      ;;; bit 7 -> x23
    b.eq  3f
    str   x23, [x3], #8
    ldr   x23, [x4], #8
3:
    tst   w5, #256                      ;;; bit 8 -> x24
    b.eq  4f
    str   x24, [x3], #8
    ldr   x24, [x4], #8
4:
    tst   w5, #512                      ;;; bit 9 -> x25
    b.eq  5f
    str   x25, [x3], #8
    ldr   x25, [x4], #8
5:
    ;;; advance sp past the whole (16-aligned) frame; pick up the next frame's
    ;;; resume address from this frame's SF_RETURN_ADDR (now at [sp-8]).
    add   SP, SP, x6, lsl #3
    ldr   x30, [SP, #-8]

so_test_finished:
    ldr   x0, [USP]
    ldr   x1, [x0, #_PS_STATE]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    cmp   x3, x1
    b.hi  so_loop

    ;;; Finished.  sp now sits at the pre-existing (un-saved) frame that we are
    ;;; about to resume; restore ITS procedure base from its SF_OWNER at [sp+0].
    ;;; The usual chained trampoline (identfn) is a leaf `ret` that does NOT
    ;;; restore PB, and the resumed code may use PB immediately; a non-leaf
    ;;; chained proc restores PB via its own epilogue, so this is harmless there.
    ldr   PB, [SP]

    ;;; save flags and chain to procedure on user stack
    add   USP, USP, #8
    mov   x1, #0
    str   x1, [x0, #_PS_CALLSTACK_PARTIAL]
    strh  w1, [x0, #_PS_FLAGS]
    ldr   x0, [USP], #8
    ldr   x16, [x0, #_PD_EXECUTE]
    br    x16

so_do_dlexpr:
    str   x30, [x0, #_PS_PARTIAL_RETURN]
    ;;; Jump to suspend code (sp left at the frame base, frame intact)
    ldr   x16, [PB, #_PD_EXIT]
    sub   x16, x16, #(BRANCH_std << 1)
    br    x16

DEF_C_LAB (_swap_out_continue)
    ldr   x0, [USP]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    ldr   x30, [x0, #_PS_PARTIAL_RETURN]
    b     so_cont

    /* --- Swap in (resume) a saved call stack, rebuilding frames on sp ---
       Reads the record written by _swap_out_callstack and reconstructs each
       frame per the arm64 contract, allocating sp in whole 16-aligned frames
       (no 8-byte pushes, which would 8-misalign sp).  Frames are processed
       from PS_STATE (outermost) upward, so the outermost lands deepest and the
       innermost ends on top, where execution resumes.
    */
DEF_C_LAB (_swap_in_callstack)
    mov   x8, x30                       ;;; x8 = caller-return: becomes the SF_RETURN_ADDR
                                        ;;;   of the OUTERMOST restored frame (the resume
                                        ;;;   point in whoever called _swap_in_callstack).
    ldr   x0, [USP]                     ;;; process record
    ldr   x3, [x0, #_PS_STATE]          ;;; record read ptr (outermost first)
    str   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    b     si_test_finished

si_loop:
    ldr   x30, [x3, #0]                 ;;; this frame's saved RESUME addr (relative)
    ldr   PB,  [x3, #8]                 ;;; owner (record [+8])
    MOVFL w6, [PB, #_PD_FRAME_LEN]      ;;; flen
    sub   SP, SP, x6, lsl #3            ;;; allocate the whole frame (16-aligned)
    str   PB, [SP]                      ;;; SF_OWNER at [sp+0]
    ;;; SF_RETURN_ADDR (where THIS frame RETURNS) = the next-outer frame's resume
    ;;; addr, carried in x8.  saved_return[i] is where frame i RESUMES (the entry
    ;;; trampoline / where frame i-1 returns), NOT frame i's own return -- so it
    ;;; is shifted by one relative to the SF_RETURN_ADDR slots.
    sub   x9, x6, #1
    str   x8, [SP, x9, lsl #3]
    add   x8, x30, PB                   ;;; x8 = THIS frame's resume (absolute), carried on
    add   x4, SP, #8                    ;;; frame write cursor -> SF_LOCALS[0]
    add   x2, x3, #16                   ;;; record read cursor -> lvars

    ;;; on-stack lvars: record -> frame
    MOVFL w5, [PB, #_PD_NUM_STK_VARS]
    cbz   w5, si_restore_dl
si_lv_loop:
    ldr   x12, [x2], #8
    str   x12, [x4], #8
    subs  w5, w5, #1
    b.ne  si_lv_loop

si_restore_dl:
    ;;; dynamic locals: current idval -> frame slot, record value -> identifier
    MOVFL w5, [PB, #_PD_NLOCALS]
    cbz   w5, si_restore_regs
    add   x7, PB, #_PD_TABLE
si_dl_loop:
    ldr   x1,  [x7], #8                 ;;; identifier (PD_TABLE forward)
    ldr   x12, [x1]                     ;;; current idval
    str   x12, [x4], #8                 ;;;   -> frame slot
    ldr   x12, [x2], #8                 ;;; saved value from record
    str   x12, [x1]                     ;;;   -> identifier
    subs  w5, w5, #1
    b.ne  si_dl_loop

si_restore_regs:
    ;;; register locals (PD_REGMASK remap, ascending): current reg -> frame
    ;;; slot, record value -> register.
    ldrh  w5, [PB, #_PD_REGMASK]
    tst   w5, #16                       ;;; bit 4 -> x21
    b.eq  1f
    str   x21, [x4], #8
    ldr   x21, [x2], #8
1:
    tst   w5, #64                       ;;; bit 6 -> x22
    b.eq  2f
    str   x22, [x4], #8
    ldr   x22, [x2], #8
2:
    tst   w5, #128                      ;;; bit 7 -> x23
    b.eq  3f
    str   x23, [x4], #8
    ldr   x23, [x2], #8
3:
    tst   w5, #256                      ;;; bit 8 -> x24
    b.eq  4f
    str   x24, [x4], #8
    ldr   x24, [x2], #8
4:
    tst   w5, #512                      ;;; bit 9 -> x25
    b.eq  5f
    str   x25, [x4], #8
    ldr   x25, [x2], #8
5:
    ;;; advance record ptr to the next frame
    add   x3, x3, x6, lsl #3
    str   x3, [x0, #_PS_CALLSTACK_PARTIAL]

    ;;; run resume dlocal-expression code if present (x8 = carried resume addr)
    ldrb  w1, [PB, #_PD_FLAGS]
    tst   w1, #_:M_PD_PROC_DLEXPR_CODE
    b.ne  si_do_dlexpr

si_test_finished:
    ldr   x0, [USP]
    ldr   x1, [x0, #_PS_CALLSTACK_LIM]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    cmp   x3, x1
    b.lo  si_loop
    ;;; Finished: x8 now holds the INNERMOST frame's resume addr, which is where
    ;;; the chained trampoline proc must return to -- put it in LR, then chain.
    mov   x30, x8
    add   USP, USP, #8
    mov   x1, #0
    str   x1, [x0, #_PS_CALLSTACK_PARTIAL]
    ldr   x0, [USP], #8
    ldr   x16, [x0, #_PD_EXECUTE]
    br    x16

si_do_dlexpr:
    str   x8, [x0, #_PS_PARTIAL_RETURN]    ;;; preserve carried resume across dlexpr
    ;;; Jump to resume code (sp left at the frame base, frame intact)
    ldr   x16, [PB, #_PD_EXIT]
    sub   x16, x16, #BRANCH_std
    br    x16


    ;;; Continue swap in after running procedure init code
DEF_C_LAB (_swap_in_continue)
    ldr   x0, [USP]
    ldr   x3, [x0, #_PS_CALLSTACK_PARTIAL]
    ldr   x8, [x0, #_PS_PARTIAL_RETURN]
    b     si_test_finished

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
