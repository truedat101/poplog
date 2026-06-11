/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Poplog entry point for AArch64
   Author:  Waldek Hebisch
   AArch64 port by truedat101
*/


#_<

#_INCLUDE 'declare.ph'

lconstant macro (
    USP         = "x19",
    SAVED_USP   = [I_LAB(Sys$-Extern$- _saved_usp)],
);

section $-Sys;

vars
    _init_args,
    ;

endsection;

>_#

#_IF DEF UNIX_MACHO
    ;;; Mach-O PC-relative address load: adrp ...@PAGE / add ...@PAGEOFF.
    ;;; NB: backslashes are doubled because popc escape-processes .s text.
    .macro adr_l reg, sym
    adrp \\reg, \\sym@PAGE
    add  \\reg, \\reg, \\sym@PAGEOFF
    .endm
#_ELSE
    .arch armv8-a
    ;;; ELF PC-relative address load: adrp ... / add ... :lo12:...
    .macro adr_l reg, sym
    adrp \\reg, \\sym
    add  \\reg, \\reg, :lo12:\\sym
    .endm
#_ENDIF
    .file   "amain.s"

;;; Wrapping in POP object
#_IF DEF UNIX_MACHO
	.section	__POPSEED,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF
#_IF DEF UNIX_MACHO
   .quad   Ltext_size, C_LAB(Sys$-objmod_pad_key)
#_ELSE
   .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
#_ENDIF
Ltext_start:


;;; _MAIN:
;;; Entry point to Poplog; called from C/system startup.

;;; Call:
;;; main(argc, argv, envp)

DEF_C_LAB (Sys$- _entry_point)
#_IF DEF UNIX_MACHO
    ;;; On Mach-O this code sits in the non-executable __POPSEED segment, so it
    ;;; cannot be the process entry. The real `main` is the C loader
    ;;; (pop_seed_loader.c, in __TEXT): it remaps __POPSEED's pages in place as
    ;;; executable anon memory (same address -- nothing relocates), then calls
    ;;; in here.
    .globl _pop_seed_main
_pop_seed_main:
#_ELSE
    .globl  EXTERN_NAME(main)
EXTERN_NAME(main):
#_ENDIF
    ;;; Save callee-saved registers and link register.
    ;;; We save x19 (USP), x20 (PB), x21, x22 (Pop temp regs),
    ;;; x29 (FP), x30 (LR).  stp pairs keep 16-byte alignment.
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x29, sp

    ;;; Save pointer to argument vector (argv)
    adr_l x3, I_LAB(Sys$- _init_args)
    str  x1, [x3]

    ;;; Clear __pop_in_user_extern
    adr_l x3, EXTERN_NAME(__pop_in_user_extern)
    str  xzr, [x3]

#_IF DEF LINUX

    ;;; set personality

    bl linux_setper

#_ENDIF

    ;;; Set up a temporary user stack pointer
    adr_l USP, SAVED_USP
    ldr  USP, [USP]

    ;;; clear Pop registers
    mov    x21, #3
    mov    x22, x21

    ;;; Start the system
    bl  XC_LAB(setpop)

    ;;; Exit with 0
    mov w0, #0
    bl  EXTERN_NAME(_exit)

    .align  3

;;; End wrapper: set sizes
#_IF DEF UNIX_MACHO
	.section	__POPSEED,__popseed
	.p2align	3
#_ELSE
	.text
#_ENDIF
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
