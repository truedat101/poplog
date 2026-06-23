/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Signal handling and _call_sys for RISC-V (rv64gc, LP64D)
   Author:  Waldek Hebisch
   AArch64 port by truedat101
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
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

        USP = "x9",     ;;; User stack pointer  (s1, matches genproc R10)
        PB  = "x18",    ;;; Procedure base register (s2, matches genproc R11)

        SAVED_SP = [I_LAB(Sys$-Extern$- _saved_sp)],

);

>_#

        .file   "asignals.s"
    .option arch, rv64gc
    ;;; ELF PC-relative local-address load (auipc+addi).  Backslashes doubled:
    ;;; popc escape-processes .s text.
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm

;;; Wrapping in POP object
	.text
        .quad  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

        .globl  EXTERN_NAME(__pop_errsig)
EXTERN_NAME(__pop_errsig):

    ;;; reset_pop_environ
    ;;; Clear __pop_in_user_extern
    adr_l a0, EXTERN_NAME(__pop_in_user_extern)
    sd   x0, 0(a0)

    ;;; Restore USP from _userhi
    adr_l a0, I_LAB(_userhi)
    ld   USP, 0(a0)

    ;;; FIXME: handle FPE handler

    ;;; Check saved_sp
    adr_l a0, SAVED_SP
    ld   t1, 0(a0)
    beqz t1, L0.done
    mv   sp, t1
    ld   PB, 0(sp)
    ;;; never return
L0.done:
    call XC_LAB(Sys$-Error_signal)
    j    L0.done

;;; _call_sys: call a C/system function whose address and argument count are on
;;; the user stack, with the args following.  RISC-V LP64D passes the first 8
;;; integer args in a0-a7 (x10-x17), the rest on the (16-byte aligned) C stack.
;;; Scratch uses the caller-saved temporaries t0(x5)=target, t1(x6)=argcount,
;;; t2(x7)=counter, t3(x28)/t4(x29)=copy temps.  fp(x8) anchors sp recovery.

DEF_C_LAB (_call_sys)
    ;;; Save ra, fp and the Pop register-locals x19-x23 (s3-s7), which a Pop-11
    ;;; callee reached through the call below would clobber.  7 regs -> 64-byte
    ;;; (16-aligned) frame, one 8-byte slack slot at 0(sp).
    addi sp, sp, -64
    sd   ra,  56(sp)
    sd   x8,  48(sp)        ;;; fp
    sd   x19, 40(sp)
    sd   x20, 32(sp)
    sd   x21, 24(sp)
    sd   x22, 16(sp)
    sd   x23,  8(sp)
    mv   x8, sp             ;;; fp = sp (preserved across the call; recovers sp)

    ;;; entry sp = fp + 64; save to saved_sp so __pop_errsig can recover.
    addi t3, x8, 64
    adr_l t4, SAVED_SP
    sd   t3, 0(t4)

    ;;; Pop the syscall address and the argument count from the user stack.
    ld   t0, 0(USP)         ;;; t0 = syscall address
    addi USP, USP, 8
    ld   t1, 0(USP)         ;;; t1 = argument count
    addi USP, USP, 8

    ;;; stack args = argcount - 8
    addi t2, t1, -8
    blez t2, L1.2

    ;;; allocate (stackargs rounded up to even) * 8 bytes for 16-byte alignment
    addi t3, t2, 1
    andi t3, t3, -2         ;;; round up to even
    slli t3, t3, 3          ;;; * 8
    sub  sp, sp, t3

    ;;; copy stack arguments from the user stack to the C stack
    mv   t4, sp
L1.1:
    ld   t3, 0(USP)
    addi USP, USP, 8
    sd   t3, 0(t4)
    addi t4, t4, 8
    addi t2, t2, -1
    bgtz t2, L1.1
    li   t1, 8
L1.2:
    ;;; Load register args a7..a0 (x17..x10) from the user stack per arg count.
    li   t3, 8
    blt  t1, t3, 1f
    ld   x17, 0(USP)        ;;; a7
    addi USP, USP, 8
1:
    li   t3, 7
    blt  t1, t3, 2f
    ld   x16, 0(USP)        ;;; a6
    addi USP, USP, 8
2:
    li   t3, 6
    blt  t1, t3, 3f
    ld   x15, 0(USP)        ;;; a5
    addi USP, USP, 8
3:
    li   t3, 5
    blt  t1, t3, 4f
    ld   x14, 0(USP)        ;;; a4
    addi USP, USP, 8
4:
    li   t3, 4
    blt  t1, t3, 5f
    ld   x13, 0(USP)        ;;; a3
    addi USP, USP, 8
5:
    li   t3, 3
    blt  t1, t3, 6f
    ld   x12, 0(USP)        ;;; a2
    addi USP, USP, 8
6:
    li   t3, 2
    blt  t1, t3, 7f
    ld   x11, 0(USP)        ;;; a1
    addi USP, USP, 8
7:
    li   t3, 1
    blt  t1, t3, 8f
    ld   x10, 0(USP)        ;;; a0
    addi USP, USP, 8
8:

    ;;; Call the system function
    jalr t0

    ;;; Push the return value (a0) onto the user stack
    addi USP, USP, -8
    sd   x10, 0(USP)

    ;;; Clear saved_sp
    adr_l t4, SAVED_SP
    sd   x0, 0(t4)

    ;;; Recover sp via fp (preserved across the call)
    mv   sp, x8

    ;;; Restore callee-saved registers
    ld   x23,  8(sp)
    ld   x22, 16(sp)
    ld   x21, 24(sp)
    ld   x20, 32(sp)
    ld   x19, 40(sp)
    ld   x8,  48(sp)
    ld   ra,  56(sp)
    addi sp, sp, 64
    ret

;;; _call_sys_se: as _call_sys but sign-extends the low 32 bits of the return
;;; value before pushing it (SIGN_EXTEND_EXTERN: 32-bit-returning syscalls give
;;; a correctly-signed 64-bit Pop integer).
DEF_C_LAB (_call_sys_se)
    addi sp, sp, -64
    sd   ra,  56(sp)
    sd   x8,  48(sp)
    sd   x19, 40(sp)
    sd   x20, 32(sp)
    sd   x21, 24(sp)
    sd   x22, 16(sp)
    sd   x23,  8(sp)
    mv   x8, sp

    addi t3, x8, 64
    adr_l t4, SAVED_SP
    sd   t3, 0(t4)

    ld   t0, 0(USP)
    addi USP, USP, 8
    ld   t1, 0(USP)
    addi USP, USP, 8

    addi t2, t1, -8
    blez t2, L1se.2

    addi t3, t2, 1
    andi t3, t3, -2
    slli t3, t3, 3
    sub  sp, sp, t3

    mv   t4, sp
L1se.1:
    ld   t3, 0(USP)
    addi USP, USP, 8
    sd   t3, 0(t4)
    addi t4, t4, 8
    addi t2, t2, -1
    bgtz t2, L1se.1
    li   t1, 8
L1se.2:
    li   t3, 8
    blt  t1, t3, 1f
    ld   x17, 0(USP)
    addi USP, USP, 8
1:
    li   t3, 7
    blt  t1, t3, 2f
    ld   x16, 0(USP)
    addi USP, USP, 8
2:
    li   t3, 6
    blt  t1, t3, 3f
    ld   x15, 0(USP)
    addi USP, USP, 8
3:
    li   t3, 5
    blt  t1, t3, 4f
    ld   x14, 0(USP)
    addi USP, USP, 8
4:
    li   t3, 4
    blt  t1, t3, 5f
    ld   x13, 0(USP)
    addi USP, USP, 8
5:
    li   t3, 3
    blt  t1, t3, 6f
    ld   x12, 0(USP)
    addi USP, USP, 8
6:
    li   t3, 2
    blt  t1, t3, 7f
    ld   x11, 0(USP)
    addi USP, USP, 8
7:
    li   t3, 1
    blt  t1, t3, 8f
    ld   x10, 0(USP)
    addi USP, USP, 8
8:

    jalr t0

    ;;; Sign-extend the low 32 bits of the return value
    sext.w x10, x10

    addi USP, USP, -8
    sd   x10, 0(USP)

    adr_l t4, SAVED_SP
    sd   x0, 0(t4)

    mv   sp, x8

    ld   x23,  8(sp)
    ld   x22, 16(sp)
    ld   x21, 24(sp)
    ld   x20, 32(sp)
    ld   x19, 40(sp)
    ld   x8,  48(sp)
    ld   ra,  56(sp)
    addi sp, sp, 64
    ret

;;; End wrapper: set size
	.text
Ltext_end:
        .set Ltext_size, Ltext_end-Ltext_start
