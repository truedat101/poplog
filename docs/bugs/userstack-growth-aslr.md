# Large user-stack growth crashed runtime-compiled loops (was: "ASLR-dependent SIGBUS")

**Status:** FIXED 2026-08-15 · **Severity:** high ·
**Area:** `pop/src/{arm64,riscv64}/ass.p` (runtime assembler, `I_CHECK`) ·
**Filed 2026-08-14 while validating the coroutine fix**

## Root cause and fix (2026-08-15)

Not ASLR and not the memory layout: `I_CHECK` — the check the VM plants
at every **backward jump** — was an **unimplemented TODO stub** in the
arm64 (and riscv64) runtime assembler `ass.p`, the same port-skeleton
family as the coroutine branch-to-self stubs. `I_CHECK` is the only
check site *inside* loops, and it does two jobs:

1. **Userstack overflow**: call `_checkall` when USP has grown below
   `_userlim`, which expands the open segment and moves the stack.
2. **Interrupt polling**: call `_checkall` when the `_trap` flag is set,
   which is how Ctrl-C and timer ASTs get serviced inside loops.

With the stub, any runtime-compiled loop that pushes without calling a
procedure (`for i ... do `x` endfor`, `file_to_string`'s char loop,
`read_all` in lib shell) grew the user stack straight down through the
open segment — **overwriting the literal pools of the very code being
executed** — and no loop could be interrupted. popc-compiled system
code uses a different backend (`syscomp/<arch>/genproc.p`, `pas_CHECK`)
which was always correct, which is why the engine itself mostly worked.

Diagnosed from the fault pattern: the first crash writes through a
"pointer" equal to the tagged popint of the loop bound (the stack had
pushed it over a code literal at exactly USP), and a `_pop_brk` trace
showed the break never moved — expansion was never even attempted.
The earlier "~4/5 of launches fail" reading was noise in what the
corrupted memory happened to contain, not address-space layout.

Both assemblers now plant the full check (trap test, `_userlim` vs USP,
conditional `_checkall` call), following each file's branch-offset and
deferred-compare conventions. Verified on macos-arm64 after a clean
rebuild:

- `pushn(200000)` repro: 10/10 pass (previously 0/10 that day);
  `pushn(2000000)` passes with `popmemlim` raised; hitting the default
  limit now produces the proper `MEMORY LIMIT (popmemlim)` mishap.
- A runtime-compiled infinite loop is now interruptable with SIGINT
  (previously unkillable — the popsession/Jupyter runaway-`repeat`
  behaviour).
- `tools/gen-docs.sh` completes on macOS for the **first time**
  (921 pages) — docs generation is no longer Linux-only.
- `tools/test-libs.sh`: all suites green (http suites SKIP on Darwin —
  see `darwin-no-sockets.md`; `test_shell` previously crashed the old
  engine outright in `read_all`, same root cause).
- Coroutine repro still 3/3 (no regression).

riscv64 is mirrored but untested on hardware (pending VisionFive
rebuild), same status as its coroutine fix.

## Related fix: bounded hibernation (`pause_popintr`)

Making interrupts fire promptly widened an ancient race: if a wake-up
signal's AST is processed at a check point after `sys_wait`/`syssleep`
re-tested its wait condition but *before* `pause()` parks, nothing is
left to wake the process (observed as an intermittent hang in
`sigsuspend` with the child long dead). On Darwin `pause_popintr` now
parks in 100ms `poll()` ticks — a signal still interrupts immediately,
and a lost wake-up costs one tick instead of a hang (c_core.c).

Everything below is the original (mis-)report, kept for the record.

---

## Original symptom (2026-08-14)

Pushing a large number of items onto the user stack (~200k words — e.g.
`lib fileutils`'s `file_to_string`, which stacks every character before
`consstring`) dies with a NULL write, and the error-delivery machinery
then faults recursively:

```
[wx-decline] addr=0 base=8000000000 brk=8000048000 exec=0
[fatal] sig=10 pc=…Error_signal addr=0 lr=…__pop_errsig …
```

Repro:

```pop11
define pushn(n);
    lvars i;
    for i from 1 to n do `x` endfor;
    erase(consstring(n));
enddefine;
pushn(200000);
```

The report attributed the pass/fail variation to per-launch ASLR layout
vs the fixed 0x8000000000 heap reserve (porting doc Phase 3). That
analysis was wrong — see above.
