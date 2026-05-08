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
        .arch armv8-a

;;; Wrapping in POP object
        .text
        .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

        .globl  EXTERN_NAME(__pop_errsig)
EXTERN_NAME(__pop_errsig):

    ;;; reset_pop_environ
    ;;; Clear __pop_in_user_extern
    adrp x0, EXTERN_NAME(__pop_in_user_extern)
    add  x0, x0, :lo12:EXTERN_NAME(__pop_in_user_extern)
    str  xzr, [x0]

    ;;; Restore USP from _userhi
    adrp x0, I_LAB(_userhi)
    add  x0, x0, :lo12:I_LAB(_userhi)
    ldr  USP, [x0]

    ;;; FIXME: handle FPE handler

    ;;; Check saved_sp
    adrp x0, SAVED_SP
    add  x0, x0, :lo12:SAVED_SP
    ldr  x1, [x0]
    cbz  x1, L0.done
    mov  sp, x1
    ldr  PB, [sp]
    ;;; never return
L0.done:
    bl   XC_LAB(Sys$-Error_signal)
    b    L0.done

DEF_C_LAB (_call_sys)
    ;;; Save sp to saved_sp
    adrp x9, SAVED_SP
    add  x9, x9, :lo12:SAVED_SP
    mov  x10, sp
    str  x10, [x9]

    ;;; Save callee-saved registers and lr.
    ;;; We save x21-x24 (scratch/temp) plus x29 (FP), x30 (LR).
    ;;; 6 regs = 48 bytes (3 stp pairs), 16-byte aligned.
    stp  x29, x30, [sp, #-48]!
    stp  x21, x22, [sp, #16]
    stp  x23, x24, [sp, #32]
    mov  x29, sp

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

    ;;; Clear saved_sp and restore stack
    adrp x9, SAVED_SP
    add  x9, x9, :lo12:SAVED_SP
    ldr  x10, [x9]
    str  xzr, [x9]

    ;;; Restore sp to point at saved registers frame
    ;;; saved_sp pointed at sp before the 48-byte frame was pushed
    sub  sp, x10, #48

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
    ;;; Save sp to saved_sp
    adrp x9, SAVED_SP
    add  x9, x9, :lo12:SAVED_SP
    mov  x10, sp
    str  x10, [x9]

    stp  x29, x30, [sp, #-48]!
    stp  x21, x22, [sp, #16]
    stp  x23, x24, [sp, #32]
    mov  x29, sp

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

    adrp x9, SAVED_SP
    add  x9, x9, :lo12:SAVED_SP
    ldr  x10, [x9]
    str  xzr, [x9]

    sub  sp, x10, #48

    ldp  x23, x24, [sp, #32]
    ldp  x21, x22, [sp, #16]
    ldp  x29, x30, [sp], #48
    ret

;;; End wrapper: set size
        .text
Ltext_end:
        .set Ltext_size, Ltext_end-Ltext_start
