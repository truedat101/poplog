/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Purpose: Bitfield/compare/copy/move assembly routines for AArch64
   Author:  Waldek Hebisch
   AArch64 port by truedat101
*/

#_<

#_INCLUDE 'declare.ph'

lconstant macro (
    USP = "x19",
    PB  = "x20",
);

>_#

    .arch armv8-a
    .file   "amove.s"
;;; Wrapping in POP object
   .text
   .xword  Ltext_size, C_LAB(Sys$-objmod_pad_key)
Ltext_start:

;;; _bcmp, _scmp, _cmp, _icmp
;;; Compare two memory regions.  Three Pop arguments on USP:
;;;   ( byte_count, src2, src1 )
;;; Pushes true/false back on USP.

DEF_C_LAB (_bcmp)
DEF_C_LAB (_scmp)
DEF_C_LAB (_cmp)
DEF_C_LAB (_icmp)
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ;;; USP order is ( byte_count, src2, src1 ) with src1 on TOP, so the pops
    ;;; below already land args in memcmp(s1, s2, n) order. (The earlier code
    ;;; mislabelled the stack as byte_count-on-top and added a spurious x0<->x2
    ;;; swap -> memcmp(byte_count, src2, src1), dereferencing the count.  cf.
    ;;; _move / _bfill, fixed the same way.)
    ldr x0, [USP], #8          ;;; x0 = src1   (top of stack) = memcmp s1
    ldr x1, [USP], #8          ;;; x1 = src2                    = memcmp s2
    ldr x2, [USP]              ;;; x2 = byte_count (peek; result slot) = memcmp n
    bl memcmp
    cmp x0, #0
    b.eq .Lcmp_true
    adrp x0, C_LAB(false)
    add  x0, x0, :lo12:C_LAB(false)
    ldr  x0, [x0]
    b .Lcmp_done
.Lcmp_true:
    adrp x0, C_LAB(true)
    add  x0, x0, :lo12:C_LAB(true)
    ldr  x0, [x0]
.Lcmp_done:
    str x0, [USP]
    ldp x29, x30, [sp], #16
    ret

;;; _moveq, _bmove, _smove, _imove, _dmove, _move
;;; Move (copy) memory using memmove.  Three Pop arguments on USP:
;;;   ( byte_count, src, dst )
;;; Updates dst on USP to dst + byte_count.

DEF_C_LAB (_moveq)
    ;;; version below still works
DEF_C_LAB (_bmove)
DEF_C_LAB (_smove)
DEF_C_LAB (_imove)
DEF_C_LAB (_dmove)
DEF_C_LAB (_move)
    ;;; USP order is ( byte_count, src, dst ) with dst on TOP, so the pops
    ;;; below already land args in memmove(dst, src, n) order. (The earlier
    ;;; code mislabelled the stack as byte_count-on-top and added a spurious
    ;;; x0<->x2 swap, which called memmove(byte_count, src, dst) -> NULL-dest
    ;;; segfault.  cf. _fill below, which has the correct convention.)
    ldr x0, [USP], #8          ;;; x0 = dst   (top of stack)
    ldr x1, [USP], #8          ;;; x1 = src
    ldr x2, [USP]              ;;; x2 = byte_count (peek; becomes result slot)
    add x3, x0, x2             ;;; dst + byte_count
    str x3, [USP]              ;;; update result on stack to dst + byte_count
    ;;; x0=dst, x1=src, x2=byte_count already = memmove(dst, src, n)
    b memmove

;;; _bfill
;;; Byte fill using memset.  Three Pop arguments on USP:
;;;   ( fill_value, byte_count, dst )

DEF_C_LAB (_bfill)
    ;;; USP order is ( fill_value, byte_count, dst ) with dst on TOP. The pops
    ;;; below already land args in memset(dst, value, n) order, so no swap is
    ;;; needed. (The earlier code mislabelled the stack and added a spurious
    ;;; x0<->x1 swap -> memset(fill_value, dst, n), corrupting memory.)
    ldr x0, [USP], #8          ;;; x0 = dst   (top of stack)
    ldr x2, [USP], #8          ;;; x2 = byte_count
    ldr x1, [USP], #8          ;;; x1 = fill_value
    ;;; x0=dst, x1=value, x2=n already = memset(dst, value, n)
    b memset

;;; _ifill, _fill
;;; Word fill.  Three Pop arguments on USP:
;;;   ( fill_value, word_count_in_bytes, dst )
;;; Stores a Poplog word (8 bytes) at each position.

DEF_C_LAB (_ifill)
DEF_C_LAB (_fill)
    ;;; dst
    ldr x0, [USP], #8
    ;;; length (in bytes)
    ldr x2, [USP], #8
    ;;; value
    ldr x1, [USP], #8
    cmp x2, #0
    b.le .Lfill_done
.Lfill_loop:
    str x1, [x0], #8
    subs x2, x2, #8
    b.gt .Lfill_loop
.Lfill_done:
    ret

;;; _move_userstack
;;; Move user stack by a given number of bytes.

DEF_C_LAB (_move_userstack)
    ldr x0, [USP], #8          ;;; byte offset
    adrp x3, I_LAB(_userhi)
    add  x3, x3, :lo12:I_LAB(_userhi)
    ldr  x2, [x3]              ;;; old _userhi
    add  x1, x2, x0            ;;; new _userhi
    str  x1, [x3]              ;;; store new _userhi
    add  x0, USP, x0           ;;; new USP = old USP + offset
    sub  x2, x2, USP           ;;; byte count = old _userhi - old USP
    mov  x1, USP               ;;; src = old USP
    mov  USP, x0               ;;; update USP to new value
    ;;; memmove(dst=x0, src=x1, n=x2) -- x0 already has new USP as dst
    ;;; but dst should be old USP position in new location...
    ;;; Actually: dst = new USP (x0 already set), src = old USP (x1), n = x2
    mov  x0, USP               ;;; dst = new USP base
    ;;; x1 = old USP (src), x2 = byte count (n)
    b memmove

;;; _move_callstack
;;; Move the call stack up or down.
;;; Two Pop arguments on USP:
;;;   ( delta, current_top )
;;; where delta > 0 means stack moves up, delta < 0 means down.

DEF_C_LAB (_move_callstack)
    ldr x0, [USP], #8          ;;; current_top
    ldr x1, [USP], #8          ;;; delta
    ;;; sp can't be Xm; copy to scratch first
    mov x2, sp
    sub x2, x0, x2             ;;; byte count = current_top - sp
    ;;; Note: due to signed overflow direction may be opposite
    ;;; to indicated by labels.  But since address 0 is illegal
    ;;; in case of overflow source area does not intersect
    ;;; destination area, so direction does not matter.
    cmp x1, #0
    b.gt .Lmove_up
    b.lt .Lmove_down
    ret
    ;;; Stack moves up, so copy goes down
.Lmove_up:
    ;;; New limit in x9
    add x9, x0, x1
.Lup_loop:
    ldr x3, [x0, #-8]!
    str x3, [x9, #-8]!
    subs x2, x2, #8
    b.gt .Lup_loop
    ;;; finally adjust sp
    add sp, sp, x1
    ret
    ;;; Stack moves down, so copy goes up
.Lmove_down:
    ;;; copy sp so we keep sp valid
    mov x9, sp
    ;;; adjust
    add sp, sp, x1
    ;;; again copy sp
    mov x0, sp
.Ldown_loop:
    ldr x3, [x9], #8
    str x3, [x0], #8
    subs x2, x2, #8
    b.gt .Ldown_loop
    ret

;;; _bfield
;;; Extract unsigned bitfield.
;;; Arguments: x0 = field width (bits), x1 = bit offset, x2 = base address
;;; Returns result in x0.
;;; On 64-bit: word = 8 bytes = 64 bits.
;;; bit_in_word = offset & 63, word_index = offset >> 6 (asr #6)
;;; Load from [base + word_index * 8], shift right by bit_in_word.
;;; If field spans two words, load next word and combine.

DEF_C_LAB(_bfield)
    and     x9, x1, #63            ;;; bit_in_word = offset & 63
    asr     x1, x1, #6             ;;; word_index = offset / 64
    add     x3, x9, x0             ;;; bit_in_word + width
    ldr     x3, [x2, x1, lsl #3]   ;;; load word at base[word_index]
    add     x1, x1, #1             ;;; next word index
    cmp     x9, #0                  ;;; check if we need to shift
    lsr     x3, x3, x9             ;;; shift right by bit_in_word
    ;;; Check if field spans two 64-bit words
    add     x10, x9, x0            ;;; total bits needed
    cmp     x10, #64
    b.ls    .Lbfield_one_word
    ;;; Need second word
    ldr     x1, [x2, x1, lsl #3]   ;;; load next word
    sub     x10, x10, #64           ;;; overflow bits
    neg     x11, x9
    add     x11, x11, #64           ;;; 64 - bit_in_word
    lsl     x1, x1, x11            ;;; shift second word left
    orr     x3, x3, x1             ;;; combine
.Lbfield_one_word:
    ;;; Mask to field width: shift left by (64 - width), then lsr back
    neg     x2, x0
    add     x2, x2, #64            ;;; 64 - width
    lsl     x0, x3, x2
    lsr     x0, x0, x2
    ret

;;; _sbfield
;;; Extract signed bitfield.
;;; Same as _bfield but sign-extends the result.

DEF_C_LAB(_sbfield)
    and     x9, x1, #63            ;;; bit_in_word = offset & 63
    asr     x1, x1, #6             ;;; word_index = offset / 64
    add     x3, x9, x0             ;;; bit_in_word + width
    ldr     x3, [x2, x1, lsl #3]   ;;; load word at base[word_index]
    add     x1, x1, #1             ;;; next word index
    lsr     x3, x3, x9             ;;; shift right by bit_in_word
    ;;; Check if field spans two 64-bit words
    add     x10, x9, x0            ;;; total bits needed
    cmp     x10, #64
    b.ls    .Lsbfield_one_word
    ;;; Need second word
    ldr     x1, [x2, x1, lsl #3]   ;;; load next word
    neg     x11, x9
    add     x11, x11, #64           ;;; 64 - bit_in_word
    lsl     x1, x1, x11            ;;; shift second word left
    orr     x3, x3, x1             ;;; combine
.Lsbfield_one_word:
    ;;; Sign-extend: shift left by (64 - width), then asr back
    neg     x2, x0
    add     x2, x2, #64            ;;; 64 - width
    lsl     x0, x3, x2
    asr     x0, x0, x2             ;;; arithmetic shift right for sign extension
    ret

;;; _ubfield
;;; Update (write) bitfield.
;;; Arguments: x0 = field width (bits), x1 = bit offset, x2 = base address
;;; Value to store is on USP.
;;; On 64-bit: word = 8 bytes = 64 bits.

DEF_C_LAB (_ubfield)
    ;;; Create mask of 'width' ones: mask = (1 << width) - 1
    ;;; For width < 64, use mov -1 and lsr
    mov     x5, #-1                ;;; all ones
    neg     x6, x0
    add     x6, x6, #64            ;;; 64 - width
    lsr     x5, x5, x6             ;;; mask = 0xFFF...F >> (64 - width)
    ;;; Compute word index and bit position
    asr     x3, x1, #6             ;;; word_index = offset / 64
    add     x2, x2, x3, lsl #3     ;;; base += word_index * 8
    ldr     x9, [x2]               ;;; load current word
    ldr     x3, [USP], #8          ;;; value to store from USP
    and     x1, x1, #63            ;;; bit_in_word = offset & 63
    ;;; Clear field bits in current word
    lsl     x10, x5, x1            ;;; shift mask to position
    bic     x9, x9, x10            ;;; clear field bits
    ;;; Mask and position the new value
    and     x3, x3, x5             ;;; mask value to field width
    add     x0, x1, x0             ;;; bit_in_word + width
    ;;; orr does not accept shift-by-register; do the shift separately
    lsl     x12, x3, x1
    orr     x9, x9, x12            ;;; insert value bits
    str     x9, [x2]               ;;; store back
    ;;; Check if field spans two 64-bit words
    cmp     x0, #64
    b.ls    .Lubfield_done
    ;;; Handle second word
    ldr     x0, [x2, #8]           ;;; load next word
    neg     x10, x1
    add     x10, x10, #64          ;;; 64 - bit_in_word
    lsr     x11, x5, x10           ;;; mask shifted for second word
    bic     x0, x0, x11            ;;; clear field bits in second word
    lsr     x3, x3, x10            ;;; shift value for second word
    orr     x0, x0, x3             ;;; insert value bits
    str     x0, [x2, #8]           ;;; store second word
.Lubfield_done:
    ret

;;; End wrapper: set size
    .text
Ltext_end:
    .set Ltext_size, Ltext_end-Ltext_start
