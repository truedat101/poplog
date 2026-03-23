/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Copyright Dave Kordgyk (AArch64 port).
   File:        src/arm64/pdr_compose.p
   Purpose:     Composition of two procedures, AArch64
   Author:      Waldek Hebisch (ARM32 original)
                 Dave Kordgyk (AArch64 rewrite)
*/

#_INCLUDE 'declare.ph'

section $-Sys;

;;; Fill in machine specific part of composition of two procedures.
;;;
;;; AArch64 Register conventions:
;;;   PB  = x20  (procedure base)
;;;   USP = x19  (user stack pointer)
;;;   LR  = x30  (link register)
;;;   SP  = sp   (call stack pointer, 16-byte aligned)
;;;   Scratch: x0-x7, x16, x17
;;;
;;; Stack frame layout (Poplog convention, grows downward):
;;;   [sp+0]  = PB  (owner / procedure base)
;;;   [sp+8]  = LR  (return address)
;;;   Total frame = 16 bytes (2 x 8-byte words, 16-byte aligned)
;;;
;;; Generated code: 12 AArch64 instructions (12 x 4 = 48 bytes = 6 words)
;;;
;;;   Entry (compute PB and save frame):
;;;    1. adr  x20, .                 ; get address of this instruction
;;;    2. sub  x20, x20, #TABLE_OFF   ; subtract offset to get record base
;;;    3. stp  x20, x30, [sp, #-16]!  ; push PB (owner) and LR
;;;
;;;   Call P1:
;;;    4. ldr  x0, [x20, #PD_COMPOSITE_P1] ; load procedure 1
;;;    5. ldr  x16, [x0, #PD_EXECUTE]      ; get its execute address
;;;    6. blr  x16                          ; call P1
;;;
;;;   Call P2:
;;;    7. ldr  x0, [x20, #PD_COMPOSITE_P2] ; load procedure 2
;;;    8. ldr  x16, [x0, #PD_EXECUTE]      ; get its execute address
;;;    9. blr  x16                          ; call P2
;;;
;;;   Exit (unwind frame and return):
;;;   10. ldp  x20, x30, [sp], #16   ; pop saved PB and LR (skip owner)
;;;   11. ldr  x20, [sp]             ; restore PB from previous frame's owner
;;;   12. ret                         ; return via x30
;;;
;;; AArch64 instruction encodings (32-bit each):
;;;   adr  x20, .               = 0x10000014
;;;   sub  x20, x20, #imm12    = 0xD1000294 | (imm12 << 10)
;;;   stp  x20, x30, [sp,#-16]!= 0xA9BF7BF4
;;;   ldr  x0, [x20, #off]     = 0xF9400280 | ((off/8) << 10)
;;;   ldr  x16, [x0, #off]     = 0xF9400010 | ((off/8) << 10)
;;;   blr  x16                 = 0xD63F0200
;;;   ldp  x20, x30, [sp],#16  = 0xA8C17BF4
;;;   ldr  x20, [sp]           = 0xF94003F4
;;;   ret                      = 0xD65F03C0

define Cons_pcomposite() -> _comp;
    lvars _drop_ptr, _comp, _size;

    ;;; Determine size of procedure record.
    ;;; Code is 12 instructions = 48 bytes = 6 (64-bit) words.
    @@PD_COMPOSITE_TABLE[_6] _sub @@POPBASE -> _size;

    ;;; Allocate new procedure record
    Get_store(_size) -> _comp;

    ;;; Initialise some of the header
    ##(w){_size} ->> _size -> _comp!PD_LENGTH;
    _0 ->> _comp!PD_REGMASK -> _comp!PD_NLOCALS;
    _0 ->> _comp!PD_NUM_STK_VARS -> _comp!PD_NUM_PSTK_VARS;
    ##SF_LOCALS -> _comp!PD_GC_OFFSET_LEN;
    _0 -> _comp!PD_GC_SCAN_LEN;
    ##SF_LOCALS _sub ##SF_RETURN_ADDR -> _comp!PD_FRAME_LEN;

    ;;; Plant the executable code.
    ;;; _drop_ptr tracks the byte offset from the record base into the code area.
    @@PD_COMPOSITE_TABLE -> _drop_ptr;
    _comp@(w){_drop_ptr} -> _comp!PD_EXECUTE;

    ;;; ---------------------------------------------------------------
    ;;; Instruction 1: adr x20, .
    ;;; Gets the PC (address of this instruction) into x20.
    ;;; Encoding: 0x10000014
    _16:10000014 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 2: sub x20, x20, #@@PD_COMPOSITE_TABLE
    ;;; Subtract the byte offset from execute address to record base,
    ;;; yielding PB (the procedure record base address).
    ;;; SUB (immediate) encoding: 0xD1000000 | (imm12 << 10) | (Rn << 5) | Rd
    ;;; For sub x20, x20, #imm: base = 0xD1000294, imm12 = @@PD_COMPOSITE_TABLE
    _16:D1000294 _biset _shift(@@PD_COMPOSITE_TABLE, _10)
        -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 3: stp x20, x30, [sp, #-16]!
    ;;; Push PB (owner) and LR onto the call stack (pre-index, 16-byte frame).
    ;;; Encoding: 0xA9BF7BF4
    _16:A9BF7BF4 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; ---------------------------------------------------------------
    ;;; Call PD_COMPOSITE_P1

    ;;; Instruction 4: ldr x0, [x20, #PD_COMPOSITE_P1]
    ;;; Load procedure 1 from the composite record.
    ;;; LDR (unsigned offset, 64-bit) encoding:
    ;;;   0xF9400000 | ((off/8) << 10) | (Rn << 5) | Rt
    ;;;   = 0xF9400280 | (@@PD_COMPOSITE_P1 >> 3) << 10
    ;;;   = 0xF9400280 | @@PD_COMPOSITE_P1 << 7
    _16:F9400280 _biset _shift(@@PD_COMPOSITE_P1, _7)
        -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 5: ldr x16, [x0, #PD_EXECUTE]
    ;;; Get the execute address of P1.
    _16:F9400010 _biset _shift(@@PD_EXECUTE, _7)
        -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 6: blr x16
    ;;; Call P1.
    _16:D63F0200 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; ---------------------------------------------------------------
    ;;; Call PD_COMPOSITE_P2

    ;;; Instruction 7: ldr x0, [x20, #PD_COMPOSITE_P2]
    ;;; Load procedure 2 from the composite record.
    _16:F9400280 _biset _shift(@@PD_COMPOSITE_P2, _7)
        -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 8: ldr x16, [x0, #PD_EXECUTE]
    ;;; Get the execute address of P2.
    _16:F9400010 _biset _shift(@@PD_EXECUTE, _7)
        -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 9: blr x16
    ;;; Call P2.
    _16:D63F0200 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; ---------------------------------------------------------------
    ;;; PD_EXIT: mark the start of the exit sequence.
    _comp@(w){_drop_ptr} -> _comp!PD_EXIT;

    ;;; Instruction 10: ldp x20, x30, [sp], #16
    ;;; Pop our saved PB and LR from the call stack (post-index).
    ;;; This restores LR for the return and temporarily loads our PB.
    ;;; Encoding: 0xA8C17BF4
    _16:A8C17BF4 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 11: ldr x20, [sp]
    ;;; Restore PB from the previous frame's owner on the stack.
    ;;; This overwrites the PB we just loaded with the correct caller's PB.
    ;;; LDR x20, [sp, #0] unsigned offset = 0xF94003F4
    _16:F94003F4 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 12: ret
    ;;; Return to caller via x30.
    ;;; Encoding: 0xD65F03C0
    _16:D65F03C0 -> _comp!(i){_drop_ptr};
enddefine;

endsection;     /* $-Sys */
