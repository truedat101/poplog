# AArch64 Port — Validation Status (WIP)

Companion to `PORTING-ARM64-LINUX-RPI5.md`. Captures the state of an attempted
smoke-test validation on branch `4-raspi5-arm64-port-round2`, host x86_64
Ubuntu, cross-toolchain `aarch64-linux-gnu-{gcc,as,ld}`.

> **Workflow update (2026-06-03) — debugging moved to real RPi5 hardware.**
> A Pi 5 (DietPi, Debian 13 trixie, kernel 6.12, native `gdb`) is reachable over
> SSH as `raspi5` (user `dietpi`). Cross-build on the x86_64 host, `rsync` the
> tree to `~/poplog` on the Pi (sed the hardcoded path in the `poplog` wrapper:
> `/home/dkords/.../poplog` → `/home/dietpi/poplog`), then run/debug **natively**.
> Native gdb is far faster and more reliable than the qemu gdbstub, and avoids
> qemu user-mode artifacts (e.g. the `linux_setper` execve re-exec). All crashes
> below reproduce natively, so they are real bugs, not emulation artifacts.

> **Runtime bring-up progress (2026-06-03) — two more real bugs fixed; basepop11
> now executes far into startup.** With the codegen + stack-leak work done,
> running the linked `basepop11` exposed runtime bugs, each fix advancing it:
> 1. **Frame-size epilog bug** (`arm64/genproc.p`, `M_UNWIND_SF`): freed
>    `(Nstkvars+1)*16`, treating every stkvar as a 16-byte slot, but
>    `M_CREATE_SF` packs non-POP stkvars (e.g. `lstackmem` structs) 8 bytes each
>    rounded to 16. For a proc with non-POP stkvars this over-freed by 16 bytes,
>    restoring the saved LR from the wrong offset → return-to-garbage. Fixed by
>    carrying the exact allocated byte count (`sf_var_bytes`) from CREATE to
>    UNWIND. Advanced basepop11 from "exits cleanly during `Setpop_setup_system`"
>    → "allocates heap, runs into execution."
> 2. **`_move`/`_bfill` arg-order bug** (`arm64/amove.s`): both popped their USP
>    args into exactly memmove/memset order (`x0=dst,x1=src,x2=n`) but then did a
>    spurious `x0<->x2` (resp. `x0<->x1`) swap, calling `memmove(n,src,dst)` /
>    `memset(val,dst,n)`. With `n`=0 (Prolog-area init) this became
>    `memmove(NULL,…,huge)` → NULL-write segfault in `Area_expand`. The correct
>    template is `_fill` right below them (no swap). Fixed by removing both
>    swaps. Advanced past `Area_expand`.
>
> **Current crash (next):** an unhandled exception is raised during startup and
> reaches `sys_exception_final` → `sys_pr_message` (errors.p:380), which crashes
> walking the call stack: `_sframe!SF_OWNER` returns `popint 0` (not a procedure
> record), so `call_pdr!PD_PROPS` (errors.p:544) dereferences 0x3-16. Two threads
> to chase: (a) what exception is being raised (root cause), and (b) the
> call-stack-frame layout bug in the reporter — `SF_OWNER` reading 0 implicates
> the stack-frame owner placement (`M_CREATE_SF` `push_operand(PB)`) vs the
> `SF_OWNER` field offset, and/or the callstack code in `aprocess.s`.
> Both fixes are committed (`ab99219`).

> **Update (2026-06-03, later) — the SF_OWNER=0 crash is the big one: arm64 stack
> frames do not match the canonical Poplog `STACK_FRAME` layout.** Diagnosed on
> the Pi with native gdb. The crash is the error reporter (`sys_pr_message`,
> reached via `sys_exception_final` while trying to output via `charout`) walking
> the call stack: `_caller_sp_flush() -> _sframe`, then `_sframe!SF_OWNER` returns
> `popint 0` instead of a procedure record (the real owner, `c_charout`, sits 32
> bytes away in the frame).
>
> Root cause: the **canonical frame is 8-byte-packed** (x86_64 `M_CREATE_SF`
> uses `pushq` for regs/dlocals/pop-stkvars/owner and `subq (n)*8` for non-pop
> stkvars; `STACK_FRAME` in `syscomp/symdefs.p` lays fields out 8 bytes apart:
> `SF_RETURN_ADDR`@FP-8, `SF_OWNER`@FP, `SF_LOCALS`@FP+8). **arm64 uses 16-byte
> slots** (`push_operand` = `str …,[sp,#-16]!`) to keep SP 16-aligned, producing
> `owner,pad,return,pad` — doubled and mis-ordered. So every frame *consumer* —
> the call-stack walkers (`errors.p`, `control.p`, `iscaller.p`,
> `caller_valof.p`, `plogcore.p`), the GC frame scan (`gccopy.p`, `gcncopy.p`),
> `_caller_sp`, and `m_trans.p`'s offset / `PD_FRAME_LEN` math — misreads arm64
> frames. Procedure call/return is self-consistent (prologue/body/epilog agree),
> which is why bring-up got this far; only frame *introspection* breaks.
>
> **Fix (substantial — the porting docs' "Hard" item):** rework the arm64
> backend so frames match the canonical 8-byte-packed `STACK_FRAME`, while
> keeping SP 16-aligned. The standard AArch64 approach: allocate the whole frame
> once (`sub sp, sp, #rounded16`), set a frame-pointer register (x29) at the
> `SF_OWNER` position, and access regs/dlocals/stkvars/owner via 8-byte offsets
> from it — instead of incremental 16-byte `push_operand`s. Touches
> `M_CREATE_SF`, `M_UNWIND_SF`, `push_operand`/`pop_operand`, and the frame-local
> operand addressing in `arm64/genproc.p`; must keep `PD_FRAME_LEN` (computed by
> shared `m_trans.p`) consistent. Reference: x86_64 `genproc.p` `M_CREATE_SF`
> (1803) / `M_UNWIND_SF` (1859).
>
> **Contract written + design resolved (2026-06-03):** see
> `PORTING-ARM64-FRAME-CONTRACT.md`. The frame must be **8-byte-packed,
> SP-relative** (the 16-byte slots were never needed — `m_trans.p` already pads
> `pd_frame_len` to 16 bytes via `STACK_ALIGN_BITS=128`, and AArch64 only needs
> *SP* 16-aligned, not the slots). The only real arm64 difference is the return
> address (`bl`→LR vs `call`→stack): the prologue stores LR into the
> `SF_RETURN_ADDR` slot at `[SP+(pd_frame_len-1)*8]` (design **D1**), making
> frames **byte-identical to x86_64** with identical `_caller_sp` arithmetic —
> so the shared walkers/GC need no changes. Fix is localized to `M_CREATE_SF`,
> `M_UNWIND_SF`, `push_operand`, `pop_operand` in `arm64/genproc.p`. All five
> §7 questions resolved on paper. Ready to implement pending review.

**Status: Phase 2c (`make stamp_srclib`) ✅ PASSES (2026-06-02).** The stack-leak
that blocked a clean source-library build is **fixed** (one line in
`arm64/genproc.p` `outinst` — a spurious `false` arg to `asmf_printf` in the
`#`-comment branch leaked onto the user stack, one per procedure). With that
fixed, all three masking band-aids were removed and `do_asm.p` restored to its
original **fatal** `ITEMS LEFT ON STACK` check; the full library now builds
**exit 0, zero mishaps, zero assembler errors**. Both the `items-left` leak
(≈291 files → 0) and the raw-values-to-`outdatum` corruption (16 → 0) were the
same bug. Full write-up in `PORTING-ARM64-BUG-false-label-leak.md` (now marked
RESOLVED). 

**Stage advanced — `make stamp_new_corepop` ✅ + corepop runs under QEMU.**
With the clean srclib, the cross-link produced a fresh arm64 `new_corepop`
(`ELF 64-bit ARM aarch64`, NEEDS only libc/libm/ld-linux). Run under
`qemu-aarch64-static` (`QEMU_LD_PREFIX=/usr/aarch64-linux-gnu`) it **executes
real bootstrap work and exits cleanly** — 187 syscalls incl. `mmap`/`mprotect`,
`rt_sigaction`, `uname`, 70× `openat` (path search), `brk`; **no segfault**
(the broken codegen used to crash here). Strong evidence the codegen is correct.

Build command (host x86_64, cross toolchain):
```
POP__cc="aarch64-linux-gnu-gcc -no-pie -Wl,-export-dynamic -Wl,--no-as-needed" \
  POP__as=/usr/bin/aarch64-linux-gnu-as POP__ar=/usr/bin/aarch64-linux-gnu-ar \
  make CC=aarch64-linux-gnu-gcc stamp_new_corepop
```

Next: build the full `basepop11` image (needs `libncurses6:arm64` +
`libtinfo6:arm64` in the QEMU sysroot — see Stage 7.1) and run the 7.2 REPL
smoke test (`2 + 2 =>` etc.) for observable output.

> **⚠ Correction (2026-06-03) — the "corepop runs / full build succeeded" claims
> above were PREMATURE. The linked image does NOT run the Poplog system yet.**
>
> What is solid: the **popc static-codegen fix is real** — `stamp_srclib` builds
> clean under the *fatal* items-left gate, and `stamp_new_corepop` /
> `make` (full) link a valid arm64 `basepop11`. Nothing to install for that
> (multiarch arm64 `libncurses6`/`libtinfo6`/`libc6` already present;
> linking uses `/usr/lib/aarch64-linux-gnu`). A complete QEMU run-sysroot was
> assembled at `/tmp/arm64-sysroot` (symlink farm: ld/libc/libm + ncurses/tinfo).
>
> What is NOT true: the images do **not** execute. Evidence:
> - `target/psv/` is **empty** — no `startup.psv`/`clisp.psv`/… were ever
>   produced. The full `make` "succeeded" only because each `mkimage` step
>   exits 0 (silently) and `make` then `touch`es the stamp. **Deceptive green.**
> - strace of `basepop11 %nort %noinit <mkimage.p>` (with full wrapper env):
>   **267 syscalls, all shared-lib loads + `rt_sigaction`/`prlimit64`, then
>   `exit_group(0)`.** It **never opens a single Poplog file, never allocates
>   its heap** — it exits during C-runtime / early `setpop`, *before* the
>   Pop-11 system starts. Same for `corepop` (the earlier "187 syscalls = real
>   bootstrap" reading was wrong — those `openat`s are just ld.so lib searches).
> - Holds for all flag combinations; no banner, no output, clean exit 0.
>
> **So there is a second, independent bug: the linked image fails to start the
> Poplog system at runtime** — a Stage-3/4 issue (the hand-ported `.s` runtime
> entry `amain.s`/`setpop`, `c_core.c`, or the `sysdefs.p` memory-layout
> constants the docs flagged: `UNIX_USRSTACK`, `LOWEST_ADDRESS`). It was never
> reached before because the build never got this far. `main` is at `0x5d92d0`,
> entry `_start` at `0x46ee80`. Next: gdb-step from `main`/`setpop` (or
> instrument `c_core.c`) to find the early clean-exit point. Note
> `set_robust_list` returns `ENOSYS` under QEMU (normal, non-fatal).
>
> Also pending cleanup: leftover accea93 ARM64-DIAG diagnostics remain in
> `arm64/genproc.p` (`mc_code_generator`) and `m_optimise.p` — now dead (never
> fire post-fix), harmless, but should be removed.

The historical log below predates the fix; retained for context.

> **Update (2026-05-15) — QEMU validation attempt: fruitless, root cause known.**
>
> After the later commits (`8d60ae3 → accea93`) `make stamp_srclib` now runs to
> completion, but only because `do_asm.p` was patched to **warn-and-drain**
> instead of mishap on leftover stack items. ~290 of ~330 core library files
> still leak `<false>` / `<procedure %OP_CALL>` onto the Pop-11 stack, so the
> emitted machine code is wrong for ~90% of the library. The aarch64
> `target/pop/basepop11` linked on 2026-05-08 was built from this broken
> codegen (and predates the 2026-05-14 srclib).
>
> A QEMU smoke-test of that binary made no progress — expected: the codegen
> gate was never met, and separately the `gcc-aarch64-linux-gnu` cross sysroot
> is missing `libncurses.so.6`/`libtinfo.so.6` that `basepop11` `NEEDED`s, so
> it could not even load. Both blockers and the full runnable procedure are now
> documented as **Stage 7 (QEMU Host Validation)** + the **Phase 5 / 5.5 / 6 /
> 7** checklist in `PORTING-ARM64-LINUX-RPI5.md`. Do not re-attempt QEMU until
> Phase 5 (clean srclib, zero `items-left` warnings, drain reverted) is green.
>
> `accea93` adds ARM64-DIAG instrumentation to localize the leaking M-handler
> but **no build has been run with it yet** — that is the next action.

> **Update (2026-06-01) — ROOT CAUSE IDENTIFIED. The stack leak and the
> unrunnable binary are the same bug.**
>
> Ran the instrumented build for the first time (rebuilt `popc.psv` so the
> `accea93` genproc/do_asm/m_optimise ARM64-DIAG probes are actually in the
> image, then `POP__as=… make stamp_srclib`). Findings:
>
> 1. **It is NOT in the M-instruction handlers.** The genproc `generate
>    leaked` and m_optimise `do_premove leaked` probes never fired. `generate`
>    and `m_optimise` are stack-balanced. So the earlier theory (broken
>    M-handler in arm64/genproc.p) was wrong.
>
> 2. **It is the structure/literal emission chain.** The leaked items are
>    `<false>` and the closure `<procedure %OP_CALL>` (`OP_CALL =
>    do_call(%false,false%)`, m_optimise.p:977). These are *structure
>    components* — a closure literal and its `false` frozvals — that the
>    `genstructure` / `label_of` / `asm_outword` chain is supposed to convert
>    to **asm symbol labels** but instead emits raw. `genstruct.p` is shared
>    and works on x86_64, so the divergence is arm64-side.
>
> 3. **Three band-aids mask it, and they are what break the binary:**
>    - `arm64/asmout.p` `outdatum` (commit 3e3dd24): substitutes a leaked
>      `false`/`true`/`[]` with a label, and a leaked **procedure/vector with
>      `0`** — i.e. writes a **null pointer** into the binary. `outdatum`
>      itself is stack-balanced (peek+update, then `asmf_pr()`+`erasenum(n-1)`
>      = n consumed), so it masks but does not itself leak.
>    - `genstruct.p` `gen_prop_entries` (3e3dd24): "tolerate a false-leak in
>      the table arg" — `() -> _tab; if isvector(_tab) … else 0`.
>    - `arm64/genproc.p` `get_addressable_op` (~line 479): "defensive fallback
>      if a Pop-11 boolean leaks here from the genstructure chain."
>    Each converts a leaked value into a null pointer / placeholder. That is
>    exactly why a "successfully built" `basepop11` cannot run: it is full of
>    null pointers where procedure/structure references belong.
>
> 4. **Per-file attribution** (loop-top `consvector` drains to 0 each
>    iteration, so file N+1's loop-top count == items file N leaked): all 285
>    files leak ≥1; leak scales with file size. Top leakers: `lispcore.p`
>    (136), `arm64/asignals.s` (107), `pop11_syntax.p` (99), `vm_plant.p`
>    (73), `intvec.p` (64), `item.p` (56), `getstore.p` (52). A bare
>    `constant` decl does not leak; the leak appears with procedure/closure
>    literals (the baseline `<false>` is one per file).
>
> **The fix is upstream, not another band-aid.** The three workarounds above
> must be *removed*, and the real defect found: why does the arm64 path feed
> raw values (booleans, closures, vectors) into `asm_outword` instead of
> labels? Recommended next action — convert the masking into a locator:
> temporarily make `arm64/asmout.p` `outdatum` (and/or `asm_outword`) call
> `mishap(v, 1, 'RAW VALUE TO outdatum')` instead of substituting, the moment
> it sees a non-label (boolean/procedure/vector). The mishap backtrace names
> the exact `genstruct.p` caller that passed a raw value — that call site (or
> the arm64 `label_of`/`perm_const_lab` path it relies on) is the fix. This is
> the "instrument asmf_pr to mishap with the call stack" recommendation from
> the original triage, now narrowed to `outdatum` with a confirmed signature.
>
> Reproducer for a single leaked `<false>` (fast iteration, no full build):
> `cd pop/src && POP__as=/usr/bin/aarch64-linux-gnu-as ../../poplog
> ../../target/pop/popc -c -nosys -od /tmp allbutfirst.p allbutlast.p`
> → `allbutlast.p` loop-top shows `{<false>}` (the item allbutfirst left).

> **Update (2026-06-02) — backtrace captured, root cause documented.** Ran the
> locator (temporary `mishap` in `outdatum` instead of the substitution
> band-aid). The raw value enters via **`generate_closure`** (m_trans.p:2226) →
> `genstructure` (genstruct.p:330) → `label_of(false, false)` returns `false`
> (ident_labs.p:536) because `struct_label_prop(false)` was never seeded with
> the `"false"` label. The seed mechanism — `poplink_unique_struct` (lib.p:170)
> consumed by `setup_selected_consts()` (ident_labs.p:759) — is shared with the
> working x86_64 build, so the divergence is *why the seed is ineffective on the
> arm64 cross-compile*. Full chain, evidence, the three band-aids to remove, and
> the fix plan are written up in **`PORTING-ARM64-BUG-false-label-leak.md`**.
> Locator reverted; `stamp_popc` rebuilt clean. Next: the decisive probe
> (print `struct_label_prop`/`poplink_unique_struct`/`word_identifier('false',
> pop_section)` on both arches) named at the end of that doc.

> **Update (2026-06-02, later) — probe run; the `genstructure(false)` root cause
> is REFUTED.** Ran the decisive probe on both arm64 and x86_64 (rebuilt popc
> for each, compiled the same files). Findings:
> - `genstructure(false)` returns the correct label `c_false` **2928/2928** in a
>   full arm64 build (`item==lab=<false>` every time). It is **not** the leak.
> - `word_identifier('false', pop_section)` returns `false` and the seed shows
>   `slp=false` *identically on both arches* — a **red herring**, not the
>   divergence. By `genstructure` time `struct_label_prop(false)=c_false` on both.
> - `asmf_pr` is shared (`lib.p:51` → `<false>`), so x86_64 never feeds a raw
>   `false` to the asm layer; arm64 sometimes does. The divergence is therefore
>   **arm64-specific**, on the quoted-literal emission path the locator backtrace
>   showed: `pas_PUSHQ`/`getstr`/`push_str` (arm64 `genproc.p`) and the
>   `mc_code_generator` `asm_outword` loop — **not** the shared structure chain.
> - The `items-left` leak (≈291 files) persists and is unexplained by
>   `genstructure(false)`; it is the real Phase 5 blocker.
>
> `PORTING-ARM64-BUG-false-label-leak.md` has been corrected (Correction box +
> refined locus + revised fix plan). All probes reverted; arm64 `stamp_popc`
> rebuilt clean; tree buildable. Next: diff x86_64-vs-arm64 emitted `.s` for one
> closure-bearing file, and add a `stacklength()` delta probe around the arm64
> `pas_PUSHQ`/`getstr` handlers to localize the imbalance.

> **Update (2026-06-02, `.s` diff) — the two phenomena are SEPARATE; asm
> corruption is tiny; the stack leak is the real blocker.** Captured emitted
> assembly (`.a`) from clean arm64 and x86_64 popc for the same files and ran a
> whole-library inventory of the `outdatum` band-aid's substitutions:
> - **arm64 codegen is structurally sound** — correct per-procedure constant
>   pool (PC-relative `ldr` loads, required on AArch64); `false/true/[]` →
>   correct labels; most `.xword 0` are legitimate (rawstruct/stackmark, same on
>   x86_64).
> - **(A) raw-value-to-`outdatum` → null pointer is TINY:** 16 raw values
>   library-wide, 9 are `false→c_false` (correct), only **7 genuinely corrupt**
>   (6× `%OP_CALL` closure→0, 1× vector→0). Not ~285 files of damage.
> - **(B) `items-left` stack leak is the real Phase 5 blocker and is unrelated
>   to (A):** ≈285 files, values never reach `outdatum`. **Confirmed
>   arm64-specific** — x86_64 leaves 0 items on the same files. `generate`/
>   `m_optimise`/`outdatum` are all balanced, so the imbalance is in the
>   per-procedure emission around them (suspect: post-`generate` literal/pdr
>   emission in arm64 `mc_code_generator`).
>
> Bug doc updated (`Update 2` box + revised title/status). All captures used
> throwaway assembler-wrapper scripts in `/tmp`; source tree clean, arm64
> `stamp_popc` rebuilt. **Next: localize (B)** with a `stacklength()` delta probe
> around `mc_code_generator`'s post-`generate` emission.

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
