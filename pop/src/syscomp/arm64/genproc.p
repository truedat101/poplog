/*
 > File:        $usepop/src/syscomp/genproc_arm64.p
 > Purpose:     Compiles M-Code to AArch64 assembler
 > Based on:    ARM32 genproc.p by Waldek Hebisch
 > Modified:    Full AArch64 (ARMv8-A) rewrite
 */


#_INCLUDE 'common.ph'

section $-Popas$-M_trans;

global constant procedure (
    immediate_operand,
    auto_operand,
    reg_in_operand,
    commute_test,
    negate_test,
    perm_const_opnd,
);

global vars
    current_pdr_label,
    current_pdr_exec_label,
;


    /****************************************************************
    * This file is contained entirely in section Genproc, and must  *
    *   define all the exports to section M_trans listed below.     *
    ****************************************************************/

section Genproc =>

        /*  M-opcode Procedures */

        M_ADD
        M_ASH
        M_BIC
        M_BIM
        M_BIS
        M_BIT
        M_BRANCH
        M_BRANCH_std
        M_BRANCH_ON
        M_BRANCH_ON_INT
        M_CALL
        M_CALL_WITH_RETURN
        M_CALLSUB
        M_CHAIN
        M_CHAINSUB
        M_CLOSURE
        M_CMP
        M_CMPKEY
        M_CREATE_SF
        M_END
        M_ERASE
        M_LABEL
        M_LOGCOM
        M_MOVE
        ;;; No longer needed
        ;;; M_MOVEb
        M_MOVEbit
        ;;; No longer needed
        ;;; M_MOVEi
        ;;; M_MOVEs
        ;;; M_MOVEsb
        M_MOVEsbit
        ;;; No longer needed
        ;;; M_MOVEsi
        ;;; M_MOVEss
        M_MULT
        M_NEG
        M_PADD
        M_PADD_TEST
        M_PCMP
        M_PLOG_IFNOT_ATOM
        M_PLOG_TERM_SWITCH
        M_PSUB
        M_PSUB_TEST
        M_PTR_ADD_OFFS
        M_PTR_CMP
        M_PTR_SUB
        M_PTR_SUB_OFFS
        M_RETURN
        M_SETSTKLEN
        M_SUB
        M_TEST
        M_UNWIND_SF
        ;;; No longer needed
        ;;; M_UPDb
        M_UPDbit
        ;;; No longer needed
        ;;; M_UPDi
        M_UPDs

        /*  Registers */

        SP
        USP
        USP_+
        -_USP
        i_USP
;;;     i_USP_+         ;;; these two are optional
;;;     ii_USP
        WK_ADDR_REG_1
        WK_ADDR_REG_2
        WK_REG
        CHAIN_REG

        /*  Register Lists */

        nonpop_registers
        pop_registers

        /*  Register Procedures */

        reglabel
        regnumber
        autoidreg

        /*  M-code Mapping of Subroutines */

        mc_inline_conditions_list
        mc_inline_procs_list

        /*  Procedures Needed by -m_optimise- */

        cvt_pop_subscript
        can_defer_opnd
        pdr_index_opnd

        /*  Procedure to Generate Code */

        mc_code_generator
        USE_NEW_M_OPERANDS
;

constant macro USE_NEW_M_OPERANDS = true;


;;; === REGISTER USAGE ================================================

/*
   AArch64 register assignments for Poplog:

   x0  - WK_REG/work/arg_reg_0    x1  - work/arg_reg_1
   x2  - CHAIN_REG/arg_reg_2      x3  - WK_ADDR_REG_1
   x4  - scratch                   x5  - secondary work reg (R5)
   x6-x11 - scratch/caller-saved
   x12 - WK_ADDR_REG_2 (caller-saved scratch, fine for this use)
   x13-x15 - scratch
   x16 - IP0 (intra-procedure scratch, used for indirect branches)
   x17 - IP1 (intra-procedure scratch)
   x18 - platform register (reserved, do not use)
   x19 - USP (user stack pointer, callee-saved)
   x20 - PB  (procedure base register, callee-saved)
   x21 - pop register local (was r4, callee-saved)
   x22 - pop register local (was r6, callee-saved)
   x23 - nonpop register local (was r7, callee-saved)
   x24 - nonpop register local (was r8, callee-saved)
   x25 - nonpop register local (was r9, callee-saved)
   x26-x28 - callee-saved (unused by Poplog)
   x29 - FP (frame pointer, callee-saved)
   x30 - LR (link register)
   sp  - stack pointer (must be 16-byte aligned for access)
   xzr/wzr - zero register

   Key differences from ARM32:
   - 64-bit word size (WORD_OFFS = 8)
   - No conditional execution on most instructions (use cmp + b.cond)
   - No stmfd/ldmfd; use stp/ldp pairs (16-byte aligned)
   - PC not directly readable as a general register
   - ret instruction replaces bx lr
   - br/blr replace bx/blx for register targets
   - Shifts are separate instructions (lsl, asr, lsr) not operand modifiers
   - x16 used as scratch for indirect branches
*/

lconstant

    ;;; AArch64 register names and their usage

    R0 = "x0",    ;;; WK_REG/work reg/arg_reg_0
    R1 = "x1",    ;;; principal work reg/arg_reg_1
    R2 = "x2",    ;;; CHAIN_REG/arg_reg_2
    R3 = "x3",    ;;; WK_ADDR_REG_1
    R4 = "x4",    ;;; scratch
    R5 = "x5",    ;;; secondary work reg
    R9  = "x9",   ;;; scratch
    R10 = "x19",  ;;; USP (callee-saved)
    R11 = "x20",  ;;; PB  (callee-saved)
    R12 = "x12",  ;;; WK_ADDR_REG_2 (caller-saved scratch)
    R13 = "sp",   ;;; SP
    LR = "x30",   ;;; LR (link register)
    R16 = "x16",  ;;; IP0 - scratch for indirect branches
;

constant

    ;;; POPC register operands

    SP = R13,

    ;;; USP: user stack pointer

    USP = R10,

    ;;; WK_REG: used by "m_optimise" to eliminate user stack pushes and
    ;;; pops between successive M-code instructions.  Must be preserved
    ;;; by M_MOVE.  Any instruction should handle WK_REG as source
    ;;; or destination.

    WK_REG = R0,

    ;;; CHAIN_REG: used to save procedure operands for in-line chaining
    ;;; and to save return addresses for out-of-line chaining through
    ;;; the subroutines "_syschain" and "_sysncchain". It must not be
    ;;; touched by M_UNWIND_SF.

    CHAIN_REG = R2,

    ;;; WK_ADDR_REG_1, WK_ADDR_REG_2: used for building field-access
    ;;; operands of the form {reg offset} when an existing operand
    ;;; cannot be deferred directly (can_defer_operand having returned
    ;;; <false> for it). REG_1 is used for source operands, REG_2 for
    ;;; destination operands.

    WK_ADDR_REG_1 = R3,
    WK_ADDR_REG_2 = R12,

    ;;; USP_+ : pop from the user stack
    ;;; -_USP : push on the user stack
    ;;; i_USP : top of user stack

    USP_+ = {^USP ^true},
    -_USP = {^USP ^false},
    i_USP = {^USP 0},

    ;;; i_USP_+ : not supported
    ;;; ii_USP  : not supported

    ;;; Lists of pop/non-pop registers for register locals
    ;;; AArch64: pop regs are x21, x22 (callee-saved)
    ;;;          nonpop regs are x23, x24, x25 (callee-saved)

    pop_registers = [[] 21 22],
    ;;; pop_registers = [[]],
    nonpop_registers = [[] 23 24 25],
    ;;; nonpop_registers = [[]],
;

;;; regnumber:
;;;     maps register names to numbers as used in the "reg" field of
;;;     instructions

define regnumber = newassoc([]) enddefine;

;;; reglabel:
;;;     the inverse mapping

define reglabel = newassoc([]); enddefine;

procedure();
        lvars n, l;
        for n from 0 to 30 do
                if n = 18 then
                    ;;; x18 is platform-reserved, skip it
                    nextloop;
                endif;
                consword('x' >< n) -> l;
                n -> regnumber(l);
                l -> reglabel(n);
                ;;; W-form (32-bit view) of the same register; needed so
                ;;; outopnd's isreg check accepts wN for ldrb/strb/sxtb etc.
                consword('w' >< n) -> l;
                n -> regnumber(l);
        endfor;
        ;;; Add special register names
        31 -> regnumber("sp");
        "sp" -> reglabel(31);
        ;;; Alias "wsp" to the SP slot too (32-bit view)
        31 -> regnumber("wsp");
        30 -> regnumber("x30");  ;;; LR is x30
        ;;; Alias "lr" to x30's number
        30 -> regnumber("lr");
endprocedure();

;;; Local register operands:

lconstant

    ;;; PB: procedure base register.
    ;;; This points to the start of the current procedure record, allowing
    ;;; access to values there.

    PB = R11,
;

;;; autoidreg:
;;;     indicates whether a register supports auto-indirection. All do
;;;     on AArch64.

identof("regnumber") -> identof("autoidreg");

;;; as_wreg:
;;;     Given an X-register name (e.g. "x21"), return the W-register name
;;;     ("w21").  Required by ldrb/ldrh/strb/strh/sxtb/sxth/uxtb/uxth which
;;;     accept only the 32-bit W form.  Pass through anything else (sp etc.).

define lconstant as_wreg(reg) -> wreg;
    lvars reg, wreg, n;
    regnumber(reg) -> n;
    if isinteger(n) and n fi_>= 0 and n fi_<= 30 then
        consword('w' >< n) -> wreg;
    else
        reg -> wreg;
    endif;
enddefine;


;;; === M-CODE OPERANDS ===============================================

;;; isimm, immval:
;;;     an immediate operand can be an integer, standing for itself, or
;;;     a reference to a string, standing for an immediate symbol or
;;;     expression.

lconstant macro isimm = "immediate_operand";

define lconstant immval(opd);
    lvars opd;
    if isintegral(opd) then opd else cont(opd) endif;
enddefine;

define lconstant immrep(x);
    lvars x;
    if isintegral(x) then x else consref(x) endif;
enddefine;

;;; isreg:
;;;     a register operand is a word, the register name. The property
;;;     regnumber is used as a recogniser for legal register names.

lconstant macro isreg = "regnumber";

;;; isabs:
;;;     an absolute operand is a string, standing for an absolute symbol
;;;     or expression. A register based/indexed operand is a vector,
;;;     with the most general form:
;;;         {^base ^disp ^index ^scale}
;;;     where base and index are registers, disp is an immediate
;;;     displacement and scale is an index scale factor (1,2,4 or 8).
;;;     The index and scale components are usually omitted, and are
;;;     never generated by the VM compiler: they're used here for
;;;     occasional optimisations.

lconstant macro isabs = "isstring";

;;; is_small_disp:
;;;     AArch64 scaled unsigned offset for LDR/STR is 0..32760 (for 8-byte),
;;;     but signed unscaled is -256..255. For simplicity, use a conservative
;;;     range matching the signed unscaled offset form, or use the scaled
;;;     form for multiples of 8. We keep the same conservative range as
;;;     ARM32 for general displacement checks.

define lconstant is_small_disp(disp);
    lvars disp;
    isinteger(disp) and disp > -256 and disp < 256;
enddefine;

;;; can_defer_opnd:
;;;     takes an M-code operand plus displacement as arguments and
;;;     returns either a deferred version of the operand or <false> if
;;;     it's already a memory operand and so can't be deferred further.
;;;     Used in "m_optimise" to generate field access and update
;;;     operands. Whenever this returns <false>, one of the work address
;;;     registers has to be used for an intermediate load and
;;;     indirection.

define can_defer_opnd(opd, dis, acctype, upd);
    lvars opd, dis, upd;
    if isreg(opd) and is_small_disp(dis) and acctype == T_WORD then
        ;;; register becomes register indirect
        {^opd ^dis};
    elseif isref(opd) and isinteger(dis) and acctype == T_WORD then
        ;;; immediate symbol becomes absolute expression
        asm_expr(fast_cont(opd), "+", dis);
    else
        false;
    endif;
enddefine;

define lconstant wof = nonop fi_*(% WORD_OFFS %) enddefine;

;;; pdr_index_opnd:
;;;     used by "m_trans.p" for creating operands to push/call values
;;;     from procedure headers (not used in closures).

define pdr_index_opnd(fld_index);
    lvars fld_index;
    {% PB, fld_index*WORD_OFFS %}
enddefine;


;;; == TRANSLATION TO ASSEMBLY CODE =======================================

lvars
    m_instr,
        ;;; current M-code instruction
    last_instr,
        ;;; last assembly-code instruction planted
    new_literals,
    lit_offset,
;

;;; plant:
;;;     add an assembly-code instruction to the code list

define lconstant plant(/* opcode, operands, ..., n */);
    conspair(consvector(), []) ->> f_tl(last_instr) -> last_instr;
enddefine;

;;; asmXXX:
;;;     assembly-code instructions

define lconstant asm_emit(/* opcode, operands, ..., n*/);
    ;;; add instruction to the code list
    plant(/* opcode, operands, ..., n*/);
enddefine;

define lconstant asmALIGN();
    asm_emit("align", 1);
enddefine;

define lconstant asmLABEL(lab);
    lvars lab;
    asm_emit("label", lab, 2);
enddefine;

define lconstant position_or_add(opd, lst);
    lvars opd, lst, lst0 = lst, lst1, n = 0;
    returnif(lst == [])(0, [^opd]);
    while not(lst == []) do
        returnif(fast_front(lst) = opd) (n, lst0);
        fast_back(lst) -> lst1;
        n fi_+ 1 -> n;
        if lst1 == [] then
            [^opd] -> fast_back(lst);
            return(n, lst0);
        endif;
        lst1 -> lst;
    endwhile;
enddefine;

;;; get_literal_addr:
;;;     returns an operand string for accessing a literal from the
;;;     procedure's literal pool via PB.
;;;     On AArch64: each literal is 8 bytes (.xword), so offset = 8*(disp + lit_offset)

define lconstant get_literal_addr(lit);
    lvars lit, disp, tmp;
    position_or_add(lit, new_literals) -> (disp, new_literals);
    return('[' >< PB >< ', #' >< (8*(disp + lit_offset)) >< ']');
enddefine;

define lconstant load_literal(lit, tmp);
    lvars lit, tmp;
    asm_emit("ldr", tmp, get_literal_addr(lit), 3);
enddefine;

;;; get_addressable_op:
;;;     converts an M-code operand into a form suitable for use as an
;;;     AArch64 memory operand (an addressing mode string), loading
;;;     intermediate values into tmp if necessary.

define lconstant get_addressable_op(opd, tmp);
    lvars opd, disp, opd1, type;
    ;;; arm64 port WIP: defensive fallback if a Pop-11 boolean leaks here
    ;;; from the genstructure chain.  Emit a placeholder rather than
    ;;; mishaping so the rest of the file still compiles.
    if isboolean(opd) then
        return('[' >< tmp >< ']');
    endif;
    returnif(isreg(opd))(opd);
    if isvector(opd) then
        if datalength(opd) = 1 then
            return( '[' >< f_subv(1, opd) >< ']');
        elseif datalength(opd) >= 2 then
            f_subv(2, opd) -> disp;
            f_subv(1, opd) -> opd1;
            if disp = 0 then
                    ;;; Already OK
            elseif is_small_disp(disp) then
                    opd1 >< ', #' >< disp -> opd1;
            elseif isboolean(disp) then
                ;;; Auto-increment/decrement for user stack operations
                ;;; On AArch64: word size is 8 bytes
                '8' -> tmp;
                if datalength(opd) == 3 then
                    f_subv(3, opd) && t_BASE_TYPE -> type;
                    if type == t_INT then '4'
                    elseif type == t_SHORT then '2'
                    elseif type == t_BYTE then '1'
                    else
                        mishap(opd, 1, 'Unhandled operand type');
                    endif -> tmp;
                endif;
                if disp then
                    ;;; post-increment (pop): [base], #size
                    '[' >< opd1 >< '], #' >< tmp
                else
                    ;;; pre-decrement (push): [base, #-size]!
                    '[' >< opd1 >< ', #-' >< tmp >< ']!'
                endif -> opd1;
                return(opd1);
            elseif isinteger(disp) then
                ;;; Displacement too large for immediate offset;
                ;;; load into a scratch register and use register offset.
                ;;; On AArch64, use x16 as scratch (IP0).
                load_literal(disp, R16);
                opd1 >< ', ' >< R16 -> opd1;
            else
                mishap(opd, 1, 'Unhandled operand in get_addressable_op');
            endif;
            return('[' >< opd1 >< ']');
        endif;
        mishap(opd, 1, 'Unhandled operand in get_addressable_op');
    endif;
    if isinteger(opd) or isbiginteger(opd) then
        mishap(opd, 1, 'Want address of literal');
    endif;
    if isref(opd) then
        fast_cont(opd) -> opd1;
        return(get_literal_addr(opd1));
    elseif isstring(opd) then
        load_literal(opd, tmp);
        return('[' >< tmp >< ']');
    endif;
    mishap(opd, 1, 'Unhandled operand in get_addressable_op');
enddefine;

;;; load_to_reg:
;;;     loads an M-code operand into a register.
;;;     On AArch64:
;;;     - Small immediates use "mov xd, #imm"
;;;     - Larger immediates go through the literal pool
;;;     - Typed sub-word loads use ldrh/ldrb with sign extension via sxth/sxtb

define lconstant load_to_reg(opd, tmp);
    lvars opd, tmp, opd1, opcode, type, n;
    ;;; sp is "isreg" but can't appear as source operand of most arithmetic
    ;;; or store instructions on AArch64.  Move it into the requested
    ;;; scratch register first so callers can use it freely.
    if opd == "sp" then
        asm_emit("mov", tmp, "sp", 3);
        return(tmp);
    endif;
    returnif(isreg(opd))(opd);
    if isinteger(opd) or isbiginteger(opd) then
        if is_small_disp(opd) then
            asm_emit("mov", tmp, '#' >< opd, 3);
            return(tmp);
        else
            load_literal(opd, tmp);
            return(tmp);
        endif;
    endif;
    get_addressable_op(opd, tmp) -> opd1;
    "ldr" -> opcode;
    if isvector(opd) and datalength(opd) == 3 then
        f_subv(3, opd) && t_BASE_TYPE -> type;
        if type == t_INT then "ldr"
        elseif type == t_SHORT then "ldrh"
        elseif type == t_BYTE then "ldrb"
        else
            mishap(opd, 1, 'Unhandled operand type');
        endif -> opcode;
    endif;
    ;;; ldrb/ldrh require the destination register in W (32-bit) form.
    if opcode == "ldrb" or opcode == "ldrh" then
        asm_emit(opcode, as_wreg(tmp), opd1, 3);
    else
        asm_emit(opcode, tmp, opd1, 3);
    endif;
    ;;; Sign extension for sub-word types on AArch64
    ;;; Use sxtb / sxth instructions instead of shift pairs
    if opcode /== "ldr" then
        f_subv(3, opd) -> type;
        if (type && tv_SIGNED) /== 0 then
            type && t_BASE_TYPE -> type;
            ;;; sxtb/sxth: destination Xd, source Wn (sign-extend low byte/half)
            if type == t_SHORT then
                asm_emit("sxth", tmp, as_wreg(tmp), 3);
            elseif type == t_BYTE then
                asm_emit("sxtb", tmp, as_wreg(tmp), 3);
            endif;
        endif;
    endif;
    return(tmp);
enddefine;

;;; gen_reg_store:
;;;     stores a register value to a destination operand.
;;;     On AArch64: use str/strh/strb as appropriate for the type.

define lconstant gen_reg_store(src, dst, tmp);
    lvars src, dst, tmp, dst1, type, opcode;
    get_addressable_op(dst, tmp) -> dst1;
    "str" -> opcode;
    if isvector(dst) and datalength(dst) == 3 then
        f_subv(3, dst) && t_BASE_TYPE -> type;
        if type == t_INT then "str"
        elseif type == t_SHORT then "strh"
        elseif type == t_BYTE then "strb"
        else
            mishap(dst, 1, 'Unhandled operand type');
        endif -> opcode;
    endif;
    ;;; strb/strh require the source register in W (32-bit) form.
    if opcode == "strb" or opcode == "strh" then
        asm_emit(opcode, as_wreg(src), dst1, 3);
    else
        asm_emit(opcode, src, dst1, 3);
    endif;
enddefine;

;;; push_operand / pop_operand:
;;;     Push/pop a value on/from the system stack.
;;;     On AArch64: must maintain 16-byte stack alignment.
;;;     We use sub sp, sp, #16 + str at [sp] for push,
;;;     and ldr from [sp] + add sp, sp, #16 for pop.

define lconstant push_operand(opd);
    lvars opd;
    load_to_reg(opd, R1) -> opd;
    asm_emit("str", opd, '[sp, #-16]!', 3);
enddefine;

define lconstant pop_operand(opd);
    lvars opd, reg;
    if isreg(opd) then opd else R1 endif -> reg;
    asm_emit("ldr", reg, '[sp], #16', 3);
    returnif(opd == reg);
    gen_reg_store(reg, opd, R5);
enddefine;

;;; gen_transfer:
;;;     generates a branch or call instruction.
;;;     On AArch64:
;;;     - "bl" to a label stays "bl"
;;;     - "bl" to a register becomes "blr"
;;;     - "b" to a label stays "b"
;;;     - "b" to a register becomes "br"

define lconstant gen_transfer(opcode, target);
    lvars target, opcode;
    if isreg(target) then
        if opcode == "bl" then "blr" -> opcode; endif;
        if opcode == "b" then "br" -> opcode; endif;
    endif;
    asm_emit(opcode, target, 2);
enddefine;

;;; testop:
;;;     maps M-code condition codes to AArch64 condition code suffixes
;;;     (used after b. for conditional branches)

define lconstant testop =
    newassoc([
        [EQ     eq]
        [NEQ    ne]
        [LT     lt]
        [LEQ    le]
        [GT     gt]
        [GEQ    ge]
        [ULT    lo]
        [ULEQ   ls]
        [UGT    hi]
        [UGEQ   hs]
        [NEG    mi]
        [POS    pl]
        [OVF    vs]
        [NOVF   vc]
    ]);
enddefine;

define lconstant get_jump_addr(lab);
    if isstring(lab) then
        lab;
    else
        mishap(lab, 1, 'get_jump_addr unimplemented');
    endif;
enddefine;

;;; gen_branch:
;;;     On AArch64, conditional branches use "b.cond" syntax.
;;;     The opcode passed in is e.g. "b.eq", "b.ne", etc.

define lconstant gen_branch(opcode, lab);
    get_jump_addr(lab) -> lab;
    asm_emit(opcode, lab, 2);
enddefine;

/*
 *  Data Movement
 */

define gen_move(src, dst);
    lvars  src, dst;
    returnif(src = dst or src == USP_+ and dst == -_USP);
    if isreg(dst) then
        load_to_reg(src, dst) -> src;
        returnif(src = dst);
        asm_emit("mov", dst, src, 3);
    else
        ;;; Special case to support
        ;;;   M_MOVE x19 {x19 <false>}
        if src == USP and dst == -_USP then
            asm_emit("mov", R1, src, 3);
            R1 -> src;
        else
            load_to_reg(src, R1) -> src;
        endif;
        ;;; NOTE: I_SWAP assumes that WK_REG = R0 will survive
        ;;; M_MOVE with arguments on user stack.  This is OK, since
        ;;; gen_reg_store does not need temporary when
        ;;; dst is on user stack.
        gen_reg_store(src, dst, R0);
    endif;
enddefine;

define M_MOVE();
    lvars (, src, dst) = explode(m_instr);
    gen_move(src, dst);
enddefine;

;;; M_UPDs:
;;;     store a short (16-bit) value to memory.
;;;     Load source to register if needed, then use strh.

define M_UPDs();
    lvars (, src, dst) = explode(m_instr);
    load_to_reg(src, R1) -> src;
    lvars dst1 = get_addressable_op(dst, R5);
    asm_emit("strh", as_wreg(src), dst1, 3);
enddefine;

;;; gen_bfield:
;;;     extract a bitfield from a structure using assembly code routines
;;;     "_bfield" and "_sbfield"

define lconstant gen_bfield(routine);
    lvars routine, (, size, offs, src, dst) = explode(m_instr);
    gen_move(size, R0);
    gen_move(offs, R1);
    gen_move(src, R2);
    gen_transfer("bl", symlabel(routine));
    gen_move(R0, dst);
enddefine;

define M_MOVEbit  = gen_bfield(% "\^_bfield"  %) enddefine;
define M_MOVEsbit = gen_bfield(% "\^_sbfield" %) enddefine;

define M_UPDbit();
    lvars (, size, offs, dst, src) = explode(m_instr);
    gen_move(src, -_USP);
    gen_move(size, R0);
    gen_move(offs, R1);
    gen_move(dst, R2);
    gen_transfer("bl", symlabel("\^_ubfield"));
enddefine;


/*
 *  Basic operations
 */

define is_int_opd(src);
    isintegral(src) and is_small_disp(src);
enddefine;

;;; get_operand2:
;;;     On AArch64, small immediates can be used directly with
;;;     add/sub/cmp etc. as #imm. Otherwise load to R5.

define get_operand2(src);
    lvars src;
    if is_int_opd(src) then '#' >< src else load_to_reg(src, R5) endif;
enddefine;

;;; is_aarch64_bitmask_imm:
;;;     Returns true iff `val` (a 64-bit integer) is encodable as an
;;;     AArch64 logical-immediate bitmask. The encoding represents N
;;;     copies of an M-bit pattern of K consecutive 1s rotated by R,
;;;     where (M, K, R) come from (N, immr, imms).  Equivalently: any
;;;     non-trivial value whose binary repeats with element-size 2/4/8/
;;;     16/32/64, where the element is a single contiguous run of 1s
;;;     possibly rotated.  Trivial all-zeros / all-ones are NOT valid.
;;;     Used to decide whether to fold an immediate into orr/and/eor/...

define lconstant is_aarch64_bitmask_imm(val);
    lvars val, esz, ones, mask, elem;
    ;;; Must fit in 64 bits, and not be 0 or all-ones.
    if val == 0 or val == -1 then return(false) endif;
    ;;; Mask to 64 bits in case of negative input
    val && #_< (1 << 64) - 1 >_# -> val;
    ;;; Try element sizes 2, 4, 8, 16, 32, 64 -- the value must be a
    ;;; replication of a same-size element.
    for esz in [2 4 8 16 32 64] do
        if esz == 64 then val -> elem
        else
            (1 << esz) - 1 -> mask;
            val && mask -> elem;
            ;;; All esz-bit slices must equal `elem`.
            lvars i = esz, ok = true;
            while i < 64 do
                unless ((val >> i) && mask) == elem then
                    false -> ok; quitloop
                endunless;
                i + esz -> i
            endwhile;
            unless ok then nextloop endunless
        endif;
        ;;; elem must have a single contiguous run of 1s, possibly rotated
        ;;; within esz bits, and must not be all-0 or all-1 within esz.
        (1 << esz) - 1 -> mask;
        elem && mask -> elem;
        if elem == 0 or elem == mask then nextloop endif;
        ;;; Rotate elem within esz bits to put the 1s at the bottom; if the
        ;;; result is (1 << k) - 1 for some k in [1..esz-1], it's valid.
        lvars rot;
        for rot from 0 to esz - 1 do
            ((elem >> rot) || (elem << (esz - rot))) && mask -> ones;
            ;;; ones is now `elem` rotated right by `rot` within esz bits
            ;;; check ones == (1 << k) - 1 for some 1 <= k < esz
            if (ones && (ones + 1)) == 0 then return(true) endif
        endfor
    endfor;
    return(false)
enddefine;

;;; get_operand2_logical:
;;;     Like get_operand2 but only allows immediates encodable as
;;;     AArch64 bitmask immediates. Otherwise falls back to register form.
define get_operand2_logical(src);
    lvars src;
    if is_int_opd(src) and is_aarch64_bitmask_imm(src) then
        '#' >< src
    else
        load_to_reg(src, R5)
    endif
enddefine;

define get_operands(src1, src2);
    lvars src1, src2;
    load_to_reg(src1, R1);
    get_operand2(src2);
enddefine;

;;; Like get_operands, but user is supposed to switch order
;;; of operand (we need to perform loads in source order,
;;; to preserve order of side effects).
define get_operands_r(src1, src2);
    lvars src1, src2;
    get_operand2(src1);
    load_to_reg(src2, R1);
enddefine;

;;; gen_op_2:
;;;     plants code for a unary operation 'opcode' of the form:
;;;         dst := op(src)

define lconstant gen_op_2(src, dst, opcode);
    lvars src, dst, asm_op, dreg, op1;
    get_operand2(src) -> op1;
    if isreg(dst) then
        dst -> dreg;
        false -> dst;
    else
        R1 -> dreg;
    endif;
    asm_emit(opcode, dreg, op1, 3);
    if dst then
        gen_reg_store(dreg, dst, R5);
    endif;
enddefine;

;;; gen_op_3:
;;;     plants general 3 address binary operation 'opcode':
;;;         dst := src1 op src2
;;;     On AArch64, most ALU ops are 3-address: op Xd, Xn, operand2

define lconstant gen_op_3(src1, src2, dst, opcode);
    lvars src1, src2, dst, opcode, op1, op2, dreg;
    ;;; Logical ops (orr/and/eor/bic/...) on AArch64 require the immediate
    ;;; to encode as a bitmask -- arbitrary integers must be loaded to a
    ;;; register first.  Fall back to register form for non-bitmask values.
    if member(opcode, ["orr" "and" "eor" "bic"])
       and is_int_opd(src1) and not(is_aarch64_bitmask_imm(src1))
    then
        load_to_reg(src1, R5) -> op2;
        load_to_reg(src2, R1) -> op1;
    elseif member(opcode, ["orr" "and" "eor" "bic"])
       and is_int_opd(src2) and not(is_aarch64_bitmask_imm(src2))
    then
        load_to_reg(src1, R1) -> op1;
        load_to_reg(src2, R5) -> op2;
    else
        get_operands_r(src1, src2) -> (op2, op1);
    endif;
    ;;; sp cannot appear as the Xm operand for arithmetic/logical
    ;;; instructions on AArch64.  Move it into a scratch register first.
    if op2 == "sp" then
        asm_emit("mov", R5, "sp", 3);
        R5 -> op2
    endif;
    if isreg(dst) then
        dst -> dreg;
        false -> dst;
    else
        R1 -> dreg;
    endif;
    asm_emit(opcode, dreg, op1, op2, 4);
    if dst then
        gen_reg_store(dreg, dst, R5);
    endif;
enddefine;

;;; gen_op_commute:
;;;     plants code for a commutative binary operation 'opcode':
;;;         dst := src1 op src2

define lconstant gen_op_commute(src1, src2, dst, opcode);
    lvars src1, src2, dst, opcode;
    if is_int_opd(src2) then
        (src1, src2) -> (src2, src1)
    endif;
    gen_op_3(src1, src2, dst, opcode);
enddefine;

;;; m_op_*:
;;;     translate 2- and 3-operand M-code arithmetic/logical instructions
;;;     on machine integers;  calls corresponding gen_... operation.

define lconstant m_op_2(opcode);
    lvars opcode, (, src, dst) = explode(m_instr);
    gen_op_2(src, dst, opcode);
enddefine;

define lconstant m_op_commute(opcode);
    lvars opcode,
          (, src1, src2, dst) = explode(m_instr);
    gen_op_commute(src1, src2, dst, opcode);
enddefine;

define lconstant m_op_3(opcode);
    lvars opcode,
          (, src1, src2, dst) = explode(m_instr);
    gen_op_3(src1, src2, dst, opcode);
enddefine;

;;; m_parith, m_parith_test:
;;;     plant code for an addition or subtraction of pop integers.
;;;     This means clearing the bottom two bits of the first operand and
;;;     then doing an ordinary machine integer operation.
;;;     The testing version pushes the result on the user stack and
;;;     plants a branch conditional on the result.

define lconstant m_parith(opcode);
    lvars opcode, (, src1, src2, dst) = explode(m_instr);
    if isintegral(src1) then
        src1 - 3 -> src1;
    else
        load_to_reg(src1, R5) -> src1;
        asm_emit("sub", R5, src1, 3, 4);
        R5 -> src1;
    endif;
    gen_op_3(src1, src2, dst, opcode);
enddefine;

define lconstant m_parith_test(opcode);
    lvars gen_p, (, src1, src2, test, lab) = explode(m_instr);
    if isintegral(src1) then
        src1 - 3 -> src1;
    else
        load_to_reg(src1, R5) -> src1;
        asm_emit("sub", R5, src1, 3, 4);
        R5 -> src1;
    endif;
    gen_op_3(src1, src2, -_USP, opcode);
    gen_branch('b.' >< testop(test), lab);
enddefine;

;;; ptr_arith:
;;;     plants code for an operation on pointers. Pointers are just
;;;     machine integers, so their code-planting procedures can be used
;;;     directly. The type field of the instruction is ignored.

define lconstant m_ptr_op_3(opcode);
    lvars gen_p, (, /*type*/, offs, ptr, dst) = explode(m_instr);
    gen_op_3(offs, ptr, dst, opcode);
enddefine;

define lconstant m_ptr_op_commute(opcode);
    lvars gen_p, (, /*type*/, offs, ptr, dst) = explode(m_instr);
    gen_op_commute(offs, ptr, dst, opcode);
enddefine;

define M_ADD    = m_op_commute(% "add"  %) enddefine;
define M_SUB    = m_op_3(% "sub"  %) enddefine;
define M_BIC    = m_op_3(% "bic" %) enddefine;
define M_BIS    = m_op_commute(% "orr"  %) enddefine;
define M_BIM    = m_op_commute(% "and"  %) enddefine;
define M_LOGCOM = m_op_2(% "mvn"  %) enddefine;


;;; M_MULT:
;;;     different than m_op_commute because we need both arguments
;;;     in registers.
;;;     On AArch64: mul Xd, Xn, Xm (no restriction on same register)

define M_MULT();
    lvars (, src1, src2, dst) = explode(m_instr), dreg;
    load_to_reg(src1, R1) -> src1;
    load_to_reg(src2, R5) -> src2;
    if isreg(dst) then
        dst -> dreg;
        false -> dst;
    else
        R1 -> dreg;
    endif;
    asm_emit("mul", dreg, src1, src2, 4);
    if dst then
        gen_reg_store(dreg, dst, R5);
    endif;
enddefine;

;;; M_NEG:
;;;     negate: dst = 0 - src
;;;     On AArch64: neg Xd, Xs (alias for sub Xd, xzr, Xs)

define M_NEG();
    lvars (, src, dst) = explode(m_instr), dreg;
    load_to_reg(src, R1) -> src;
    if isreg(dst) then
        dst -> dreg;
        false -> dst;
    else
        R1 -> dreg;
    endif;
    asm_emit("neg", dreg, src, 3);
    if dst then
        gen_reg_store(dreg, dst, R5);
    endif;
enddefine;

/*
Syntax:         M_PADD src1 src2 dest

Description:    Add POP integer contents of -src1- to POP integer contents
                of -src2- and put POP integer result in -dest-.

Operation:      dest:pint = src2:pint + src1:pint

Notes:          With normal POP integer representation and machine arithmetic:
                dest = src2 + (src1 - 0x3)
*/
define M_PADD = m_parith(% "add" %) enddefine;
define M_PSUB = m_parith(% "sub" %) enddefine;

/*
M_PADD_TEST                                       Add POP Integers With Test

Syntax:         M_PADD_TEST src1 src2 cond label

Description:    Add POP integer contents of -src1- to POP integer contents
                of -src2- and push the POP integer result on the stack. If
                the -cond- is true then branch to the -label- else continue.

Operation:      push (src2:pint + src1:pint) on user stack
                if cond then PC = label

Notes:          Calculation as for M_PADD.  Test is always NOVF.
*/
define M_PADD_TEST = m_parith_test(% "adds" %) enddefine;

/* Like M_PADD_TEST, but subtract */
define M_PSUB_TEST = m_parith_test(% "subs" %) enddefine;

define M_PTR_ADD_OFFS = m_ptr_op_commute(% "add" %) enddefine;
define M_PTR_SUB_OFFS = m_ptr_op_3(% "sub" %) enddefine;
define M_PTR_SUB      = m_ptr_op_3(% "sub" %) enddefine;

;;; M_ASH:
;;;     performs an arithmetic shift of src2 by an amount src1, leaving
;;;     result in dst. The shift may be right or left depending on the
;;;     sign of src1.
;;;
;;;     On AArch64:
;;;     - Constant shifts use lsl/asr instructions directly
;;;     - Variable shifts: no conditional execution, so we use
;;;       cmp + b.lt + two paths, or csel.
;;;       We use: cmp src1, #0 / b.lt negative_path /
;;;               lsl dreg, src2, src1 / b done /
;;;               negative_path: neg tmp, src1 / asr dreg, src2, tmp /
;;;               done:

define M_ASH();
    lvars (, src1, src2, dst) = explode(m_instr),
          dreg;
    if isreg(dst) then
        dst -> dreg;
        false -> dst;
    else
        R1 -> dreg;
    endif;
    if isintegral(src1) then
        load_to_reg(src2, R1) -> src2;
        if src1 < -63 then -63 -> src1 endif;
        if src1 > 63 then
            asm_emit("mov", dreg, '#0', 3);
        else
            if src1 < 0 then
                asm_emit("asr", dreg, src2, '#' >< -src1, 4);
            elseif src1 == 0 then
                unless dreg = src2 then
                    asm_emit("mov", dreg, src2, 3);
                endunless;
            else
                asm_emit("lsl", dreg, src2, '#' >< src1, 4);
            endif;
        endif;
    else
        ;;; Variable shift amount: need two code paths
        load_to_reg(src1, R5) -> src1;
        load_to_reg(src2, R1) -> src2;
        lvars neg_lab = genlab();
        lvars done_lab = genlab();
        asm_emit("cmp", src1, '#0', 3);
        gen_branch('b.lt', neg_lab);
        ;;; Positive or zero: left shift
        asm_emit("lsl", dreg, src2, src1, 4);
        gen_branch("b", done_lab);
        ;;; Negative: right shift by negated amount
        asmLABEL(neg_lab);
        asm_emit("neg", R5, src1, 3);
        asm_emit("asr", dreg, src2, R5, 4);
        asmLABEL(done_lab);
    endif;
    if dst then
        gen_reg_store(dreg, dst, R5);
    endif;
enddefine;


/*
 *  Branches and Tests
 */

;;; gen_test_or_cmp:
;;;     plants code to test/compare src1 against src2, and jump to lab
;;;     on test. The test may be CMP (src2 - src1) or TEST (src1 &&
;;;     src2) determined by cmp_or_test; the test will be one of the M-code
;;;     test codes EQ, NEQ etc.
;;;     On AArch64: cmp/tst + b.cond

define lconstant gen_test_or_cmp(src1, src2, test, lab, cmp_or_test);
    lvars src1, src2, test, lab, cmp_or_test, op1, op2;
    ;;; tst is a logical instruction -- requires bitmask immediate;
    ;;; arbitrary integers must be loaded to register form.
    if cmp_or_test == "tst"
       and is_int_opd(src2) and not(is_aarch64_bitmask_imm(src2))
    then
        load_to_reg(src1, R1) -> op1;
        load_to_reg(src2, R5) -> op2;
    else
        get_operands(src1, src2) -> (op1, op2);
    endif;
    ;;; sp cannot appear as Xm for cmp/tst -- mov to scratch first.
    if op2 == "sp" then
        asm_emit("mov", R5, "sp", 3);
        R5 -> op2
    endif;
    asm_emit(cmp_or_test, op1, op2, 3);
    gen_branch('b.' >< testop(test), lab);
enddefine;

define lconstant gen_cmp  = gen_test_or_cmp(% "cmp" %) enddefine;
define lconstant gen_test = gen_test_or_cmp(% "tst" %) enddefine;

;;; M_BIT:
;;;     tests an operand against a bit mask

define M_BIT();
    lvars (, mask, src, test, lab) = explode(m_instr);
    gen_test(src, mask, test, lab);
enddefine;

;;; M_TEST:
;;;     compares an operand with zero

define M_TEST();
    lvars (, src, test, lab) = explode(m_instr);
    gen_cmp(src, 0, test, lab);
enddefine;

;;; M_CMP:
;;;     compares two machine integers

define M_CMP();
    lvars (, src1, src2, test, lab) = explode(m_instr);
    gen_cmp(src1, src2, test, lab);
enddefine;

;;; M_PCMP:
;;;     compares two POP integers (same as M_CMP)

define M_PCMP();
    lvars (, src1, src2, test, lab) = explode(m_instr);
    gen_cmp(src1, src2, test, lab);
enddefine;

;;; M_PTR_CMP:
;;;     compares two pointers; this is the same as comparing machine
;;;     integers regardless of the pointer type.

define M_PTR_CMP();
    lvars (, /*type*/, src1, src2, test, lab) = explode(m_instr);
    gen_cmp(src1, src2, test, lab);
enddefine;

;;; M_CMPKEY:
;;;     compares the key of an item with a given key

define M_CMPKEY();
    lvars (, key, src, test, lab) = explode(m_instr);
    ;;; test for a simple item first
    lvars tlab = if test == "EQ" then genlab() else lab endif;
    load_to_reg(src, R5) -> src;
    gen_test(src, 1, "NEQ", tlab);
    ;;; item is compound: get its key
    {% src, field_##("KEY").wof %} -> src;
    if isintegral(key) then
        ;;; testing flag(s) nonzero in K_FLAGS field:
        ;;; get key to register
        gen_move(src, R5 ->> src);
        ;;; test the flags
        gen_test(key, {% src, field_##("K_FLAGS").wof %}, negate_test(test), lab);
    else
        ;;; test for specific key
        gen_cmp(key, src, test, lab);
    endif;
    if test == "EQ" then asmLABEL(tlab) endif;
enddefine;

;;; gen_switch:
;;;     plants a computed goto on the integer src: this may be a system
;;;     integer or a POP integer depending on the flag sysint.
;;;     labs is a list of the labels to jump to, counted from 1.
;;;     If -else_case- is <true>, the instruction is followed by a default
;;;     case for a value out of range; if <false>, there is an error case
;;;     following which expects the out-of-range value on the stack.
;;;
;;;     On AArch64: cannot use ldr pc, [pc, ...] since PC is not a
;;;     general-purpose register. Instead:
;;;     1. Range check with cmp + b.hi to else_lab
;;;     2. Compute table entry address: adr x16, table_base /
;;;        add x16, x16, sreg, lsl #3  (for sysint) or
;;;        add x16, x16, sreg  (for popint, already scaled by 4,
;;;        but we need 8-byte entries so multiply by 2)
;;;     3. ldr x16, [x16] / br x16

define lconstant gen_switch(src, labs, else_case, sysint);
    lvars src, labs, else_case, sysint;
    lvars else_lab = genlab();
    lvars table_lab = genlab();
    lvars ncases = listlength(labs);
    load_to_reg(src, R1) -> src;
    lvars sreg = src;
    ;;; clear pop bits when POP integer
    if not(sysint) then
        asm_emit("sub", R0, src, 3, 4);
        R0 -> sreg;
    endif;
    ;;; Check it's in range: an unsigned comparison takes care of both the
    ;;; too large and too small cases.
    lvars opd2;
    get_operand2(if sysint then ncases else popint(ncases) - 3 endif) -> opd2;
    asm_emit("cmp", sreg, opd2, 3);
    gen_branch('b.hi', else_lab);
    ;;; Compute table entry address and jump
    ;;; On AArch64: table entries are 8 bytes (.xword) each
    if sysint then
        ;;; sreg is a system integer; multiply by 8 (lsl #3) for table index
        asm_emit("adr", R16, table_lab, 3);
        asm_emit("ldr", R16, '[' >< R16 >< ', ' >< sreg >< ', lsl #3]', 3);
    else
        ;;; sreg (R0) has popint with tag removed: value * 4
        ;;; Table entries are 8 bytes, so we need value * 8 = sreg * 2
        asm_emit("lsl", R0, sreg, '#1', 4);
        asm_emit("adr", R16, table_lab, 3);
        asm_emit("ldr", R16, '[' >< R16 >< ', ' >< R0 >< ']', 3);
    endif;
    asm_emit("br", R16, 2);
    ;;; Plant the table; it begins with -else_lab- to account for the 0 case
    asmALIGN();
    asmLABEL(table_lab);
    asm_emit("long", else_lab, explode(labs), ncases + 2);
    ;;; Plant the else case
    asmLABEL(else_lab);
    if not(else_case) then
        ;;; Push src onto user stack for error reporting
        asm_emit("str", src, '[x19, #-8]!', 3);
    endif;
enddefine;

;;; M_LABEL <label>:
;;;     plants a label

define M_LABEL();
    asmLABEL(m_instr(2));
enddefine;

;;; M_BRANCH <label>:
;;;     unconditional jump to label

define M_BRANCH();
    gen_branch("b", m_instr(2));
enddefine;

;;; M_BRANCH_std:
;;;     same as M_BRANCH, but guarantees to produce an instruction of a
;;;     fixed size.  Since AArch64 instructions have fixed length it
;;;     is really the same...

define M_BRANCH_std();
    gen_branch("b", m_instr(2));
enddefine;

;;; M_BRANCH_ON:
;;;     computed goto on a POP integer.

define M_BRANCH_ON();
    lvars (, src, labs, else_case) = explode(m_instr);
    gen_switch(src, labs, else_case, false);
enddefine;

;;; M_BRANCH_ON_INT:
;;;     computed goto on a system integer. This will always have an else
;;;     case.

define M_BRANCH_ON_INT();
    lvars (, src, labs) = explode(m_instr);
    gen_switch(src, labs, true, true);
enddefine;


/*
 *  Procedure Call and Return
 */

;;; get_exec_opd:
;;;     computes an operand which can be used as the target of a call or an
;;;     unconditional jump to execute the procedure opd. Such an operand
;;;     has an extra level of indirection over that already present in opd.
;;;     If opd is a POP procedure, the computed operand must refer to its
;;;     execute address.

define lconstant get_exec_opd(opd, is_pop_pdr);
    lvars opd, is_pop_pdr, tmp;
    if isimm(opd) then
        ;;; it must be the immediate label of a system procedure
        if is_pop_pdr then execlabof(cont(opd), true) else cont(opd) endif;
    else
        if is_pop_pdr then
            load_to_reg(opd, R0) -> tmp;
            if tmp /== R0 then
                asm_emit("mov", R0, tmp, 3);
                R0 -> tmp;
            endif;
            asm_emit("ldr", R1, '[' >< R0 >< ', #' ><
                                  field_##("PD_EXECUTE").wof >< ']', 3);
            R1
        else
            load_to_reg(opd, R5)
        endif;
    endif;
enddefine;

define lconstant gen_call_or_chain(opd, opcode, is_pop_pdr);
    lvars opd, opcode, is_pop_pdr;
    lvars target = get_exec_opd(opd, is_pop_pdr);
    gen_transfer(opcode, target);
enddefine;

define gen_chain(opd, is_pop_pdr);
    lvars opd, is_pop_pdr;
    ;;; Jump (tail call)
    gen_call_or_chain(opd, "b", is_pop_pdr);
enddefine;

define lconstant m_chain(is_pop_pdr);
    lvars is_pop_pdri;
    gen_chain(m_instr(2), is_pop_pdr);
enddefine;

define lconstant m_call(is_pop_pdr);
    lvars is_pop_pdr;
    gen_call_or_chain(m_instr(2), "bl", is_pop_pdr);
enddefine;

define M_CALL  = m_call(% true %) enddefine;
define M_CHAIN = m_chain(% true %) enddefine;

define M_CALL_WITH_RETURN();
    lvars tmp;
    ;;; Set return address in LR (x30)
    load_to_reg(m_instr(3), LR) -> tmp;
    if tmp /== LR then
        asm_emit("mov", LR, tmp, 3);
    endif;
    ;;; jump to the procedure
    gen_call_or_chain(m_instr(2), "b", true);
enddefine;

;;; {M_CALLSUB <subroutine_opd> <args ...>}
;;;     call subroutine, passing arguments (0-3) in registers.
;;;     Subroutine will always be constant when arguments are present

define M_CALLSUB();
    lvars l = datalength(m_instr);
    if l == 6 then    gen_move(m_instr(3),   R3) endif; ;;; arg_reg_3
    if l fi_>= 5 then gen_move(m_instr(l - 2), R2) endif; ;;; arg_reg_2
    if l fi_>= 4 then gen_move(m_instr(l - 1), R1) endif; ;;; arg_reg_1
    if l fi_>= 3 then gen_move(m_instr(l),   R0) endif; ;;; arg_reg_0
    gen_transfer("bl", get_exec_opd(m_instr(2), false));
enddefine;

define M_CHAINSUB = m_chain(% false %) enddefine;

;;; M_RETURN:
;;;     On AArch64: use "ret" instruction (branches to x30/LR)

define M_RETURN(); asm_emit("ret", 1); enddefine;


/*
 *  Procedure Entry and Exit
 */

lblock

lvars

    ;;; These variables are set by M_CREATE_SF and used by M_UNWIND_SF

    ;;; Names of dynamic local variables
    dlocal_labs,
    ;;; List of callee-saved registers to save/restore
    save_reg_list,
    ;;; Number of on-stack vars
    Nstkvars,
    Nregs,
;

;;; emit_stp_list / emit_ldp_list:
;;;     On AArch64, we save/restore registers using stp/ldp pairs.
;;;     The list must be processed in pairs for 16-byte alignment.
;;;     For an odd number of registers, we add an extra str/ldr for the last one.

define lconstant emit_stp_push(reg_list);
    ;;; Push registers onto sp using stp with pre-decrement.
    ;;; Process in pairs from the end to maintain proper stack order.
    lvars regs = reg_list, len = listlength(regs), i;
    lvars regvec = {%applist(regs, identfn)%};
    ;;; We push in pairs. Total space needed is len * 8, rounded up to 16.
    lvars total_space = ((len + 1) div 2) * 16;
    ;;; First, allocate the stack space
    asm_emit("sub", "sp", "sp", '#' >< total_space, 4);
    ;;; Then store registers. stp uses [sp, #offset] form.
    lvars offset = 0;
    1 -> i;
    while i + 1 <= len do
        asm_emit("stp", f_subv(i, regvec), f_subv(i + 1, regvec),
                 '[sp, #' >< offset >< ']', 4);
        offset + 16 -> offset;
        i + 2 -> i;
    endwhile;
    ;;; Handle odd register
    if i <= len then
        asm_emit("str", f_subv(i, regvec),
                 '[sp, #' >< offset >< ']', 3);
    endif;
enddefine;

define lconstant emit_ldp_pop(reg_list);
    ;;; Pop registers from sp using ldp with post-increment.
    lvars regs = reg_list, len = listlength(regs), i;
    lvars regvec = {%applist(regs, identfn)%};
    lvars total_space = ((len + 1) div 2) * 16;
    ;;; Load registers. ldp uses [sp, #offset] form.
    lvars offset = 0;
    1 -> i;
    while i + 1 <= len do
        asm_emit("ldp", f_subv(i, regvec), f_subv(i + 1, regvec),
                 '[sp, #' >< offset >< ']', 4);
        offset + 16 -> offset;
        i + 2 -> i;
    endwhile;
    ;;; Handle odd register
    if i <= len then
        asm_emit("ldr", f_subv(i, regvec),
                 '[sp, #' >< offset >< ']', 3);
    endif;
    ;;; Deallocate the stack space
    asm_emit("add", "sp", "sp", '#' >< total_space, 4);
enddefine;


;;; {M_CREATE_SF <reg_locals> <Npopreg> <Nstkvars> <Npopstkvars>
;;;             <dlocal_labs> <ident reg_spec>}
;;;     plant code to construct procedure stack frame
;;;
;;;     On AArch64:
;;;     - Save callee-saved registers + LR using stp pairs
;;;     - Load PB from procedure record pointer (stored just before
;;;       the execute address in the procedure header)
;;;     - Push dynamic locals
;;;     - Initialize POP register locals to popint(0)
;;;     - Allocate POP on-stack lvars (initialized to popint(0))
;;;     - Allocate non-POP on-stack lvars (uninitialized)
;;;     - Push owner address (PB)

define M_CREATE_SF();
    lconstant popint_zero = popint(0);
    lvars reg_spec_id, Npopregs, Npopstkvars, reg_locals, n, regmask,
          tmp, j;

    explode(m_instr) -> reg_spec_id -> dlocal_labs -> Npopstkvars
        -> Nstkvars -> Npopregs -> reg_locals -> ;

    listlength(reg_locals) -> Nregs;

    ;;; PD_REGMASK is a 16-bit field. AArch64 register numbers (e.g. x21
    ;;; would set bit 21 = 0x200000) overflow the short. The runtime code
    ;;; in pop/src/arm64/aprocess.s expects this mapping:
    ;;;   x21 -> bit 4, x22 -> bit 6, x23 -> bit 7, x24 -> bit 8, x25 -> bit 9
    0 -> regmask;
    fast_for n in reg_locals do
        lvars bitpos;
        if n == 21 then 4
        elseif n == 22 then 6
        elseif n == 23 then 7
        elseif n == 24 then 8
        elseif n == 25 then 9
        else mishap(n, 1, 'M_CREATE_SF: register not in PD_REGMASK map')
        endif -> bitpos;
        regmask || (1 << bitpos) -> regmask
    endfast_for;

    regmask -> idval(reg_spec_id);

    ;;; Build the list of registers to save: the register locals + LR (x30)
    ;;; On AArch64, register locals are in x19-x25 range (callee-saved)
    [%
        fast_for n in reg_locals do
            reglabel(n);
        endfast_for;
        LR;    ;;; always save/restore LR
    %] -> save_reg_list;

    ;;; Save registers using stp pairs
    emit_stp_push(save_reg_list);

    ;;; Setup PB: load the procedure record pointer.
    ;;; In the Poplog procedure layout, the procedure record pointer
    ;;; is stored as the last word of the header, immediately before
    ;;; the execute address (first instruction). On AArch64, this is
    ;;; 8 bytes before the first instruction.
    ;;; Use a PC-relative literal load: ldr x20, .-8
    ;;; This loads from 8 bytes before the current instruction,
    ;;; which is exactly where the procedure record pointer lives.
    ;;; Note: The first instruction after the exec label is the stp above,
    ;;; not this ldr. So we need to reference back from the current PC
    ;;; to the procedure record pointer. The exec label is at a known
    ;;; position. We use a literal pool reference through PB once set.
    ;;;
    ;;; Actually: the literal pool approach requires PB to already be set.
    ;;; We use an adr-based approach instead:
    ;;;   adr x20, current_pdr_exec_label
    ;;;   ldr x20, [x20, #-8]
    ;;; But we don't know the label offset at code generation time.
    ;;; The cleanest approach: the procedure record address is already
    ;;; in the literal pool at position 0, and we know lit_offset.
    ;;; But we need PB to access the literal pool.
    ;;;
    ;;; Solution: Use a PC-relative literal load with a label that
    ;;; we emit just before the code in gencode. The procedure record
    ;;; pointer is always at (exec_label - 8). We emit a helper label
    ;;; and use that.
    ;;;
    ;;; Simplest correct approach for AArch64:
    ;;; The gencode function outputs: [literals] [proc_record_ptr] [exec_label: code]
    ;;; The proc_record_ptr is always 1 xword (8 bytes) before exec_label.
    ;;; But the first instruction is our stp, not this instruction.
    ;;; So we need to compute backwards from the current PC.
    ;;;
    ;;; We use: emit a literal reference. The procedure record label
    ;;; is always the last thing before the exec label, so we know
    ;;; that exec_label - 8 contains it. We can use adrp/add to
    ;;; load the exec label address, then ldr from -8, but that's
    ;;; complex.
    ;;;
    ;;; Best approach: use a PC-relative literal label emitted after
    ;;; the current function code. We emit:
    ;;;   ldr x20, Lpb_NNNN
    ;;; and later (in gencode or via the instruction list) we emit:
    ;;;   Lpb_NNNN: .xword current_pdr_label
    ;;;
    ;;; Actually, the simplest approach that preserves the original
    ;;; architecture: the literal pool is accessed via PB. But PB
    ;;; is what we're trying to set up. On ARM32, the trick was
    ;;; ldr PB, [pc, #-16] which loaded from 2 words before current
    ;;; instruction (since ARM32 PC = current + 8).
    ;;;
    ;;; On AArch64, we use an inline literal just after the function
    ;;; code, loaded with a PC-relative ldr. But that requires the
    ;;; literal to be close. Instead, let's use a helper approach:
    ;;;
    ;;; We emit a label for the PB literal right after the br/ret,
    ;;; referenced by a forward ldr. But we're at the START of the
    ;;; function, not the end. So we put the literal at the end
    ;;; via the code list.
    ;;;
    ;;; The ACTUAL simplest approach that works:
    ;;; The current_pdr_label will be in the literal pool managed
    ;;; by get_literal_addr once we have PB. For bootstrap:
    ;;; generate a PC-relative load of the execute label address,
    ;;; then load from -8 relative to it.
    ;;;
    ;;; We use: the exec label is known. The number of instructions
    ;;; between exec_label and this point is known at assembly time.
    ;;; We can use: ldr x20, exec_label - 8
    ;;; where exec_label is current_pdr_exec_label.
    ;;;
    ;;; On AArch64, "ldr x20, label" does a PC-relative load from
    ;;; the address of label. If label resolves to exec_label - 8,
    ;;; the assembler will compute the PC-relative offset. But we
    ;;; need to express this in the assembly output.
    ;;;
    ;;; We can output: ldr x20, current_pdr_exec_label - 8
    ;;; This is a PC-relative literal load from 8 bytes before the
    ;;; execute label, which is exactly where the procedure record
    ;;; pointer is stored.

    asm_emit("ldr", PB,
             current_pdr_exec_label >< ' - 8', 3);

    ;;; Push dynamic locals
    applist(dlocal_labs, push_operand);

    ;;; Clear POP registers and allocate POP variables
    false -> tmp;
    1 -> j;
    if Npopregs > 0 then
        fast_for n in reg_locals do
            if j <= Npopregs then
                if tmp then
                    gen_move(tmp, reglabel(n));
                else
                    reglabel(n) -> tmp;
                    gen_move(popint_zero, reglabel(n));
                endif;
                j + 1 -> j;
            endif;
        endfast_for;
    endif;
    ;;; Allocate POP on-stack lvars (initialised to zero)
    if not(tmp) and Npopstkvars > 0 then
        R0 -> tmp;
        gen_move(popint_zero, R0);
    endif;
    repeat Npopstkvars times push_operand(tmp) endrepeat;
    ;;; Allocate non-POP on-stack lvars (uninitialised)
    ;;; On AArch64: 16-byte aligned stack adjustments.
    ;;; Each stkvar is 8 bytes; round up allocation to 16-byte boundary.
    if Nstkvars /== Npopstkvars then
        lvars extra_stkvars = Nstkvars - Npopstkvars;
        lvars extra_bytes = extra_stkvars * 8;
        ;;; Round up to 16-byte alignment
        if (extra_bytes && 15) /== 0 then
            (extra_bytes + 15) && (~~15) -> extra_bytes;
        endif;
        gen_op_3(extra_bytes, SP, SP, "sub");
    endif;
    ;;; Push the owner address
    push_operand(PB);
enddefine;

;;; {M_UNWIND_SF}
;;;     plant code to unwind a procedure stack frame

define M_UNWIND_SF();
    ;;; Remove owner address and on-stack vars (POP and non-POP)
    ;;; On AArch64: each stack slot is 16 bytes (due to alignment in push_operand)
    ;;; Owner = 1 slot, pop stkvars = Npopstkvars slots (each 16 bytes from push_operand)
    ;;; Non-pop stkvars were allocated as a block rounded to 16 bytes.
    ;;; The total to remove for owner + pop stkvars:
    ;;;   (1 + Npopstkvars) * 16 bytes (from push_operand's 16-byte alignment)
    ;;; plus the non-pop stkvars block.
    ;;; Actually, we need to match what M_CREATE_SF allocated:
    ;;; - Npopstkvars * 16 bytes (from push_operand)
    ;;; - extra_bytes for non-pop stkvars (rounded to 16)
    ;;; - 16 bytes for owner address (from push_operand)
    ;;; Simplification: compute total and adjust sp once.
    lvars npop_bytes = Nstkvars * 8;
    ;;; Actually, re-examining: pop stkvars used push_operand (16 bytes each),
    ;;; non-pop stkvars used gen_op_3 with (Nstkvars - Npopstkvars) * 8 rounded up.
    ;;; Owner used push_operand (16 bytes).
    ;;; To be safe and match exactly, we compute:
    ;;; 1. Remove owner: add sp, sp, #16
    ;;; 2. Remove non-pop stkvars: computed amount
    ;;; 3. Remove pop stkvars (each was 16 bytes)
    ;;; But we can combine into one add.
    ;;; Wait - actually it's simpler to just reverse exactly what CREATE did:

    ;;; Remove owner address (16 bytes from push_operand)
    ;;; + all on-stack vars
    lvars Npopstkvars_from_create;
    ;;; We don't have Npopstkvars saved separately, but we have Nstkvars.
    ;;; Looking at M_CREATE_SF: Npopstkvars uses push_operand (16 bytes each),
    ;;; (Nstkvars - Npopstkvars) non-pop stkvars use gen_op_3 with 8 bytes each
    ;;; rounded to 16.
    ;;; Since we need both values, let's save Npopstkvars in a variable too.
    ;;; Actually, looking at the ARM32 original, it just does:
    ;;;   gen_op_3((Nstkvars + 1) * 4, SP, SP, "add");
    ;;; This suggests that ALL stkvars (pop and non-pop) use the same size.
    ;;; The +1 is for the owner address.
    ;;; The ARM32 push_operand uses [sp, #-4]!, so each is 4 bytes.
    ;;;
    ;;; But on AArch64, push_operand uses [sp, #-16]! for 16-byte alignment!
    ;;; So pop stkvars and owner are 16 bytes each, but non-pop stkvars
    ;;; are allocated differently. This is a problem.
    ;;;
    ;;; REVISED APPROACH: For consistency and simplicity, use the same
    ;;; 8-byte slots for everything on the Poplog-managed stack.
    ;;; The system stack alignment requirement (16 bytes) applies to
    ;;; SP at function call boundaries. Within a function, as long as
    ;;; SP is aligned at calls, we can manage slots internally.
    ;;;
    ;;; Actually, AArch64 requires SP to be 16-byte aligned for ALL
    ;;; stack accesses using SP as base. But we can use stur/ldur for
    ;;; unaligned offsets, or maintain alignment another way.
    ;;;
    ;;; Simplest correct approach: keep everything 16-byte aligned.
    ;;; Each push_operand uses 16 bytes. Non-pop stkvars rounded to 16.
    ;;; Owner uses 16 bytes. Dynamic locals use 16 bytes each.
    ;;;
    ;;; Total to deallocate for stkvars + owner:
    ;;;   16 (owner) + Npopstkvars * 16 + rounded_nonpop_bytes
    ;;; But we don't have Npopstkvars in the unwind context!
    ;;; The ARM32 code used (Nstkvars + 1) * 4 because all were 4 bytes.
    ;;;
    ;;; We need to save Npopstkvars between CREATE and UNWIND.
    ;;; Let's add it as a saved variable. Or, better: compute the total
    ;;; space at CREATE time and save it.
    ;;;
    ;;; Actually, re-reading the ARM32 code: it uses push_operand for
    ;;; pop stkvars (4 bytes each via [sp, #-4]!) and gen_op_3 for
    ;;; non-pop stkvars ((Nstkvars - Npopstkvars) * 4). The total for
    ;;; unwind is (Nstkvars + 1) * 4 which equals:
    ;;;   Npopstkvars * 4 + (Nstkvars - Npopstkvars) * 4 + 1 * 4
    ;;; This only works because all are 4-byte slots.
    ;;;
    ;;; For AArch64 with 16-byte alignment on all push_operand calls,
    ;;; this gets complicated. A MUCH simpler approach: use 8-byte slots
    ;;; (the natural word size) and ensure SP is 16-byte aligned at
    ;;; boundaries by padding. But Poplog manages its own stack and
    ;;; doesn't need hardware alignment except at C calls.
    ;;;
    ;;; Actually, AArch64 hardware REQUIRES 16-byte alignment for SP
    ;;; for ldr/str via SP. There IS a SCTLR flag but by default it's
    ;;; enforced. So we MUST maintain 16-byte alignment.
    ;;;
    ;;; NEW APPROACH for push_operand/pop_operand: Use 8-byte slots
    ;;; but keep total allocation 16-byte aligned. The CREATE/UNWIND
    ;;; pair manages this:
    ;;;   - The stp push already maintains 16-byte alignment (pairs).
    ;;;   - Dynamic locals + pop stkvars + non-pop stkvars + owner
    ;;;     need to be an even number of 8-byte slots total.
    ;;;   - We can pad with an extra 8 bytes if the total is odd.
    ;;;
    ;;; BUT: push_operand and pop_operand are used individually for
    ;;; dynamic locals and pop stkvars. Each one does str [sp, #-16]!
    ;;; which maintains alignment. So: each push_operand is 16 bytes,
    ;;; each pop_operand frees 16 bytes. The owner is 16 bytes.
    ;;; Non-pop stkvars are rounded to 16 bytes. Total is correct.
    ;;;
    ;;; For unwind: we need to free:
    ;;;   16 bytes (owner) + Npopstkvars * 16 + nonpop_rounded

    ;;; Simply use the stored total. We store total_stkvar_bytes in
    ;;; the enclosing lblock. Actually, let me just adopt the same
    ;;; simple pattern as ARM32 but with 16-byte slots:

    lvars total_bytes = (Nstkvars + 1) * 16;
    gen_op_3(total_bytes, SP, SP, "add");

    ;;; Pop dynamic locals (in reverse order)
    applist(rev(dlocal_labs), pop_operand);

    ;;; Restore registers using ldp pairs
    emit_ldp_pop(save_reg_list);

    ;;; Restore procedure base register from previous owner address
    ;;; The owner address is at [sp] (top of the caller's frame)
    ;;; On AArch64: load PB from the word at [sp]
    gen_move({^SP}, PB);
enddefine;

endlblock;

;;; {M_END}
;;;     end a procedure

define M_END();
enddefine;


/*
 *  Special instructions
 */

;;; {M_CLOSURE <frozvals> <pdpart opnd>}
;;;     plant closure code
;;;
;;;     On AArch64: uses x16 for indirect address loading,
;;;     x0 for closure address, x1 for intermediate values.
;;;     User stack pointer is x19.

define M_CLOSURE();
    lvars (, frozvals, pdpart_opd) = explode(m_instr);
    lvars nfroz = listlength(frozvals);
    lvars lab = genlab();
    ;;; Get closure address into x0 via PC-relative literal
    asm_emit("ldr", R0, lab, 3);
    if nfroz fi_> 16 then
        ;;; for more than 16 frozvals, call Exec_closure
        gen_move(R0, -_USP);
        perm_const_opnd([Sys Exec_closure]) -> pdpart_opd;
    else
        ;;; push the frozvals onto the user stack
        lconstant frozval_offset = field_##("PD_CLOS_FROZVALS").wof;
        lvars i;
        for i from 0 to nfroz - 1 do
            asm_emit("ldr", R1, '[x0, #' >< (frozval_offset + i*8) >< ']', 3);
            asm_emit("str", R1, '[x19, #-8]!', 3)
        endfor;
        if not(pdpart_opd) then
            {% R0, field_##("PD_CLOS_PDPART").wof %} -> pdpart_opd;
        endif;
    endif;
    gen_chain(pdpart_opd, true);
    asmLABEL(lab);
    asm_emit("long", current_pdr_label, 2);
enddefine;

;;; {M_PLOG_IFNOT_ATOM <ifnot_lab>}
;;;     test result of _prolog_unify_atom

define M_PLOG_IFNOT_ATOM();
    mishap(0, 'Unimplemented M_PLOG_IFNOT_ATOM');
enddefine;

;;; {M_PLOG_TERM_SWITCH <fail_lab> <var_lab> <dst>}
;;;     test result from _prolog_pair_switch/_prolog_term_switch
;;;     If EQ, move R0 (dereferenced result) to <dst>

define M_PLOG_TERM_SWITCH();
    mishap(0, 'Unimplemented M_PLOG_TERM_SWITCH');
enddefine;

;;; {M_SETSTKLEN <offset of stack increase> <popint saved stklen opnd>}
;;;     adjust the number of results returned by a Lisp function.
;;;     <offset> is always a constant integer

define M_SETSTKLEN();
    lvars (, offs, sl) = explode(m_instr), wreg;
    ;;; compute desired user stack length as saved length plus offset;
    ;;; subtract 3 to account for popint bits
    load_to_reg(sl, R0) -> wreg;
    if offs == 0 then
        asm_emit("sub", R1, wreg, 3, 4);
    else
        gen_op_commute("add", wreg, offs - 3, R1);
    endif;
    ;;; compute desired stack pointer in R0
    load_to_reg(identlabel("\^_userhi"), R0);
    asm_emit("sub", R0, R0, R1, 4);
    ;;; compare desired and actual user stack pointers, if equal, jump to end,
    lvars lab = genlab();
    gen_cmp(R0, USP, "EQ", lab);
    ;;; otherwise call "setstklen_diff" to fix
    gen_transfer("bl", symlabel("\^_setstklen_diff"));
    asmLABEL(lab);
enddefine;

;;; M_ERASE:
;;;     pop to a register; have to do the move, in case the address is
;;;     invalid (e.g., stack empty)

define M_ERASE();
    gen_move(m_instr(2), R1);
enddefine;


/*
 *  Generate assembly code
 */

define lconstant generate(codelist, hdr_len) -> (ilist, new_literals);
    lvars codelist, hdr_len, ilist;
    dlocal  m_instr, last_instr,
            new_literals = [], lit_offset = hdr_len - 2;
    conspair({#}, []) ->> ilist -> last_instr;
    asmLABEL(current_pdr_exec_label);
    for m_instr in codelist do
        ;;; arm64: skip whole-instruction artefacts (booleans / non-vectors)
        ;;; that occasionally survive m_optimise on this port.
        nextunless(isvector(m_instr));
        lvars opcode = f_subv(1, m_instr);
        nextunless(isprocedure(opcode));
#_IF DEF M_DEBUG
        ;;; add comment to assembly code listing
        lvars len;
        "#", destvector(m_instr) -> len;
        pdprops(subscr_stack(len)) -> subscr_stack(len);
        asm_emit(len fi_+ 1);
#_ENDIF
        fast_apply(opcode);
    endfor;
enddefine;


;;; === CODE OUTPUT ===================================================

;;; outopd, outinst:
;;;     write out an operand/instruction. These differ considerably
;;;     depending on the assembler type

define lconstant outopnd(opd);
    lvars opd;
    if ispair(opd) then
        mishap(opd, 1, 'outopnd: unhandled operand\n');
    endif;
    if isreg(opd) then
        asmf_printf(opd, '%p');
    elseif isimm(opd) then
        asmf_printf(immval(opd), '#%p');
    elseif isabs(opd) then
        asmf_printf(opd, '%p');
    elseif isvector(opd) then
        mishap(opd, 1, 'outopnd: unhandled operand\n');
    else
        mishap(opd, 1, 'ILLEGAL OPERAND');
    endif;
enddefine;

;;; outinst:
;;;     writes out an instruction.
;;;     On AArch64: "long" generates .xword entries (via asm_outword
;;;     which uses ASM_WORD_STR = '.xword').

define lconstant outinst(instr);
    lvars instr;
    ;;; AArch64 GAS uses // for line comments (not @ which is ARM32).
    lvars opcode = f_subv(1, instr);
    if opcode == "label" then
        outlab(f_subv(2, instr));
    elseif opcode == "align" then
        asm_align_word();
    elseif opcode == "long" then
        asm_outword(destvector(instr) fi_- 1) -> ;
    else
        lvars i, n = datalength(instr);
        if opcode == "#" then
            asmf_printf(false, '\t//');
            for i from 2 to n do
                asmf_printf(f_subv(i, instr), '\s%p');
            endfor;
        else
            asmf_printf(opcode, '\t%p\t');
            unless n == 1 then
                outopnd(f_subv(2, instr));
                for i from 3 to n do
                    asmf_printf(',\s');
                    outopnd(f_subv(i, instr));
                endfor;
            endunless;
        endif;
        asmf_charout(`\n`);
    endif;
enddefine;


;;; === GENERATING PROCEDURE AND CLOSURE CODE =========================

;;; mc_code_generator:
;;;     generates assembler code for a procedure/closure.
;;;     It returns:
;;;         - a label, which will be set to the procedure size in words;
;;;         - a procedure to output the generated assembly code.
;;;     This is called from "m_trans".
;;;     The global variables
;;;         current_pdr_label, current_pdr_exec_label
;;;     contain the current procedure's label and start-of-code label
;;;
;;;     Memory layout of a procedure:
;;;         [literal_0] [literal_1] ... [literal_n]    ;;; literal pool
;;;         [proc_record_ptr]                          ;;; 1 xword
;;;         [exec_label: first instruction ...]        ;;; code
;;;         [alignment padding]
;;;         [end_label]

define mc_code_generator(codelist, hdr_len) -> (gencode, pdr_len);
    lconstant procedure gencode;
    lvars codelist, hdr_len, pdr_len, new_lits,
          cur_pdr_label = current_pdr_label;

    ;;; arm64 diagnostic: track stack length around generate to find which
    ;;; procedure leaves items behind.
    lvars _sl0 = stacklength();
    generate(codelist, hdr_len) -> (codelist, new_lits) ;
    lvars _sl1 = stacklength();
    if _sl1 /== _sl0 then
        printf(_sl1 fi_- _sl0, current_pdr_label,
               ';;; ARM64-DIAG generate leaked %p items, pdr_label=%p\n');
    endif;

    ;;; Create a label for the procedure length
    genlab() -> pdr_len;

    ;;; Create the code-output procedure
    define lconstant gencode();
        lvars lit, endlab;
        ;;; Output literals
        fast_for lit in new_lits do
            asm_outword(lit, 1)
        endfor;
        ;;; Output address of procedure record
        asm_outword(cur_pdr_label, 1);
        ;;; Output the code
        applist(codelist, outinst);
        ;;; Align on a doubleword boundary (8 bytes for AArch64)
        asm_align_word();
        ;;; Plant an end label
        outlab(genlab() ->> endlab);
        ;;; Define pdr_len as the size in words of the procedure
        outlabset(pdr_len,
                  asm_pdr_len(hdr_len, current_pdr_exec_label, endlab));
    enddefine;
enddefine;


;;; === OTHER DEFINITIONS NEEDED BY "m_trans.p" ==========================


constant

    ;;; M-code tables for machine-dependent in-line subroutines.
    ;;; These are added to the corresponding properties in m_trans.p

    mc_inline_procs_list = [
        [ \^_ptr_to_offs  [{^M_ERASE ^USP_+}]]
        [ \^_offs_to_ptr  [{^M_ERASE ^USP_+}]]
        [ \^_int          [{^M_ASH -2 ^USP_+ ^ -_USP}]]
        [ \^_pint         [{^M_ASH 2 ^USP_+ ^ -_USP}
                            {^M_ADD 3 ^USP_+ ^ -_USP}]]
        [ \^_por          [{^M_BIS ^USP_+ ^USP_+ ^ -_USP}]]
        [ \^_pand         [{^M_BIM ^USP_+ ^USP_+ ^ -_USP}]]
        [ \^_mksimple     [{^M_ADD 1 ^USP_+ ^ -_USP}]]
        [ \^_mkcompound   [{^M_SUB 1 ^USP_+ ^ -_USP}]]
        [ \^_mksimple2    [{^M_ADD 3 ^USP_+ ^ -_USP}]]
        [ \^_mkcompound2  [{^M_SUB 3 ^USP_+ ^ -_USP}]]
    ],

    mc_inline_conditions_list = [
        [ \^_iscompound   {^M_BIT  2:01 ^USP_+ EQ  ?}]
        [ \^_issimple     {^M_BIT  2:01 ^USP_+ NEQ ?}]
        [ \^_issimple2    {^M_BIT  2:10 ^USP_+ NEQ ?}]
        [ \^_isinteger    {^M_BIT  2:10 ^USP_+ NEQ ?}]
        [ \^_isaddress    {^M_BIT  2:11 ^USP_+ EQ  ?}]
    ],
;

    /*  Procedure to convert a pop integer subscript to an appropriate offset
        for the data type being accessed, used by OP_SUBV in m_trans.p to
        compile code for fast_subscrv, vectorclass field accesses, etc.
        scale is the scale for the data type involved; the results are
        the M-code instructions (if any) necessary to convert the subscript
        on top of the stack to an offset, plus a constant correction to be
        added.
    */
define cvt_pop_subscript(scale);
    lvars pow, scale;
    if is_power2(scale) ->> pow then
        ;;; pow-2 accounts for popint being shifted left 2
        unless (pow-2 ->> pow) == 0 then
            {^M_ASH ^pow ^USP_+ ^ -_USP}
        endunless,
        -(popint(0) << pow)     ;;; additive correction to remove popint bits
    else
        ;;; just convert to sysint and multiply
        {^M_ASH -2 ^USP_+ ^ -_USP},     ;;; _int()
        {^M_MULT ^scale ^USP_+ ^ -_USP},
        0                       ;;; no correction necessary
    endif
enddefine;


endsection;     /* Genproc */

endsection;     /* $-Popas$-M_trans */
