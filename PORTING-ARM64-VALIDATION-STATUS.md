# AArch64 Port — Validation Status (WIP)

Companion to `PORTING-ARM64-LINUX-RPI5.md`. Captures the state of an attempted
smoke-test validation on branch `4-raspi5-arm64-port-round2`, host x86_64
Ubuntu, cross-toolchain `aarch64-linux-gnu-{gcc,as,ld}`.

**Status: Phase 2c (`make stamp_srclib`) blocked.** popc-compiler builds
end-to-end and emits AArch64 assembly, but the emitted code has multiple
classes of bug.  About 6 root-cause fixes already applied (uncommitted) push
the build through the cross-popc stage; the remaining gaps below need
engineering before a runnable `new_corepop` is reachable.

---

## What was discovered before any code changes

The pre-existing state of the branch:

- `Makefile` was generated for `POP_arch = arm` (32-bit ARM) — not arm64.
  Configure picks the arch from `HOST_ARCH` env var; needs
  `HOST_ARCH=aarch64 ./configure --with_no_x` to set `POP_arch = arm64`.
- `pop/src/unixdefs.ph` `struct STATB` had no branch for `ARM64_LINUX`.
  Falling through to the `#_ELSE need to define !` would have failed compile;
  even if it didn't, the X86_LINUX 64-bit branch is not the right model — the
  glibc layout for aarch64 differs from x86_64 (mode before nlink, no `__pad0`,
  an 8-byte `__dev_t __pad1` between `rdev` and `size`). I verified this from
  `/usr/aarch64-linux-gnu/include/bits/struct_stat.h`.
- `pop/src/syscomp/arm64/genproc.p` has multiple Pop-11-syntax and
  AArch64-encoding bugs (see fixes below).

The audit done in plan-mode rated all 17 ported source files plus the 2 C
helpers as `[DONE]` based on absence of ARM32 mnemonics. That rating was
over-optimistic: it confirmed the files were re-keyed for AArch64 instructions,
but did not catch (a) Pop-11 dialect errors that prevent `popc` from running,
nor (b) M-instruction implementations that emit invalid AArch64 assembly.

---

## Fixes applied (uncommitted; see `git diff`)

### `pop/src/unixdefs.ph`

`struct STATB` lines 296–317. Added `ARM64_LINUX` to the `mode_t ST_MODE;
nlink_t ST_NLINK;` branch (aarch64 puts mode first, like 32-bit ARM, unlike
x86_64). Added a new `#_ELSEIF DEF ARM64_LINUX` branch with `long ST_PAD3`
(8-byte) for the `__dev_t __pad1` slot between `rdev` and `size`.

### `pop/src/syscomp/arm64/genproc.p`

1. `gen_branch("b.lt", neg_lab)` / `gen_branch("b.hi", else_lab)` →
   `'b.lt'` / `'b.hi'`. Pop-11 word constants (double-quoted) cannot contain
   `.`; needs single-quoted strings. (M_ASH, M_BIT.)

2. `emit_stp_push` / `emit_ldp_pop`: `i = 1;` → `1 -> i;`. The `=` form is an
   equality test that returns boolean; the loop variable was never initialized,
   yielding `BAD SUBSCRIPT FOR INDEXED ACCESS, INVOLVING: 0 {x21 x30}` from
   `subscrv` at index 0 (Pop-11 vectors are 1-indexed).

3. `outinst`: comment character `@` (ARM32 GAS) → `//` (AArch64 GAS line
   comment). Was producing `Error: junk at end of line, first unrecognized
   character is '@'` on every M-code listing line.

4. `M_CREATE_SF` regmask: `1 << n` (where `n` is hardware register number,
   e.g. 21 for x21, giving 0x200000) overflows the 16-bit `PD_REGMASK` and
   triggers `value 0x200000 truncated to 0x0` from `as`. The runtime in
   `pop/src/arm64/aprocess.s` uses a 16-bit-fitting bit map: x21→bit 4,
   x22→bit 6, x23→bit 7, x24→bit 8, x25→bit 9. genproc.p now applies that
   remapping. (Comment in aprocess.s line 113 documents the bit positions.)

5. New helper `as_wreg(reg)` near the `regnumber/reglabel` definitions:
   converts `"x21"` → `"w21"`. Used in `gen_reg_load` (for `ldrb`/`ldrh`
   destination), `gen_reg_store` (for `strb`/`strh` source), `M_UPDs` (for
   the `strh` source), and in the `sxtb`/`sxth` source operand. AArch64 only
   accepts the W form (32-bit view) for byte/half-word load/store and for the
   source of sign-extending instructions.

These changes get `make stamp_popc` clean and let `make stamp_srclib` reach
the per-file compilation phase. They don't fix the issues in the next section.

---

## Remaining gaps (blocking smoke test)

Counted from `/tmp/build-srclib.log` after the fixes above. Categories sorted
by occurrence; root causes are best-guesses pending detailed inspection.

### A. `.xword <false>` text leaking into emitted asm — 161 errors in 1 file

```
Error: bad expression
Error: junk at end of line, first unrecognized character is `f'
```

The popc-emitted assembly contains literal lines like:

```asm
.xword  _LC
.xword  <false>
.xword  <false>
...
```

`<false>` is Pop-11's syntactic-print form for the boolean `false`, not a
valid asm token. Path: `asm_outword(...)` → `outdatum` (asmout.p) →
`asmf_pr(value)` → `sys_syspr(value)` (lib.p:51), and `sys_syspr(false)`
prints `<false>`.

The boolean must not be reaching `asmf_pr` directly: somewhere upstream a
conversion to a label/integer (e.g. `false_lab` from
`unique_struct_lab(false)` in `poplink_main.p`) should happen first. Suspect
sites: vector / closure / procedure-record initialization in
`pop/src/syscomp/genstruct.p` or in the arm64 port's `outwords`-style
helpers. The same Pop-11 source compiles cleanly on x86_64, so this is an
arm64-port-specific regression — likely a missing `isboolean(...)` guard in
arm64-specific code, or an arm64 procedure that calls `asm_outword(false)`
where x86_64 calls something that resolves to a label.

**Recommendation**: instrument `asmf_pr` with an `isboolean` guard that
mishaps with the call stack — find the upstream caller, fix there.

### B. Pop-11 mishaps during compile (well before any assembler runs)

| Mishap | Count | Likely cause |
|---|---|---|
| `ITEMS LEFT ON STACK AFTER COMPILING FILE` | 75 | An M-instruction handler in `genproc.p` is leaving values on the stack — emit-side stack discipline mismatch |
| `ILLEGAL OPERAND` | 73 | An M-instruction handler is rejecting an operand shape it should accept (likely a missing case in operand classification) |
| `PROCEDURE NEEDED` | 66 | A name lookup is returning a non-procedure where the M-translator expects one — possibly missing definition in arm64 `genproc.p`, falling back to a raw constant |

These three categories likely collapse to 2–4 root causes once one example
is debugged with `pop_debugging = true` and the file's source identified.
Many .p files trigger them, suggesting a single shared M-instruction (or a
small set) is broken.

### C. AArch64 instruction-encoding errors (assembler-level)

| Pattern | Example | Fix needed |
|---|---|---|
| Logical immediate not a valid bitmask | `tst x1, #34`, `orr x1, x22, #11` | Logical immediates must encode as `(N, immr, imms)` bitmask — arbitrary integers don't qualify. M_BIT / M_BIS must either pick a bitmask-encodable immediate, load to register first (`mov xN, #imm; orr Xd, Xn, xN`), or fall back to `movz/movk`. |
| `sub Xd, Xn, sp` | `sub x2, x0, sp` | sp can be Xn or destination but not Xm. Emit `mov xT, sp; sub Xd, Xn, xT` instead. |
| Shift-by-register on non-shift instructions | `orr x9, x9, x3, lsl x1` | AArch64 only allows shift-by-immediate in `orr`/`and`/`eor` operand. For shift-by-register, compute `lsl xT, x3, x1` first then `orr x9, x9, xT`. (Or use the `lslv`/`lsrv` instructions.) |

### D. Misc

- `_K_EXTERN_TYPE must agree with ext_arm64.c` — popc looks for a file named
  `ext_arm64.c`, but the actual file is `pop/extern/lib/ext_arm.c`. Either
  rename the file (and update the build) or change the name popc expects in
  `pop/src/syscomp/arm64/sysdefs.p` / nearby. Search for `ext_arm64.c` in
  the syscomp dir.

- `ERROR IN ! OR @ (unknown structure field)` — one occurrence; somewhere in
  the arm64 code or shared headers a `struc!FIELD` access references an
  unknown field. Likely related to PD_REGMASK / PD_FRAME_LEN sizing change
  needed (see also "PD_REGMASK is 16-bit but arm64 wants more" thread,
  unresolved — current fix uses bit-remap, but might mask other issues).

---

## Pipeline plumbing learned along the way

Useful for whoever picks this up:

- `HOST_ARCH=aarch64 ./configure --with_no_x` is the right configure
  invocation. `target/pop/corepop` (host x86_64) must already exist.
- `POP__as` env var must be an **absolute** path; popc's `sysobey` doesn't
  PATH-search. Use `POP__as=/usr/bin/aarch64-linux-gnu-as`.
- To capture popc's emitted `.s` files for inspection (they're auto-deleted),
  wrap the assembler:

  ```sh
  cat > /tmp/keep_a.sh <<'EOF'
  #!/bin/sh
  for arg in "$@"; do
      case "$arg" in *.a|*.s) cp "$arg" "/tmp/save_$(basename $arg)" ;; esac
  done
  exec /usr/bin/aarch64-linux-gnu-as "$@"
  EOF
  chmod +x /tmp/keep_a.sh
  POP__as=/tmp/keep_a.sh make stamp_srclib
  # captured files appear in /tmp/save_popcNNN*.a
  ```

- `make stamp_popc` does **not** invoke any C or asm tools — pure Pop-11
  saved-image generation, runs entirely on host x86_64.
- `make stamp_srclib` is where the cross-assembler enters. Failures from this
  point on are split between popc Pop-11 mishaps (genproc.p bugs) and
  aarch64-as rejections (asmout.p / instruction-encoding bugs).
- `make stamp_new_corepop` (not yet reached) will additionally need
  `CC=aarch64-linux-gnu-gcc` and `POP__cc="aarch64-linux-gnu-gcc -no-pie -Wl,-export-dynamic -Wl,--no-as-needed"`,
  plus `libncurses-dev:arm64` and `libtinfo-dev:arm64` multi-arch installed
  on the host. None of that has been exercised yet.

---

## Recommended triage order for the next attempt

Start with the highest-fanout root causes, since each fix may resolve dozens
of downstream errors:

1. **Boolean-leak (Category A)**: instrument `asmf_pr` with an `isboolean`
   guard that mishaps with full backtrace; identify the calling arm64 routine
   and fix it. Single fix, ~161 errors gone.

2. **PD_REGMASK width / `ERROR IN ! OR @`**: confirm whether widening
   PD_REGMASK to `int` for ARM64_LINUX (vs the bit-remap approach already
   applied) is cleaner — if the runtime / ass.p uses `ldrh` and `tst w0,
   #imm`, the remap stays; if there are other consumers, widening may be
   simpler. Inspect all `PD_REGMASK` references.

3. **PROCEDURE NEEDED (Category B-3)**: enable `pop_debugging = true` in
   `mk_cross` invocation, capture the failing identifier; likely points at
   a small set of missing M-instruction handlers in arm64/genproc.p.

4. **ILLEGAL OPERAND / ITEMS LEFT (Category B-1, B-2)**: same as above —
   one focused trace will identify the broken handler(s).

5. **AArch64 encoding (Category C)**: rework M_BIT, M_BIS, M_ASH (variable
   shift) to either preflight-encode logical immediates or always fall back
   to register form. The instruction-encoding constraints are well documented
   (ARM ARM, "Logical (immediate)").

6. **`ext_arm64.c` filename**: rename file or fix the name in syscomp.

7. Then attempt `make stamp_new_corepop` — expect a fresh wave of issues at
   link time (undefined symbols from the runtime `.s` files, or signal-
   context layout in `c_core.c`).

---

## Files touched (uncommitted)

```
modified:   pop/src/unixdefs.ph
modified:   pop/src/syscomp/arm64/genproc.p

untracked artifacts (regenerated):
    Makefile        (from configure)
    poplog          (from configure)
    target/pop/{popc,poplink,poplibr}.psv
    stamp_popc, stamp_dirs_and_symlinks
```

Diffs are localized; review with `git diff -- pop/src/unixdefs.ph
pop/src/syscomp/arm64/genproc.p`. The genproc.p changes are mechanical
(literal-form, equality-vs-assignment, comment char, register form). The
`as_wreg` helper is new; its definition is near the `regnumber`/`reglabel`
table around line ~300. The regmask remap is in `M_CREATE_SF` around line
~1400.

Build logs from the last attempt are at `/tmp/build-popc.log` and
`/tmp/build-srclib.log` (will be wiped on reboot).
