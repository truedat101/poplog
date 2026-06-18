# ARM64 codegen bug: high-word corruption in a tail-position integer subtract

**Status:** characterised, not yet fixed. Found 2026-06-17 on Apple M-silicon
(native arm64 `basepop11`) while adding a `bench` word to Poplog Forth.
Arch-specificity (arm64-only vs upstream) **not yet confirmed** — see *Next steps*.

## Symptom

A compiled Pop-11 procedure that subtracts two large integers **in
tail/return position**, where at least one operand came from an FFI /
`lstackmem` procedure (`sys_microtime`), returns a value whose **high 32
bits are corrupted to a constant `0x7F` (127)** while the **low 32 bits are
correct**.

```
result      = 545460857618        ;;; garbage
low 32 bits = 11026               ;;; == the correct answer
high bits   = 127  (0x7F)         ;;; garbage
```
i.e. `result == (0x7F << 32) | correct_value`.

The procedure runs without error — it just returns the wrong number.

## Minimal reproduction

```pop11
define Z();
    lvars a = sys_microtime();                              ;;; (1) FFI/lstackmem call, large int
    lvars i, s = 0;
    fast_for i from 1 to 3000000 do i + s -> s endfor;      ;;; (2) accumulating loop
    lvars b = sys_microtime();
    b - a                                                   ;;; (3) subtraction in TAIL position
enddefine;
Z() =>
** 545460857860            ;;; WRONG (should be ~11000, i.e. the elapsed microseconds)
```

Binding the result to a local first makes it correct:

```pop11
define S();
    lvars a = sys_microtime();
    lvars i, s = 0;
    fast_for i from 1 to 3000000 do i + s -> s endfor;
    lvars b = sys_microtime();
    lvars d = b - a;          ;;; bind result, then return it
    d
enddefine;
S() => ** 11151              ;;; CORRECT
```

## Localisation matrix (all variants compiled via `define`)

| variant                                                        | result   |
|----------------------------------------------------------------|----------|
| `b - a` in tail, both operands from `sys_microtime()`          | GARBAGE  |
| `lvars d = b - a; d`  (result bound before return)             | correct  |
| both operands large **literals**                               | correct  |
| both operands from ordinary Pop-11 procs (`mv1`/`mv2`)         | correct  |
| both operands large **computed** values                        | correct  |
| `a` literal, `b` = `sys_microtime()`                           | GARBAGE  |
| `a` = `sys_microtime()`, `b` literal                           | GARBAGE  |
| **empty** loop body (`do endfor`, no accumulator)              | correct  |
| no loop at all                                                 | correct  |
| only **one** `sys_microtime()` call (`b = a + 11215`)          | correct  |
| `sys_microtime()` but values are small (e.g. `systime()`)      | correct* |

\* small values can't expose a high-32-bit corruption.

## Trigger — all of these together are required

1. At least one operand value originates from an **FFI / `lstackmem`** proc
   call. `sys_microtime` uses `lstackmem struct TIMEVAL _tvp; _extern
   gettimeofday(_tvp, _NULL)` (see `pop/src/sys_real_time.p`). Ordinary
   Pop-11 procs returning the same magnitude do **not** trigger it.
2. An **accumulating loop** runs (register pressure). An empty loop body
   does not trigger it; no loop does not trigger it.
3. The subtraction is in **tail / return position**. Binding the result to
   an `lvars` before returning fixes it.
4. The operands are **large** (> 2^32) so the high-word corruption is
   visible. (`systime()`, which returns small CPU-centisecond ints, is
   unaffected — hence the Forth `bench`/`testbench` timing uses it.)

Both operands need not be FFI results — corrupting *either* operand's
source to `sys_microtime` is enough, which argues the fault is in the
**tail subtraction's result materialisation**, not in either input value
(the inputs are demonstrably fine: the low 32 bits are always correct).

## Hypothesis

Register-allocation / value-tracking in the tail-return path fails to
materialise the **high 32 bits** of a 64-bit pop-integer result when an
`lstackmem`/FFI call's stack manipulation is live under loop register
pressure. The constant `0x7F` looks like a stale register/stack-slot value
rather than a shifted/truncated operand. Likely in
`pop/src/syscomp/arm64/genproc.p` (instruction selection / frame / result
return), the same area as the other documented arm64 codegen fixes.

## Workaround (in use)

- Bind the arithmetic result to an `lvars` before returning it.
- For elapsed-time measurement specifically, use `systime()` (CPU
  hundredths-of-a-second, small ints) instead of `sys_microtime()`
  (~1e15 µs). This is what `pop/forth/src/forth.p` (`bench`, `testbench`)
  does.

## Next steps

1. **Disassemble** `bad` vs `good`. `popc -nosys` rejects the standalone
   snippet (syntax/`lstackmem` deps); needs compiling within the full
   system or a different popc invocation to capture the emitted `.s`, then
   diff the subtract/return sequence. The `0x7F` high word should point
   straight at the offending instruction.
2. **Arch-specificity:** reproduce on **x86_64** (upstream) and **riscv64**.
   If arm64-only it's a port bug in `arm64/genproc.p`; the riscv64 backend
   was retargeted from arm64 so it may share the fault — worth checking the
   same minimal repro under qemu. This determines whether it's our port or
   upstream Poplog.
3. If confirmed arm64-port-specific, fix in `genproc.p` and add the minimal
   repro to `validate-*.sh`.
