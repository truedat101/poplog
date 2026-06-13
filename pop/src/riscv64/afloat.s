/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Floating-point assembler routines for RISC-V (rv64gc, LP64D)
   Author:  Waldek Hebisch
   AArch64 port by truedat101
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'
#_INCLUDE 'numbers.ph'

constant
        procedure Sys$-Float_qrem
        ;

weak constant
    _pfcopy
    _pfzero
    _pfneg
    _pfeq
    _pfsgreq
    _pfsgr
    _pfabs
;

lconstant macro (
    USP   = "x9",      ;;; s1 (matches genproc R10)
    PB    = "x18",     ;;; s2 (matches genproc R11)
    _DD_1 = @@DD_1,
);

>_#

    .option arch, rv64gc
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    .file   "afloat.s"
	.text

;;; Wrapping in POP object
	.text
   .quad  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

/* Calling conventions:
   - double floats are represented by their addresses (pointers)
   - ddecimals are pointers to Pop structures; DD_1 holds the IEEE double
   - decimals and single floats are passed by value
   - Poplog word = 8 bytes
   Register remap: arm64 d7/d6/s13 -> ft7/ft6/ft1; ft0 = a 0.0 constant; GPR
   scratch x0-x3 -> a0-a3, x9/x10/x11/x12 -> t3/t4/t5/t6 (x2=sp,x3=gp reserved,
   USP=x9 here); FP compare result -> t0.  csel becomes a branch-select; arm64's
   shared-flags L.ret_false trick is expanded to explicit register tests. */

DEF_C_LAB (_pfcopy)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 16
    fld  ft7, 0(a2)
    fsd  ft7, 0(a3)
    ret

;;; Conversions

;;; Pop decimal to single float, just drop pop tag bit (disabled in arm64
;;; source via a self-branch; replicated faithfully).
DEF_C_LAB (_pf_sfloat_dec)
    tail C_LAB (_pf_sfloat_dec)
    ld   a3, 0(USP)
    addi a3, a3, -1
    sd   a3, 0(USP)
    ret

;;; machine integer -> double; result pointer on top, integer below
DEF_C_LAB (_pf_dfloat_int)
    ld   a3, 8(USP)            /* machine integer */
    ld   a2, 0(USP)            /* result pointer */
    addi USP, USP, 16
    fcvt.d.l ft7, a3           /* signed 64-bit int -> double */
    fsd  ft7, 0(a2)
    ret

DEF_C_LAB (_pf_dfloat_uint)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 16
    fcvt.d.lu ft7, a3          /* unsigned 64-bit int -> double */
    fsd  ft7, 0(a2)
    ret

;;; Pop decimal -> double; result pointer on top
DEF_C_LAB (_pf_dfloat_dec)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 16
    addiw a3, a3, -1           /* drop pop tag bit (32-bit single) */
    fmv.w.x ft1, a3
    fcvt.d.s ft7, ft1          /* single -> double */
    fsd  ft7, 0(a2)
    ret

;;; Pop ddecimal -> double; result pointer on top
DEF_C_LAB (_pf_dfloat_ddec)
    ld   a3, 8(USP)            /* ddecimal pointer */
    ld   a2, 0(USP)            /* result pointer */
    addi USP, USP, 16
    fld  ft7, _DD_1(a3)
    fsd  ft7, 0(a2)
    ret

;;; Double float -> Pop decimal, returns false on overflow
DEF_C_LAB (_pf_cvt_to_dec)
    ld   a3, 0(USP)
    ;;; Rounding fix in the low 32 bits of the double (see arm64 derivation).
    fld  ft7, 0(a3)
    fmv.x.d t3, ft7            /* 64-bit IEEE representation */
    slli t4, t3, 32
    srli t4, t4, 32           /* low 32 bits (zero-extended) */
    srli t5, t3, 32           /* high 32 bits */
    li   t6, 0x40000000
    beq  t4, t6, 1f
    li   t6, 0x38000000
    or   t4, t4, t6
1:
    slli t5, t5, 32
    or   t3, t4, t5           /* reconstruct 64-bit double */
    fmv.d.x ft7, t3
    fcvt.s.d ft1, ft7         /* double -> single */
    fmv.x.w a2, ft1
    andi a2, a2, -4           /* bic #3 */
    ori  a2, a2, 1            /* set pop tag bit */
    slliw t4, a2, 1
    srliw t4, t4, 24          /* extract exponent */
    beqz t4, 2f               /* exponent 0 -> pop integer 1 */
    li   t6, 0xff
    beq  t4, t6, 3f           /* exponent 0xff -> overflow */
    sd   a2, 0(USP)
    ret
2:
    li   a2, 1
    sd   a2, 0(USP)
    ret
3:
    adr_l t3, L.false
    ld   a2, 0(t3)
    sd   a2, 0(USP)
    ret

;;; Double float -> Pop ddecimal
DEF_C_LAB (_pf_cvt_to_ddec)
    ld   a3, 8(USP)           /* source double pointer */
    ld   a2, 0(USP)           /* ddecimal pointer */
    addi USP, USP, 16
    fld  ft7, 0(a3)
    fsd  ft7, _DD_1(a2)
    ret

DEF_C_LAB (_pf_round_d_to_s)
    ld   a3, 0(USP)
    fld  ft7, 0(a3)
    fcvt.s.d ft1, ft7         /* double -> single */
    fmv.x.w a2, ft1
    slliw t4, a2, 1
    srliw t4, t4, 24          /* extract exponent */
    li   t6, 0xff
    beq  t4, t6, L.ret_false
    fsw  ft1, 0(a3)
    ret

DEF_C_LAB (_pf_extend_s_to_d)
    ld   a3, 0(USP)
    lw   a2, 0(a3)
    slliw t4, a2, 1
    srliw t4, t4, 24
    li   t6, 0xff
    beq  t4, t6, L.ret_false
    fmv.w.x ft1, a2
    fcvt.d.s ft7, ft1         /* single -> double */
    fsd  ft7, 0(a3)
    ret

DEF_C_LAB(_pf_check_d)
    ld   a3, 0(USP)
    fld  ft7, 0(a3)
    fmv.x.d t3, ft7
    srli t3, t3, 32           /* high 32 bits */
    li   t4, 0x7ff00000       /* exponent mask */
    and  t3, t3, t4
    bne  t3, t4, 1f           /* not inf/nan -> leave unchanged */
    adr_l t3, L.false
    ld   a3, 0(t3)
    sd   a3, 0(USP)
1:
    ret

;;; shared tail: store false on the user stack
L.ret_false:
    adr_l t3, L.false
    ld   a3, 0(t3)
    sd   a3, 0(USP)
    ret

;;; Convert double -> signed 64-bit integer
DEF_C_LAB (_pf_intof)
    ld   a3, 0(USP)
    fld  ft7, 0(a3)
    adr_l t3, L.maxint
    fld  ft6, 0(t3)
    fle.d t0, ft6, ft7        /* maxint <= d7 -> out of range */
    bnez t0, L.out_of_range
    adr_l t3, L.minint
    fld  ft6, 0(t3)
    fle.d t0, ft7, ft6        /* d7 <= minint -> out of range */
    bnez t0, L.out_of_range
    fcvt.l.d t3, ft7, rtz     /* double -> signed 64-bit, toward zero */
    sd   t3, 0(USP)
    adr_l t4, L.true
    ld   a0, 0(t4)
    addi USP, USP, -8
    sd   a0, 0(USP)           /* push true */
    ret
L.out_of_range:
    adr_l t3, L.false
    ld   a0, 0(t3)
    sd   a0, 0(USP)
    ret

    .align  3
L.maxint:
    .quad  0x43E0000000000000   /* 2^63 */
L.minint:
    .quad  0xC3E0000000000000   /* -(2^63) */
L.maxuint:
    .quad  0x43F0000000000000   /* 2^64 */

DEF_C_LAB (_pf_uintof)
    ld   a3, 0(USP)
    fld  ft7, 0(a3)
    adr_l t3, L.maxuint
    fld  ft6, 0(t3)
    fle.d t0, ft6, ft7        /* maxuint <= d7 -> out of range */
    bnez t0, L.out_of_range
    fmv.d.x ft0, x0           /* 0.0 */
    flt.d t0, ft7, ft0        /* d7 < 0.0 -> out of range */
    bnez t0, L.out_of_range
    fcvt.lu.d t3, ft7, rtz    /* double -> unsigned 64-bit */
    sd   t3, 0(USP)
    adr_l t4, L.true
    ld   a0, 0(t4)
    addi USP, USP, -8
    sd   a0, 0(USP)
    ret

;;; Extract exponent of a double float
DEF_C_LAB (_pf_expof)
    ld   a0, 0(USP)
    fld  ft7, 0(a0)
    fmv.x.d t3, ft7
    srli t3, t3, 52           /* exponent + sign */
    andi t3, t3, 0x7ff        /* mask 11-bit exponent */
    addi t3, t3, -1023        /* remove bias */
    sd   t3, 0(USP)
    ret

;;; Set exponent of a double float
DEF_C_LAB(-> _pf_expof)
    ld   a0, 0(USP)
    addi USP, USP, 8
    ld   a1, 0(USP)           /* new exponent (pre-index) */
    addi a1, a1, 1023         /* add bias */
    fld  ft7, 0(a0)
    fmv.x.d t3, ft7
    li   t4, 0x7ff
    slli t4, t4, 52           /* exponent mask in position */
    not  t4, t4
    and  t3, t3, t4           /* clear exponent bits (bic) */
    li   t1, 2048
    bgeu a1, t1, L.exp_too_big
    slli a1, a1, 52
    or   t3, t3, a1           /* set new exponent */
    fmv.d.x ft7, t3
    fsd  ft7, 0(a0)
    adr_l t3, L.true
    ld   a3, 0(t3)
    sd   a3, 0(USP)
    ret
L.exp_too_big:
    adr_l t3, L.false
    ld   a3, 0(t3)
    sd   a3, 0(USP)
    ret

;;; _pfmodf: split double into integer and fractional parts
DEF_C_LAB (_pfmodf)
    ld   a1, 8(USP)           /* fractional result pointer */
    ld   a0, 0(USP)           /* argument / integer result pointer */
    addi USP, USP, 16
    fld  ft7, 0(a0)
    fmv.x.d t3, ft7           /* 64-bit representation */
    srli t1, t3, 52
    andi a2, t1, 0x7ff        /* 11-bit exponent field (ubfx 52,11) */
    addi a2, a2, -1023        /* unbias */
    bltz a2, L.negexp
    li   t1, 52
    blt  t1, a2, L.bigexp     /* exponent > 52 */
    ;;; Normal case: clear the lower (52 - exponent) mantissa bits
    li   a3, 52
    sub  a3, a3, a2
    li   t4, -1
    sll  t4, t4, a3           /* mask: upper set, lower cleared */
    and  t5, t3, t4           /* integer part bits */
    fmv.d.x ft6, t5
    fsd  ft6, 0(a0)           /* store integer part */
    fsub.d ft7, ft7, ft6      /* fractional = original - integer */
    fsd  ft7, 0(a1)
    ret
L.bigexp:
    sd   x0, 0(a1)            /* fraction = +0.0 */
    ret
L.negexp:
    fld  ft7, 0(a0)
    fsd  ft7, 0(a1)           /* whole value is fractional */
    li   t4, 1
    slli t4, t4, 63           /* sign bit */
    and  t3, t3, t4           /* keep sign only */
    sd   t3, 0(a0)            /* signed zero */
    ret

DEF_C_LAB (_pfzero)
    ld   a3, 0(USP)
    fld  ft7, 0(a3)
    fmv.d.x ft0, x0           /* 0.0 */
    feq.d t0, ft7, ft0
    adr_l t3, L.false
    ld   a0, 0(t3)
    adr_l t3, L.true
    ld   a1, 0(t3)
    beqz t0, 1f
    mv   a0, a1
1:
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_pfneg)
    ld   a3, 0(USP)
    fld  ft7, 0(a3)
    fmv.d.x ft0, x0
    flt.d t0, ft7, ft0        /* d7 < 0.0 */
    adr_l t3, L.false
    ld   a0, 0(t3)
    adr_l t3, L.true
    ld   a1, 0(t3)
    beqz t0, 1f
    mv   a0, a1
1:
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_pfeq)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fld  ft6, 0(a2)
    feq.d t0, ft6, ft7
    adr_l t3, L.false
    ld   a0, 0(t3)
    adr_l t3, L.true
    ld   a1, 0(t3)
    beqz t0, 1f
    mv   a0, a1
1:
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_pfsgreq)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fld  ft6, 0(a2)
    fle.d t0, ft6, ft7        /* d6 <= d7 */
    adr_l t3, L.false
    ld   a0, 0(t3)
    adr_l t3, L.true
    ld   a1, 0(t3)
    beqz t0, 1f
    mv   a0, a1
1:
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_pfsgr)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fld  ft6, 0(a2)
    flt.d t0, ft6, ft7        /* d6 < d7 */
    adr_l t3, L.false
    ld   a0, 0(t3)
    adr_l t3, L.true
    ld   a1, 0(t3)
    beqz t0, 1f
    mv   a0, a1
1:
    sd   a0, 0(USP)
    ret

DEF_C_LAB (_pfabs)
    ld   a3, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fabs.d ft7, ft7
    fsd  ft7, 0(a3)
    ret

DEF_C_LAB (_pfnegate)
    ld   a3, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fneg.d ft7, ft7
    fsd  ft7, 0(a3)
    ret

;;; first arg pointer on top; the second is also the result
DEF_C_LAB (_pfadd)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fld  ft6, 0(a2)
    fadd.d ft7, ft7, ft6
    fsd  ft7, 0(a3)
    ret

DEF_C_LAB (_pfsub)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fld  ft6, 0(a2)
    fsub.d ft7, ft7, ft6
    fsd  ft7, 0(a3)
    ret

DEF_C_LAB (_pfmult)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 8
    fld  ft7, 0(a3)
    fld  ft6, 0(a2)
    fmul.d ft7, ft7, ft6
    fsd  ft7, 0(a3)
    ret

DEF_C_LAB (_pfdiv)
    ld   a3, 8(USP)
    ld   a2, 0(USP)
    addi USP, USP, 8
    fld  ft6, 0(a2)
    fld  ft7, 0(a3)
    fdiv.d ft7, ft7, ft6
    fsd  ft7, 0(a3)
    ret

    .align  3
L.true:
    .quad C_LAB(true)
L.false:
    .quad C_LAB(false)

DEF_C_LAB (_pfqrem)
    tail XC_LAB(Sys$-Float_qrem)

    .align  3

;;; End wrapper: set size
	.text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
