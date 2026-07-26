# C23 modernization: drop the `-std=gnu17` pin in the extern-lib build

**Status:** open · **Severity:** low (build compiles today via a dialect pin) ·
**Area:** `pop/extern/lib` C sources · **Filed while porting to aarch64**

## Summary

The Poplog C externs are legacy K&R/C89. Modern GCC rejects them:

- **GCC 14** promoted `-Wincompatible-pointer-types`,
  `-Wimplicit-function-declaration`, `-Wint-conversion`, `-Wimplicit-int` from
  warnings to **errors by default**.
- **GCC 15** defaults to **C23**, where `bool`/`true`/`false` are **keywords**
  and an empty parameter list `()` means `(void)` (not K&R "unspecified").

Today this is worked around in `Makefile.in`:

```make
POPCFLAGS = -std=gnu17 -Wno-error=incompatible-pointer-types
```

That compiles cleanly (verified on aarch64, GCC 15). This issue tracks the
**source modernization** that would let us drop the pin and build under the
compiler's default dialect (`-std=c23`) with no relaxed flags.

> Note: a **separate, already-fixed** bug — `rv_cacheflush()` in `c_core.c`
> emitting RISC-V `fence`/`fence.i` asm on non-RISC-V targets — is resolved by a
> `#if defined(__riscv)` guard and is **not** part of this modernization.

## Item 1 — `typedef unsigned bool` vs C23's `bool` keyword

`pop/extern/lib/c_core.h:196`:

```c
/* macOS system headers pull in <stdbool.h>, making `bool` a macro for _Bool
 * (1 byte). Poplog uses `bool` as an unsigned word; drop the macro and keep the
 * ... */
#undef bool
typedef unsigned bool;
```

In C23 `bool` is a keyword aliasing `_Bool`, so `typedef unsigned bool;` is
illegal, and `#undef bool` no longer helps. **`bool` is used as a 4-byte word in
~30 places across `c_core.h`, `c_core.c`, `pop_timer.c`** — and it crosses the
pop11↔C boundary, so its width is **ABI-significant** (it must stay a word;
switching to 1-byte `_Bool` would silently change layouts/returns).

**Fix:** rename Poplog's word-sized boolean to a distinct name so it no longer
collides with the keyword — e.g.

```c
typedef unsigned pop_bool;   /* Poplog's 4-byte boolean word */
```

and replace the ~30 `bool` uses in those three files with `pop_bool`. Leave the
C++ backends (`imgui_*.cpp/.mm`) alone — there `bool` is the correct 1-byte C++
keyword. Grep scope:

```sh
grep -rnwE 'bool' pop/extern/lib/*.c pop/extern/lib/*.h   # ~30 hits, 3 files
```

## Item 2 — K&R signal-handler prototypes

`pop/extern/lib/c_core.c`:

- `:502  void _pop_errsig_handler();`  — K&R "unspecified args"; in C23 this is
  `(void)`, which then **conflicts** with the real definitions.
- Five platform-varying definitions: `:309` (VMS-style), `:627`
  `(int, siginfo_t*, ucontext_t*)`, `:784` `(int)`, `:821`/`:876`
  `(int, int, struct sigcontext*)`.
- `:506  void (* _pop_sigaction(int sig, void (*handler)()))()` and
  `:519  sa.sa_sigaction = handler;` — generic `void(*)()` assigned to
  `sa_sigaction`'s `void(*)(int, siginfo_t*, void*)` (incompatible-pointer).

**Fix:** give `_pop_errsig_handler` a single, explicit, per-platform prototype
that matches its definition under each `#if`; type `_pop_sigaction`'s `handler`
parameter to the actual handler signature (or cast at the `sa_sigaction`
assignment). The generic-`()` function-pointer style recurs elsewhere in the
signal code — audit `void (*...)()` in `c_core.c` while here.

## Effort & risk

- **Contained:** everything is under `pop/extern/lib` (3 C files).
- **ABI-sensitive:** Item 1 touches types on the C↔pop11 boundary — verify
  `bool`/`pop_bool` stays word-sized and re-bootstrap corepop on each arch.
- **Verification:** after the source fixes, drop `POPCFLAGS` (or set it to
  `-std=c23`) in `Makefile.in` and confirm a clean `make all` + a corepop
  rebuild + the in-build smoke test on x86_64, aarch64, and riscv64.
