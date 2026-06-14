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
   RISC-V (rv64gc / LP64D) register assignments for Poplog.  ABI name in
   parentheses; we emit the xN form.

   x0  (zero) - hardwired zero            x1  (ra)  - LR (return address)
   x2  (sp)   - SP (control stack)        x3  (gp)  - reserved (global ptr)
   x4  (tp)   - reserved (thread ptr)     x5  (t0)  - WK_ADDR_REG_1
   x6  (t1)   - WK_ADDR_REG_2             x7  (t2)  - scratch (R4)
   x8  (s0/fp)- (unused; frame ptr if needed)
   x9  (s1)   - USP (user stack ptr, callee-saved)
   x10 (a0)   - WK_REG/work/arg_reg_0     x11 (a1)  - work/arg_reg_1
   x12 (a2)   - CHAIN_REG/arg_reg_2       x13-x17 (a3-a7) - args/scratch
   x18 (s2)   - PB  (procedure base, callee-saved)
   x19 (s3)   - pop register local        x20 (s4)  - pop register local
   x21 (s5)   - nonpop register local     x22 (s6)  - nonpop register local
   x23 (s7)   - nonpop register local     x24-x27 (s8-s11) - callee-saved spare
   x28 (t3)   - secondary work reg (R5)   x29 (t4)  - scratch (R9)
   x30 (t5)   - scratch for indirect branches   x31 (t6) - scratch

   Key differences from AArch64 (the port's reference backend):
   - Return address is in x1/ra (saved into the frame), like arm64's x30/LR.
   - No condition-codes register: compare two registers and branch in one
     instruction (beq/bne/blt/bge/bltu/bgeu) -- no cmp + b.cond.
   - No auto-index addressing: a user-stack push [USP,#-8]! / pop [USP],#8
     becomes two instructions (addi + sd / ld + addi).
   - Load/store syntax is off(reg), not [reg,#off]; ld/sd (8-byte), lw/sw,
     lh/sh, lb/sb -- no separate 32-bit W register views.
   - PC-relative addressing via auipc + %pcrel_hi/_lo (and the la/lla, call,
     li, mv pseudo-ops).
   - 12-bit signed immediates; larger need lui/li expansion.
*/

lconstant

    ;;; RISC-V (LP64D) register names and their Poplog usage.  Roles are the
    ;;; same as the arm64 backend; only the physical register differs.  We emit
    ;;; xN names (riscv64-as accepts both xN and the ABI names).  ABI name in
    ;;; the comment.  See PORTING-RISCV64-LINUX.md "P3 transformation map".

    R0 = "x10",   ;;; a0  - WK_REG/work reg/arg_reg_0
    R1 = "x11",   ;;; a1  - principal work reg/arg_reg_1
    R2 = "x12",   ;;; a2  - CHAIN_REG/arg_reg_2
    R3 = "x5",    ;;; t0  - WK_ADDR_REG_1
    R4 = "x7",    ;;; t2  - scratch
    R5 = "x28",   ;;; t3  - secondary work reg
    R9  = "x29",  ;;; t4  - scratch
    R10 = "x9",   ;;; s1  - USP (callee-saved)
    R11 = "x18",  ;;; s2  - PB  (callee-saved)
    R12 = "x6",   ;;; t1  - WK_ADDR_REG_2 (caller-saved scratch)
    R13 = "x2",   ;;; sp  - SP (control stack)
    LR = "x1",    ;;; ra  - link register (return address)
    R16 = "x30",  ;;; t5  - scratch for indirect branches (was arm64 IP0/x16)
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
    ;;; RISC-V: pop regs are x19, x20 (s3, s4, callee-saved)
    ;;;         nonpop regs are x21, x22, x23 (s5, s6, s7, callee-saved)

    pop_registers = [[] 19 20],
    ;;; pop_registers = [[]],
    nonpop_registers = [[] 21 22 23],
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
        ;;; RISC-V: 32 integer registers x0..x31, all usable here (none is
        ;;; "platform-reserved" the way arm64's x18 was -- x0/zero, x1/ra,
        ;;; x2/sp, x3/gp, x4/tp are simply assigned roles, not skipped).  No
        ;;; 32-bit register sub-views exist, so no wN names.
        for n from 0 to 31 do
                consword('x' >< n) -> l;
                n -> regnumber(l);
                l -> reglabel(n);
        endfor;
        ;;; ABI-name aliases so hand-written references resolve (canonical
        ;;; reglabel stays "xN", which is what we emit).
        2 -> regnumber("sp");           ;;; x2
        1 -> regnumber("ra");           ;;; x1
        1 -> regnumber("lr");           ;;; alias ra as lr
        0 -> regnumber("zero");         ;;; x0
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
;;;     on RISC-V (any x-register can be a base register).

identof("regnumber") -> identof("autoidreg");

;;; as_wreg:
;;;     On arm64 this mapped an X-register to its 32-bit W view for byte/half
;;;     ops.  RISC-V has no separate 32-bit register names -- byte/half/word
;;;     loads and stores (lb/lh/lw, sb/sh/sw) use the full register -- so this
;;;     is the identity, kept so existing call sites stay valid.

define lconstant as_wreg(reg) -> wreg;
    lvars reg, wreg;
    reg -> wreg;
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
    ;;; fits a RISC-V signed 12-bit immediate / load-store offset (-2048..2047).
    ;;; Use a symmetric (-2047..2047) range so the negated form (sub -> addi
    ;;; with -imm) also fits.
    lvars disp;
    isinteger(disp) and disp > -2048 and disp < 2048;
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
;;;     returns a RISC-V memory operand "off(PB)" for accessing a literal from
;;;     the procedure's literal pool via PB.  Each literal is 8 bytes, so
;;;     offset = 8*(disp + lit_offset).
;;;     (TODO: literal pools larger than 4 KB exceed the 12-bit ld offset and
;;;     will need an auipc/add fixup; small pools are fine for now.)

define lconstant get_literal_addr(lit);
    lvars lit, disp, tmp;
    position_or_add(lit, new_literals) -> (disp, new_literals);
    return((8*(disp + lit_offset)) >< '(' >< PB >< ')');
enddefine;

define lconstant load_literal(lit, tmp);
    lvars lit, tmp;
    asm_emit("ld", tmp, get_literal_addr(lit), 3);
enddefine;

;;; get_addressable_op:
;;;     converts an M-code operand into a form suitable for use as an
;;;     AArch64 memory operand (an addressing mode string), loading
;;;     intermediate values into tmp if necessary.

define lconstant get_addressable_op(opd, tmp);
    lvars opd, disp, opd1, type;
    returnif(isreg(opd))('0(' >< opd >< ')');   ;;; bare reg base -> 0(reg)
    if isvector(opd) then
        if datalength(opd) = 1 then
            return('0(' >< f_subv(1, opd) >< ')');
        elseif datalength(opd) >= 2 then
            f_subv(2, opd) -> disp;
            f_subv(1, opd) -> opd1;
            if isboolean(disp) then
                ;;; Auto-index (USP push/pop): not a single RISC-V memory
                ;;; operand -- emit the explicit pointer bump here.
                ;;;   disp == false -> push (pre-decrement): decrement the base
                ;;;     and return 0(base); the caller's store writes the new top.
                ;;;   disp == true  -> pop (post-increment): the access must read
                ;;;     the CURRENT top and only then advance.  Save the current
                ;;;     pointer in a scratch (R16), advance the base, and return
                ;;;     0(scratch) so the caller's access uses the pre-bump top.
                lvars size = 8;
                if datalength(opd) == 3 then
                    f_subv(3, opd) && t_BASE_TYPE -> type;
                    if type == t_INT then 4 elseif type == t_SHORT then 2
                    elseif type == t_BYTE then 1 else mishap(opd,1,'type') endif
                        -> size;
                endif;
                if disp then
                    asm_emit("mv", R16, opd1, 3);          ;;; save current top
                    asm_emit("addi", opd1, opd1, size, 4); ;;; advance (post-inc)
                    return('0(' >< R16 >< ')');
                else
                    asm_emit("addi", opd1, opd1, -size, 4);  ;;; push: pre-decrement
                    return('0(' >< opd1 >< ')');
                endif;
            elseif disp == 0 then
                return('0(' >< opd1 >< ')');
            elseif is_small_disp(disp) then
                return(disp >< '(' >< opd1 >< ')');
            elseif isinteger(disp) then
                ;;; displacement too large for the 12-bit ld/sd offset:
                ;;; materialise base+disp in a scratch register.
                load_literal(disp, R16);
                asm_emit("add", R16, opd1, R16, 4);
                return('0(' >< R16 >< ')');
            else
                mishap(opd, 1, 'Unhandled operand in get_addressable_op');
            endif;
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
        return('0(' >< tmp >< ')');
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
    lvars opd, tmp, opd1, opcode, type, rawtype, base, size;
    ;;; sp (x2) is a normal register on RISC-V -- usable directly -- so no
    ;;; arm64-style "move sp out first" special case is needed.
    returnif(isreg(opd))(opd);
    if isinteger(opd) or isbiginteger(opd) then
        if is_small_disp(opd) then
            ;;; li handles the lui/addi expansion for any 32-bit immediate
            asm_emit("li", tmp, opd, 3);
            return(tmp);
        else
            load_literal(opd, tmp);
            return(tmp);
        endif;
    endif;
    ;;; Auto-index pop (post-increment): load from 0(base), then bump base.  The
    ;;; LOAD WIDTH must match the operand type (a typed `ptr!(b)++` reads ONE
    ;;; byte, not a word) -- size alone is not enough; the load opcode too.
    if isvector(opd) and datalength(opd) fi_>= 2 and isboolean(f_subv(2, opd)) then
        f_subv(1, opd) -> base;
        8 -> size;
        "ld" -> opcode;
        if datalength(opd) == 3 then
            f_subv(3, opd) -> rawtype;
            rawtype && t_BASE_TYPE -> type;
            if type == t_INT then
                4 -> size;
                if (rawtype && tv_SIGNED) /== 0 then "lw" else "lwu" endif -> opcode
            elseif type == t_SHORT then
                2 -> size;
                if (rawtype && tv_SIGNED) /== 0 then "lh" else "lhu" endif -> opcode
            elseif type == t_BYTE then
                1 -> size;
                if (rawtype && tv_SIGNED) /== 0 then "lb" else "lbu" endif -> opcode
            else mishap(opd, 1, 'type')
            endif;
        endif;
        asm_emit(opcode, tmp, '0(' >< base >< ')', 3);
        asm_emit("addi", base, base, size, 4);
        return(tmp);
    endif;
    get_addressable_op(opd, tmp) -> opd1;
    "ld" -> opcode;
    if isvector(opd) and datalength(opd) == 3 then
        f_subv(3, opd) -> rawtype;
        rawtype && t_BASE_TYPE -> type;
        ;;; RISC-V loads extend into the 64-bit register directly: lw/lh/lb
        ;;; sign-extend, lwu/lhu/lbu zero-extend -- no separate sxt fixup, and
        ;;; no 32-bit register sub-view.  (ld = full 8-byte word.)
        if type == t_INT then
            if (rawtype && tv_SIGNED) /== 0 then "lw" else "lwu" endif
        elseif type == t_SHORT then
            if (rawtype && tv_SIGNED) /== 0 then "lh" else "lhu" endif
        elseif type == t_BYTE then
            if (rawtype && tv_SIGNED) /== 0 then "lb" else "lbu" endif
        else
            mishap(opd, 1, 'Unhandled operand type');
        endif -> opcode;
    endif;
    asm_emit(opcode, tmp, opd1, 3);
    return(tmp);
enddefine;

;;; gen_reg_store:
;;;     stores a register value to a destination operand.
;;;     On AArch64: use str/strh/strb as appropriate for the type.

define lconstant gen_reg_store(src, dst, tmp);
    lvars src, dst, tmp, dst1, type, opcode = "sd";
    get_addressable_op(dst, tmp) -> dst1;
    if isvector(dst) and datalength(dst) == 3 then
        f_subv(3, dst) && t_BASE_TYPE -> type;
        ;;; RISC-V stores the low N bits directly: sw/sh/sb -- no W-register
        ;;; form and no overrun (a t_INT field is a genuine 32-bit store).
        if type == t_INT then "sw"
        elseif type == t_SHORT then "sh"
        elseif type == t_BYTE then "sb"
        else mishap(dst, 1, 'Unhandled operand type')
        endif -> opcode;
    endif;
    asm_emit(opcode, src, dst1, 3);
enddefine;

;;; push_operand / pop_operand:
;;;     Push/pop a value on/from the system stack.
;;;     On AArch64: must maintain 16-byte stack alignment.
;;;     We use sub sp, sp, #16 + str at [sp] for push,
;;;     and ldr from [sp] + add sp, sp, #16 for pop.

define lconstant push_operand(opd);
    lvars opd;
    load_to_reg(opd, R1) -> opd;
    ;;; push to the control stack (16-byte slot): pre-decrement then store
    asm_emit("addi", "sp", "sp", -16, 4);
    asm_emit("sd", opd, '0(sp)', 3);
enddefine;

define lconstant pop_operand(opd);
    lvars opd, reg;
    if isreg(opd) then opd else R1 endif -> reg;
    ;;; pop from the control stack: load then post-increment
    asm_emit("ld", reg, '0(sp)', 3);
    asm_emit("addi", "sp", "sp", 16, 4);
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
;;;     Plant an UNCONDITIONAL branch.  RISC-V uses "j label".  (Conditional
;;;     branches no longer come through here: gen_test_or_cmp plants a single
;;;     compare-and-branch, since RISC-V has no condition-codes register.)

define lconstant gen_branch(opcode, lab);
    lvars opcode, lab;
    get_jump_addr(lab) -> lab;
    if opcode == "b" then
        asm_emit("j", lab, 2);
    else
        asm_emit(opcode, lab, 2);   ;;; residual b.cond -- fixed at its call site
    endif;
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
    ;;; Map AArch64 mnemonics to RISC-V base names.
    if     opcode == "orr" then "or"  -> opcode
    elseif opcode == "eor" then "xor" -> opcode
    endif;
    ;;; destination register
    if isreg(dst) then dst -> dreg; false -> dst else R1 -> dreg endif;
    ;;; Poplog M-op convention: dst = src2 OP src1 (cf. M_PADD "dest = src2 +
    ;;; src1"), exactly as arm64's get_operands_r swap.  For the commutative ops
    ;;; (add/and/or/xor) src2 OP src1 == src1 OP src2, but sub/bic must subtract
    ;;; in the right order.
    if opcode == "sub" then
        ;;; dst = src2 - src1
        if (isinteger(src1) or isbiginteger(src1)) and is_small_disp(src1) then
            ;;; src2 - imm  ->  addi dst, src2, -imm
            load_to_reg(src2, R1) -> op2;
            asm_emit("addi", dreg, op2, negate(src1), 4);
        else
            load_to_reg(src1, R1) -> op1;
            load_to_reg(src2, R5) -> op2;
            asm_emit("sub", dreg, op2, op1, 4);
        endif;
    elseif opcode == "bic" then
        ;;; dst = src2 & ~src1  (RISC-V base has no and-not: not + and)
        load_to_reg(src1, R1) -> op1;
        load_to_reg(src2, R5) -> op2;
        asm_emit("not", R16, op1, 3);     ;;; not = xori rd,rs,-1 (pseudo)
        asm_emit("and", dreg, op2, R16, 4);
    else
        ;;; commutative op: load src1, then immediate or register form.
        load_to_reg(src1, R1) -> op1;
        if (isinteger(src2) or isbiginteger(src2)) and is_small_disp(src2) then
            lvars imm = src2;
            if     opcode == "add" then asm_emit("addi", dreg, op1, imm, 4)
            elseif opcode == "and" then asm_emit("andi", dreg, op1, imm, 4)
            elseif opcode == "or"  then asm_emit("ori",  dreg, op1, imm, 4)
            elseif opcode == "xor" then asm_emit("xori", dreg, op1, imm, 4)
            else
                load_to_reg(src2, R5) -> op2;
                asm_emit(opcode, dreg, op1, op2, 4);
            endif;
        else
            load_to_reg(src2, R5) -> op2;
            asm_emit(opcode, dreg, op1, op2, 4);
        endif;
    endif;
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
        ;;; Stage the detagged src1 in R4 (a dead scratch), NOT R5: gen_op_3's
        ;;; sub/bic else-path loads op2 into R5, and load_to_reg(reg,..) returns an
        ;;; already-resident register as-is -- so detagging into R5 makes op1 alias
        ;;; op2 and the result collapses to "src2 - src2 = 0".
        load_to_reg(src1, R4) -> src1;
        asm_emit("addi", R4, src1, -3, 4);
        R4 -> src1;
    endif;
    gen_op_3(src1, src2, dst, opcode);
enddefine;

;;; m_parith_test: opcode is "adds"/"subs" -- the overflow-CHECKED POP-int add /
;;; subtract.  arm64 set the V flag with adds/subs and branched b.vs/b.vc.
;;; RISC-V has no overflow flag, so we compute the 64-bit signed-overflow bit by
;;; hand (the same condition the V flag encodes), push the result, then branch on
;;; OVF/NOVF.  For r = a <op> b the signed overflow is:
;;;     add:  (r < a) XOR (b < 0)        sub:  (a < r) XOR (b < 0)
;;; (clearing src1's POP-int tag first, exactly as the non-test path does).
define lconstant m_parith_test(opcode);
    lvars (, src1, src2, test, lab) = explode(m_instr);
    lvars baseop = if opcode == "subs" then "sub" else "add" endif;
    ;;; a = src1 with the POP-int tag cleared, in R1
    if isintegral(src1) then
        asm_emit("li", R1, src1 - 3, 3);
    else
        load_to_reg(src1, R1) -> src1;
        asm_emit("addi", R1, src1, -3, 4);
    endif;
    ;;; b = src2 (tagged) in R5
    load_to_reg(src2, R5) -> src2;
    ;;; r = a <baseop> b in R12
    asm_emit(baseop, R12, R1, R5, 4);
    ;;; signed-overflow bit -> R16
    if baseop == "sub" then
        asm_emit("slt", R16, R1, R12, 4)          ;;; a < r
    else
        asm_emit("slt", R16, R12, R1, 4)          ;;; r < a
    endif;
    asm_emit("slti", R5, R5, 0, 4);               ;;; (b < 0); b now dead
    asm_emit("xor", R16, R16, R5, 4);             ;;; R16 = overflow (0/1)
    ;;; push the result on the user stack (R1 is free again -- not used by a push)
    gen_reg_store(R12, -_USP, R1);
    ;;; OVF -> branch when set; NOVF -> branch when clear
    asm_emit(if test == "OVF" then "bne" else "beq" endif,
             R16, "x0", get_jump_addr(lab), 4);
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
            asm_emit("li", dreg, 0, 3);
        else
            if src1 < 0 then
                ;;; arithmetic shift right by immediate
                asm_emit("srai", dreg, src2, -src1, 4);
            elseif src1 == 0 then
                unless dreg = src2 then
                    asm_emit("mv", dreg, src2, 3);
                endunless;
            else
                ;;; logical shift left by immediate
                asm_emit("slli", dreg, src2, src1, 4);
            endif;
        endif;
    else
        ;;; Variable shift amount: sign-test, then left or (negated) right shift
        load_to_reg(src1, R5) -> src1;
        load_to_reg(src2, R1) -> src2;
        lvars neg_lab = genlab();
        lvars done_lab = genlab();
        asm_emit("blt", src1, "x0", neg_lab, 4);   ;;; src1 < 0 -> right shift
        ;;; Positive or zero: left shift
        asm_emit("sll", dreg, src2, src1, 4);
        asm_emit("j", done_lab, 2);
        ;;; Negative: right shift by the negated amount
        asmLABEL(neg_lab);
        asm_emit("neg", R5, src1, 3);              ;;; neg = sub rd,x0,rs (pseudo)
        asm_emit("sra", dreg, src2, R5, 4);
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

;;; rv_cond:
;;;     maps an M-code test code to a RISC-V compare-and-branch mnemonic for
;;;     "branch if (op1 <test> op2)", plus a flag saying whether op1/op2 must be
;;;     swapped (RISC-V has blt/bge/bltu/bgeu but no bgt/ble, so > and <= are
;;;     done by swapping operands).  NEG/POS test the sign of op1-op2, i.e. the
;;;     same as LT/GEQ.  OVF/NOVF (overflow) have no RISC-V flag and belong to
;;;     the typed-arithmetic path, not here.
define lconstant rv_cond(test);
    lvars test;
    if     test == "EQ"                 then "beq"
    elseif test == "NEQ"                then "bne"
    elseif test == "LT"  or test == "NEG" then "blt"
    elseif test == "GEQ" or test == "POS" then "bge"
    elseif test == "GT"                 then "blt"   ;;; with operand swap
    elseif test == "LEQ"                then "bge"   ;;; with operand swap
    elseif test == "ULT"                then "bltu"
    elseif test == "UGEQ"               then "bgeu"
    elseif test == "UGT"                then "bltu"  ;;; with operand swap
    elseif test == "ULEQ"               then "bgeu"  ;;; with operand swap
    else mishap(test, 1, 'rv_cond: unhandled test code (OVF/NOVF go via the arith path)')
    endif;
enddefine;

;;; rv_swap: true for >, <=, u>, u<= -- RISC-V has no bgt/ble/bgtu/bleu, so
;;; those are done by swapping the two branch operands.
define lconstant rv_swap(test);
    lvars test;
    test == "GT" or test == "LEQ" or test == "UGT" or test == "ULEQ"
enddefine;

;;; to_branch_reg: force an operand into a register for a RISC-V branch
;;; (immediate 0 -> the hardwired zero register x0; other values via load_to_reg).
define lconstant to_branch_reg(src, tmp);
    lvars src, tmp;
    if (isinteger(src) or isbiginteger(src)) and src == 0 then
        "x0"
    else
        load_to_reg(src, tmp)
    endif;
enddefine;

;;; gen_test_or_cmp:
;;;     plant a single RISC-V compare-and-branch (cmp) or and+branch (tst):
;;;       cmp:  b<cond> op1, op2, lab     (op1 from src1, op2 from src2)
;;;       tst:  and R5, op1, op2 ; beq/bne R5, x0, lab
;;;     replacing arm64's flag-setting cmp/tst + b.cond (RISC-V has no flags).

define lconstant gen_test_or_cmp(src1, src2, test, lab, cmp_or_test);
    lvars src1, src2, test, lab, cmp_or_test, op1, op2;
    if cmp_or_test == "tst" then
        load_to_reg(src1, R1) -> op1;
        load_to_reg(src2, R5) -> op2;
        asm_emit("and", R5, op1, op2, 4);
        ;;; the test for tst is EQ ((op1&op2)==0) or NEQ; branch R5 vs zero
        asm_emit(rv_cond(test), R5, "x0", get_jump_addr(lab), 4);
    else
        to_branch_reg(src1, R1) -> op1;
        to_branch_reg(src2, R5) -> op2;
        if rv_swap(test) then
            asm_emit(rv_cond(test), op2, op1, get_jump_addr(lab), 4)
        else
            asm_emit(rv_cond(test), op1, op2, get_jump_addr(lab), 4)
        endif;
    endif;
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
        asm_emit("addi", R0, src, -3, 4);
        R0 -> sreg;
    endif;
    ;;; Check it's in range: an unsigned comparison takes care of both the
    ;;; too large and too small cases.
    ;;; Bounds check: if sreg > limit (unsigned) take the else case.  RISC-V
    ;;; compares two registers, so load the limit and use bltu (sreg > limit
    ;;; <=> limit < sreg).
    lvars limit = if sysint then ncases else popint(ncases) - 3 endif;
    lvars limreg = to_branch_reg(limit, R5);
    asm_emit("bltu", limreg, sreg, else_lab, 4);
    ;;; Compute table-entry address (entries are 8 bytes) and jump.  RISC-V has
    ;;; no scaled-index addressing: shift, add to the table base (lla), load.
    if sysint then
        asm_emit("lla", R16, table_lab, 3);
        asm_emit("slli", R0, sreg, 3, 4);          ;;; index * 8
        asm_emit("add", R16, R16, R0, 4);
        asm_emit("ld", R16, '0(' >< R16 >< ')', 3);
    else
        ;;; sreg has popint with tag removed (value*4); entries 8 bytes -> *2
        asm_emit("slli", R0, sreg, 1, 4);
        asm_emit("lla", R16, table_lab, 3);
        asm_emit("add", R16, R16, R0, 4);
        asm_emit("ld", R16, '0(' >< R16 >< ')', 3);
    endif;
    asm_emit("jr", R16, 2);
    ;;; Plant the table; it begins with -else_lab- to account for the 0 case
    asmALIGN();
    asmLABEL(table_lab);
    asm_emit("long", else_lab, explode(labs), ncases + 2);
    ;;; Plant the else case
    asmLABEL(else_lab);
    if not(else_case) then
        ;;; Push src onto the user stack (USP=R10) for error reporting
        asm_emit("addi", R10, R10, -8, 4);
        asm_emit("sd", src, '0(' >< R10 >< ')', 3);
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

    ;;; Frame geometry recorded by M_CREATE_SF, read back by M_UNWIND_SF.
    ;;; The frame is 8-byte-packed and SP-relative, matching the shared
    ;;; STACK_FRAME struct (syscomp/symdefs.p) and sp_offset (m_trans.p).
    ;;; See PORTING-ARM64-FRAME-CONTRACT.md.
    sf_reg_locals,    ;;; register-locals, list order (pop regs first)
    sf_dlocal_labs,   ;;; dynamic-local save operands (so M_UNWIND_SF can restore)
    sf_Nstkvars,      ;;; total on-stack lvars (incl. m_trans alignment pad)
    sf_Ndlocals,      ;;; dynamic-local slots
    sf_Nregs,         ;;; register-local count
    sf_frame_len,     ;;; pd_frame_len in words (== m_trans's; incl. return slot)
;

;;; emit_stp_list / emit_ldp_list:
;;;     On AArch64, we save/restore registers using stp/ldp pairs.
;;;     The list must be processed in pairs for 16-byte alignment.
;;;     For an odd number of registers, we add an extra str/ldr for the last one.

define lconstant emit_stp_push(reg_list);
    ;;; RISC-V has no store-pair instruction: allocate a 16-byte-aligned block
    ;;; then sd each register at 8-byte offsets.
    lvars regs = reg_list, len = listlength(regs), i;
    lvars regvec = {%applist(regs, identfn)%};
    lvars total_space = ((len + 1) div 2) * 16;
    gen_sp_adjust(total_space, "sub");
    lvars offset = 0;
    for i from 1 to len do
        asm_emit("sd", f_subv(i, regvec), offset >< '(sp)', 3);
        offset fi_+ 8 -> offset;
    endfor;
enddefine;

define lconstant emit_ldp_pop(reg_list);
    ;;; RISC-V has no load-pair: ld each register then free the block.
    lvars regs = reg_list, len = listlength(regs), i;
    lvars regvec = {%applist(regs, identfn)%};
    lvars total_space = ((len + 1) div 2) * 16;
    lvars offset = 0;
    for i from 1 to len do
        asm_emit("ld", f_subv(i, regvec), offset >< '(sp)', 3);
        offset fi_+ 8 -> offset;
    endfor;
    gen_sp_adjust(total_space, "add");
enddefine;


;;; gen_sp_adjust:
;;;     Emit a DIRECT-immediate SP adjustment for frame alloc/dealloc:
;;;         sub/add sp, sp, #nbytes
;;;     -opcode- is "sub" (allocate) or "add" (deallocate).
;;;
;;;     This MUST NOT route the constant through load_to_reg/get_operand2,
;;;     because those materialise a non-small immediate from the literal
;;;     pool via PB (`ldr Xt, [PB, #off]`).  During M_UNWIND_SF, PB has
;;;     already been restored to the *caller's* owner (NULL at the top of
;;;     runtime startup), so a PB-relative load of the frame size faults.
;;;     A direct add/sub immediate depends on nothing but SP -- matching the
;;;     single rounded allocation specified in PORTING-ARM64-FRAME-CONTRACT.md.
;;;
;;;     AArch64 add/sub take a 12-bit unsigned immediate, optionally shifted
;;;     left by 12.  nbytes is a multiple of 16 (STACK_ALIGN); cover the full
;;;     24-bit range with at most two instructions.
;;; RISC-V: one addi sp,sp,+/-nbytes when nbytes fits the signed 12-bit
;;; immediate (|n| <= 2047); otherwise materialise the delta in a scratch
;;; register with li (NOT a PB-relative literal load -- see the M_UNWIND_SF
;;; note above) and add it.  -opcode- "sub" allocates (negative), "add" frees.
define lconstant gen_sp_adjust(nbytes, opcode);
    lvars nbytes, opcode, delta;
    if nbytes < 0 then
        mishap(nbytes, 1, 'gen_sp_adjust: negative frame size');
    endif;
    (if opcode == "sub" then negate(nbytes) else nbytes endif) -> delta;
    if delta == 0 then
        ;;; no adjustment needed
    elseif is_small_disp(delta) then
        asm_emit("addi", "sp", "sp", delta, 4);
    else
        asm_emit("li", R16, delta, 3);
        asm_emit("add", "sp", "sp", R16, 4);
    endif;
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
          tmp, j, dlocal_labs, Nstkvars, Nregs, Ndlocals, ix,
          SFO = field_##("SF_OWNER"),
          SFL = field_##("SF_LOCALS"),
          SFR = field_##("SF_RETURN_ADDR"),
          frame_len;

    explode(m_instr) -> reg_spec_id -> dlocal_labs -> Npopstkvars
        -> Nstkvars -> Npopregs -> reg_locals -> ;

    listlength(reg_locals) -> Nregs;
    listlength(dlocal_labs) -> Ndlocals;

    ;;; Canonical frame length in words -- identical to m_trans.p's pd_frame_len
    ;;; (m_trans.p:2061): SF_LOCALS + Nstkvars + Ndlocals + Nregs - SF_RETURN_ADDR.
    ;;; Nstkvars here already includes m_trans's STACK_ALIGN padding, so frame_len
    ;;; is an even (16-byte-multiple) word count -- a single sub keeps SP aligned.
    SFL + Nstkvars + Ndlocals + Nregs - SFR -> frame_len;

    ;;; Hand the geometry to M_UNWIND_SF.
    reg_locals  -> sf_reg_locals;
    dlocal_labs -> sf_dlocal_labs;
    Nstkvars    -> sf_Nstkvars;
    Ndlocals    -> sf_Ndlocals;
    Nregs       -> sf_Nregs;
    frame_len   -> sf_frame_len;

    ;;; PD_REGMASK bit-map (GC register scan): which register-local registers
    ;;; this procedure uses.  Register numbers must map into the 16-bit field;
    ;;; this is a CONTRACT with aprocess.s (process switch / GC register scan).
    ;;; RISC-V register locals: pop x19,x20 (s3,s4); nonpop x21,x22,x23 (s5-s7).
    0 -> regmask;
    fast_for n in reg_locals do
        lvars bitpos;
        if n == 19 then 0
        elseif n == 20 then 1
        elseif n == 21 then 2
        elseif n == 22 then 3
        elseif n == 23 then 4
        else mishap(n, 1, 'M_CREATE_SF: register not in PD_REGMASK map')
        endif -> bitpos;
        regmask || (1 << bitpos) -> regmask
    endfast_for;
    regmask -> idval(reg_spec_id);

    ;;; Allocate the whole 8-byte-packed frame in one 16-aligned step.
    ;;; SP now points at the SF_OWNER slot; all frame fields are [sp, #index*8].
    ;;; Direct immediate -- must not go via PB's literal pool (see gen_sp_adjust).
    gen_sp_adjust(frame_len * WORD_OFFS, "sub");

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

    ;;; SF_OWNER: store PB (just loaded above) at frame index SF_OWNER (= [sp]).
    asm_emit("str", PB, '[sp, #' >< (SFO * WORD_OFFS) >< ']', 3);

    ;;; SF_RETURN_ADDR: store LR (the return-into-caller that `bl` left in x30)
    ;;; at the top frame slot, index frame_len-1.  This materialises the slot
    ;;; the call-stack walkers / GC read, byte-identical to x86 `call`; the
    ;;; matching `ret` reloads it from M_UNWIND_SF.
    asm_emit("str", LR, '[sp, #' >< ((frame_len - 1) * WORD_OFFS) >< ']', 3);

    ;;; Save the register-locals' INCOMING values into their reg slots (list
    ;;; order: pop regs first), BEFORE clearing them below.  Reg region starts
    ;;; just above the dlocals: SF_LOCALS + Nstkvars + Ndlocals.
    SFL + Nstkvars + Ndlocals -> ix;
    fast_for n in reg_locals do
        asm_emit("str", reglabel(n), '[sp, #' >< (ix * WORD_OFFS) >< ']', 3);
        ix + 1 -> ix;
    endfast_for;

    ;;; Store the dynamic-local save values into their slots.  m_trans
    ;;; lists POP dlocals FIRST and the canonical frame layout puts pop
    ;;; dlocals at the TOP of the dlocal region (directly below the pop
    ;;; register saves): PD_GC_OFFSET_LEN/PD_GC_SCAN_LEN and the runtime
    ;;; Dlocal_frame_offset all map list index k to slot (Ndlocals-1-k).
    ;;; So assign slots DESCENDING from the top of the dlocal region.
    ;;; (Ascending assignment put the pop dlocals where the GC expects
    ;;; the non-pop ones: the GC then never relocated saved pop values
    ;;; -- stale cucharout etc. after any GC -- and Copyscan'd the
    ;;; non-pop saves as if they were pop pointers.)
    SFL + Nstkvars + Ndlocals - 1 -> ix;
    fast_for n in dlocal_labs do
        lvars dv = load_to_reg(n, R1);
        asm_emit("str", dv, '[sp, #' >< (ix * WORD_OFFS) >< ']', 3);
        ix - 1 -> ix;
    endfast_for;

    ;;; Clear the POP register-locals (the registers themselves) to popint 0 --
    ;;; the first Npopregs entries of reg_locals.
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

    ;;; Initialise the POP on-stack lvars to popint 0; the non-POP ones are left
    ;;; uninitialised (space already allocated by the single sub above).  Pop
    ;;; stkvars occupy the high stkvar indices: SF_LOCALS + (Nstkvars-Npopstkvars)..
    if Npopstkvars > 0 then
        unless tmp then R0 -> tmp; gen_move(popint_zero, R0) endunless;
        SFL + Nstkvars - Npopstkvars -> ix;
        repeat Npopstkvars times
            asm_emit("str", tmp, '[sp, #' >< (ix * WORD_OFFS) >< ']', 3);
            ix + 1 -> ix;
        endrepeat;
    endif;
enddefine;

;;; {M_UNWIND_SF}
;;;     plant code to unwind a procedure stack frame

define M_UNWIND_SF();
    lvars n, ix,
          SFL = field_##("SF_LOCALS"),
          frame_len = sf_frame_len;

    ;;; Reverse M_CREATE_SF exactly, reading every value out of its 8-byte slot
    ;;; before deallocating.  See PORTING-ARM64-FRAME-CONTRACT.md.

    ;;; Reload the return address (LR/x30) from SF_RETURN_ADDR (top slot,
    ;;; index frame_len-1).  The following M_RETURN ( `ret` ) uses it.
    asm_emit("ldr", LR, '[sp, #' >< ((frame_len - 1) * WORD_OFFS) >< ']', 3);

    ;;; Restore the register-locals from their reg slots, same order/offsets as
    ;;; M_CREATE_SF saved them: SF_LOCALS + Nstkvars + Ndlocals ..
    SFL + sf_Nstkvars + sf_Ndlocals -> ix;
    fast_for n in sf_reg_locals do
        asm_emit("ldr", reglabel(n), '[sp, #' >< (ix * WORD_OFFS) >< ']', 3);
        ix + 1 -> ix;
    endfast_for;

    ;;; Restore the dynamic-locals' saved (old) values back into their cells,
    ;;; from the same slots M_CREATE_SF saved them: SF_LOCALS + Nstkvars + k.
    ;;; This is the dlocal-context restore that x86_64 M_UNWIND_SF performs via
    ;;; `applist(rev(dlocal_labs), asmPOPL)`; omitting it leaks dlocal values
    ;;; (e.g. pop_expr_prec) across a returning call.  It MUST run before PB is
    ;;; restored to the caller below, since a dlocal operand may be addressed
    ;;; PB-relative (literal pool of THIS procedure).
    ;;; (slots assigned DESCENDING -- see M_CREATE_SF)
    SFL + sf_Nstkvars + sf_Ndlocals - 1 -> ix;
    fast_for n in sf_dlocal_labs do
        asm_emit("ldr", R1, '[sp, #' >< (ix * WORD_OFFS) >< ']', 3);
        gen_reg_store(R1, n, R5);
        ix - 1 -> ix;
    endfast_for;

    ;;; Restore PB to the caller's owner (its SF_OWNER one frame up, at
    ;;; [sp + frame_len*8] == _caller_sp).  Read it before deallocating.
    asm_emit("ldr", PB, '[sp, #' >< (frame_len * WORD_OFFS) >< ']', 3);

    ;;; Deallocate the whole frame in one step (keeps SP 16-aligned).
    ;;; Direct immediate -- PB has already been restored to the caller's owner
    ;;; above, so the frame size MUST NOT be loaded via PB (see gen_sp_adjust).
    gen_sp_adjust(frame_len * WORD_OFFS, "add");
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
            asm_emit("ld", R1, (frozval_offset + i*8) >< '(' >< R0 >< ')', 3);
            asm_emit("addi", R10, R10, -8, 4);
            asm_emit("sd", R1, '0(' >< R10 >< ')', 3)
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
        asm_emit("addi", R1, wreg, -3, 4);
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

;;; mem_operand:
;;;     Translate a residual AArch64 memory-operand string into RISC-V form:
;;;       "[reg]"        -> "0(reg)"
;;;       "[reg, #off]"  -> "off(reg)"   (off may be negative)
;;;     Structural forms -- auto-index "[reg,#-8]!", post-index "[reg], #8",
;;;     indexed "[reg, reg2, lsl #3]" -- cannot be a single RISC-V operand and
;;;     are converted at their emit sites; leave them unchanged here so a missed
;;;     one surfaces as an assembler error rather than being silently mangled.
;;;     Non-"[" strings (labels, "off(reg)" already done) pass straight through.
define lconstant mem_operand(s) -> out;
    lvars s, out = s, inner, p, n = datalength(s);
    returnunless(n fi_>= 2 and subscrs(1, s) == `[` and subscrs(n, s) == `]`);
    returnif(issubstring('!', s));        ;;; pre-decrement push
    returnif(issubstring('], ', s));      ;;; post-increment pop
    returnif(issubstring('lsl', s));      ;;; scaled/indexed
    substring(2, n fi_- 2, s) -> inner;   ;;; strip the [ and ]
    if issubstring(', #', inner) ->> p then
        substring(p fi_+ 3, datalength(inner) fi_- (p fi_+ 2), inner)
            >< '(' >< substring(1, p fi_- 1, inner) >< ')' -> out;
    else
        '0(' >< inner >< ')' -> out;
    endif;
enddefine;

define lconstant outopnd(opd);
    lvars opd;
    if ispair(opd) then
        mishap(opd, 1, 'outopnd: unhandled operand\n');
    endif;
    if isreg(opd) then
        asmf_printf(opd, '%p');
    elseif isimm(opd) then
        ;;; RISC-V immediates are bare (no AArch64 '#').
        asmf_printf(immval(opd), '%p');
    elseif isabs(opd) then
        ;;; Much arm64 code builds immediate operands as '#' >< n strings;
        ;;; RISC-V wants the bare number, so strip a leading '#'.  Otherwise
        ;;; translate any residual "[reg,#off]" memory operand to "off(reg)".
        if isstring(opd) and datalength(opd) fi_>= 1 and subscrs(1, opd) == `#` then
            asmf_printf(allbutfirst(1, opd), '%p');
        elseif isstring(opd) then
            asmf_printf(mem_operand(opd), '%p');
        else
            asmf_printf(opd, '%p');
        endif;
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
            ;;; NB: format has no %p, so pass no value arg -- a spurious `false`
            ;;; here is never consumed by printf and leaks onto the user stack
            ;;; (one per `#` comment instruction, i.e. per procedure), which was
            ;;; the source of the `items-left after file` stack leak.
            ;;; RISC-V GAS uses '#' for line comments (not arm64's '//').
            asmf_printf('\t#');
            for i from 2 to n do
                asmf_printf(f_subv(i, instr), '\s%p');
            endfor;
        else
            ;;; Translate the unambiguous residual AArch64 load/store/branch
            ;;; mnemonics to RISC-V.  ldr->ld covers both a normal load (with an
            ;;; off(reg) operand) AND a PC-relative load "ldr rd, sym": RISC-V
            ;;; GAS reads "ld rd, sym" as an auipc/%pcrel pseudo.  (Sub-word and
            ;;; immediate forms are already emitted directly as ld/lw/lh/lb,
            ;;; li, mv etc. by the generators, so they never reach here.)
            lvars rvop = opcode;
            if     opcode == "str" then "sd"   -> rvop;
            elseif opcode == "strh" then "sh"  -> rvop;  ;;; 16-bit store
            elseif opcode == "strb" then "sb"  -> rvop;  ;;; 8-bit store
            elseif opcode == "ldr" then "ld"   -> rvop;
            elseif opcode == "bl"  then "call" -> rvop;
            elseif opcode == "mov" then "mv"   -> rvop;  ;;; reg moves (imm uses li)
            elseif opcode == "blr" then "jalr" -> rvop;  ;;; indirect call
            elseif opcode == "b"   then "j"    -> rvop;  ;;; unconditional branch
            elseif opcode == "br"  then "jr"   -> rvop;  ;;; indirect branch (jalr x0)
            elseif opcode == "mvn" then "not"  -> rvop;  ;;; bitwise-NOT move (xori -1)
            endif;
            asmf_printf(rvop, '\t%p\t');
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

#_IF DEF UNIX_MACHO
;;; Mach-O: clang's assembler cannot evaluate a FORWARD shifted label-difference
;;; in a data directive, so popc must emit PD_LENGTH as a literal number rather
;;; than the `.set _LF, ((endlab - exec) >> 3) + hdr` the ELF path uses.  popc
;;; emits the whole exec..endlab span itself (no assembler-managed literal pools
;;; on this backend), so its byte size is the sum over the final codelist:
;;;     "label" / "#"  -> 0 bytes
;;;     "align"        -> pad up to an 8-byte boundary
;;;     "long"         -> (datalength-1) * 8   (xword data, via asm_outword)
;;;     anything else  -> 4   (one fixed-width AArch64 instruction)
define lconstant codelist_nbytes(codelist) -> nbytes;
    lvars instr, opcode;
    0 -> nbytes;
    fast_for instr in codelist do
        f_subv(1, instr) -> opcode;
        if opcode == "label" or opcode == "#" then
            ;;; emits no bytes
        elseif opcode == "align" then
            ((nbytes + 7) >> 3) << 3 -> nbytes      ;;; pad to 8-byte boundary
        elseif opcode == "long" then
            nbytes + (datalength(instr) - 1) * 8 -> nbytes
        else
            nbytes + 4 -> nbytes
        endif
    endfor
enddefine;
#_ENDIF

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
#_IF DEF UNIX_MACHO
        ;;; Mach-O: literal length (see codelist_nbytes above). exec..endlab is
        ;;; the codelist rounded up to 8 by the final align, /8 words, + header.
        outlabset(pdr_len, ((codelist_nbytes(codelist) + 7) >> 3) + hdr_len);
#_ELSE
        outlabset(pdr_len,
                  asm_pdr_len(hdr_len, current_pdr_exec_label, endlab));
#_ENDIF
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
