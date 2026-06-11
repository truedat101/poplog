/*
   Copyright Waldek Hebisch, you can distribute this file
   under terms of Free Poplog licence.
   File:        src/arm64/closure_cons.p
   Purpose:     Construction of closures for AArch64
   Author:      Waldek Hebisch (ARM32 original)
   AArch64 port by Poplog contributors
*/

#_INCLUDE 'declare.ph'

constant
        procedure (Sys$-Exec_closure)
    ;


section $-Sys;

;;; Macro for dropping code at _drop_ptr (a raw memory pointer).
;;; INSTR drops a 32-bit AArch64 instruction, advancing by 4 bytes.

lconstant macro (
    INSTR   = [_drop_ptr!(i)++ -> _drop_ptr],
);


;;; Encode an ADR instruction: adr Xd, .+imm
;;; imm is a signed byte offset from the ADR instruction itself.
;;; Returns the 32-bit encoding.
;;; ADR: op=0, immlo=imm[1:0], immhi=imm[20:2], Rd
;;; Encoding: 0x10000000 | (immlo << 29) | (immhi << 5) | Rd
define lconstant _adr_encode(_imm, _rd) -> _enc;
    lvars _imm, _rd, _enc, _immlo, _immhi;
    _imm _bimask _2:11 -> _immlo;              ;;; imm[1:0]
    _shift(_imm, _-2) _bimask _16:7FFFF -> _immhi;  ;;; imm[20:2], 19 bits
    _16:10000000
        _biset _shift(_immlo, _29)
        _biset _shift(_immhi, _5)
        _biset _rd
        -> _enc;
enddefine;


;;; Fill in machine specific part of a closure record.
;;; _nfroz is number of frozen arguments.

define Cons_closure(_nfroz) -> _clos;
    lvars _drop_ptr, _nfroz, _size, _clos, _code_bytes, _code_words,
          _offs, _fv_offs, _exec_offs;

    ;;; Compute code size in bytes
    ;;; (DARWIN: +1 instruction per closure -- the canonicalising AND after
    ;;; the adr; see below.)
    if _nfroz _gr _16 then
        ;;; Large closure: 1 data word (Exec_closure addr) + 4 instructions
        ;;; = 8 + 16 = 24 bytes
#_IF DEF DARWIN
        _28
#_ELSE
        _24
#_ENDIF
    else
        ;;; Small closure: adr + nfroz*(ldr+str) + ldr_pdpart + ldr_exec + br
        ;;; = nfroz*2 + 4 instructions, each 4 bytes
#_IF DEF DARWIN
        (_nfroz _mult _2 _add _5) _mult _4
#_ELSE
        (_nfroz _mult _2 _add _4) _mult _4
#_ENDIF
    endif -> _code_bytes;

    ;;; Convert code bytes to words, rounding up
    ##(w)[_code_bytes | b.r] -> _code_words;

    ;;; Add header size and frozval size to get total
    @@PD_CLOS_FROZVALS[_nfroz _add _code_words] _sub @@POPBASE -> _size;

    Get_store(_size) -> _clos;
    ##(w){_size} ->> _size -> _clos!PD_LENGTH;
    unless _clos!PD_LENGTH == _size then
        _clos -> Get_store();       ;;; junk it
        mishap(0, 'CLOSURE EXCEEDS MAXIMUM ALLOWABLE SIZE');
    endunless;

    ;;; Plant the code
    if _nfroz _gr _16 then
        ;;; Large closure: store Exec_closure address before code
        ;;; Plant it at frozvals[_nfroz] (first code word slot)
        Exec_closure!PD_EXECUTE
            -> _clos!PD_CLOS_FROZVALS[_nfroz];

        ;;; PD_EXECUTE points to the first instruction, after the data word
        _clos@PD_CLOS_FROZVALS[_nfroz _add _1] -> _drop_ptr;
#_IF DEF DARWIN
        ;;; Phase 4: bias PD_EXECUTE into the RX view (+2**36) so calls
        ;;; need no exec-fault redirect; code is PLANTED at the canonical
        ;;; _drop_ptr.
        _drop_ptr _add _16:1000000000 -> _clos!PD_EXECUTE;
#_ELSE
        _drop_ptr -> _clos!PD_EXECUTE;
#_ENDIF

        ;;; Compute byte distance from adr instruction back to closure base.
        ;;; _drop_ptr is where we are now (the adr instruction).
        ;;; Closure base is at _clos (adjusted by POPBASE).
        ;;; The adr needs imm = closure_base - adr_pc.
        _clos _sub _drop_ptr -> _offs;

        ;;; adr x0, .-N  (compute closure base address in x0)
        _adr_encode(_offs, _0) -> INSTR;

#_IF DEF DARWIN
        ;;; dual-mapped heap: the adr executed in the RX view yields
        ;;; closure_base + 2**36; canonicalise before x0 escapes as a Pop
        ;;; pointer.  and x0, x0, #0xffffffefffffffff  (verified vs clang)
        _16:925BF800 -> INSTR;
#_ENDIF

        ;;; str x0, [x19, #-8]!  (push closure address on USP, pre-index writeback)
        ;;; Encoding: 0xF81F8E60 (idx=11 => writeback; 0xF81F8260 would be STUR
        ;;; with NO writeback, leaving USP unchanged).
        _16:F81F8E60 -> INSTR;

        ;;; Now load Exec_closure address from the data word.
        ;;; It is at frozvals[_nfroz], byte offset from closure base
        ;;; = @@PD_CLOS_FROZVALS[_nfroz]
        _clos@PD_CLOS_FROZVALS[_nfroz] _sub _clos -> _exec_offs;

        ;;; ldr x16, [x0, #_exec_offs]  (unsigned scaled offset)
        ;;; Encoding: 0xF9400010 | (offset/8 << 10)
        _16:F9400010 _biset _shift(_shift(_exec_offs, _-3), _10)
            -> INSTR;

        ;;; br x16
        _16:D61F0200 -> INSTR;
    else
        ;;; Small closure: inline frozval push + pdpart chain
        _clos@PD_CLOS_FROZVALS[_nfroz] -> _drop_ptr;
#_IF DEF DARWIN
        ;;; Phase 4 view bias (see above)
        _drop_ptr _add _16:1000000000 -> _clos!PD_EXECUTE;
#_ELSE
        _drop_ptr -> _clos!PD_EXECUTE;
#_ENDIF

        ;;; Compute byte distance from adr instruction back to closure base.
        _clos _sub _drop_ptr -> _offs;

        ;;; adr x0, .-N  (compute closure base address in x0)
        _adr_encode(_offs, _0) -> INSTR;

#_IF DEF DARWIN
        ;;; canonicalise (see large-closure path above)
        _16:925BF800 -> INSTR;
#_ENDIF

        ;;; Compute byte offset of first frozval from closure base
        _clos@PD_CLOS_FROZVALS[_0] _sub _clos -> _fv_offs;

        until _zero(_nfroz) do
            ;;; ldr x1, [x0, #_fv_offs]  (load frozval, unsigned scaled)
            ;;; Encoding: 0xF9400001 | (offset/8 << 10)
            _16:F9400001 _biset _shift(_shift(_fv_offs, _-3), _10)
                -> INSTR;

            ;;; str x1, [x19, #-8]!  (push frozval on USP, pre-index writeback)
            ;;; Encoding: 0xF81F8E61 (idx=11 => writeback; 0xF81F8261 would be
            ;;; STUR with NO writeback, so every frozval would overwrite the
            ;;; same slot and USP would never advance -> closure passes 0 args).
            _16:F81F8E61 -> INSTR;

            _fv_offs _add _8 -> _fv_offs;
            _nfroz _sub _1 -> _nfroz;
        enduntil;

        ;;; Load PD_CLOS_PDPART into x0
        ;;; ldr x0, [x0, #@@PD_CLOS_PDPART]  (unsigned scaled offset)
        ;;; Encoding: 0xF9400000 | (offset/8 << 10)
        _16:F9400000 _biset _shift(_shift(@@PD_CLOS_PDPART, _-3), _10)
            -> INSTR;

        ;;; Load execute address from pdpart (@@PD_EXECUTE == 0)
        ;;; ldr x16, [x0]
        ;;; Encoding: 0xF9400010
        _16:F9400010 -> INSTR;

        ;;; br x16
        _16:D61F0200 -> INSTR;
    endif;
enddefine;

endsection;     /* $-Sys */
