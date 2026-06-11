import subprocess, sys

C = {  # constants from ass.p
 'ADD_IMM':0x91000000,'SUB_IMM':0xD1000000,'ADDS_IMM':0xB1000000,'SUBS_IMM':0xF1000000,
 'ADD_REG':0x8B000000,'SUB_REG':0xCB000000,'ADDS_REG':0xAB000000,'SUBS_REG':0xEB000000,
 'MADD':0x9B000000,'ORR_REG':0xAA000000,'AND_REG':0x8A000000,'ANDS_REG':0xEA000000,
 'ORN_REG':0xAA200000,'MOVZ':0xD2800000,'MOVK':0xF2800000,'MOVN':0x92800000,
 'LDR_IMM':0xF9400000,'STR_IMM':0xF9000000,'LDR_PRE':0xF8400C00,'STR_PRE':0xF8000C00,
 'LDR_POST':0xF8400400,'STR_POST':0xF8000400,'LDR_REG':0xF8606800,'STR_REG':0xF8206800,
 'LDRB_IMM':0x39400000,'STRB_IMM':0x39000000,'LDRH_IMM':0x79400000,'STRH_IMM':0x79000000,
 'LDRW_IMM':0xB9400000,'STRW_IMM':0xB9000000,'LDRSB_IMM':0x39800000,'LDRSH_IMM':0x79800000,
 'LDRSW_IMM':0xB9800000,'STP_PRE':0xA9800000,'LDP_POST':0xA8C00000,'STP_OFF':0xA9000000,
 'LDP_OFF':0xA9400000,'B':0x14000000,'BL':0x94000000,'BR':0xD61F0000,'BLR':0xD63F0000,
 'RET':0xD65F03C0,'B_COND':0x54000000,'CBZ':0xB4000000,'CBNZ':0xB5000000,
 'LSL_REG':0x9AC02000,'LSR_REG':0x9AC02400,'ASR_REG':0x9AC02800,
 'UBFM':0xD3400000,'SBFM':0x93400000,'NOP':0xD503201F,
}
XZR=31; SP=31
cases=[]  # (name, word, asm)
def add(n,w,a): cases.append((n, w & 0xFFFFFFFF, a))

# mov / arith
add('mov_reg', C['ORR_REG']|(3<<16)|(XZR<<5)|1, 'mov x1, x3')
add('add_imm', C['ADD_IMM']|((42&0xFFF)<<10)|(2<<5)|1, 'add x1, x2, #42')
add('sub_imm', C['SUB_IMM']|((42&0xFFF)<<10)|(2<<5)|1, 'sub x1, x2, #42')
add('sub_imm_sp', C['SUB_IMM']|((48&0xFFF)<<10)|(SP<<5)|SP, 'sub sp, sp, #48')
add('adr_dot', 0x10000000|1, 'adr x1, .')
add('add_reg', C['ADD_REG']|(3<<16)|(2<<5)|1, 'add x1, x2, x3')
add('sub_reg', C['SUB_REG']|(3<<16)|(2<<5)|1, 'sub x1, x2, x3')
add('subs_reg', C['SUBS_REG']|(3<<16)|(2<<5)|1, 'subs x1, x2, x3')
add('cmp_reg', C['SUBS_REG']|(3<<16)|(2<<5)|XZR, 'cmp x2, x3')
add('cmp_imm', C['SUBS_IMM']|((42&0xFFF)<<10)|(2<<5)|XZR, 'cmp x2, #42')
add('ands_reg', C['ANDS_REG']|(3<<16)|(2<<5)|1, 'ands x1, x2, x3')
add('tst_reg', C['ANDS_REG']|(3<<16)|(2<<5)|XZR, 'tst x2, x3')
add('mul', C['MADD']|(3<<16)|(XZR<<10)|(2<<5)|1, 'mul x1, x2, x3')
# loads/stores imm scaled
add('ldr_imm', C['LDR_IMM']|(((504>>3)&0xFFF)<<10)|(2<<5)|1, 'ldr x1, [x2, #504]')
add('str_imm', C['STR_IMM']|(((504>>3)&0xFFF)<<10)|(2<<5)|1, 'str x1, [x2, #504]')
# register-offset (UNSCALED per constants)
add('ldr_reg', C['LDR_REG']|(3<<16)|(2<<5)|1, 'ldr x1, [x2, x3]')
add('str_reg', C['STR_REG']|(3<<16)|(2<<5)|1, 'str x1, [x2, x3]')
# unscaled signed
add('ldur', 0xF8400000|(((-16)&0x1FF)<<12)|(2<<5)|1, 'ldur x1, [x2, #-16]')
add('stur', 0xF8000000|(((-16)&0x1FF)<<12)|(2<<5)|1, 'stur x1, [x2, #-16]')
# push/pop
add('push', C['STR_PRE']|(0x1F8<<12)|(19<<5)|1, 'str x1, [x19, #-8]!')
add('pop',  C['LDR_POST']|(8<<12)|(19<<5)|1, 'ldr x1, [x19], #8')
# pairs
add('stp_pre', C['STP_PRE']|((((-48)>>3)&0x7F)<<15)|(30<<10)|(SP<<5)|29, 'stp x29, x30, [sp, #-48]!')
add('ldp_post', C['LDP_POST']|(((16>>3)&0x7F)<<15)|(2<<10)|(SP<<5)|1, 'ldp x1, x2, [sp], #16')
add('stp_off', C['STP_OFF']|(((16>>3)&0x7F)<<15)|(2<<10)|(SP<<5)|1, 'stp x1, x2, [sp, #16]')
add('ldp_off', C['LDP_OFF']|(((16>>3)&0x7F)<<15)|(2<<10)|(SP<<5)|1, 'ldp x1, x2, [sp, #16]')
# branches
add('b_fwd', C['B']|((8>>2)&0x3FFFFFF), 'b . + 8')
add('bl_fwd', C['BL']|((8>>2)&0x3FFFFFF), 'bl . + 8')
add('br', C['BR']|(16<<5), 'br x16')
add('blr', C['BLR']|(16<<5), 'blr x16')
add('ret', C['RET'], 'ret')
add('beq', C['B_COND']|(((8>>2)&0x7FFFF)<<5)|0, 'b.eq . + 8')
add('bne', C['B_COND']|(((8>>2)&0x7FFFF)<<5)|1, 'b.ne . + 8')
add('bhi', C['B_COND']|(((8>>2)&0x7FFFF)<<5)|8, 'b.hi . + 8')
add('bcc_neg', C['B_COND']|((((-8)>>2)&0x7FFFF)<<5)|3, 'b.lo . - 8')
add('cbz', C['CBZ']|(((8>>2)&0x7FFFF)<<5)|1, 'cbz x1, . + 8')
add('cbnz', C['CBNZ']|(((8>>2)&0x7FFFF)<<5)|1, 'cbnz x1, . + 8')
# moves
add('movz', C['MOVZ']|(42<<5)|1, 'movz x1, #42')
add('movz_hw0_big', C['MOVZ']|(0xFFFF<<5)|1, 'movz x1, #65535')
add('movk_hw1', C['MOVK']|(1<<21)|(0x1234<<5)|1, 'movk x1, #0x1234, lsl #16')
add('movn', C['MOVN']|(42<<5)|1, 'movn x1, #42')
# shifts (register)
add('lslv', C['LSL_REG']|(3<<16)|(2<<5)|1, 'lsl x1, x2, x3')
add('lsrv', C['LSR_REG']|(3<<16)|(2<<5)|1, 'lsr x1, x2, x3')
add('asrv', C['ASR_REG']|(3<<16)|(2<<5)|1, 'asr x1, x2, x3')
# bitfields as used inline
add('asr2_sbfm', C['SBFM']|(2<<16)|(0x3F<<10)|(0<<5)|0, 'asr x0, x0, #2')
add('lsl3_ubfm', C['UBFM']|(0x3D<<16)|(0x3C<<10)|(0<<5)|0, 'lsl x0, x0, #3')
add('lsl2_ubfm', C['UBFM']|(0x3E<<16)|(0x3D<<10)|(0<<5)|0, 'lsl x0, x0, #2')
add('nop', C['NOP'], 'nop')
# field loads/stores at offset 0
add('ldrb', C['LDRB_IMM']|(0<<5)|1, 'ldrb w1, [x0]')
add('strb', C['STRB_IMM']|(0<<5)|1, 'strb w1, [x0]')
add('ldrh', C['LDRH_IMM']|(0<<5)|1, 'ldrh w1, [x0]')
add('strh', C['STRH_IMM']|(0<<5)|1, 'strh w1, [x0]')
add('ldrw', C['LDRW_IMM']|(0<<5)|1, 'ldr w1, [x0]')
add('strw', C['STRW_IMM']|(0<<5)|1, 'str w1, [x0]')
add('ldrsb', C['LDRSB_IMM']|(0<<5)|1, 'ldrsb x1, [x0]')
add('ldrsh', C['LDRSH_IMM']|(0<<5)|1, 'ldrsh x1, [x0]')
add('ldrsw', C['LDRSW_IMM']|(0<<5)|1, 'ldrsw x1, [x0]')
# ldr (literal)
add('ldr_lit', 0x58000000|(((24>>2)&0x7FFFF)<<5)|16, 'ldr x16, . + 24')
# I_SWITCH's ADR X1,#16
add('adr_x1_16', 0x10000000|(4<<5)|1, 'adr x1, . + 16')
# closure_cons _adr_encode negative back-ref: imm=-24
imm=-24; add('adr_neg', 0x10000000|((imm&3)<<29)|(((imm>>2)&0x7FFFF)<<5)|0, 'adr x0, . - 24')
# closure_cons hardcoded words
add('clos_push_x0', 0xF81F8E60, 'str x0, [x19, #-8]!')
add('clos_push_x1', 0xF81F8E61, 'str x1, [x19, #-8]!')
add('clos_ldr_pdpart', 0xF9400000|((0>>3)<<10)|(0<<5)|0, 'ldr x0, [x0]')
add('clos_br', 0xD61F0200, 'br x16')
add('my_and_pb', 0x925BFA94, 'and x20, x20, #0xffffffefffffffff')
add('my_and_x0', 0x925BF800, 'and x0, x0, #0xffffffefffffffff')

asm = '\n'.join(a for _,_,a in cases) + '\n'
open('all.s','w').write(asm)
r = subprocess.run(['clang','-c','-arch','arm64','-x','assembler','all.s','-o','all.o'],
                   capture_output=True, text=True)
if r.returncode: print("ASSEMBLY FAILED:\n", r.stderr[:2000]); sys.exit(1)
out = subprocess.run(['otool','-t','all.o'], capture_output=True, text=True).stdout
words=[]
for line in out.splitlines():
    parts=line.split()
    if parts and all(len(p)==8 for p in parts[1:]) and len(parts)>1:
        words += [int(p,16) for p in parts[1:]]
fails=0
for (name,w,a),g in zip(cases,words):
    if w!=g:
        print(f"  MISMATCH {name:16s} asspop={w:08x} clang={g:08x}   ({a})"); fails+=1
print(f"\n{len(cases)} cases, {fails} mismatches")
