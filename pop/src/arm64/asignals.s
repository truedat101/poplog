/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Signal handling and _call_sys for AArch64
   Author:  Waldek Hebisch
   AArch64 port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'

section $-Sys;

constant procedure (Error_signal,)
;


vars
        Extern$- _saved_sp,
;

endsection;

lconstant macro (

        USP = "x19",    ;;; User stack pointer
        PB  = "x20",    ;;; Procedure base register

        SAVED_SP = [I_LAB(Sys$-Extern$- _saved_sp)],

);

>_#

        .file   "asignals.s"
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

;;; Wrapping in POP object
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
#_ELSE
	.text
#_ENDIF
        .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

        .globl  EXTERN_NAME(__pop_errsig)
EXTERN_NAME(__pop_errsig):

    ;;; reset_pop_environ
    ;;; Clear __pop_in_user_extern
    adr_l x0, EXTERN_NAME(__pop_in_user_extern)
    str  xzr, [x0]

    ;;; Restore USP from _userhi
    adr_l x0, I_LAB(_userhi)
    ldr  USP, [x0]

    ;;; FIXME: handle FPE handler

    ;;; Check saved_sp
    adr_l x0, SAVED_SP
    ldr  x1, [x0]
    cbz  x1, L0.done
    mov  sp, x1
    ldr  PB, [sp]
    ;;; never return
L0.done:
    bl   XC_LAB(Sys$-Error_signal)
    b    L0.done

DEF_C_LAB (_call_sys)
    ;;; Save callee-saved registers and lr.
    ;;; We save x21-x24 (scratch/temp) plus x29 (FP), x30 (LR).
    ;;; 6 regs = 48 bytes (3 stp pairs), 16-byte aligned.
    stp  x29, x30, [sp, #-48]!
    stp  x21, x22, [sp, #16]
    stp  x23, x24, [sp, #32]
    mov  x29, sp

    ;;; x29 (FP) now points at our saved frame. We use x29 to recover sp on
    ;;; exit, since Pop-11 procedures called via blr x12 below clobber
    ;;; x21-x25 (which Pop-11 treats as register locals, not callee-saved).
    ;;; x29 is the AAPCS frame pointer and is preserved across calls.
    ;;;
    ;;; Save entry sp (= x29 + 48) to saved_sp so __pop_errsig can recover.
    add  x10, x29, #48
    adr_l x9, SAVED_SP
    str  x10, [x9]

    ;;; Get the system call address and the argument count from user stack
    ;;; Poplog words are 8 bytes on AArch64
    ldr  x12, [USP], #8        ;;; syscall address
    ldr  x9,  [USP], #8        ;;; argument count

    ;;; On AArch64, first 8 args go in x0-x7, remainder on stack.
    subs x7, x9, #8
    b.le L1.2

    ;;; Ensure 16-byte stack alignment for stack arguments.
    ;;; x7 = number of stack args. Round up to even for alignment.
    add  x10, x7, #1
    bic  x10, x10, #1          ;;; round up to even
    sub  sp, sp, x10, lsl #3   ;;; allocate x10*8 bytes

    ;;; Copy stack arguments from user stack to system stack
    mov  x11, sp
L1.1:
    ldr  x10, [USP], #8
    str  x10, [x11], #8
    subs x7, x7, #1
    b.gt L1.1
    mov  x9, #8
L1.2:
    ;;; Load register arguments x0-x7 based on arg count in x9.
    ;;; We pop them from the user stack in reverse order (arg N-1 first).
    cmp  x9, #8
    b.lt 1f
    ldr  x7, [USP], #8
1:
    cmp  x9, #7
    b.lt 2f
    ldr  x6, [USP], #8
2:
    cmp  x9, #6
    b.lt 3f
    ldr  x5, [USP], #8
3:
    cmp  x9, #5
    b.lt 4f
    ldr  x4, [USP], #8
4:
    cmp  x9, #4
    b.lt 5f
    ldr  x3, [USP], #8
5:
    cmp  x9, #3
    b.lt 6f
    ldr  x2, [USP], #8
6:
    cmp  x9, #2
    b.lt 7f
    ldr  x1, [USP], #8
7:
    cmp  x9, #1
    b.lt 8f
    ldr  x0, [USP], #8
8:

    ;;; Call the system function
    blr  x12

    ;;; Push return value onto user stack
    str  x0, [USP, #-8]!

    ;;; Clear saved_sp (mirror of original ARM32 contract: cleared between calls)
    adr_l x9, SAVED_SP
    str  xzr, [x9]

    ;;; Restore sp using x29 (frame pointer), which was set to sp at entry
    ;;; and is preserved across the C call by AAPCS. Robust against both
    ;;; SAVED_SP clobber (nested _call_sys) and Pop-11 callees clobbering x21.
    add  sp, x29, #0

    ;;; Restore callee-saved registers
    ldp  x23, x24, [sp, #32]
    ldp  x21, x22, [sp, #16]
    ldp  x29, x30, [sp], #48
    ret

;;; _call_sys_se: same as _call_sys but sign-extends the low 32 bits of
;;; the return value before pushing it on the user stack.  Used by
;;; SIGN_EXTEND_EXTERN paths so that 32-bit-returning syscalls produce a
;;; correctly-signed 64-bit Pop integer.
DEF_C_LAB (_call_sys_se)
    stp  x29, x30, [sp, #-48]!
    stp  x21, x22, [sp, #16]
    stp  x23, x24, [sp, #32]
    mov  x29, sp

    ;;; x29 (FP) recovers sp on exit; entry sp = x29 + 48.
    ;;; Save entry sp to saved_sp for __pop_errsig.
    add  x10, x29, #48
    adr_l x9, SAVED_SP
    str  x10, [x9]

    ldr  x12, [USP], #8        ;;; syscall address
    ldr  x9,  [USP], #8        ;;; argument count

    subs x7, x9, #8
    b.le L1se.2

    add  x10, x7, #1
    bic  x10, x10, #1
    sub  sp, sp, x10, lsl #3

    mov  x11, sp
L1se.1:
    ldr  x10, [USP], #8
    str  x10, [x11], #8
    subs x7, x7, #1
    b.gt L1se.1
    mov  x9, #8
L1se.2:
    cmp  x9, #8
    b.lt 1f
    ldr  x7, [USP], #8
1:
    cmp  x9, #7
    b.lt 2f
    ldr  x6, [USP], #8
2:
    cmp  x9, #6
    b.lt 3f
    ldr  x5, [USP], #8
3:
    cmp  x9, #5
    b.lt 4f
    ldr  x4, [USP], #8
4:
    cmp  x9, #4
    b.lt 5f
    ldr  x3, [USP], #8
5:
    cmp  x9, #3
    b.lt 6f
    ldr  x2, [USP], #8
6:
    cmp  x9, #2
    b.lt 7f
    ldr  x1, [USP], #8
7:
    cmp  x9, #1
    b.lt 8f
    ldr  x0, [USP], #8
8:

    blr  x12

    ;;; Sign-extend the low 32 bits of the return value
    sxtw x0, w0

    str  x0, [USP, #-8]!

    adr_l x9, SAVED_SP
    str  xzr, [x9]

    ;;; Recover sp via x29 (frame pointer) — preserved across the C call.
    add  sp, x29, #0

    ldp  x23, x24, [sp, #32]
    ldp  x21, x22, [sp, #16]
    ldp  x29, x30, [sp], #48
    ret

;;; End wrapper: set size
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
#_ELSE
	.text
#_ENDIF
Ltext_end:
        .set Ltext_size, Ltext_end-Ltext_start
