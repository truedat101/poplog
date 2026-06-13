/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Poplog entry point for RISC-V (rv64gc, LP64D)
   Author:  Waldek Hebisch
   AArch64 port by truedat101
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
*/


#_<

#_INCLUDE 'declare.ph'

lconstant macro (
    ;;; USP = user stack pointer = x9 (s1), matching genproc's R10/USP.
    USP         = "x9",
    SAVED_USP   = [I_LAB(Sys$-Extern$- _saved_usp)],
);

section $-Sys;

vars
    _init_args,
    ;

endsection;

>_#

    ;;; ELF PC-relative address load: lla reg, sym  (auipc + addi pseudo,
    ;;; non-PIC local address).  NB: backslashes are doubled because popc
    ;;; escape-processes .s text.
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    .option arch, rv64gc
    .file   "amain.s"

;;; Wrapping in POP object
    .text
   .quad  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:


;;; _MAIN:
;;; Entry point to Poplog; called from C/system startup.

;;; Call:
;;; main(argc, argv, envp)        ;;; a0=argc, a1=argv, a2=envp

DEF_C_LAB (Sys$- _entry_point)
    .globl  EXTERN_NAME(main)
EXTERN_NAME(main):
    ;;; Save the callee-saved registers Poplog takes over plus the return
    ;;; address.  RISC-V LP64: ra=x1, fp=x8(s0), USP=x9(s1), PB=x18(s2), and the
    ;;; two Pop register-locals x19/x20 (s3/s4) -- the GC-scanned VM registers
    ;;; (see genproc M_CREATE_SF / PD_REGMASK).  48-byte frame keeps sp 16-aligned.
    addi sp, sp, -48
    sd   ra,  40(sp)
    sd   x8,  32(sp)        ;;; fp (s0)
    sd   x9,  24(sp)        ;;; USP (s1)
    sd   x18, 16(sp)        ;;; PB  (s2)
    sd   x19,  8(sp)        ;;; Pop register-local (s3)
    sd   x20,  0(sp)        ;;; Pop register-local (s4)
    mv   x8, sp             ;;; fp = sp

    ;;; Save pointer to argument vector (argv = a1 = x11)
    adr_l x5, I_LAB(Sys$- _init_args)
    sd   x11, 0(x5)

    ;;; Clear __pop_in_user_extern
    adr_l x5, EXTERN_NAME(__pop_in_user_extern)
    sd   x0, 0(x5)          ;;; x0 = hardwired zero

#_IF DEF LINUX

    ;;; set personality

    call linux_setper

#_ENDIF

    ;;; Set up a temporary user stack pointer
    adr_l USP, SAVED_USP
    ld   USP, 0(USP)

    ;;; clear Pop registers (x19, x20) to the tagged POP integer 3
    li     x19, 3
    mv     x20, x19

    ;;; Start the system
    call  XC_LAB(setpop)

    ;;; Exit with 0
    li   a0, 0
    call EXTERN_NAME(_exit)

    .align  3

;;; End wrapper: set sizes
    .text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
