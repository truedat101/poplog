/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Bitfield/compare/copy/move assembly routines for RISC-V (rv64gc)
   Author:  Waldek Hebisch
   AArch64 port by truedat101
   RISC-V (rv64gc/LP64D/Linux ELF) port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'

lconstant macro (
    USP = "x9",        ;;; s1 (matches genproc R10)
    PB  = "x18",       ;;; s2 (matches genproc R11)
);

>_#

    .option arch, rv64gc
    .macro adr_l reg, sym
    lla \\reg, \\sym
    .endm
    .file   "amove.s"
;;; Wrapping in POP object
	.text
   .quad  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

;;; NB register remapping note: arm64's general scratch x0-x12 overlaps RISC-V's
;;; reserved registers (x2=sp, x3=gp, x4=tp) and this port's USP=x9.  C-ABI
;;; arguments are a0-a2 (x10-x12); arm64 scratch x3/x5/x6/x9/x10/x11/x12 map to
;;; the RISC-V temporaries a3/t1/t2/t3/t4/t5/t6.

;;; _bcmp, _scmp, _cmp, _icmp
;;; Compare two memory regions.  USP: ( byte_count, src2, src1 ) src1 on top.

DEF_C_LAB (_bcmp)
DEF_C_LAB (_scmp)
DEF_C_LAB (_cmp)
DEF_C_LAB (_icmp)
    addi sp, sp, -16
    sd   ra, 8(sp)
    ld   a0, 0(USP)            ;;; a0 = src1 (top)        = memcmp s1
    addi USP, USP, 8
    ld   a1, 0(USP)            ;;; a1 = src2              = memcmp s2
    addi USP, USP, 8
    ld   a2, 0(USP)            ;;; a2 = byte_count (peek) = memcmp n
    call EXTERN_NAME(memcmp)
    beqz a0, .Lcmp_true
    ;;; Pop `false`/`true` are the ADDRESSES of C_LAB(false)/C_LAB(true) (never
    ;;; deref -- the cell holds the C int).
    adr_l a0, C_LAB(false)
    j    .Lcmp_done
.Lcmp_true:
    adr_l a0, C_LAB(true)
.Lcmp_done:
    sd   a0, 0(USP)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

;;; _moveq, _bmove, _smove, _imove, _dmove, _move
;;; Move memory (memmove).  USP: ( byte_count, src, dst ) dst on top.
;;; Updates dst on USP to dst + byte_count.

DEF_C_LAB (_moveq)
DEF_C_LAB (_bmove)
DEF_C_LAB (_smove)
DEF_C_LAB (_imove)
DEF_C_LAB (_dmove)
DEF_C_LAB (_move)
    ld   a0, 0(USP)            ;;; a0 = dst (top)
    addi USP, USP, 8
    ld   a1, 0(USP)            ;;; a1 = src
    addi USP, USP, 8
    ld   a2, 0(USP)            ;;; a2 = byte_count (peek; result slot)
    add  a3, a0, a2            ;;; dst + byte_count
    sd   a3, 0(USP)            ;;; update result on stack
    tail EXTERN_NAME(memmove)  ;;; memmove(dst, src, n)

;;; _bfill -- byte fill (memset).  USP: ( fill_value, byte_count, dst ) dst top.

DEF_C_LAB (_bfill)
    ld   a0, 0(USP)            ;;; a0 = dst (top)
    addi USP, USP, 8
    ld   a2, 0(USP)            ;;; a2 = byte_count
    addi USP, USP, 8
    ld   a1, 0(USP)            ;;; a1 = fill_value
    addi USP, USP, 8
    tail EXTERN_NAME(memset)   ;;; memset(dst, value, n)

;;; _ifill, _fill -- word fill (8-byte Pop words).
;;; USP: ( fill_value, byte_count, dst )

DEF_C_LAB (_ifill)
DEF_C_LAB (_fill)
    ld   a0, 0(USP)            ;;; dst
    addi USP, USP, 8
    ld   a2, 0(USP)            ;;; length (bytes)
    addi USP, USP, 8
    ld   a1, 0(USP)            ;;; value
    addi USP, USP, 8
    blez a2, .Lfill_done
.Lfill_loop:
    sd   a1, 0(a0)
    addi a0, a0, 8
    addi a2, a2, -8
    bgtz a2, .Lfill_loop
.Lfill_done:
    ret

;;; _move_userstack -- move user stack by a number of bytes.

DEF_C_LAB (_move_userstack)
    ld   a0, 0(USP)            ;;; byte offset
    addi USP, USP, 8
    adr_l t0, I_LAB(_userhi)
    ld   a2, 0(t0)            ;;; old _userhi
    add  a1, a2, a0          ;;; new _userhi
    sd   a1, 0(t0)           ;;; store new _userhi
    add  a0, USP, a0         ;;; new USP = old USP + offset
    sub  a2, a2, USP         ;;; byte count = old _userhi - old USP
    mv   a1, USP             ;;; src = old USP
    mv   USP, a0             ;;; update USP
    mv   a0, USP             ;;; dst = new USP base
    tail EXTERN_NAME(memmove) ;;; memmove(dst, src, n)

;;; _move_callstack -- move the call stack up or down.
;;; USP: ( delta, current_top ); delta > 0 up, < 0 down.

DEF_C_LAB (_move_callstack)
    ld   a0, 0(USP)            ;;; current_top
    addi USP, USP, 8
    ld   a1, 0(USP)            ;;; delta
    addi USP, USP, 8
    mv   a2, sp               ;;; sp can't be a load/store base index; copy out
    sub  a2, a0, a2          ;;; byte count = current_top - sp
    bgtz a1, .Lmove_up
    bltz a1, .Lmove_down
    ret
    ;;; Stack moves up, so copy goes down
.Lmove_up:
    add  t3, a0, a1          ;;; new limit
.Lup_loop:
    addi a0, a0, -8
    ld   t0, 0(a0)
    addi t3, t3, -8
    sd   t0, 0(t3)
    addi a2, a2, -8
    bgtz a2, .Lup_loop
    add  sp, sp, a1          ;;; adjust sp
    ret
    ;;; Stack moves down, so copy goes up
.Lmove_down:
    mv   t3, sp
    add  sp, sp, a1
    mv   a0, sp
.Ldown_loop:
    ld   t0, 0(t3)
    addi t3, t3, 8
    sd   t0, 0(a0)
    addi a0, a0, 8
    addi a2, a2, -8
    bgtz a2, .Ldown_loop
    ret

;;; _bfield -- extract unsigned bitfield.
;;; a0 = width (bits), a1 = bit offset, a2 = base address; result in a0.
;;; word = 8 bytes = 64 bits.

DEF_C_LAB(_bfield)
    andi t3, a1, 63           ;;; bit_in_word = offset & 63
    srai a1, a1, 6            ;;; word_index = offset / 64
    slli t0, a1, 3
    add  t0, a2, t0
    ld   t0, 0(t0)           ;;; load word at base[word_index]
    addi a1, a1, 1           ;;; next word index
    srl  t0, t0, t3          ;;; shift right by bit_in_word
    add  t4, t3, a0          ;;; total bits needed
    li   t5, 64
    bgeu t5, t4, .Lbfield_one_word
    ;;; field spans two words: load next word
    slli t6, a1, 3
    add  t6, a2, t6
    ld   a1, 0(t6)
    neg  t5, t3
    addi t5, t5, 64          ;;; 64 - bit_in_word
    sll  a1, a1, t5          ;;; shift second word left
    or   t0, t0, a1          ;;; combine
.Lbfield_one_word:
    ;;; Mask to width: shift left by (64-width), then lsr back
    neg  a2, a0
    addi a2, a2, 64
    sll  a0, t0, a2
    srl  a0, a0, a2
    ret

;;; _sbfield -- extract signed bitfield (sign-extends).

DEF_C_LAB(_sbfield)
    andi t3, a1, 63
    srai a1, a1, 6
    slli t0, a1, 3
    add  t0, a2, t0
    ld   t0, 0(t0)
    addi a1, a1, 1
    srl  t0, t0, t3
    add  t4, t3, a0
    li   t5, 64
    bgeu t5, t4, .Lsbfield_one_word
    slli t6, a1, 3
    add  t6, a2, t6
    ld   a1, 0(t6)
    neg  t5, t3
    addi t5, t5, 64
    sll  a1, a1, t5
    or   t0, t0, a1
.Lsbfield_one_word:
    ;;; Sign-extend: shift left by (64-width), then asr back
    neg  a2, a0
    addi a2, a2, 64
    sll  a0, t0, a2
    sra  a0, a0, a2
    ret

;;; _ubfield -- update (write) bitfield.
;;; a0 = width (bits), a1 = bit offset, a2 = base; value to store on USP.

DEF_C_LAB (_ubfield)
    li   t1, -1               ;;; all ones
    neg  t2, a0
    addi t2, t2, 64          ;;; 64 - width
    srl  t1, t1, t2          ;;; mask = 0xF...F >> (64-width)
    srai t0, a1, 6           ;;; word_index = offset / 64
    slli t5, t0, 3
    add  a2, a2, t5          ;;; base += word_index * 8
    ld   t3, 0(a2)          ;;; current word
    ld   t0, 0(USP)         ;;; value to store
    addi USP, USP, 8
    andi a1, a1, 63         ;;; bit_in_word = offset & 63
    sll  t4, t1, a1         ;;; mask shifted to position
    not  t4, t4
    and  t3, t3, t4         ;;; clear field bits  (bic)
    and  t0, t0, t1         ;;; mask value to field width
    add  a0, a1, a0         ;;; bit_in_word + width
    sll  t6, t0, a1         ;;; position the new value
    or   t3, t3, t6         ;;; insert value bits
    sd   t3, 0(a2)         ;;; store back
    li   t5, 64
    bgeu t5, a0, .Lubfield_done
    ;;; field spans two words
    ld   a0, 8(a2)
    neg  t4, a1
    addi t4, t4, 64         ;;; 64 - bit_in_word
    srl  t5, t1, t4        ;;; mask shifted for second word
    not  t5, t5
    and  a0, a0, t5        ;;; clear field bits in second word
    srl  t0, t0, t4        ;;; shift value for second word
    or   a0, a0, t0        ;;; insert value bits
    sd   a0, 8(a2)        ;;; store second word
.Lubfield_done:
    ret

;;; End wrapper: set size
	.text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
