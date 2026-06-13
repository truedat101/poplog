/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   File:        src/riscv64/array_cons.p
   Purpose:     Construction of array procedures for RISC-V (rv64gc, LP64D)
   Author:      Waldek Hebisch (ARM32 original)
                AArch64 port by truedat101
                RISC-V port by truedat101
*/

#_INCLUDE 'declare.ph'

global constant
    _array_sub,
;

;;; ---------------------------------------------------------------------

section $-Sys;


    /*  Fill in the machine-specific part of an array procedure.  _tabsize is
        the size in bytes of the array params starting at PD_ARRAY_TABLE.

        RISC-V code layout (56 bytes total):
          12 instructions x 4 bytes = 48 bytes of code + 1 x 8-byte literal.

        Register conventions (this port): USP=x9, PB=x18, LR=ra, SP=sp; the
        indirect-call scratch is t5 (x30).  Stack frame (grows downward):
          [sp+0] = PB (SF_OWNER),  [sp+8] = LR (SF_RETURN_ADDR).

        Instructions planted (byte offset from execute):
           0  auipc x18, hi20(-drop_ptr)   ; PB = execute - drop_ptr = record base
           4  addi  x18, x18, lo12(-drop_ptr)
           8  addi  sp, sp, -16            ; push frame
          12  sd    x18, 0(sp)             ; SF_OWNER
          16  sd    ra, 8(sp)              ; SF_RETURN_ADDR
          20  auipc t5, 0                  ; t5 = &(this auipc)
          24  ld    t5, 28(t5)             ; t5 = _array_sub (literal at +48)
          28  jalr  ra, t5, 0              ; call _array_sub
        EXIT (offset 32):
          32  ld    ra, 8(sp)             ; restore LR
          36  ld    x18, 16(sp)           ; restore caller's PB (caller SF_OWNER)
          40  addi  sp, sp, 16            ; drop the whole frame (16-aligned)
          44  ret                         ; jalr x0, ra, 0
        LITERAL (offset 48):
          .quad _array_sub
        (arm64 used a single `adr` for PB; RISC-V needs auipc+addi, so this is
        12 instructions / 56 bytes, not arm64's 8 / 40.)
    */
define Array$-Cons(_tabsize) -> _arrayp;
    lvars _tabsize, _arrayp, _drop_ptr, _size, _off, _hi20, _lo12;

    ;;; Get procedure record -- 56 bytes of code+literal
    @@PD_ARRAY_TABLE{_tabsize _add _56} _sub @@POPBASE -> _size;
    Get_store(_size) -> _arrayp;

    ;;; initialise some of the procedure header
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
    ;;; Instruction 0+1: auipc x18, hi ; addi x18, x18, lo  -> PB = record base.
    ;;; delta = -drop_ptr (PB = execute - drop_ptr).  Split into the auipc 20-bit
    ;;; and addi 12-bit immediates (the +0x800 rounds for the addi sign-extend):
    ;;;   lo12  = delta & 0xFFF                 (addi imm[31:20])
    ;;;   hi20  = ((delta + 0x800) >> 12) & 0xFFFFF   (auipc imm[31:12])
    ;;; Base encodings: auipc x18 = 0x917, addi x18,x18 = 0x90913.
    _negate(_drop_ptr) -> _off;
    _off _bimask _16:FFF -> _lo12;
    _shift(_off _add _16:800, _-12) _bimask _16:FFFFF -> _hi20;
    _shift(_hi20, _12) _biset _16:917 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    _shift(_lo12, _20) _biset _16:90913 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 2: addi sp, sp, -16
    _16:FF010113 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 3: sd x18, 0(sp)        ; SF_OWNER = PB
    _16:01213023 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 4: sd ra, 8(sp)         ; SF_RETURN_ADDR = LR
    _16:00113423 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 5: auipc t5, 0          ; t5 = &(this instruction)
    _16:00000F17 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 6: ld t5, 28(t5)        ; t5 = _array_sub (literal at +48)
    _16:01CF3F03 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 7: jalr ra, t5, 0       ; call _array_sub
    _16:000F00E7 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; ---------------------------------------------------------------
    ;;; EXIT point
    _arrayp@(w){_drop_ptr} -> _arrayp!PD_EXIT;

    ;;; Instruction 8: ld ra, 8(sp)         ; restore LR
    _16:00813083 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 9: ld x18, 16(sp)       ; restore caller's PB (caller SF_OWNER)
    _16:01013903 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 10: addi sp, sp, 16     ; drop the whole frame (16-aligned)
    _16:01010113 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instruction 11: ret                 ; jalr x0, ra, 0
    _16:00008067 -> _arrayp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; ---------------------------------------------------------------
    ;;; Literal: 8-byte address of _array_sub at byte offset 48 from execute.
    _array_sub -> _arrayp!(w){_drop_ptr};
enddefine;

endsection;     /* $-Sys */
