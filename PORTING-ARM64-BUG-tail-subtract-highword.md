# ARM64 bug: high-word corruption of a tail-position arithmetic result

**Status:** root cause localised to the **macOS dual-map / W^X layer** (NOT
codegen), **not yet fixed**. Found 2026-06-17/18 on Apple M-silicon while adding
a Forth `bench` word.

## ⭐ Decisive result: macOS-W^X-specific (RPi5 is clean)

The exact same source, byte-for-byte:

| platform                   | `(f6() >> 32) =>` |
|----------------------------|-------------------|
| **RPi5 / aarch64 Linux**   | `0`  (correct)    |
| **Apple M-silicon / macOS**| `127` (0x7F, BUG) |

Same arm64 ISA, same `arm64/ass.p` + genproc, **so the generated machine code is
correct** — the corruption is purely in the **macOS-only runtime layer** (the
dual-mapped W^X heap). **Consequences:** (1) the **riscv64 port (Linux, no W^X
dual-map) does NOT inherit this bug**; (2) the fix belongs in `c_core.c` /
`asmout.p` / `ass.p`'s macOS-gated bias canonicalisation, not in shared codegen.

This is almost certainly another instance of the **+2^36 "view-bias"
canonicalisation gap** documented in `PORTING-ARM64-M-SILICON-OSX.md`: Pop code
executes at the RX view (`canon + 2^36`), so any PC-relative pointer computation
yields a view-biased value that must be masked (`and reg, reg, #~bit36`). Several
sites were fixed (`I_CREATE_SF`, `closure_cons`); a few are flagged **unfixed**
(exfunc trampoline; `pdr_compose adr x20,.`). The bare-tail-arithmetic-return
path appears to hit one more unfixed site. (Note: `_pop_wx_fixup`, the lazy
exec-fault handler, is **not** called during `f6` — the view runs in steady
state — so the fault path is not involved; it's the view-execution bias.)

## Symptom

A compiled Pop-11 procedure whose **last expression is an integer subtraction
left on the stack as the result** returns a value whose **high 32 bits are
corrupted to a constant `0x7F` (127)**; the **low 32 bits are correct**:

```
result == (0x7F << 32) | correct_value
```

The procedure runs without error — it just returns the wrong number.

## Deterministic reproduction (bare tail-expr fails; result-var works)

```pop11
;;; FAILS: result of `b - a` is the bare tail expression (left on the stack)
define f6();
    lvars a = sys_microtime();
    lvars i, s = 0;
    fast_for i from 1 to 3000000 do i + s -> s endfor;   ;;; accumulating loop
    lvars b = sys_microtime();
    b - a
enddefine;
(f6() >> 32) =>     ** 127      ;;; WRONG (should be 0)

;;; WORKS: identical, but the result is stored to a variable before returning
define ok() -> r;
    lvars a = sys_microtime();
    lvars i, s = 0;
    fast_for i from 1 to 3000000 do i + s -> s endfor;
    lvars b = sys_microtime();
    b - a -> r
enddefine;
(ok() >> 32) =>     ** 0        ;;; correct
```

`lvars d = b - a; d` also works. The trigger needs **all** of: an FFI/`lstackmem`
call (`sys_microtime`), the **accumulating loop** (empty loop / no loop don't
trigger), a **large** value (> 2^32, else the high-word damage is invisible), and
the subtraction as the **bare tail expression** (not stored to a local).

## What was ruled out

- **Not the value / type.** `sys_microtime()` returns a *simple* integer
  (`isbiginteger` = false); same magnitude as a literal. Large literals, ordinary
  Pop-procedure results, and computed values all work in the same position.
- **Not `popc`/`asmout.p`.** Compiling the same source with `popc` (text backend)
  emits **correct** code. The bug is on the **interactive / in-memory assembler
  path (`pop/src/arm64/ass.p`)** — same file as the earlier `lit_buff` bug.
- **Not fresh-compile / I-cache.** `syssave` the procedure, restart, restore: the
  bare-tail version **still** returns `0x7F` garbage; the result-var version is
  still correct. So it is the *compiled code/behaviour*, not a first-touch flush.
- **Not the subtract routine.** Both versions call the **same** `-` proc
  (`identof` deref to the same code) and set up an **identical** x19 stack
  (`[a, b]`) immediately before the call.

## Disassembly — the only difference (both verified from one saved image)

Tail of the **failing** `f6` (result left on x19, then return):
```
    blr     x1                  ; subtract  ->  result pushed on x19 (user stack)
    ldr     x30, [sp, #0x28]    ; epilogue (touches sp/x30/x20, NOT x19)
    ldr     x20, [sp, #0x30]
    add     sp, sp, #0x30
    ret                         ; returns with the result still on x19
```
Tail of the **working** `ok` (`-> r`):
```
    blr     x1                  ; subtract  ->  result on x19
    ldr     x0, [x19], #8       ; POP result
    str     x0, [sp, #0x28]     ; store to r (frame slot)
    ldr     x0, [sp, #0x28]     ; reload r
    str     x0, [x19, #-8]!     ; RE-PUSH result
    ldr     x30, [sp, #0x38]    ; epilogue
    ...
    ret
```

Both leave the result on x19 as the return value; the working one merely
**pops and re-pushes** it (round-trips through a 64-bit frame slot) first. The
epilogues touch only the call stack (`sp`), never x19. **Statically the two are
equivalent** — yet they behave differently, so the corruption is a *runtime*
effect occurring between the subtract and the caller reading x19-top, in the
window where `f6` does *nothing* but `ok` does the pop/re-push.

## Leading hypotheses (for the single-step)

The result on x19 is correct immediately after the subtract (the working version
loads it and it is fine). Something corrupts x19-top's **high 32 bits** during
`f6`'s epilogue/return that the round-trip in `ok` avoids. Most likely a
**W^X dual-map / cross-procedure redirect-fault** or a signal that uses the x19
user stack as scratch and leaves `0x7F` in the high word of the pending return
slot; the working version re-materialises x19-top after that point. (The
"~1 fault per cross-procedure call" dual-map handler is the prime suspect — see
the M-silicon notes.) An optimiser/`ass.p` mis-step on the bare-tail-return path
is the alternative.

## Next steps

1. ✅ **Discriminating arch test — DONE:** RPi5 / aarch64 Linux is clean ⇒
   macOS-W^X-specific; riscv64 unaffected; codegen correct.
2. **Find the unfixed +2^36 canonicalisation site.** Disassemble `f6` at its
   *runtime* (view) address and look for a PC-relative computation (`adr`, or a
   value derived from a view-biased PC/LR) on the bare-tail-return path whose
   result reaches the integer being returned — then mask it (`and …,#~bit36`),
   macOS-gated, the same way `I_CREATE_SF`/`closure_cons` were fixed. The
   round-trip-through-a-frame-slot version (`-> r`) doesn't carry the biased
   value out, which is why it's clean. A hardware watchpoint on the result's
   x19 slot (set after reading x19 from a `gettimeofday`/`_pop_wx_fixup`
   `ucontext`) will catch the write that sets the high word; lldb can't unwind
   Poplog frames, so go via a C-symbol breakpoint + the `ucontext` register
   image rather than `bt`.
3. Once fixed, re-run on macOS (expect `0`) and add the minimal repro to
   `validate-msilicon.sh`.

## Workaround (in use)

Store the result to a local before returning (`-> r`, or `lvars d = expr; d`).
For elapsed-time measurement, the Forth `bench`/`testbench` code uses `systime()`
(small CPU-centisecond ints, never > 2^32) which never exposes the bug.
