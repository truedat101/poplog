# Coroutine machinery broken on arm64 AND riscv64 (port rung-3 gate)

**Status:** FIXED 2026-08-14 · **Severity:** high ·
**Area:** `pop/src/{arm64,riscv64}/aprocess.s` ·
**Filed 2026-08-14 while fixing the dirent/stat struct bug**

## Root cause and fix (2026-08-14)

Not macOS-specific and not W^X: `_ussave` and `_userasund` in the
arm64 (and riscv64) `aprocess.s` were **branch-to-self placeholder
stubs** from the original port skeleton (`b C_LAB(_ussave)` directly
under its own `DEF_C_LAB` — a literal `b .`), which survived the June
2026 process-swap rewrite that implemented everything around them.
Every `runproc`/`suspend` needing to swap out a non-empty user stack
spun forever in that branch — on macOS *and* arm64 Linux (verified on
raspi5: identical hang; earlier Linux successes only ever suspended
with an empty stack). The `wx-decline` SIGBUS variant was downstream
confusion, not the cause.

Both routines are now implemented (faithful ports of the x86-64
versions: save the deepest LENGTH bytes ascending into the record,
shift the retained top against `_userhi`, pop the freed space), and
mirrored in `pop/src/riscv64/aprocess.s` (same self-tail stubs there;
untested on hardware pending a VisionFive rebuild).

Verified on macos-arm64 after a clean rebuild, repeatedly: the minimal
consproc/suspend/runproc repro (5/5), `sys_file_match` from procedures
and with `...`-recursion (3/3 ALL OK), `test_fileutils` (ALL PASS —
previously spun 31 minutes), and `make_indexes` completes on macOS for
the first time. A separate PRE-EXISTING flake found during validation
is filed as `userstack-growth-aslr.md` — since diagnosed (not ASLR: the
runtime assembler's `I_CHECK` was another port-skeleton stub) and FIXED
2026-08-15; gen-docs now runs on macOS.

Everything below is the original report.

---

This is the known-open item from `PORTING-ARM64-M-SILICON-OSX.md`:

> Gates: process/coroutine machinery (rung 3) … which all use runtime codegen

filed as a bug so it has a repro and a symptom inventory.

## Minimal repro (hangs at ~100 % CPU in `ussave`)

```pop11
define gen();
    lvars i;
    for i from 1 to 3 do suspend(i, 1) endfor;
enddefine;
vars myp = consproc(0, gen);
runproc(0, myp);          ;;; never returns; sample(1) shows all time in ussave
```

Depending on stack depth at `consproc`/`runproc` time this manifests as
either an infinite loop in the userstack-save routine or a SIGBUS:

```
[wx-decline] addr=7667ffff8 base=8000000000 brk=8000028000 exec=0
[fatal] sig=10 pc=1000021ec ...
```

(the `wx-decline` line is pop_jit's write-to-executable-page log — the
save/restore path writes where W^X forbids, consistent with the porting
doc's open Phase-4 items: bracket every code-write site, route code
allocation through `pop_jit_alloc`).

## Symptom inventory (all one root cause)

- `sys_file_match` repeaters are processes (`consproc`/`suspend` in
  `pop/lib/auto/sys_file_match.p`), so: plain single-directory globs
  happen to survive when driven from top level, but the same call **from
  inside a procedure** hangs, and `...`-recursive patterns crash
  (SIGBUS in `matchindir`).
- `make_indexes` (doc index build) crashes → the Makefile now skips it on
  Darwin with a pointer here. Until this is fixed the HELP/TEACH/REF
  indexes must be built on Linux (they are tree-portable text files).
- `gen-docs` on macOS: `collect()` calls `dir_files` from a procedure →
  hangs. Docs site generation stays Linux-only for now.
- Anything user-level built on `consproc`/`suspend`/`runproc`
  (`simproc`, generators) hangs or crashes.
- `tools/test-libs.sh` on macOS: csv + datetime suites pass, then
  `test_fileutils.p` spins forever (its checks call `dir_files` from
  procedures). Run the suite on Linux until this is fixed.

## What already works (do not confuse with this bug)

The dirent/stat struct-layout bug (`macos-sys-file-match.md`) is FIXED:
`stat`-family builtins (`sysisdirectory`, `sysfilesize`, `sysmodtime`,
`sys_file_stat`) and directory-entry decoding are correct on macOS as of
2026-08-14. Simple top-level globs return correct results.

## Fix direction

Complete the porting doc's Phase 4 list for the save/restore paths:
process stack copy-in/copy-out must run between
`pop_jit_write_enable`/`disable` when it touches code-adjacent segments,
and the `ussave` loop needs auditing on this port for the W^X fault-retry
case (a declined write that keeps retrying explains the 100 % CPU spin).
Acceptance: the repro above, then `make_indexes`, then rung 3 of the
Part 7 ladder (coroutines) in the porting doc.
