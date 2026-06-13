/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Lisp support assembly routines for RISC-V (rv64gc, LP64D)
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'

lconstant macro (

        ;;; User stack pointer

        USP     = "x9",     ;;; s1 (matches genproc R10)
);

>_#

    .option arch, rv64gc
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    .file "alisp.s"
	.text

;;; Wrapping in POP object
	.text
   .quad  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

L0._userhi:
    .quad I_LAB(_userhi)
nil.lab:
    .quad C_LAB(nil)

DEF_C_LAB (_setstklen)
    ld    t1, 8(USP)
    ld    t0, 0(USP)
    addi  USP, USP, 16
    add   t0, t0, t1
    addi  t0, t0, -6
    ;;; (nresults + saved_len) are POPINTS (scale 4/item); subtracting the two
    ;;; tags (#6) leaves 4*(items).  Stack items are 8 bytes on LP64, so double
    ;;; to get the byte offset 8*(items).  (See the arm64 note: without this the
    ;;; user stack underflows -- "Ste: stack empty" blocking Lisp eval.)
    add   t0, t0, t0
    adr_l t1, L0._userhi
    ld    t1, 0(t1)
    ld    t1, 0(t1)
    sub   t0, t1, t0
    bne   USP, t0, 1f
    ret
1:
    ;;; fall through
DEF_C_LAB (_setstklen_diff)
    ;;; if too short set and return  (b.cs == unsigned >=)
    bgeu  USP, t0, 2f
    mv    USP, t0
    ret
2:
    adr_l t1, nil.lab
    ld    t1, 0(t1)
str.loop:
    addi  USP, USP, -8
    sd    t1, 0(USP)
    bne   USP, t0, str.loop
    ret

;;; End wrapper: set size
	.text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
