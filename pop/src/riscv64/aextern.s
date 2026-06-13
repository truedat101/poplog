/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Assembly routines supporting calling external
            functions for RISC-V (rv64gc, LP64D)
   Author:  Waldek Hebisch (ARM32 original)
            AArch64 port by truedat101
            RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'
#_INCLUDE 'external.ph'
#_INCLUDE 'numbers.ph'

lconstant macro (
    USP   = "x9",       ;;; s1 (matches genproc R10)
    PB    = "x18",      ;;; s2 (matches genproc R11)
    SP    = "sp",

    _K_EXTERN_TYPE  = @@K_EXTERN_TYPE,
    _EFC_FUNC   = @@EFC_FUNC,
    _EFC_ARG    = @@EFC_ARG,
    _EFC_ARG_DEST   = @@EFC_ARG_DEST,
);

;;; Sanity check: keep the asm-side offset of K_EXTERN_TYPE in sync with the
;;; offset that the C side uses (see pop/extern/lib/ext_arm.c, __riscv branch).
;;; The K-record field offset is word-size dependent: LP64D matches AArch64 at
;;; 11 word slots in + 2 byte tag = 90.
if _pint(_K_EXTERN_TYPE) /== (11*8 + 2) then
    mishap(_pint(_K_EXTERN_TYPE), (11*8 + 2), 2,
           '_K_EXTERN_TYPE must agree with ext_arm.c (__riscv branch)');
endif;

>_#

    .option arch, rv64gc
    ;;; ELF PC-relative local-address load (auipc+addi).
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    .file   "aextern.s"
	.text

;;; Wrapping in POP object
	.text
   .quad   Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

;;; Literal pool entries (pointer-sized): each holds the ADDRESS of a Pop
;;; identifier; `ld reg, label` (PC-relative pseudo) loads that address, then a
;;; second ld/sd dereferences it.
saved_sp.lab:
    .quad I_LAB(Sys$-Extern$- _saved_sp)

saved_usp.lab:
    .quad I_LAB(Sys$-Extern$- _saved_usp)

pop_in_extern.lab:
    .quad EXTERN_NAME(__pop_in_user_extern)

ext_result.lab:
    .quad C_LAB(Sys$-Extern$-result_struct)

;;; _call_external(nargs, routine, fltsingle)
;;;
;;; RISC-V LP64D calling convention:
;;;   Integer args: a0-a7 (x10-x17)        -- 8 registers
;;;   FP args:      fa0-fa7 (f10-f17)       -- 8 registers, 64-bit (8-byte) each
;;;   Register buffer: 8*8 (int) + 8*8 (FP, 8-byte stride) = 128 bytes
;;;   NB: arm64 used a 16-byte FP stride (q regs); RISC-V's d regs are 8 bytes.
;;;       The C marshaller copy_external_arguments must use the SAME layout.
;;;
;;; Poplog registers (callee-saved): USP=x9, PB=x18, Pop locals x19-x23.
;;; This routine uses the spare callee-saved s8-s11 (x24-x27) as scratch and
;;; saves them; the caller is responsible for the Pop register locals (GC).
;;;
DEF_C_LAB (_call_external)
    ;;; Save caller's stack pointer for interrupt/callback (entry sp, pre-push)
    ld   t0, saved_sp.lab
    mv   t1, sp
    sd   t1, 0(t0)

    ;;; Save the callee-saved scratch we use: s8-s11 + fp + ra (48-byte frame)
    addi sp, sp, -48
    sd   ra,  40(sp)
    sd   x8,  32(sp)        ;;; fp
    sd   x24, 24(sp)        ;;; s8  - fltsingle
    sd   x25, 16(sp)        ;;; s9  - routine
    sd   x26,  8(sp)        ;;; s10 - register buffer
    sd   x27,  0(sp)        ;;; s11 - nargs

    ;;; Load fixed arguments from the user stack (each Pop word = 8 bytes)
    ld   x24, 0(USP)        ;;; fltsingle -> s8
    addi USP, USP, 8
    ld   x25, 0(USP)        ;;; routine   -> s9
    addi USP, USP, 8
    ld   a0,  0(USP)        ;;; nargs     -> a0
    addi USP, USP, 8

    ;;; Allocate the 128-byte register-argument buffer (already 16-aligned)
    addi sp, sp, -128
    mv   x26, sp            ;;; register buffer -> s10

    ;;; Allocate stack-argument space if nargs > 8 (rounded to 16-byte align)
    li   t0, 8
    bgeu t0, a0, do_args    ;;; nargs <= 8 -> no stack args
    addi t1, a0, -8
    slli t1, t1, 3          ;;; (nargs-8)*8
    addi t1, t1, 15
    andi t1, t1, -16        ;;; round up to 16
    sub  sp, sp, t1

do_args:
    mv   a2, sp             ;;; stack arg pointer -> arg3
    mv   x27, a0            ;;; save nargs -> s11

    ;;; copy_external_arguments(nargs, USP, sp, regbuf, fltsingle)  -- a0..a4
    mv   a4, x24            ;;; fltsingle -> arg5
    mv   a3, x26            ;;; reg buffer -> arg4
                            ;;; a2 already = stack arg pointer (arg3)
    mv   a1, USP            ;;; user stack pointer -> arg2
                            ;;; a0 already = nargs (arg1)
    call EXTERN_NAME(copy_external_arguments)

    ;;; Advance USP past the arguments
    slli t0, x27, 3
    add  USP, USP, t0

    ;;; Load buffered integer arguments a0-a7 (offset 0, 8-byte stride)
    ld   x10,  0(x26)
    ld   x11,  8(x26)
    ld   x12, 16(x26)
    ld   x13, 24(x26)
    ld   x14, 32(x26)
    ld   x15, 40(x26)
    ld   x16, 48(x26)
    ld   x17, 56(x26)

    ;;; Load buffered FP arguments fa0-fa7 (offset 64, 8-byte stride)
    fld  fa0,  64(x26)
    fld  fa1,  72(x26)
    fld  fa2,  80(x26)
    fld  fa3,  88(x26)
    fld  fa4,  96(x26)
    fld  fa5, 104(x26)
    fld  fa6, 112(x26)
    fld  fa7, 120(x26)

    ;;; Save USP and enable async callback
    ld   t0, saved_usp.lab
    sd   USP, 0(t0)
    ld   t0, pop_in_extern.lab
    mv   t1, sp
    sd   t1, 0(t0)

    ;;; Call the external function
    jalr x25

    ;;; Disable async callback
    ld   t0, pop_in_extern.lab
    sd   x0, 0(t0)

    ;;; Restore USP
    ld   t0, saved_usp.lab
    ld   USP, 0(t0)

    ;;; Store result (FP result at offset 0, int/pointer result at offset 8)
    ld   t0, ext_result.lab
    sd   x10, 8(t0)
    fsd  fa0, 0(t0)

    ;;; Restore sp to our saved-register block: entry sp - 48
    ld   t0, saved_sp.lab
    ld   t0, 0(t0)
    addi t0, t0, -48
    mv   sp, t0

    ;;; Restore callee-saved registers
    ld   x27,  0(sp)
    ld   x26,  8(sp)
    ld   x25, 16(sp)
    ld   x24, 24(sp)
    ld   x8,  32(sp)
    ld   ra,  40(sp)
    addi sp, sp, 48        ;;; sp now = entry sp

    ;;; Restore PB (saved by the caller at the top of its frame)
    ld   PB, 0(sp)

    ;;; Zero saved sp to indicate the external call is over
    ld   t0, saved_sp.lab
    sd   x0, 0(t0)

    ret


;;; _EXFUNC_CLOS_ACTION:
;;; Called (tail-jumped) from an exfunc_closure's stub code.  By the contract in
;;; asm_gen_exfunc_clos_code (asmout.p) the closure record address is in t1(x6).
;;; We must preserve the C argument registers a0-a7.

DEF_C_LAB(Sys$- _exfunc_clos_action)
    ;;; Save the two argument registers we use as scratch
    addi sp, sp, -16
    sd   a0, 8(sp)
    sd   a1, 0(sp)

    ;;; Store the frozen argument to its destination
    ld   a0, _EFC_ARG_DEST(t1)
    ld   a1, _EFC_ARG(t1)
    sd   a1, 0(a0)

    ;;; Restore argument registers
    ld   a0, 8(sp)
    ld   a1, 0(sp)
    addi sp, sp, 16

    ;;; Chain to the function via its external pointer
    ld   t1, _EFC_FUNC(t1)
    ld   t2, 0(t1)
    jr   t2


;;; _POP_EXTERNAL_CALLBACK:
;;; Interface routine for external callback.
;;;
;;; C Synopsis:  int _pop_external_callback(unsigned long argp[])
;;; argp[0] is the function code for -Callback-.

.globl  EXTERN_NAME(_pop_external_callback)
EXTERN_NAME(_pop_external_callback):
DEF_C_LAB(Sys$- _external_callback_func)
    ;;; Save ALL callee-saved registers and the return address:
    ;;; ra, fp(s0), s1(USP), s2(PB), s3-s11 (x19-x27).  13 regs -> 112-byte
    ;;; (16-aligned) frame, one 8-byte slack slot at 0(sp).
    addi sp, sp, -112
    sd   ra,  104(sp)
    sd   x8,   96(sp)      ;;; fp  (s0)
    sd   x9,   88(sp)      ;;; USP (s1)
    sd   x18,  80(sp)      ;;; PB  (s2)
    sd   x19,  72(sp)
    sd   x20,  64(sp)
    sd   x21,  56(sp)
    sd   x22,  48(sp)
    sd   x23,  40(sp)
    sd   x24,  32(sp)
    sd   x25,  24(sp)
    sd   x26,  16(sp)
    sd   x27,   8(sp)

    ;;; Save __pop_in_user_extern (pushed in its own 16-byte aligned slot)
    ld   t0, pop_in_extern.lab
    ld   t1, 0(t0)
    addi sp, sp, -16
    sd   t1, 0(sp)

    ;;; Dummy stack frame (32 bytes, keeps alignment)
    addi sp, sp, -32

    ;;; Zero __pop_in_user_extern (disable async callback)
    sd   x0, 0(t0)

    ;;; Restore old PB (from the saved entry sp's frame)
    ld   t0, saved_sp.lab
    ld   t1, 0(t0)
    ld   PB, 0(t1)

    ;;; Restore USP
    ld   t0, saved_usp.lab
    ld   USP, 0(t0)

    ;;; Pass argp (a0 holds argp from the C caller) on the user stack
    addi USP, USP, -8
    sd   a0, 0(USP)

    ;;; Dummy for change in break addr
    addi USP, USP, -8
    sd   x0, 0(USP)

    ;;; Put Pop-11 zero (popint 0 = 3) in the Pop register-locals x19-x23
    li   x19, 3
    li   x20, 3
    li   x21, 3
    li   x22, 3
    li   x23, 3

    call XC_LAB(Sys$-Extern$-Callback)

    ;;; Handle return value (pop from the user stack)
    ld   a0, 0(USP)
    addi USP, USP, 8

    ;;; Save USP
    ld   t0, saved_usp.lab
    sd   USP, 0(t0)

    ;;; Remove the dummy stack frame
    addi sp, sp, 32

    ;;; Restore __pop_in_user_extern
    ld   t0, pop_in_extern.lab
    ld   t1, 0(sp)
    addi sp, sp, 16
    sd   t1, 0(t0)

    ;;; Restore callee-saved registers and return
    ld   ra,  104(sp)
    ld   x8,   96(sp)
    ld   x9,   88(sp)
    ld   x18,  80(sp)
    ld   x19,  72(sp)
    ld   x20,  64(sp)
    ld   x21,  56(sp)
    ld   x22,  48(sp)
    ld   x23,  40(sp)
    ld   x24,  32(sp)
    ld   x25,  24(sp)
    ld   x26,  16(sp)
    ld   x27,   8(sp)
    addi sp, sp, 112
    ret

;;; End wrapper: set size
	.text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
