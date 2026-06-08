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

### Stage 7: QEMU Host Validation (gate before touching hardware)

QEMU user-mode emulation (`qemu-aarch64-static`) runs the aarch64 `basepop11`
on the x86_64 host, giving a fast edit/test loop without an RPi5. **It only
produces meaningful results once the precondition gate below is green.**

#### 7.0 Precondition gate — read this first

> **Do not run QEMU validation until `make stamp_srclib` completes with ZERO
> `WARNING items-left after file` lines.**
>
> The warn-and-drain band-aid in `pop/src/syscomp/do_asm.p` lets `stamp_srclib`
> "succeed" while ~290 of ~330 core library files still leave `<false>` /
> `<procedure %OP_CALL>` on the Pop-11 stack. Those files are compiled to
> **semantically wrong machine code**. A `basepop11` linked in that state will
> crash or hang under QEMU no matter how many runtime `.s` fixes are applied.
>
> This is exactly why the first QEMU validation attempt made no progress: the
> binary was built from broken codegen. Fix Stage 2/5 codegen first; QEMU is
> wasted effort before then.

Gate checklist (all must be true before proceeding to 7.1):

- [ ] `make stamp_popc` clean
- [ ] `make stamp_srclib` clean **and** `grep -c 'items-left after file' /tmp/build-srclib*.log` is `0`
- [ ] `do_asm.p` warn-and-drain reverted to a hard mishap (so a green build is a *correct* build, not a drained one)
- [ ] `make stamp_new_corepop` regenerated *after* a clean srclib (delete the stale `stamp_new_corepop` first so it actually rebuilds)
- [ ] `file target/pop/basepop11` reports `ELF 64-bit ARM aarch64`

#### 7.1 One-time host setup

`target/pop/basepop11` is dynamically linked and `NEEDED`s
`libncurses.so.6 libtinfo.so.6 libm.so.6 libc.so.6 ld-linux-aarch64.so.1`.
The `gcc-aarch64-linux-gnu` cross sysroot (`/usr/aarch64-linux-gnu/lib`) ships
`ld-linux` + `libc` + `libm` but **not** `libncurses`/`libtinfo` — so
`QEMU_LD_PREFIX` pointed at the bare cross sysroot will fail to load the binary.
Provide a complete aarch64 sysroot:

- [ ] `qemu-aarch64-static` installed (`which qemu-aarch64-static`)
- [ ] aarch64 multiarch libs available, e.g.
      `sudo dpkg --add-architecture arm64 && sudo apt install libncurses6:arm64 libtinfo6:arm64`
      (or copy `/lib/aarch64-linux-gnu` + `/usr/lib/aarch64-linux-gnu` from an RPi/aarch64 rootfs)
- [ ] A sysroot dir that contains **all** five NEEDED libs; export it:
      `export QEMU_LD_PREFIX=/usr/aarch64-linux-gnu` (or your assembled rootfs)
- [ ] `aarch64-linux-gnu-readelf -d target/pop/basepop11 | grep NEEDED` — confirm every NEEDED lib resolves under `$QEMU_LD_PREFIX`

#### 7.2 Smoke test procedure

The `./poplog` wrapper sets the `pop*` env vars then `exec "$@"`, so prefix the
binary with the emulator:

```bash
# Pop-11 banner + immediate exit (most basic "does it start at all")
echo 'sysexit();' | QEMU_LD_PREFIX=$QEMU_LD_PREFIX \
  ./poplog qemu-aarch64-static target/pop/basepop11 %nort

# Interactive REPL
QEMU_LD_PREFIX=$QEMU_LD_PREFIX \
  ./poplog qemu-aarch64-static target/pop/basepop11 %nort %noinit
```

Run in order; stop at the first failure and debug it (7.3) before moving on:

- [ ] `basepop11` reaches `setpop` without an early SIGSEGV/SIGILL/SIGBUS
- [ ] Pop-11 banner prints
- [ ] `2 + 2 =>` returns `** 4` (integer arithmetic — exercises `aarith.s`, M-code path)
- [ ] `1.5 * 2 =>` returns `** 3.0` (float — exercises `afloat.s`)
- [ ] `[a b c] ==> ` prints the list (heap alloc + GC structures)
- [ ] A `define`d procedure runs (runtime code generator `ass.p`, closures)
- [ ] A deliberate GC (`sysgarbage();`) survives (relocatable code in `ass.p`)
- [ ] `sysexit();` exits cleanly (no abort, exit code 0)

#### 7.3 Debugging under QEMU + GDB

`qemu-aarch64-static` exposes a gdbstub with `-g <port>`:

```bash
# Terminal 1: start under emulator, paused, gdbstub on :1234
QEMU_LD_PREFIX=$QEMU_LD_PREFIX \
  ./poplog qemu-aarch64-static -g 1234 target/pop/basepop11 %nort

# Terminal 2: attach the aarch64 GDB
gdb-multiarch target/pop/basepop11
(gdb) set architecture aarch64
(gdb) target remote :1234
(gdb) break setpop
(gdb) continue
```

For stubbed runtime routines (Stage 3 uses `b .` infinite loops), a hang is the
signal — break in, inspect `x0-x30`/`sp`, identify the unimplemented routine.

**Common issues to watch for:**
- Segfaults from incorrect stack alignment (must be 16-byte on AArch64)
- Wrong register usage in callee-saved vs caller-saved conventions
- 32-bit vs 64-bit pointer truncation (WORD_BITS must be 64)
- Branch range exceeded (use indirect branches for >128MB)
- Cache coherency (must flush icache after writing code to memory)
- Signal handler context structure differences
- **QEMU-specific:** user-mode QEMU emulates signals/`mmap`/coroutine stack
  switching imperfectly. Failures isolated to `aprocess.s`, `asignals.s`, or
  FFI may be QEMU artifacts — re-confirm them on real RPi5 hardware (Stage 8)
  before treating them as port bugs.

### Stage 8: Native RPi5 Validation

Only after Stage 7 passes under QEMU. Transfer the tree (Stage 6), rebuild
natively on the Pi, then re-run the 7.2 smoke test and the Phase 6 feature
matrix on real hardware:

- [ ] Native `make` completes on RPi5 (Debian/Raspbian 64-bit)
- [ ] 7.2 smoke test passes natively (no QEMU)
- [ ] Re-confirm any QEMU-suspect failures (signals / `aprocess.s` / FFI)
- [ ] Full Phase 6 feature matrix passes on hardware
- [ ] Capture a known-good `corepop` for the arm64 corepops archive

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

### Phase 5: Host Bootstrap (x86_64, no RPi5 needed)
- [ ] `make stamp_srclib` clean **with zero `items-left after file` warnings** (drained ≠ done)
- [ ] `do_asm.p` warn-and-drain reverted to a hard mishap
- [ ] Stale downstream stamps deleted, `make stamp_new_corepop` regenerated
- [ ] aarch64 `target/pop/basepop11` linked from a *clean* srclib

### Phase 5.5: QEMU Host Validation Gate (Stage 7)
> Blocked until every Phase 5 box is checked — see Stage 7.0. The first QEMU
> attempt was fruitless because this gate was not met.
- [ ] 7.1 host setup: complete aarch64 sysroot, all 5 NEEDED libs resolve
- [ ] 7.2 smoke test passes end-to-end under `qemu-aarch64-static`
- [ ] Phase 6 feature matrix passes **under QEMU**

### Phase 6: Validation (run under QEMU first, then on RPi5 hardware — Stage 8)
- [ ] Pop-11 REPL starts and basic expressions work
- [ ] Prolog subsystem loads
- [ ] Common Lisp subsystem loads
- [ ] Standard ML subsystem loads
- [ ] External function calls work
- [ ] Floating point operations work
- [ ] Process/coroutine switching works
- [ ] Signal handling works
- [ ] Garbage collection works (critical for `ass.p` relocatable code)

### Phase 7: Native RPi5 (Stage 8)
- [ ] Transfer to RPi5 and link/build natively
- [ ] Obtain working `corepop` binary on RPi5
- [ ] 7.2 smoke test + Phase 6 matrix pass on hardware (no QEMU)
- [ ] Re-confirm any QEMU-suspect failures (signals / `aprocess.s` / FFI)

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

---

## Portability to other AArch64 platforms

The ARM32 port carried a real "how broad a target?" question (armel vs armhf,
soft- vs hard-float, ARMv6 vs v7, Thumb, optional VFP/NEON). **On AArch64 that
question is almost entirely gone**: there is one ABI (AAPCS64 / LP64 /
little-endian), FP+SIMD are *mandatory*, and `armv8-a` is a universal baseline
every AArch64 core implements. This port is written to that baseline and is not
tuned to the Pi 5's Cortex-A76, so moving to a MediaTek Genio 520/720
(Cortex-A78+A55) or a Qualcomm Snapdragon (Kryo) Linux board is mostly a
*rebuild*, not a re-port. Concretely:

**Already generic (no change needed):**

- **ISA baseline.** Every `.s` file and the runtime code generator emit
  `.arch armv8-a` (see `asmout.p`). No `-mcpu`/`-mtune`/LSE/optional extensions,
  so the same code runs on A53/A55/A72/A76/A78/Kryo alike. Tuning for a specific
  core would only buy performance on the *C* support files, at the cost of
  breadth -- not worth it. (The hand-written `.s` and the JIT are assembly, so
  compiler `-mcpu` would not touch them anyway.)
- **I-cache coherency for JIT'd code.** Poplog compiles code at the REPL and
  must sync I/D caches afterwards. `CACHEFLUSH` (`sysdefs.p`) is wired to
  `__clear_cache`, which reads `CTR_EL0` and issues the correct
  `dc cvau`/`ic ivau`/`dsb`/`isb` for *that* core's cache-line size -- so it is
  already correct across microarchitectures (this is the #1 thing that bites
  naive AArch64 JIT ports; here it is handled).
- **Calling convention, data model, endianness, FP-as-single** -- all fixed by
  AAPCS64; identical on every AArch64 Linux board.

**Platform-specific knobs to check when retargeting:**

1. **Kernel page size (the main one).** `sysdefs.p VPAGE_OFFS` is hard-coded to
   `16384` because the Pi 5 (rpi-2712 kernel) uses **16 KB** pages, and saved
   images are `mmap`'d `MAP_FIXED`, which requires the base+offset to be aligned
   to the *runtime* page size. Most other AArch64 Linux boards (Genio, Snapdragon
   dev boards, generic arm64 distros) use **4 KB** pages -- a 16 KB-aligned image
   still loads there (16384 is a multiple of 4096), so the current images are
   forward-compatible to 4 KB. But a **64 KB**-page kernel (some server/RHEL
   configs) would *reject* a 16 KB-aligned image. The robust options, in order of
   preference: (a) build natively on the target with `VPAGE_OFFS` set to that
   kernel's page size; (b) set `VPAGE_OFFS = 65536` for "build once, load
   anywhere" images (64 KB is a multiple of 4/16/64 KB -- costs a little image
   padding); (c) make it dynamic via `sysconf(_SC_PAGESIZE)`. Check with
   `getconf PAGE_SIZE` on the target first.
2. **Non-PIE fixed load address.** `basepop11` is linked `-no-pie` and the saved
   image loads at its fixed link address. Standard Linux allows this; a kernel
   that *forces* PIE, or a very different memory map / high `mmap_min_addr`, could
   refuse it. Rare, but verify the image loads (not just that it builds).
3. **PAC / BTI / MTE on newer cores + hardened kernels.** ARMv8.3+ pointer
   authentication and BTI are not used or required here, but if a distro enforces
   **BTI** on executable mappings, the JIT'd pages (plain `br`/`blr`, no `bti`
   landing pads) could fault. It works today because the binary does not opt into
   BTI (`GNU_PROPERTY_AARCH64_FEATURE_1_BTI`). Keep in mind for hardened targets.
4. **libc.** The toolchain assumed is `aarch64-linux-gnu-*` (glibc). A musl distro
   (e.g. Alpine) needs a musl cross-toolchain; `__clear_cache` is a compiler
   builtin so it is fine, but other `_extern` C support assumes glibc.

**big.LITTLE (Genio/Snapdragon) is a non-issue** for correctness: Poplog's core
is single-threaded, and both the big and LITTLE clusters implement the same
`armv8-a` ISA, so it simply runs on whichever core the scheduler picks.

Bottom line: for a Genio 520/720 or a Snapdragon Linux board, expect to (1)
check `getconf PAGE_SIZE` and set `VPAGE_OFFS` accordingly (likely 4 KB), (2)
cross-build with the generic `aarch64-linux-gnu` toolchain, (3) verify the image
*loads* and the REPL JIT runs. No instruction-set or ABI work should be needed.

---

## Graphical subsystem (X11 / Xt / Motif / XVed) — status & remaining work

**Status: not yet built or tested on AArch64.** The console core (all four
languages, all three saved images) is complete, but the build is currently
configured **`-nox`** (`Makefile` `XL_FLAG=-nox`), so nothing graphical has been
compiled or linked. The X source is all present in-tree; only the *core* externs
are built on the Pi (`c_core.o`, `c_callback.o`, `ext_arm.o`, … — no `Xpw`
objects, no `libXpw.so`, no `xved.psv`).

### What "graphical" comprises in Poplog

- `pop/x/Xpw/` — Poplog's primitive X widget set (15 C files: `Graphics.c`,
  `Text.c`, `XpwComposit.c`, `CallMethod.c`, …) → `libXpw.so`.
- `pop/x/ved/` — **XVed**, the windowed editor → `xved.psv` (built via `mkxved`;
  `stamp_images` already lists `stamp_xved`).
- `pop/x/ui/`, `pop/x/src/` — the Pop-11 X / widget / graphics libraries.
- `XtPoplog.c` — the Xt ↔ Poplog glue (event loop + callback dispatch).
- Pop-11 graphics (`XpwGraphic` line/pixmap drawing) and XVed need only
  **X11 + Xt + Xpw**; the heavier widget GUI (propsheets, menus) needs **Motif**
  (`libXm`).

### Pi prerequisites (currently missing)

- Runtime `libX11.so.6` / `libXt.so.6` / `libXext.so.6` are present, but the
  **`-dev` packages are not** (no bare `libX11.so` link / full headers):
  `sudo apt install libx11-dev libxt-dev libxext-dev`.
- **Motif is entirely absent** (`libXm`, `/usr/include/Xm`). For the full GUI:
  `sudo apt install libmotif-dev`. Not needed for XVed / basic graphics.
- A display for testing: the Pi 5 desktop, SSH X-forwarding, or headless `Xvfb`.

### Work required (in order)

1. **Install the X (and optionally Motif) `-dev` packages** above.
2. **Flip the build off `-nox`** (`XL_FLAG`) and rebuild. This compiles the 15
   `Xpw` C files → `libXpw.so`, links X into `basepop11`, and builds `xved.psv`.
   *Low AArch64 risk* — the Xpw C is generic, portable X-widget code, and Motif
   builds normally on aarch64 (standard Debian package).
3. **Validate the C→Poplog callback path — the real AArch64 work.** X is
   event-driven: Xt calls *back into* Poplog for every event/callback (button,
   expose, timer), via `XtPoplog.c` → `aextern.s` (`_pop_external_callback`,
   `_exfunc_clos_action`) → `Sys$-Extern$-Callback`. These trampolines are
   *implemented but have never executed* under `-nox`. It is the same class of
   frame / register / USP-reconstruction asm as the forward `_extern` path, but
   in the harder *reverse* direction (rebuilding Poplog's register + stack state
   from a cold C entry), so expect it to need the same gdb-on-the-Pi validation
   pass the forward path got. The arg marshaller `copy_external_arguments` must
   also handle X's call patterns — mostly pointers (fine); watch struct-by-value
   and any varargs (Poplog generally avoids Xt's `Va*` forms).
4. **Test on a display** (desktop / X-forward / `Xvfb`).

### Risk summary

The **forward** call path (Poplog→C) already works — it is how the runtime
reaches `_pop_set_async_check`, `__clear_cache`, etc. — so calling *into*
libX11/libXt is on solid ground. The genuinely new AArch64 risk is the
**callback trampolines** (step 3); everything else is "install dev libs, flip the
flag, rebuild." Motif is optional unless the full widget GUI is wanted.
