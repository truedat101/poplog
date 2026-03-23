/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Floating point assembly routines for AArch64
   Author:  Waldek Hebisch
   AArch64 port by Poplog contributors
 */

#_<

#_INCLUDE 'declare.ph'

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

        ;;; User stack pointer

        USP     = "x19",

        ;;; Pop ddecimal structure fields:
        ;;; _DD_1 = MS part, _DD_2 = LS part

        _DD_1   = @@DD_1,
        _DD_2   = @@DD_2,

);

>_#
    .arch armv8-a
    .file   "afloat.s"
    .text

;;; Wrapping in POP object
   .text
   .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

/* Calling conventions:
   - double floats are represented by their addresses (pointers),
     addresses point to raw memory (without a key)
   - ddecimals are represented by pointers to Pop structures
   - decimals and single floats are passed by value
   - Poplog word = 8 bytes on AArch64
*/

DEF_C_LAB (_pfcopy)
    ldr     x3, [USP, #8]
    ldr     x2, [USP], #16
    ldr     d7, [x2]
    str     d7, [x3]
    ret

;;; Conversions

;;; Pop decimal to single float, just drop pop tag bit
DEF_C_LAB (_pf_sfloat_dec)
    b C_LAB (_pf_sfloat_dec)
    ldr   x3, [USP]
    sub   x3, x3, #1
    str   x3, [USP]
    ret

;;; Used to read floats
;;; argument on top of stack is storage for result, second one
;;; is machine integer
DEF_C_LAB (_pf_dfloat_int)
    ldr     x3, [USP, #8]          /* load machine integer (64-bit) */
    ldr     x2, [USP], #16         /* load result pointer, pop 2 words */
    scvtf   d7, x3                 /* signed 64-bit int to double */
    str     d7, [x2, #0]
    ret

DEF_C_LAB (_pf_dfloat_uint)
    ldr     x3, [USP, #8]          /* load machine unsigned int (64-bit) */
    ldr     x2, [USP], #16         /* load result pointer, pop 2 words */
    ucvtf   d7, x3                 /* unsigned 64-bit int to double */
    str     d7, [x2, #0]
    ret

;;; Pop decimal to double float, pointer to result is on top
;;; of user stack
DEF_C_LAB (_pf_dfloat_dec)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #16
    sub   w3, w3, #1               /* drop pop tag bit (32-bit single) */
    fmov  s13, w3
    fcvt  d7, s13                  /* single to double */
    str   d7, [x2, #0]
    ret

;;; Pop ddecimal to double float, pointer to result is on top
;;; of user stack.
;;; On AArch64 64-bit: DD_1 holds MS 32 bits, DD_2 holds LS 32 bits
;;; of the IEEE 754 double. We reconstruct the 64-bit double from them.
DEF_C_LAB (_pf_dfloat_ddec)
    ldr   x3, [USP, #8]            /* ddecimal pointer */
    ldr   x2, [USP], #16           /* result pointer, pop 2 words */
    ldr   w9, [x3, #_DD_1]         /* MS 32 bits */
    ldr   w10, [x3, #_DD_2]        /* LS 32 bits */
    /* Combine: x9 = (MS << 32) | LS */
    orr   x9, x10, x9, lsl #32
    fmov  d7, x9
    str   d7, [x2]
    ret

;;; Double float to Pop decimal, returns false on overflow
DEF_C_LAB (_pf_cvt_to_dec)
    ldr   x3, [USP]
    ;;; Rounding: single float has 8 bit exponent, while double
    ;;; float has 11 bit exponent, so when converting double
    ;;; to single 3 lowest bits of single come from low
    ;;; word of double.  So rounding depends only on low word
    ;;; of double.  We round towards zero when we have
    ;;;   *0*...
    ;;; or
    ;;;   010...0
    ;;; Otherwise we round outwards.  To get correct rounding
    ;;; we set 3 bits in double to 1, computing OR with
    ;;; 0x38000000.  In *0*... case conversion
    ;;; from double to single gives correct 30 upper bits and
    ;;; masking 2 lowest bits gives correctly rounded decimal.
    ;;; In *1*... case we have set 3 bits to get *1111*... After
    ;;; that conversion from double to single rounds outwards
    ;;; and also gives correct 30 upper bits, except for
    ;;; 010...0 case.  In this last case we just use double as-is.
    ;;;
    ;;; On AArch64: get the full 64-bit double, extract the low 32 bits,
    ;;; apply the rounding fix, reconstruct, convert to single.
    ldr   d7, [x3]
    fmov  x9, d7                   /* get 64-bit IEEE representation */
    mov   w10, w9                  /* low 32 bits of double */
    lsr   x11, x9, #32            /* high 32 bits of double */
    cmp   w10, #0x40000000
    b.eq  1f
    orr   w10, w10, #0x38000000
1:
    orr   x9, x10, x11, lsl #32   /* reconstruct 64-bit double */
    fmov  d7, x9
    fcvt  s13, d7                  /* double to single */
    fmov  w2, s13
    bic   w2, w2, #3
    orr   w2, w2, #1              /* set pop tag bit */
    lsl   w10, w2, #1
    lsr   w10, w10, #24           /* extract exponent */
    cbz   w10, 2f                 /* exponent 0 -> return pop integer 1 */
    cmp   w10, #0xff
    b.eq  3f                      /* exponent 0xff -> overflow, return false */
    /* Normal case: store tagged decimal */
    str   x2, [USP]
    ret
2:
    /* Zero exponent: return pop integer 1 */
    mov   x2, #1
    str   x2, [USP]
    ret
3:
    /* Overflow: return false */
    adrp  x9, L.false
    ldr   x2, [x9, #:lo12:L.false]
    str   x2, [USP]
    ret

;;; Double float to Pop ddecimal
DEF_C_LAB (_pf_cvt_to_ddec)
    ldr   x3, [USP, #8]            /* source double pointer */
    ldr   x2, [USP], #16           /* ddecimal pointer, pop 2 words */
    ldr   d7, [x3]
    fmov  x9, d7                   /* get 64-bit representation */
    lsr   x10, x9, #32            /* high 32 bits = MS */
    str   w10, [x2, #_DD_1]       /* store MS part */
    str   w9, [x2, #_DD_2]        /* store LS part (low 32 bits) */
    ret

DEF_C_LAB (_pf_round_d_to_s)
    ldr     x3, [USP]
    ldr     d7, [x3]
    fcvt    s13, d7                /* double to single */
    fmov    w2, s13
    lsl     w10, w2, #1
    lsr     w10, w10, #24          /* extract exponent */
    cmp     w10, #0xff
    b.eq    L.ret_false
    str     s13, [x3]
    ret

DEF_C_LAB (_pf_extend_s_to_d)
    ldr   x3, [USP]
    ldr   w2, [x3]
    lsl   w10, w2, #1
    lsr   w10, w10, #24
    cmp   w10, #0xff
    b.eq  L.ret_false
    fmov  s13, w2
    fcvt  d7, s13                  /* single to double */
    str   d7, [x3]
    ret

DEF_C_LAB(_pf_check_d)
    ldr   x3, [USP]
    ldr   d7, [x3]
    fmov  x9, d7
    lsr   x9, x9, #32             /* get high 32 bits */
    mov   w10, #0x7ff00000         /* exponent mask */
    and   w9, w9, w10
    cmp   w9, w10
L.ret_false:
    b.ne  1f
    adrp  x9, L.false
    ldr   x3, [x9, #:lo12:L.false]
    str   x3, [USP]
1:
    ret

;;; Convert double to integer (signed, 64-bit on AArch64)
;;; On 64-bit, integers are 64-bit. Max/min adjusted for 64-bit range.
DEF_C_LAB (_pf_intof)
    ldr   x3, [USP]
    ldr   d7, [x3]
    adrp  x9, L.maxint
    ldr   d6, [x9, #:lo12:L.maxint]
    fcmp  d7, d6
    b.pl  L.out_of_range
    adrp  x9, L.minint
    ldr   d6, [x9, #:lo12:L.minint]
    fcmp  d7, d6
    b.le  L.out_of_range
    fcvtzs x9, d7                  /* double to signed 64-bit int */
    str   x9, [USP]
    adrp  x10, L.true
    ldr   x0, [x10, #:lo12:L.true]
    str   x0, [USP, #-8]!         /* push true */
    ret
L.out_of_range:
    adrp  x9, L.false
    ldr   x0, [x9, #:lo12:L.false]
    str   x0, [USP]
    ret

    .align  3
L.maxint:
    ;;; 2^63 = 9223372036854775808.0 = 0x43E0000000000000
    .xword  0x43E0000000000000
L.minint:
    ;;; -(2^63) - 1 approximately = -9223372036854775809.0
    ;;; We use -(2^63) = 0xC3E0000000000000
    .xword  0xC3E0000000000000
L.maxuint:
    ;;; 2^64 = 0x43F0000000000000
    .xword  0x43F0000000000000

DEF_C_LAB (_pf_uintof)
    ldr   x3, [USP]
    ldr   d7, [x3]
    adrp  x9, L.maxuint
    ldr   d6, [x9, #:lo12:L.maxuint]
    fcmp  d7, d6
    b.pl  L.out_of_range
    fcmp  d7, #0.0
    b.mi  L.out_of_range
    fcvtzu x9, d7                  /* double to unsigned 64-bit int */
    str   x9, [USP]
    adrp  x10, L.true
    ldr   x0, [x10, #:lo12:L.true]
    str   x0, [USP, #-8]!         /* push true */
    ret

;;; Extract exponent of double float
DEF_C_LAB (_pf_expof)
    ldr     x0, [USP]
    ldr     d7, [x0]
    fmov    x9, d7
    lsr     x9, x9, #52           /* shift to get exponent + sign */
    and     x9, x9, #0x7ff        /* mask exponent (11 bits) */
    sub     x9, x9, #1023         /* remove bias */
    str     x9, [USP]
    ret

;;; Set exponent of double float
DEF_C_LAB(-> _pf_expof)
    ldr     x0, [USP]
    ldr     x1, [USP, #8]!        /* new exponent, advance USP by 8 */
    add     x1, x1, #1023         /* add bias */
    ldr     d7, [x0]
    fmov    x9, d7
    mov     x10, #0x7ff
    lsl     x10, x10, #52         /* exponent mask at position */
    bic     x9, x9, x10           /* clear exponent bits */
    cmp     x1, #2048
    b.cs    L.exp_too_big
    lsl     x1, x1, #52
    orr     x9, x9, x1            /* set new exponent */
    fmov    d7, x9
    str     d7, [x0]
    adrp    x9, L.true
    ldr     x3, [x9, #:lo12:L.true]
    str     x3, [USP]
    ret
L.exp_too_big:
    adrp    x9, L.false
    ldr     x3, [x9, #:lo12:L.false]
    str     x3, [USP]
    ret

;;; _pfmodf: split double into integer and fractional parts
;;; On AArch64 we manipulate the 64-bit IEEE representation directly.
;;; The double is 1 sign bit + 11 exponent bits + 52 mantissa bits.
DEF_C_LAB (_pfmodf)
    ldr     x1, [USP, #8]         /* pointer for fractional result */
    ldr     x0, [USP], #16        /* pointer to argument (integer result), pop 2 */
    ldr     d7, [x0]
    fmov    x9, d7                 /* get 64-bit representation */
    /* Extract unbiased exponent */
    ubfx    x2, x9, #52, #11      /* extract 11-bit exponent field */
    sub     x2, x2, #1023         /* unbias */
    subs    x2, x2, #0            /* test sign (negative exponent) */
    b.mi    L.negexp
    cmp     x2, #52
    b.gt    L.bigexp
    /* Normal case: zero out fractional mantissa bits */
    /* We need to mask out the lower (52 - exponent) bits */
    mov     x3, #52
    sub     x3, x3, x2            /* number of bits to clear */
    mov     x10, #-1              /* all ones */
    lsl     x10, x10, x3          /* mask: upper bits set, lower cleared */
    and     x11, x9, x10          /* integer part bits */
    fmov    d6, x11               /* integer part as double */
    str     d6, [x0]              /* store integer part */
    fsub    d7, d7, d6            /* fractional = original - integer */
    str     d7, [x1]              /* store fractional part */
    ret

L.bigexp:
    /* Exponent >= 53: number is already an integer, fraction = 0.0 */
    str     xzr, [x1]             /* store 0.0 (all zero bits = +0.0) */
    ret
L.negexp:
    /* Exponent < 0: number is purely fractional, integer part = 0 */
    ldr     d7, [x0]              /* load original */
    str     d7, [x1]              /* store as fractional part */
    /* Set integer part to +/-0.0 preserving sign */
    and     x9, x9, #0x8000000000000000  /* keep sign bit only */
    str     x9, [x0]              /* store signed zero */
    ret

DEF_C_LAB (_pfzero)
    ldr   x3, [USP]
    ldr   d7, [x3]
    fcmp  d7, #0.0
    adrp  x9, L.false
    ldr   x0, [x9, #:lo12:L.false]
    adrp  x9, L.true
    ldr   x1, [x9, #:lo12:L.true]
    csel  x0, x1, x0, eq
    str   x0, [USP]
    ret

DEF_C_LAB (_pfneg)
    ldr   x3, [USP]
    ldr   d7, [x3]
    fcmp  d7, #0.0
    adrp  x9, L.false
    ldr   x0, [x9, #:lo12:L.false]
    adrp  x9, L.true
    ldr   x1, [x9, #:lo12:L.true]
    csel  x0, x1, x0, mi
    str   x0, [USP]
    ret

DEF_C_LAB (_pfeq)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #8
    ldr   d7, [x3]
    ldr   d6, [x2]
    fcmp  d6, d7
    adrp  x9, L.false
    ldr   x0, [x9, #:lo12:L.false]
    adrp  x9, L.true
    ldr   x1, [x9, #:lo12:L.true]
    csel  x0, x1, x0, eq
    str   x0, [USP]
    ret

DEF_C_LAB (_pfsgreq)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #8
    ldr   d7, [x3]
    ldr   d6, [x2]
    ;;; d6 <= d7 ?
    fcmp  d6, d7
    adrp  x9, L.false
    ldr   x0, [x9, #:lo12:L.false]
    adrp  x9, L.true
    ldr   x1, [x9, #:lo12:L.true]
    csel  x0, x1, x0, ls          /* ls = unsigned lower or same (C clear or Z set) */
    str   x0, [USP]
    ret

DEF_C_LAB (_pfsgr)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #8
    ldr   d7, [x3]
    ldr   d6, [x2]
    ;;; d6 < d7 ?
    fcmp  d6, d7
    adrp  x9, L.false
    ldr   x0, [x9, #:lo12:L.false]
    adrp  x9, L.true
    ldr   x1, [x9, #:lo12:L.true]
    csel  x0, x1, x0, mi          /* mi = negative (less than) */
    str   x0, [USP]
    ret

DEF_C_LAB (_pfabs)
    ldr   x3, [USP], #8
    ldr   d7, [x3]
    fabs  d7, d7
    str   d7, [x3]
    ret

DEF_C_LAB (_pfnegate)
    ldr   x3, [USP], #8
    ldr   d7, [x3]
    fneg  d7, d7
    str   d7, [x3]
    ret

;;; address of first argument is on top of stack, the second is also
;;; the result
DEF_C_LAB (_pfadd)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #8
    ldr   d7, [x3]
    ldr   d6, [x2]
    fadd  d7, d7, d6
    str   d7, [x3]
    ret

DEF_C_LAB (_pfsub)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #8
    ldr   d7, [x3]
    ldr   d6, [x2]
    fsub  d7, d7, d6
    str   d7, [x3]
    ret

DEF_C_LAB (_pfmult)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #8
    ldr   d7, [x3]
    ldr   d6, [x2]
    fmul  d7, d7, d6
    str   d7, [x3]
    ret

DEF_C_LAB (_pfdiv)
    ldr   x3, [USP, #8]
    ldr   x2, [USP], #8
    ldr   d6, [x2]
    ldr   d7, [x3]
    fdiv  d7, d7, d6
    str   d7, [x3]
    ret

L.true:
    .xword C_LAB(true)
L.false:
    .xword C_LAB(false)

DEF_C_LAB (_pfqrem)
    b XC_LAB(Sys$-Float_qrem)

    .align  3

;;; End wrapper: set size
    .text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
