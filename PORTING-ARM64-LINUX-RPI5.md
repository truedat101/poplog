# Porting Poplog to ARM64 (AArch64) Linux on Raspberry Pi 5

## Overview

This document is a guide for porting Poplog to the **AArch64 (ARM64)** architecture,
targeting a **Raspberry Pi 5** running **Debian/Raspbian 64-bit Linux**.

Poplog already runs on 32-bit ARM Linux (Raspberry Pi). The ARM32 port was done by
Waldek Hebisch and is documented in `PORTING.txt`. This guide builds on that experience
and adapts the approach for the 64-bit AArch64 instruction set.

### Current State (branch: `4-raspi5-arm64-port-round2`)

The initial ARM64 porting effort copied the ARM32 files into `pop/src/arm64/` and
`pop/src/syscomp/arm64/`, changing only the `.arch` directive from `armv5` to `armv8`.
**The assembly files and code generators still contain ARM32 (AArch32) instructions and
register names.** They will not assemble or run on an AArch64 target. All 14 runtime
files and 3 compiler files need to be rewritten for AArch64.

The configure script already recognizes `aarch64` and maps it to `POP_arch=arm64`.

---

## Target Platform

| Property | Value |
|----------|-------|
| Board | Raspberry Pi 5 |
| SoC | Broadcom BCM2712, Cortex-A76 (ARMv8.2-A) |
| OS | Debian 12 (Bookworm) / Raspbian 64-bit |
| `uname -m` | `aarch64` |
| Word size | 64-bit |
| Endianness | Little-endian |
| Kernel | Linux 6.x aarch64 |

---

## Key Differences: ARM32 vs AArch64

Understanding these differences is essential before touching any code.

### Registers

| ARM32 (AArch32) | AArch64 (A64) | Notes |
|------------------|---------------|-------|
| r0-r12 (13 GPRs, 32-bit) | x0-x30 (31 GPRs, 64-bit) | w0-w30 for 32-bit views |
| r13 / sp | sp (dedicated) | Not a GPR in AArch64 |
| r14 / lr | x30 / lr | Link register |
| r15 / pc | pc (not a GPR) | Cannot read pc as a register |
| s0-s31 / d0-d15 (VFP) | v0-v31 / d0-d31 / s0-s31 (NEON/FP) | 32 SIMD/FP registers |

### Instruction Set

- AArch64 is a **completely new** ISA, not an extension of ARM32.
- No conditional execution suffix on most instructions (no `addeq`, `movne`, etc.).
- Uses `cbz`/`cbnz`/`b.cond` instead.
- No `stmfd`/`ldmfd` (push/pop multiple). Use `stp`/`ldp` (store/load pair).
- PC-relative addressing: `adr`/`adrp` + offset, not `ldr rN, =label`.
- Fixed 32-bit instruction encoding (same as ARM32, but different opcodes).
- No barrel shifter in load/store the same way; shifted register forms differ.

### Calling Convention (AAPCS64)

| Property | ARM32 (AAPCS) | AArch64 (AAPCS64) |
|----------|---------------|---------------------|
| Integer args | r0-r3 (4 regs) | x0-x7 (8 regs) |
| Integer return | r0 (r0-r1 for 64-bit) | x0 (x0-x1 for 128-bit) |
| FP args | s0-s15 / d0-d7 | v0-v7 (d0-d7 / s0-s7) |
| FP return | s0 / d0 | v0 (d0 / s0) |
| Callee-saved | r4-r11 | x19-x28, x29 (FP) |
| Frame pointer | r11 (optional) | x29 (mandatory per AAPCS64) |
| Link register | r14 / lr | x30 / lr |
| Stack alignment | 8 bytes | 16 bytes |

### Data Model

| Type | ARM32 (ILP32) | AArch64 (LP64) |
|------|---------------|-----------------|
| int | 32-bit | 32-bit |
| long | 32-bit | **64-bit** |
| pointer | 32-bit | **64-bit** |
| size_t | 32-bit | **64-bit** |

### Reference

- ARM A64 Instruction Set: https://developer.arm.com/documentation/102374/latest/
- AAPCS64: https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst
- ARM ARM (Architecture Reference Manual): https://developer.arm.com/documentation/ddi0487/latest

---

## File Inventory

### Files That Must Be Rewritten for AArch64

All files below currently contain ARM32 code with only `.arch armv8` changed.

**Compiler backend** (`pop/src/syscomp/arm64/`):

| File | Size | Purpose | Difficulty |
|------|------|---------|------------|
| `sysdefs.p` | 3.4K | Architecture parameters, word size, alignment | Medium |
| `asmout.p` | 10.7K | Assembly output (translate to GNU as aarch64 syntax) | Medium |
| `genproc.p` | 45K | M-code to machine instruction generator | **Hard** |

**Runtime assembly** (`pop/src/arm64/`):

| File | Size | Purpose | Difficulty |
|------|------|---------|------------|
| `amain.s` | 1.6K | Entry point, initialization, call `setpop` | Easy |
| `aarith.s` | 8.2K | Arithmetic operations (add, sub, mul, bit ops) | Medium |
| `afloat.s` | 9.0K | Floating point operations | Medium |
| `aextern.s` | 5.0K | External (FFI) function call support | Hard |
| `amisc.s` | 10.5K | Miscellaneous runtime support | Medium |
| `amove.s` | 3.8K | Data movement operations | Easy-Medium |
| `aprocess.s` | 6.9K | Process/coroutine switching | Hard |
| `aprolog.s` | 5.4K | Prolog runtime support | Medium |
| `alisp.s` | 1.0K | Lisp runtime support | Easy |
| `asignals.s` | 1.7K | Signal handling | Medium |

**Runtime code generators** (`pop/src/arm64/`):

| File | Size | Purpose | Difficulty |
|------|------|---------|------------|
| `ass.p` | 49K | Runtime code generator (I-code to machine code in memory) | **Hard** |
| `array_cons.p` | 3.1K | Array procedure generator | Medium |
| `closure_cons.p` | 3.2K | Closure generator | Medium |
| `pdr_compose.p` | 2.6K | Procedure composition generator | Medium |

**C support files** (shared, need `#ifdef __aarch64__` sections):

| File | Purpose | Status |
|------|---------|--------|
| `pop/extern/lib/ext_arm.c` | External call ABI helper | Has `__aarch64__` guard but uses ARM32 ABI (4 int regs, not 8) |
| `pop/extern/lib/c_core.c` | Core C runtime | Has `__aarch64__` guard, needs signal context update |

### Files That Likely Need No Changes

- `pop/src/syscomp/common.ph` - Shared compiler infrastructure
- `pop/src/syscomp/mcdata.p` - Machine data (driven by sysdefs.p constants)
- `pop/src/unixdefs.ph` - Already has ARM conditionals
- `configure` - Already handles `aarch64`
- `Makefile.in` - Architecture-agnostic (uses `POP_arch` variable)

---

## Porting Strategy

Follow the same staged approach Hebisch used for ARM32, adapted for AArch64.
Cross-compile from a working Poplog on a host machine (x86_64 Linux recommended),
then test on the Raspberry Pi 5.

### Prerequisites

**Host machine** (for cross-compilation):
- Working Poplog installation (x86_64 Linux)
- AArch64 cross-toolchain: `gcc-aarch64-linux-gnu`, `binutils-aarch64-linux-gnu`

**Target machine** (Raspberry Pi 5):
- Debian/Raspbian 64-bit
- `gcc`, `make`, `libncurses-dev`, `libx11-dev`, `libxt-dev`, `libmotif-dev` (optional)
- SSH access for file transfer and testing

### Stage 0: Background Knowledge

Required reading before starting:

1. **PORTING.txt** in this repo - Hebisch's original porting methodology
2. **AArch64 ISA overview**: https://developer.arm.com/documentation/102374/latest/
3. **AAPCS64 calling convention**: Focus on register usage, stack frame layout
4. **Poplog internals**: Study the ARM32 files alongside x86_64 files to understand
   what each routine does at a semantic level, then reimplement for AArch64
5. **Pop-11 system dialect**: The `.p` files use "syspop11", a system-level dialect

### Stage 1: Fix `sysdefs.p` for True 64-bit

The current `pop/src/syscomp/arm64/sysdefs.p` is a copy of the ARM32 version with
**WORD_BITS = 32**. This is wrong for AArch64 and must be the first thing fixed.

Key changes needed (compare with `pop/src/syscomp/x86_64/sysdefs.p`):

```
WORD_BITS       = 64,          ;;; was 32 (ARM32)
POPINT_BITS     = 61,          ;;; was 29 (ARM32)
STACK_ALIGN_BITS = 128,        ;;; was 64 (ARM32), AArch64 requires 16-byte
```

Also consider:
- Change `ARM_LINUX` to a distinct identifier like `ARM64_LINUX` (to differentiate
  from 32-bit ARM). Check all uses of `ARM_LINUX` in `unixdefs.ph` and other files
  to determine if shared behavior should use a common flag or separate ones.
- Change `PROCESSOR` to `[[arm64]]` or `[[aarch64]]`
- Review `UNIX_USRSTACK` value for AArch64 Linux address space layout
- Change `LINUX_ELF` to `UNIX_ELF = true` (as x86_64 uses)
- Consider adding `SIGN_EXTEND_EXTERN = true` (as x86_64 has)
- The `CACHEFLUSH` via `__clear_cache()` should still work on AArch64 Linux
- Consider `LOWEST_ADDRESS = 0` (as x86_64 has)

### Stage 2: Port the Compiler (`popc`) - `genproc.p` and `asmout.p`

#### 2a: `asmout.p` - Assembly Output

This file generates GNU assembler syntax. AArch64 changes needed:

- Replace `.word` with `.xword` (or `.quad`) for 64-bit pointer/word data
- Remove `.fpu vfp` directive -- AArch64 doesn't use `.fpu`; FP/NEON is integral
- Ensure label/symbol handling uses AArch64 relocation types
- Function `asm_gen_exfunc_clos_code` must generate AArch64 closure trampolines
- Function `asm_gen_poplink_code` must generate AArch64 link-time code

#### 2b: `genproc.p` - M-code to Machine Code Generator

This is the largest and hardest file (~1564 lines of M-instruction implementations).

**Approach** (from PORTING.txt):
1. Define all M-instruction procedures as stubs that print an error
2. Implement `M_CREATE_SF` (stack frame creation) first -- it's complex but required
3. Incrementally implement M-instructions as they appear during compilation
4. Cross-compile simple Pop-11 files, inspect generated assembly, verify correctness

**Key translation patterns:**

| Concept | ARM32 | AArch64 |
|---------|-------|---------|
| Load word | `ldr r0, [r1]` | `ldr x0, [x1]` |
| Store word | `str r0, [r1]` | `str x0, [x1]` |
| Push multiple | `stmfd sp!, {r4-r11, lr}` | `stp x29, x30, [sp, #-16]!` (pairs) |
| Pop multiple | `ldmfd sp!, {r4-r11, pc}` | `ldp x29, x30, [sp], #16` (pairs) |
| Branch and link | `bl label` | `bl label` (same) |
| Return | `bx lr` or `mov pc, lr` | `ret` (uses x30/lr) |
| Conditional | `addeq r0, r1, r2` | `b.ne skip; add x0, x1, x2; skip:` |
| Load address | `ldr r0, =symbol` | `adrp x0, symbol; add x0, x0, :lo12:symbol` |

**Register allocation** for Poplog:

The ARM32 port uses these Poplog register assignments:
- `r10` = USP (user stack pointer)
- `r11` = PB (procedure base)

For AArch64, choose from callee-saved registers (x19-x28) to avoid save/restore
overhead on C calls:
- Suggested: `x19` = USP, `x20` = PB (or similar callee-saved pair)
- `x29` = frame pointer (per AAPCS64 convention)
- `x30` = link register

### Stage 3: Port the Runtime Assembly (10 `.s` files)

**Approach** (from PORTING.txt):
1. Implement each routine as a stub (infinite loop: `b .`) so GDB can be attached
   when a stub is hit during testing
2. Replace stubs with real implementations one at a time
3. Test after each batch of implementations

#### 3a: `amain.s` - Entry Point (start here)

Smallest file, good warm-up. Current ARM32 code:

```asm
stmfd sp!, {r4, r6, r11, lr}   ;;; save registers
ldr r3, L1.1                    ;;; load address of _init_args
str r1, [r3]                    ;;; save argv
```

AArch64 equivalent:

```asm
stp x29, x30, [sp, #-16]!      ;;; save FP and LR
mov x29, sp                     ;;; set up frame pointer
adrp x3, _init_args             ;;; load page of _init_args
add x3, x3, :lo12:_init_args   ;;; add low 12 bits
str x1, [x3]                    ;;; save argv (x1 = argv per AAPCS64)
```

Note: The Poplog `.s` files use a preprocessor (`#_<` ... `>_#` sections contain
Pop-11 code that generates macro definitions). The assembler syntax outside those
sections is standard GNU as.

#### 3b: File-by-file Priority Order

1. **`amain.s`** - Entry point (must work first)
2. **`amisc.s`** - Miscellaneous support (many routines depend on this)
3. **`amove.s`** - Data movement (fundamental operations)
4. **`aarith.s`** - Arithmetic (core computation)
5. **`afloat.s`** - Floating point
6. **`aextern.s`** - External calls (FFI) -- depends on `ext_arm.c` fixes
7. **`aprocess.s`** - Process/coroutine switching (tricky, context-dependent)
8. **`asignals.s`** - Signal handling
9. **`aprolog.s`** - Prolog support
10. **`alisp.s`** - Lisp support (smallest, least critical for bootstrap)

#### 3c: Common Translation Patterns for Runtime

**Data widths**: All `.word` directives for pointers/Poplog words become `.xword`
(8 bytes). Integer immediates that fit in 32 bits can still use `.word` where
appropriate.

**Stack operations**: AArch64 requires 16-byte stack alignment at all times.
Use `stp`/`ldp` for pairs, or `str`/`ldr` with 16-byte-aligned offsets.

**Literal pools**: ARM32 uses `ldr rN, =constant` with literal pools. AArch64
prefers `movz`/`movk` sequences for constants, or `adrp`+`add` for addresses.

**Cache flushing**: AArch64 Linux supports `__clear_cache()` (same as ARM32).
The `dc cvau` / `ic ivau` / `dsb ish` / `isb` sequence is the raw instruction
equivalent.

### Stage 4: Fix C Support Files

#### `ext_arm.c` - External Call Helper

Current code assumes ARM32 ABI (4 integer registers, VFP float registers with
interleaved single/double allocation). AArch64 changes:

- **8 integer argument registers** (x0-x7), not 4 (r0-r3)
- **8 FP argument registers** (d0-d7 / s0-s7), simpler allocation (no interleaving)
- `int` stays 32-bit, but pointers/longs are 64-bit
- The `registers_buffer` struct needs to hold 8 64-bit integer regs + 8 128-bit FP regs
- May need a separate `ext_arm64.c` or `#ifdef __aarch64__` sections within `ext_arm.c`

#### `c_core.c` - Core C Runtime

- Signal context: AArch64 uses `struct sigcontext` with `pc` field (not `arm_pc`)
- `utsname` machine field will be `"aarch64"`
- Review all `#ifdef __arm__` sections for AArch64 equivalents

### Stage 5: Port Runtime Code Generators (4 `.p` files)

#### `ass.p` - Main Runtime Code Generator

The largest and most complex file. It generates machine code **in memory** at
runtime (unlike `genproc.p` which generates assembler text files).

Key differences from `genproc.p`:
- Must produce **relocatable** code (garbage collector moves procedures)
- Must use **indirect branches** for cross-procedure calls (absolute addresses
  loaded from a constants table, since relative positions change)
- AArch64 branch range is +/-128MB (`bl`), but for relocatable code, use
  indirect: `ldr x16, [constants_table, #offset]; blr x16`

I-code instructions map roughly to M-instructions but have different encoding.

#### `array_cons.p`, `closure_cons.p`, `pdr_compose.p`

Smaller files that generate specific code patterns. Each needs the same ARM32 ->
AArch64 instruction translation as `ass.p`.

### Stage 6: Build and Bootstrap

#### Cross-compilation (on host x86_64 machine)

```bash
# 1. Build cross-popc (compiler for arm64 target)
make stamp_popc

# 2. Build core library
make stamp_srclib

# 3. Create new corepop object files
make stamp_new_corepop
```

The output `.o` files will need to be assembled with the AArch64 cross-assembler:
```bash
make POP__as='aarch64-linux-gnu-as'
```

#### Transfer to Raspberry Pi 5

```bash
# Transfer build artifacts to RPi5
scp -r target/ pi@raspi5:~/poplog/

# On RPi5: compile C support files natively
cd ~/poplog
./scripts/mklibpop

# Link corepop natively
# (may need to edit poplink_cmd for correct paths)
```

#### Native rebuild on RPi5

Once a working `corepop` binary exists on the RPi5:
```bash
# Place corepop in target tree
cp corepop target/pop/corepop

# Configure and build
./configure
make
```

### Stage 7: Testing and Debugging

From PORTING.txt:
```bash
# Start GDB via poplog wrapper (sets up environment variables)
./poplog gdb pop/pop/basepop11

# In GDB:
(gdb) break setpop
(gdb) run
```

**Common issues to watch for:**
- Segfaults from incorrect stack alignment (must be 16-byte on AArch64)
- Wrong register usage in callee-saved vs caller-saved conventions
- 32-bit vs 64-bit pointer truncation (WORD_BITS must be 64)
- Branch range exceeded (use indirect branches for >128MB)
- Cache coherency (must flush icache after writing code to memory)
- Signal handler context structure differences

---

## Poplog Register Assignment Plan for AArch64

Proposed mapping (to be finalized during implementation):

| Poplog Role | ARM32 | AArch64 (Proposed) | Rationale |
|-------------|-------|---------------------|-----------|
| USP (user stack pointer) | r10 | x19 | Callee-saved, avoids C call save/restore |
| PB (procedure base) | r11 | x20 | Callee-saved |
| Pop temp 1 | r4 | x21 | Callee-saved |
| Pop temp 2 | r6 | x22 | Callee-saved |
| Frame pointer | (r11 shared) | x29 | AAPCS64 mandates x29 as FP |
| Link register | lr (r14) | x30/lr | Same role |
| C arg passing | r0-r3 | x0-x7 | Per AAPCS64 |
| C return value | r0 | x0 | Per AAPCS64 |
| Scratch / temp | r0-r3, r12 | x9-x15 | Caller-saved, free to use |

Note: x86_64 Poplog uses `rbx` as USP. The choice of callee-saved registers for
Poplog's dedicated registers is important -- it means C function calls won't
clobber them.

---

## Checklist

### Phase 1: Compiler (can be done on host, no RPi5 needed)
- [ ] Fix `sysdefs.p` for 64-bit (WORD_BITS=64, POPINT_BITS=61, STACK_ALIGN_BITS=128)
- [ ] Rewrite `asmout.p` for AArch64 GNU as syntax
- [ ] Rewrite `genproc.p` for AArch64 instructions (stub approach)
- [ ] Verify cross-popc builds: `make stamp_popc`
- [ ] Cross-compile simple Pop-11 files, inspect generated `.s` output

### Phase 2: Runtime Assembly (needs AArch64 assembler, ideally RPi5 for testing)
- [ ] Rewrite `amain.s` for AArch64
- [ ] Rewrite `amisc.s` for AArch64
- [ ] Rewrite `amove.s` for AArch64
- [ ] Rewrite `aarith.s` for AArch64
- [ ] Rewrite `afloat.s` for AArch64
- [ ] Rewrite `aextern.s` for AArch64
- [ ] Rewrite `aprocess.s` for AArch64
- [ ] Rewrite `asignals.s` for AArch64
- [ ] Rewrite `aprolog.s` for AArch64
- [ ] Rewrite `alisp.s` for AArch64

### Phase 3: C Support
- [ ] Fix `ext_arm.c` for AArch64 calling convention (8 int regs, 8 FP regs)
- [ ] Fix `c_core.c` signal context for AArch64
- [ ] Verify C files compile on RPi5

### Phase 4: Runtime Code Generators
- [ ] Rewrite `ass.p` for AArch64 (indirect branches, relocatable code)
- [ ] Rewrite `array_cons.p` for AArch64
- [ ] Rewrite `closure_cons.p` for AArch64
- [ ] Rewrite `pdr_compose.p` for AArch64

### Phase 5: Bootstrap
- [ ] Cross-compile full system from host
- [ ] Transfer to RPi5 and link natively
- [ ] Obtain working `corepop` binary on RPi5
- [ ] Native rebuild on RPi5

### Phase 6: Validation
- [ ] Pop-11 REPL starts and basic expressions work
- [ ] Prolog subsystem loads
- [ ] Common Lisp subsystem loads
- [ ] Standard ML subsystem loads
- [ ] External function calls work
- [ ] Floating point operations work
- [ ] Process/coroutine switching works
- [ ] Signal handling works
- [ ] Garbage collection works (critical for `ass.p` relocatable code)

---

## Reference: How the ARM32 Port Was Done

Timeline from git history (by Waldek Hebisch):

1. **2019-03-08**: Added ARM popc (`syscomp/arm/` - 3 files, ~2041 lines)
2. **2019-03-10**: Fixed order of side effects in genproc.p
3. **2019-04-04**: Misc ARM fixes (genproc.p, sysdefs.p, unixdefs.ph)
4. **2019-06-09**: Fixed exfunc closure code in asmout.p
5. **2019-06-13**: Added ARM runtime (10 `.s` files, 4 `.p` files, ext_arm.c -- ~4667 lines)
6. **2019-07-05**: Added `#ifdef __arm__` guard to ext_arm.c
7. **2020-08-12**: Fixed I_POP_FIELD in ass.p
8. **2021-07-07**: Build system integration (configure, Makefile.in)
9. **2022-09-18**: Enabled register use in ARM popc (significant refinement)

The ARM32 port took approximately 4 months of active development (March-July 2019)
for initial functionality, with bug fixes continuing through 2022.

---

## Upstream

- Upstream repo: https://github.com/hebisch/poplog
- Corepop binaries: https://poplog.fricas.org/corepops (no arm64 binary yet)
- This fork: branch `4-raspi5-arm64-port-round2`

---

## Tips

- **Study the x86_64 port alongside ARM32** when rewriting for AArch64. The x86_64
  port handles 64-bit words and has patterns (like `WORD_BITS=64`, `.quad` directives)
  that the ARM32 port doesn't. The AArch64 port needs to combine the 64-bit data
  model of x86_64 with the ARM-family instruction style.

- **Use `objdump -d` on cross-compiled output** to verify instruction encoding
  before running on hardware.

- **The `.arch armv8` directive is insufficient.** For RPi5 (Cortex-A76) you can use
  `.arch armv8.2-a` or just `.arch armv8-a` for maximum compatibility across
  AArch64 boards.

- **Start with the smallest files** (amain.s, alisp.s) to build confidence with
  AArch64 syntax before tackling the large code generators.

- **Keep the ARM32 files as reference** -- the *logic* is the same, only the
  instruction encoding and register names change.

- **QEMU user-mode emulation** (`qemu-aarch64-static`) can test individual
  binaries on the host without a real RPi5, though full system testing requires
  the real hardware.
