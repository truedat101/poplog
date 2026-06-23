/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   Copyright Dave Kordgyk (AArch64 port).
   File:        src/riscv64/pdr_compose.p
   Purpose:     Composition of two procedures, RISC-V (rv64gc, LP64D)
   Author:      Waldek Hebisch (ARM32 original)
                Dave Kordgyk (AArch64 rewrite)
                truedat101 (RISC-V port)
*/

#_INCLUDE 'declare.ph'

section $-Sys;

;;; Fill in the machine-specific part of a composition of two procedures.
;;;
;;; Register conventions (this port): PB=x18, USP=x9, LR=ra, SP=sp; indirect
;;; call scratch t5 (x30).  Frame: [sp+0]=PB (owner), [sp+8]=LR; 16 bytes.
;;;
;;; RISC-V code (15 instructions = 60 bytes; arm64 was 12 / 48): the single adr
;;; becomes auipc+addi, and each stp/ldp push/pop becomes addi + sd/ld pairs.
;;;
;;;   Entry:  auipc x18,hi ; addi x18,x18,lo   ; x18 = execute - TABLE = base
;;;           addi sp,sp,-16 ; sd x18,0(sp) ; sd ra,8(sp)
;;;   Call P1: ld a0,P1(x18) ; ld t5,PD_EXECUTE(a0) ; jalr t5
;;;   Call P2: ld a0,P2(x18) ; ld t5,PD_EXECUTE(a0) ; jalr t5
;;;   Exit:   ld ra,8(sp) ; ld x18,16(sp) ; addi sp,sp,16 ; ret
;;;
;;; RISC-V encodings (verified vs riscv64-as/objdump):
;;;   auipc x18 = 0x917 base; addi x18,x18 = 0x90913 base
;;;   addi sp,sp,-16 = 0xFF010113 ; sd x18,0(sp) = 0x01213023 ; sd ra,8(sp) = 0x00113423
;;;   ld a0,off(x18) = 0x00093503 base ; ld t5,off(a0) = 0x00053F03 base ; jalr t5 = 0x000F00E7
;;;   ld ra,8(sp) = 0x00813083 ; ld x18,16(sp) = 0x01013903 ; addi sp,sp,16 = 0x01010113 ; ret = 0x00008067

define Cons_pcomposite() -> _comp;
    lvars _drop_ptr, _comp, _size, _offs, _lo12, _hi20;

    ;;; Code is 15 instructions = 60 bytes -> 8 (64-bit) words.
    @@PD_COMPOSITE_TABLE[_8] _sub @@POPBASE -> _size;

    Get_store(_size) -> _comp;

    ;;; Initialise the header
    ##(w){_size} ->> _size -> _comp!PD_LENGTH;
    _0 ->> _comp!PD_REGMASK -> _comp!PD_NLOCALS;
    _0 ->> _comp!PD_NUM_STK_VARS -> _comp!PD_NUM_PSTK_VARS;
    ##SF_LOCALS -> _comp!PD_GC_OFFSET_LEN;
    _0 -> _comp!PD_GC_SCAN_LEN;
    ##SF_LOCALS _sub ##SF_RETURN_ADDR -> _comp!PD_FRAME_LEN;

    ;;; Plant the code at the PD_COMPOSITE_TABLE tail
    @@PD_COMPOSITE_TABLE -> _drop_ptr;
    _comp@(w){_drop_ptr} -> _comp!PD_EXECUTE;

    ;;; Instr 1+2: auipc x18,hi ; addi x18,x18,lo  -> x18 = execute - TABLE = base
    ;;; delta = -PD_COMPOSITE_TABLE; split into auipc 20-bit + addi 12-bit imms.
    _negate(@@PD_COMPOSITE_TABLE) -> _offs;
    _offs _bimask _16:FFF -> _lo12;
    _shift(_offs _add _16:800, _-12) _bimask _16:FFFFF -> _hi20;
    _shift(_hi20, _12) _biset _16:917 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    _shift(_lo12, _20) _biset _16:90913 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Instr 3: addi sp,sp,-16
    _16:FF010113 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    ;;; Instr 4: sd x18,0(sp)   (SF_OWNER = PB)
    _16:01213023 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    ;;; Instr 5: sd ra,8(sp)    (SF_RETURN_ADDR = LR)
    _16:00113423 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Call PD_COMPOSITE_P1: ld a0,P1(x18) ; ld t5,PD_EXECUTE(a0) ; jalr t5
    _shift(@@PD_COMPOSITE_P1, _20) _biset _16:00093503 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    _shift(@@PD_EXECUTE, _20) _biset _16:00053F03 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    _16:000F00E7 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; Call PD_COMPOSITE_P2
    _shift(@@PD_COMPOSITE_P2, _20) _biset _16:00093503 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    _shift(@@PD_EXECUTE, _20) _biset _16:00053F03 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    _16:000F00E7 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;

    ;;; PD_EXIT: start of the exit sequence
    _comp@(w){_drop_ptr} -> _comp!PD_EXIT;

    ;;; Instr 12: ld ra,8(sp)
    _16:00813083 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    ;;; Instr 13: ld x18,16(sp)   (restore caller's PB)
    _16:01013903 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    ;;; Instr 14: addi sp,sp,16
    _16:01010113 -> _comp!(i){_drop_ptr};
    _drop_ptr _add _4 -> _drop_ptr;
    ;;; Instr 15: ret
    _16:00008067 -> _comp!(i){_drop_ptr};
enddefine;

endsection;     /* $-Sys */
