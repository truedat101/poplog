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

* Does upstream (Hebisch) already have or want a riscv64 backend? Coordinate to
  avoid divergence (as with Solaris/FreeBSD).
* Vector (`V`) and the exact `-march` of the staged hardware — start at the
  portable `rv64gc` baseline, tune later.
