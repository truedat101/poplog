# Porting Poplog to RISC-V (rv64gc / Linux)

Status: **planning / Phase 0.** There is no RISC-V backend in the tree yet
(`pop/src/syscomp/` has `arm`, `arm64`, `i386`, `x86_64`). This is a from-scratch
code-generator port, the same class of work as the AArch64 / M-silicon port
(`PORTING-ARM64-*.md`). This doc is the roadmap and the staging setup; the
codegen backend itself is the multi-phase work that follows.

## Target

| | |
|---|---|
| ISA | **RV64GC** = RV64IMAFDC (base + mul/div, atomics, single+double FP, compressed) — the Linux baseline |
| ABI | **LP64D** — 64-bit `long`/pointer, doubles passed in FP regs |
| OS / object format | Linux, **ELF**, GNU `as` syntax |
| Hardware goal | a Scaleway RISC-V instance (rv64gc, ~4 cores, 8–16 GB); staged in QEMU until then |
| Build | console / no-GUI (`--with_no_x`); graphics is out of scope for the port |

### RISC-V facts that matter for the backend

* **Calling convention (LP64D):** integer args `a0–a7` (`x10–x17`), FP args
  `fa0–fa7`; returns in `a0`/`a1` (`fa0`/`fa1`); `sp`=`x2`, `ra`=`x1`, `gp`=`x3`,
  `tp`=`x4`, frame ptr `s0`/`fp`=`x8`; callee-saved `s0–s11`, `fs0–fs11`. This is
  the analog of the AArch64 work in `ext_arm.c` / `aextern.s` — get it wrong and
  FFI float/struct args break (cf. the arm64 `f_reg` stride + ddecimal bugs,
  `NOTES-FOR-MAINTAINERS.md` A10).
* **Self-modifying code:** Poplog generates and runs its own machine code. After
  writing code bytes, RISC-V requires a **`fence.i`** to make them visible to the
  instruction stream (the analog of AArch64 `__clear_cache`). On Linux this is
  exposed via `__builtin___clear_cache` / the `riscv_flush_icache` syscall; on
  SMP the kernel handles cross-hart flushing.
* **Tagged pointers / data model:** 64-bit word, like arm64 — reuse the arm64
  `WORD_BITS=64`, `POPINT_BITS`, alignment constants as the starting point
  (`sysdefs.p`); RISC-V has no special pointer-bit constraints.
* **PIE / relocation:** riscv64 Linux toolchains default to PIE; the engine lays
  memory at fixed addresses and is built no-PIE / no-hardening like the other
  ports. RISC-V uses `auipc`+offset for PC-relative addressing (`%pcrel_hi`/
  `%pcrel_lo` relocations) — the codegen and any hand-written `.s` must use these
  rather than absolute addresses.
* **No condition-code register:** RISC-V branches compare two registers directly
  (`beq`/`blt`/…), unlike arm64's NZCV flags — the conditional-branch lowering in
  `genproc.p` differs structurally from arm64.

## Backend surface (what has to be written)

A syscomp backend is three files (~3000 lines, cf. arm64 = 2947):

| File | Role | Effort |
|---|---|---|
| `syscomp/riscv64/sysdefs.p` | data model, OS/ABI constants, register names | small — adapt from `arm64/sysdefs.p` |
| `syscomp/riscv64/asmout.p` | emit RISC-V GAS assembly (mnemonics, directives, relocations) | large |
| `syscomp/riscv64/genproc.p` | instruction selection + procedure/frame codegen for the Poplog VM ops; must honour the frame contract (`PORTING-ARM64-FRAME-CONTRACT.md`) | large |

Plus, outside syscomp:
* C runtime / OS layer: syscalls, signal handling (SIGSEGV-driven GC grow),
  `mmap`/`mprotect`, the `fence.i` I-cache flush, and the `corepop` link recipe.
* `configure`: recognise `riscv64` → `POP_arch=riscv64` (done in Phase 0).
* A bootstrap `corepop` seed for riscv64 (see Bootstrap).

## Phase plan (mirrors the arm64 port)

0. **Env + scaffolding** *(this session)* — QEMU staging (`tools/riscv-qemu.sh`),
   `configure` arch recognition, and the `sysdefs.p` skeleton.
1. **`asmout.p`** — RISC-V assembly emission: the instruction/directive
   vocabulary popc uses, ELF sections, `%pcrel`/`%hi`/`%lo` relocations,
   procedure-length field. Validate by assembling emitted `.s` with
   `riscv64-linux-gnu-as`.
2. **`genproc.p`** — lower the Poplog VM operations to RV64GC; register
   allocation over the integer/FP files; frame layout per the frame contract;
   conditional branches via register compares.
3. **C / OS runtime** — corepop link from popc-emitted ELF + the C runtime;
   `fence.i` after codegen; signal/`mmap` glue.
4. **Bootstrap** — produce the first riscv64 `corepop`, then climb the ladder
   (`popc → src → corepop → basepop11 → images`).
5. **Validation** — the gate suite (incl. the FFI float regression,
   `tools/ffi-float-regression.p`) under QEMU.

## Bootstrap strategy

Chicken-and-egg, solved the same way as arm64: **cross-target popc** on an
existing host (x86-64 or arm64 Poplog) so it emits riscv64 `.s`, **cross-assemble
+ link** with `riscv64-linux-gnu` binutils/gcc to make the first `corepop`, then
run it under QEMU to self-host the rest. (Upstream may also publish a
`corepop_riscv64` seed, as it does for Solaris — `corepop_solaris.i386`; if so,
vendor it under `nix/seeds/` like the others.)

## Test harness (QEMU)

macOS can't run RISC-V **Linux** binaries under QEMU *user-mode* (no Linux host
kernel), so on the Mac the harness is **full-system** `qemu-system-riscv64`
booting a RISC-V Linux — see `tools/riscv-qemu.sh`, configured to approximate the
Scaleway instance (rv64gc, 4 cores, 8 GB, `virt` machine, serial console / no
GUI). On a **Linux** host (e.g. the x86-64 box) the lighter loop is
`qemu-user` + `binfmt_misc` + a `riscv64-linux-gnu` cross toolchain — cross-build
and run translated binaries directly, no VM boot. Both are valid; the Linux
`qemu-user` loop is faster for iterating on codegen, the Mac full-system loop
mirrors the real machine.

## Open questions to resolve early

* Does upstream (Hebisch) already have or want a riscv64 backend? **RESOLVED:**
  no — upstream is in preservation mode (no release plan), so write it fresh.
* Vector (`V`) and the exact `-march` of the staged hardware — start at the
  portable `rv64gc` baseline, tune later.

---

# P3: genproc transformation map (validated against real output)

This is the turnkey spec for the `genproc.p` rewrite, derived by capturing the
**actual** assembly the (scaffold) riscv64 popc emits and feeding it to
`riscv64-linux-gnu-as`. The asmout (P2) directives are already correct
(`.option arch, rv64gc`, `.quad/.byte/.word/.short`, labels, `.align 3`); only
the **instructions** (genproc) remain.

## The validation loop (use this every iteration)

On red5buntu, point `POP__as` (which popc invokes per `os_comms.p:74`) at a
wrapper that saves the `.s` and runs the real assembler:

```sh
cat > /tmp/rv-as.sh <<'EOF'
#!/bin/sh
for last in "$@"; do :; done            # popc passes (as <opts> -o ofile afile)
cp "$last" /tmp/rvcap.s 2>/dev/null      # afile (the .s) is last
shift; exec riscv64-linux-gnu-as -march=rv64gc "$@"
EOF
chmod +x /tmp/rv-as.sh
( cd pop/src && POP__as=/tmp/rv-as.sh ../../poplog popc -c -nosys -od /tmp trigc.p )
# -> /tmp/rvcap.s holds the emitted assembly; assembler errors are the to-do list.
```
Edit genproc on the Mac → `rsync` syscomp/riscv64 → `make POP_arch=riscv64
stamp_popc` → re-run the above → assembler errors shrink toward zero.

## Register mapping (roles unchanged; only the physical register differs)

Poplog's register roles map straight onto the RISC-V LP64D file. RISC-V GAS
accepts both ABI names and `xN`; the `regnumber` machinery uses `xN`, so keep
that. Note `x18` is **not** reserved on RISC-V (that was arm64's platform reg);
RISC-V's reserved set is `x0`=zero, `x1`=ra, `x2`=sp, `x3`=gp, `x4`=tp.

| Role (constant) | arm64 | RISC-V | ABI |
|---|---|---|---|
| `LR` | x30 | **x1** | ra |
| `SP` (R13) | sp | **x2** | sp |
| `USP` (R10) operand stack | x19 | **x9** | s1 (callee-saved) |
| `PB` (R11) procedure base | x20 | **x18** | s2 (callee-saved) |
| `WK_REG` (R0) work/arg0 | x0 | **x10** | a0 |
| `R1` work/arg1 | x1 | **x11** | a1 |
| `CHAIN_REG` (R2) | x2 | **x12** | a2 |
| `WK_ADDR_REG_1` (R3) | x3 | **x5** | t0 |
| `WK_ADDR_REG_2` (R12) | x12 | **x6** | t1 |
| `R4` scratch | x4 | **x7** | t2 |
| `R5` 2nd work | x5 | **x28** | t3 |
| `R9` scratch | x9 | **x29** | t4 |
| `R16` (IP0) indirect-branch scratch | x16 | **x30** | t5 |
| `pop_registers` (locals) | 21,22 | **19,20** | s3,s4 |
| `nonpop_registers` (locals) | 23,24,25 | **21,22,23** | s5,s6,s7 |

Machinery edits: `regnumber`/`reglabel` loop → iterate `0..31`, drop the `x18`
skip and the `wN` (32-bit-view) names; `sp`→2, `lr`→1 (not 31/30). `as_wreg`
→ identity (RISC-V has no separate 32-bit register names; byte/half ops use the
full register with `lb/lh/lw`/`sb/sh/sw`).

## Instruction translation (from the captured `xc_sin` procedure)

| arm64 emitted | RISC-V | note |
|---|---|---|
| `sub sp,sp,#16` | `addi sp,sp,-16` | frame alloc |
| `add sp,sp,#16` | `addi sp,sp,16` | frame free |
| `str x20,[sp,#0]` | `sd s2,0(sp)` | store: `off(reg)`, not `[reg,#off]` |
| `ldr x30,[sp,#8]` | `ld ra,8(sp)` | load |
| `ldr x1,[x20,#40]` | `ld t0,40(s2)` | field load |
| `str x1,[x19,#-8]!` (push) | `addi s1,s1,-8` ; `sd t0,0(s1)` | **no pre/post-index — split into 2** |
| `ldr x1,[x19],#8` (pop) | `ld t0,0(s1)` ; `addi s1,s1,8` | likewise |
| `mov x1,#7` | `li t0,7` | immediate |
| `mov x1,x2` | `mv t0,a2` | reg move |
| `bl xc_foo` | `call xc_foo` | sets `ra`; `call` handles far range |
| `ldr x20,xc_sin-8` | `auipc s2,%pcrel_hi(L);ld s2,%pcrel_lo(1b)(s2)` | PC-relative pointer load |
| `ret` | `ret` | same mnemonic (`jalr x0,ra,0`) |
| `cmp`/`b.cond` | `beq/bne/blt/bge ...` | **no flags reg** — compare two regs and branch |

## Structural rewrites (the genuinely different parts)

1. **No auto-index addressing.** Every Poplog user-stack push/pop (`[USP,#-8]!`
   / `[USP],#8`) becomes two instructions (`addi` + `sd`/`ld`). This touches the
   operand-formatting helpers used everywhere — do it once, centrally.
2. **No condition-codes register.** arm64's `cmp` + `b.cond` becomes a single
   RISC-V compare-and-branch (`blt`, `bgeu`, `beq`, …) on two registers; the
   M-code conditional lowering in genproc changes shape.
3. **PC-relative addressing** via `auipc`+`%pcrel_hi/_lo` (literal/label loads)
   rather than arm64's literal-pool `ldr =label` / `adrp`+`add`.
4. **Immediates** are 12-bit signed; larger values need `lui`/`li` expansion
   (the assembler's `li` pseudo handles most).
5. **`PD_LENGTH`** (`.set _L3, ((_L4 - xc_sin) >> 3) + 7`) already emits fine on
   ELF (this is the easy case the Mach-O port had to fight).

Suggested edit order within genproc: register layer (above) → the central
operand formatter (load/store `off(reg)` + the push/pop split) → mnemonics in the
`asm_emit` call sites → branch lowering → PC-relative loads → the procedure
prologue/epilogue. Gate each against the validation loop.
