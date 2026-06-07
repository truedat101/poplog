/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   File:        src/arm64/array_cons.p
   Purpose:     Construction of array procedures for AArch64
   Author:      Waldek Hebisch (ARM32 original)
   AArch64 port by truedat101
*/

#_INCLUDE 'declare.ph'

global constant
    _array_sub,
;

;;; ---------------------------------------------------------------------

section $-Sys;


    /*  Fill in machine specific part of array procedure.  _tabsize
        is size in bytes of the array params starting at PD_ARRAY_TABLE.

        Code layout (40 bytes total):
          8 instructions x 4 bytes = 32 bytes of code
          + 1 x 8-byte literal (_array_sub address)

        Register conventions (AArch64):
          USP = x19       (user stack pointer, callee-saved)
          PB  = x20       (procedure base, callee-saved)
          LR  = x30       (link register)
          SP  = sp        (system stack pointer, 16-byte aligned)
          Scratch: x0-x7, x16/x17

        Stack frame on entry (grows downward):
          [sp+0]  = PB   (SF_OWNER - owning procedure)
          [sp+8]  = LR   (SF_RETURN_ADDR - return address)

        Instructions planted:
          0: adr   x20, .-offset    ; compute PB from PC
          1: stp   x20, x30, [sp, #-16]!  ; push PB and LR
          2: ldr   x16, .+24        ; load _array_sub address (PC-relative literal)
          3: blr   x16              ; call _array_sub
        EXIT:
          4: add   sp, sp, #8       ; skip SF_OWNER
          5: ldr   x30, [sp], #8    ; restore LR, pop
          6: ldr   x20, [sp]        ; restore caller's PB (caller's SF_OWNER)
          7: ret                    ; return via x30
        LITERAL:
          .xword _array_sub         ; 8-byte address of array subscript routine
    */
define Array$-Cons(_tabsize) -> _arrayp;
    lvars _tabsize, _arrayp, _drop_ptr, _size, _immhi;

    ;;; Get procedure record -- 40 bytes of code+literal
    ;;; (8 instructions * 4 bytes + 8-byte literal = 40 bytes)
    @@PD_ARRAY_TABLE{_tabsize _add _40} _sub @@POPBASE -> _size;
    Get_store(_size) -> _arrayp;

    ;;; initialise some of procedure header
    ##(w){_size} -> _arrayp!PD_LENGTH;
    _0  ->> _arrayp!PD_REGMASK
        ->> _arrayp!PD_NUM_STK_VARS
        ->> _arrayp!PD_NUM_PSTK_VARS
        ->> _arrayp!PD_NLOCALS
        ->  _arrayp!PD_GC_SCAN_LEN;
    ##SF_LOCALS -> _arrayp!PD_GC_OFFSET_LEN;
    ##SF_LOCALS _sub ##SF_RETURN_ADDR -> _arrayp!PD_FRAME_LEN;

    ;;; Start of code
    @@PD_ARRAY_TABLE{_tabsize} -> _drop_ptr;
    _arrayp@(w){_drop_ptr} -> _arrayp!PD_EXECUTE;

    ;;; ---------------------------------------------------------------
    ;;; Instruction 0: adr x20, .-offset
    ;;; Compute PB (procedure base) from the current PC.
    ;;; PB = execute_addr - _drop_ptr (byte offset from PB to execute).
    ;;; AArch64 ADR encoding:
    ;;;   op=0, immlo[30:29], 10000[28:24], immhi[23:5], Rd[4:0]
    ;;;   offset = immhi:immlo (21-bit signed byte offset from PC)
    ;;; Here offset = -_drop_ptr. Since _drop_ptr is 8-byte aligned,
    ;;; immlo (offset bits 1:0) = 0. We only need immhi (offset bits 20:2).
    ;;; Base encoding for "adr x20": 0x10000014
    _shift(_negate(_drop_ptr), _-2) _bimask _16:7FFFF -> _immhi;
    _16:10000014 _biset _shift(_immhi, _5)
        -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 1: stp x20, x30, [sp, #-16]!
    ;;; Save PB (SF_OWNER) and LR (SF_RETURN_ADDR) on the call stack.
    ;;; Pre-index store pair, 64-bit.
    ;;; Encoding: 0xA9BF7BF4
    _16:A9BF7BF4 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 2: ldr x16, .+24
    ;;; Load address of _array_sub from the literal pool.
    ;;; PC-relative literal load, 64-bit. Literal is 24 bytes ahead
    ;;; (at byte offset 32 from execute, this instruction is at offset 8).
    ;;; LDR (literal) encoding: opc=01, 011000, imm19=6, Rt=x16
    ;;; Encoding: 0x580000D0
    _16:580000D0 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 3: blr x16
    ;;; Call the array subscript routine.
    ;;; Encoding: 0xD63F0200
    _16:D63F0200 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; ---------------------------------------------------------------
    ;;; EXIT point
    _arrayp@(w){_drop_ptr} -> _arrayp!PD_EXIT;

    ;;; Frame teardown -- MUST keep sp 16-byte aligned at every sp-based access
    ;;; (AArch64 SP-alignment check).  The old sequence (`add sp,#8` ;
    ;;; `ldr x30,[sp],#8` ; `ldr x20,[sp]`) stepped sp through an 8-misaligned
    ;;; state and faulted in runtime-compiled array accessors (e.g. loading
    ;;; Lisp).  Use offset loads then one 16-byte `add` instead.  Frame is
    ;;; [sp+0]=SF_OWNER(self PB), [sp+8]=LR; caller's SF_OWNER is at [sp+16].

    ;;; Instruction 4: ldr x30, [sp, #8]      ; restore LR (offset load)
    ;;; Encoding: 0xF94007FE
    _16:F94007FE -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 5: ldr x20, [sp, #16]     ; restore caller's PB (caller SF_OWNER)
    ;;; Encoding: 0xF9400BF4
    _16:F9400BF4 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 6: add sp, sp, #16        ; drop the whole frame, 16-aligned
    ;;; Encoding: 0x910043FF
    _16:910043FF -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 7: ret
    ;;; Return via x30 (LR).
    ;;; Encoding: 0xD65F03C0
    _16:D65F03C0 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; ---------------------------------------------------------------
    ;;; Literal: 8-byte address of _array_sub routine
    ;;; Stored as a full 64-bit word at byte offset 32 from execute.
    _array_sub -> _arrayp!(w){_drop_ptr};
enddefine;

endsection;     /* $-Sys */
