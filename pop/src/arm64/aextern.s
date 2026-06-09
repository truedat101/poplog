/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Assembly routines supporting calling external
            functions for AArch64 (ARM 64-bit)
   Author:  Waldek Hebisch (ARM32 original)
            AArch64 port
*/

#_<

#_INCLUDE 'declare.ph'
#_INCLUDE 'external.ph'
#_INCLUDE 'numbers.ph'

lconstant macro (
    USP   = "x19",
    PB    = "x20",
    SP    = "sp",

    _K_EXTERN_TYPE  = @@K_EXTERN_TYPE,
    _EFC_FUNC   = @@EFC_FUNC,
    _EFC_ARG    = @@EFC_ARG,
    _EFC_ARG_DEST   = @@EFC_ARG_DEST,
);

;;; Sanity check: keep the asm-side offset of K_EXTERN_TYPE in sync with the
;;; offset that the C side uses (see pop/extern/lib/ext_arm.c, AArch64 branch).
;;; This is the K-record field offset, which depends on word size and prior
;;; fields.  On arm64 it is 11 word slots in + 2 byte tag = 90.
if _pint(_K_EXTERN_TYPE) /== (11*8 + 2) then
    mishap(_pint(_K_EXTERN_TYPE), (11*8 + 2), 2,
           '_K_EXTERN_TYPE must agree with ext_arm.c (AArch64 branch)');
endif;

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
    .file   "aextern.s"
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF

;;; Wrapping in POP object
#_IF DEF UNIX_MACHO
	.section	__DATA,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF
   .xword   Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

;;; Literal pool entries (pointer-sized)
#_IF DEF UNIX_MACHO
	.p2align	3
#_ENDIF
saved_sp.lab:
    .xword I_LAB(Sys$-Extern$- _saved_sp)

saved_usp.lab:
    .xword I_LAB(Sys$-Extern$- _saved_usp)

pop_in_extern.lab:
    .xword EXTERN_NAME(__pop_in_user_extern)

ext_result.lab:
    .xword C_LAB(Sys$-Extern$-result_struct)

;;; _call_external(nargs, routine, fltsingle)
;;;
;;; AArch64 calling convention:
;;;   Integer args: x0-x7  (8 registers)
;;;   FP args:      d0-d7  (8 registers)
;;;   Register buffer: 8*8 (int) + 8*16 (FP) = 192 bytes
;;;
;;; Poplog registers (callee-saved):
;;;   USP = x19, PB = x20, Pop temps = x21-x25
;;; Scratch: x0-x7, x9-x15. x16/x17 = IP scratch. x29=FP, x30=LR
;;;
DEF_C_LAB (_call_external)
    ;;; Save caller's stack pointer for interrupt/callback
    ldr x0, saved_sp.lab
    mov x1, SP
    str x1, [x0]

    ;;; Save callee-saved registers we use.
    ;;; Caller should save Pop registers to avoid problems with
    ;;; garbage collection.  We do not store them (and do not use them).
    ;;;
    ;;; Save x21-x25 (Pop temps we clobber), x29 (FP), x30 (LR)
    ;;; We save in pairs for 16-byte alignment.
    stp x29, x30, [SP, #-16]!
    stp x21, x22, [SP, #-16]!
    stp x23, x24, [SP, #-16]!
    stp x25, x26, [SP, #-16]!

    ;;; Load fixed arguments from user stack (each word is 8 bytes)
    ldr    x22, [USP], #8    ;;; fltsingle
    ldr    x24, [USP], #8    ;;; routine
    ldr    x0,  [USP], #8    ;;; nargs

    ;;; Allocate buffer for register arguments
    ;;; 8*8 for integer arguments + 8*16 for floating point = 192 bytes
    ;;; We round up to keep 16-byte alignment: 192 is already 16-aligned
    sub    SP, SP, #192
    mov    x23, SP

    ;;; Allocate space for stack arguments
    ;;; At least 8 arguments are passed in registers.
    ;;; If nargs <= 8, no stack space needed.
    ;;; If nargs > 8, allocate (nargs - 8) * 8 bytes, rounded up
    ;;; to maintain 16-byte SP alignment.

    cmp x0, #8
    b.ls do_args
    sub x1, x0, #8
    lsl x1, x1, #3        ;;; (nargs - 8) * 8
    add x1, x1, #15       ;;; round up to 16-byte alignment
    and x1, x1, #~15
    sub SP, SP, x1

do_args:
    mov x2, SP             ;;; stack arg pointer
    mov x25, x0            ;;; save nargs

    ;;; Push fltsingle onto the C stack as 5th argument
    ;;; copy_external_arguments(int n, popword *ap, void *sp,
    ;;;                         reg_buff *rp, int fltsingle)
    ;;; AArch64: first 8 args in x0-x7, so all 5 args go in registers
    mov x4, x22            ;;; fltsingle -> arg5
    mov x3, x23            ;;; reg buffer -> arg4
                            ;;; x2 already has stack arg pointer -> arg3
    mov x1, USP            ;;; user stack pointer -> arg2
                            ;;; x0 already has nargs -> arg1
    bl EXTERN_NAME(copy_external_arguments)

    ;;; Advance USP past the arguments (each Pop word is 8 bytes)
    add USP, USP, x25, lsl #3

    ;;; Load buffered integer arguments from register buffer
    ;;; Integer part: 8 * 8 bytes at offset 0
    ldr x0, [x23, #0]
    ldr x1, [x23, #8]
    ldr x2, [x23, #16]
    ldr x3, [x23, #24]
    ldr x4, [x23, #32]
    ldr x5, [x23, #40]
    ldr x6, [x23, #48]
    ldr x7, [x23, #56]

    ;;; Load buffered FP arguments from register buffer
    ;;; FP part: 8 * 16 bytes at offset 64
    ldr d0, [x23, #64]
    ldr d1, [x23, #80]
    ldr d2, [x23, #96]
    ldr d3, [x23, #112]
    ldr d4, [x23, #128]
    ldr d5, [x23, #144]
    ldr d6, [x23, #160]
    ldr d7, [x23, #176]

    ;;; Save USP and enable async callback
    ldr x9, saved_usp.lab
    str USP, [x9]
    ldr x9, pop_in_extern.lab
    mov x10, SP
    str x10, [x9]

    ;;; Call the external function
    blr x24

    ;;; Disable async callback
    ldr x9, pop_in_extern.lab
    str xzr, [x9]

    ;;; Restore USP
    ldr x9, saved_usp.lab
    ldr USP, [x9]

    ;;; Store result
    ldr x9, ext_result.lab
    str x0, [x9, #8]       ;;; integer/pointer result
    str d0, [x9]            ;;; floating point result

    ;;; Restore SP to point to saved registers
    ;;; saved_sp holds the original SP before we pushed registers
    ldr x0, saved_sp.lab
    ldr x0, [x0]
    ;;; We pushed 4 pairs = 64 bytes of registers
    sub x1, x0, #64
    mov SP, x1

    ;;; Restore registers
    ldp x25, x26, [SP], #16
    ldp x23, x24, [SP], #16
    ldp x21, x22, [SP], #16
    ldp x29, x30, [SP], #16

    ;;; Restore PB (saved by caller at top of its frame)
    ldr PB, [SP]

    ;;; Zero saved SP to indicate external call is over
    ldr x1, saved_sp.lab
    str xzr, [x1]

    ret


;;; _EXFUNC_CLOS_ACTION:
;;; Called from the code in an exfunc_closure.
;;; On AArch64, x16 holds the closure address (IP0 scratch register).
;;; We must preserve argument registers x0-x7.

DEF_C_LAB(Sys$- _exfunc_clos_action)
    ;;; Save argument registers we need to use as scratch
    stp x0, x1, [SP, #-16]!

    ;;; Store frozen argument to destination
    ldr x0, [x16, #_EFC_ARG_DEST]
    ldr x1, [x16, #_EFC_ARG]
    str x1, [x0]

    ;;; Restore argument registers
    ldp x0, x1, [SP], #16

    ;;; Chain function via external ptr
    ldr x16, [x16, #_EFC_FUNC]
    ldr x9, [x16]
    br x9


;;; _POP_EXTERNAL_CALLBACK:
;;; Interface routine for external callback
;;;
;;; C Synopsis:
;;; int _pop_external_callback(unsigned long argp[])
;;;
;;; Arguments:
;;; argp[0] is the function code for -Callback-

.globl  EXTERN_NAME(_pop_external_callback)
EXTERN_NAME(_pop_external_callback):
DEF_C_LAB(Sys$- _external_callback_func)
    ;;; Save ALL callee-saved C registers and return address
    ;;; Callee-saved: x19-x28, x29(FP), x30(LR)
    stp x29, x30, [SP, #-16]!
    stp x27, x28, [SP, #-16]!
    stp x25, x26, [SP, #-16]!
    stp x23, x24, [SP, #-16]!
    stp x21, x22, [SP, #-16]!
    stp x19, x20, [SP, #-16]!

    ;;; Save __pop_in_user_extern
    ldr x9, pop_in_extern.lab
    ldr x10, [x9]
    str x10, [SP, #-16]!    ;;; push with 16-byte alignment

    ;;; Create dummy stack frame (4 words = 32 bytes to keep alignment)
    sub SP, SP, #32

    ;;; Zero __pop_in_user_extern (disable async callback)
    str xzr, [x9]

    ;;; Restore old PB
    ldr x9, saved_sp.lab
    ldr x10, [x9]
    ldr PB, [x10]

    ;;; Restore USP
    ldr x9, saved_usp.lab
    ldr USP, [x9]

    ;;; Pass argp (x0 holds argp from C caller)
    str x0, [USP, #-8]!

    ;;; Dummy for change in break addr
    str xzr, [USP, #-8]!

    ;;; Put Pop11 zero (popint 0 = 3) in Pop temp registers
    mov x21, #3
    mov x22, #3
    mov x23, #3
    mov x24, #3
    mov x25, #3

    bl XC_LAB(Sys$-Extern$-Callback)

    ;;; Handle return value
    ldr x0, [USP], #8

    ;;; Save USP
    ldr x9, saved_usp.lab
    str USP, [x9]

    ;;; Remove dummy stack frame
    add SP, SP, #32

    ;;; Restore __pop_in_user_extern
    ldr x9, pop_in_extern.lab
    ldr x10, [SP], #16
    str x10, [x9]

    ;;; Restore callee-saved C registers and return
    ldp x19, x20, [SP], #16
    ldp x21, x22, [SP], #16
    ldp x23, x24, [SP], #16
    ldp x25, x26, [SP], #16
    ldp x27, x28, [SP], #16
    ldp x29, x30, [SP], #16
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
