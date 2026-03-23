# Porting Poplog to Apple M-Silicon (AArch64 macOS / Darwin)

## Decision: Direct Native Port via Cross-Compilation from RPi5

After evaluating direct native port vs LLVM IR backend, the decision is:

- **Direct native port**, cross-compiling from a working AArch64 Linux (RPi5) Poplog
- The LLVM IR approach is deferred as a potential long-term "Poplog v2" effort
- The current `configure` + `Makefile.in` build system will be extended (no CMake/Bazel)

### Why This Approach

1. **70-80% of the AArch64 Linux code is reusable** -- the instruction set is
   identical; only OS/toolchain/ABI differences need addressing
2. **Proven bootstrap path** -- this is exactly how Hebisch did the original ARM32
   port (cross-compiled from x86_64 Linux)
3. **No new dependencies** -- keeps Poplog self-contained
4. **Fastest path to a working system** -- estimated 25-45 days vs 10-18 months
   for LLVM IR

### Why Not LLVM IR

- Requires a working native port to bootstrap from (chicken-and-egg)
- Poplog's GC moves code in memory; LLVM JIT doesn't support this without
  a GC redesign
- M-code is register-oriented; LLVM IR is SSA -- large semantic gap
- Adds ~100MB libLLVM dependency
- 10-18 month estimate for a system that works today via native port
- Could be revisited later once native ports exist to bootstrap from

### Why Not CMake/Bazel

- **CMake**: helpful if we go LLVM later, but overkill for extending the current
  build system with a `darwin` case
- **Bazel**: overkill; Poplog's bootstrap-from-corepop flow doesn't fit its
  action graph model

**Reference**: https://github.com/below/HelloSilicon -- ARM64 assembly on Apple
Silicon, documenting the critical differences from Linux.

---

## Bootstrap Strategy

### The Problem

Poplog requires a working `corepop` binary for the target platform. `corepop` is
a minimal Poplog interpreter that compiles Pop-11 source. The build chain:

```
corepop (existing binary)
  -> compiles popc (cross-compiler)
    -> popc compiles all Pop-11 sources -> .s assembly files
      -> assembler produces .o files
        -> linker produces new corepop
```

No macOS `corepop` exists, so we need to cross-compile one.

### The Solution: Cross-Compile from RPi5

```
RPi5 (AArch64 Linux, working Poplog)
  |
  |  1. Load Darwin-targeting sysdefs/asmout into popc
  |  2. popc compiles all Pop-11 sources
  |
  +---> .s files (Clang syntax, @PAGE/@PAGEOFF, _ prefix)
  |
  +---> transfer to Mac via scp/rsync
           |
           |  3. clang -c *.s         (assemble natively)
           |  4. clang -c *.c         (compile C runtime)
           |  5. clang -o corepop *.o -lSystem  (link)
           |
           +---> macOS corepop (first bootstrap binary!)
                   |
                   +---> 6. Native rebuild from here on
```

**Prerequisites**:
- A working Poplog on RPi5 (the AArch64 Linux port must bootstrap first)
- Darwin-targeting `sysdefs_darwin.p` and `asmout.p` modifications
- macOS with Xcode command-line tools installed

The instruction encodings are **identical** between Linux and macOS AArch64.
Only the assembly syntax (relocations, symbol prefixes) and C runtime differ.

---

## Critical Differences: Linux AArch64 vs macOS AArch64

| Aspect | Linux AArch64 | macOS AArch64 (Darwin) |
|--------|---------------|------------------------|
| **Object format** | ELF | Mach-O |
| **Assembler** | GNU as (`gas`) | Clang integrated assembler (LLVM) |
| **Symbol naming** | `printf` | `_printf` (underscore prefix) |
| **PC-relative addressing** | `adrp x0, sym; add x0, x0, :lo12:sym` | `adrp x0, sym@PAGE; add x0, x0, sym@PAGEOFF` |
| **Literal pools** | `:lo12:sym`, `:got:sym` | `sym@PAGE`, `sym@PAGEOFF`, `sym@GOT` |
| **Position-independent code** | Optional (`-fPIC`) | **Mandatory** (absolute addressing forbidden) |
| **Register x18** | Available | **Reserved by Apple** (do not use) |
| **Variadic functions** | Args in registers per AAPCS64 | **Args on stack** (not in registers) |
| **System calls** | `svc #0`, syscall # in x8 | `svc #0x80`, syscall # in x16 (private, may change) |
| **Dynamic linker** | `ld-linux-aarch64.so` | `dyld` |
| **Shared libraries** | `.so` (ELF) | `.dylib` (Mach-O) |
| **`sbrk`/`brk`** | Available | **Deprecated/unavailable** |
| **W^X enforcement** | Not enforced | **Enforced** (need `MAP_JIT` + `pthread_jit_write_protect_np`) |
| **Code signing** | Not required | **Required** (even ad-hoc) |
| **Debugger** | `gdb` | `lldb` |
| **Stack alignment** | 16-byte | 16-byte (same) |
| **Frame pointer (x29)** | Recommended | **Mandatory** |
| **Entry point** | `_start` / `main` | `_main` (underscore prefix) |
| **Linking** | `gcc -o out ...` | `clang -o out ... -lSystem -syslibroot $(xcrun --show-sdk-path)` |

---

## Files Requiring Changes

### Must Change (OS/toolchain layer)

**`sysdefs_darwin.p`** (new file, based on `sysdefs.p` + FreeBSD template):
- Replace `ARM64_LINUX` with `ARM64_DARWIN`
- Replace `UNIX_ELF` with new `DARWIN` / `MACHO` flag
- Replace `sbrk`/`brk` in `GET_REAL_BREAK`/`SET_REAL_BREAK` with `mmap`-based
  implementation (macOS has no `sbrk`; use pattern from c_core.c's `_pop_brk`)
- Set `CACHEFLUSH` to use `sys_icache_invalidate()` or `__clear_cache()` (both
  work on macOS)
- Add `W_XOR_X` flag to signal that writable+executable memory needs special handling

**`asmout.p`** (moderate changes -- may need Darwin variant or conditionals):
- Change `extern_name_translate` to add leading underscore (`_` prefix)
- Change PC-relative addressing syntax: `:lo12:sym` -> `sym@PAGEOFF`
- Remove `.arch armv8-a` (Clang uses `-arch arm64` flag instead)
- Change `.xword` to `.quad` (Clang/LLVM assembler preference)
- Assembler directives must be lowercase (already are)

**`genproc.p`** (moderate changes):
- All generated assembly must use Clang syntax for relocations (`@PAGE`/`@PAGEOFF`)
- Literal pool addressing patterns change
- Jump table implementation may need adjustment for mandatory PIC
- **x18 must not be used** (currently not used -- safe)

**All 10 `.s` files** (moderate, mostly mechanical changes per file):
- `:lo12:sym` -> `sym@PAGEOFF` throughout
- `adrp x0, sym` -> `adrp x0, sym@PAGE`
- All external symbol references get `_` prefix via `EXTERN_NAME` macro
- No `.arch` directive (handled by Clang `-arch arm64`)
- Possibly `.subsections_via_symbols` directive needed

**`c_core.c`** (significant changes):
- Signal handling: macOS uses `uc_mcontext->__ss.__pc` (not `uc_mcontext.pc`)
- Replace `sbrk`/`brk` memory management with `mmap`/`munmap`
- `personality()` call in `linux_setper` -- not applicable on macOS (skip/stub)
- Dynamic library handling differs (no `-Wl,--export-dynamic`)

**`ext_arm.c`** (minor changes):
- Add `__APPLE__` / `__MACH__` guards alongside `__aarch64__`
- Calling convention for variadic functions differs on Darwin

**Build system** (`configure`, `Makefile.in`, scripts):
- Detect `darwin` from `uname -s`
- Use `clang` instead of `gcc`
- Link with `-lSystem -syslibroot $(xcrun --show-sdk-path)`
- No `-Wl,--export-dynamic` (use `-Wl,-exported_symbols_list`)
- No `-no-pie` (PIE is mandatory on macOS)
- `nm` output format differs on macOS
- `ar` / `ranlib` usage may differ

---

## The Hard Problem: W^X (Write XOR Execute)

**This is the single biggest obstacle.** macOS M-silicon enforces W^X: memory
cannot be simultaneously writable and executable. Poplog's runtime code generators
(`ass.p`, `array_cons.p`, `closure_cons.p`, `pdr_compose.p`) write machine code
into memory buffers and then execute them. On Linux this works with `mmap(...,
PROT_READ|PROT_WRITE|PROT_EXEC, ...)`. On macOS:

1. Allocate with `MAP_JIT` flag: `mmap(..., MAP_JIT, ...)`
2. Before writing code: `pthread_jit_write_protect_np(false)` (make writable)
3. Write the machine code
4. After writing: `pthread_jit_write_protect_np(true)` (make executable)
5. Flush icache: `sys_icache_invalidate(addr, size)`

This requires **every code generation path** to bracket writes with these calls.
The garbage collector, which moves code in memory, also needs this treatment.

### Strategy for W^X

**Phase the work**: Get the compile-time path working first (Phases 1-3 below),
which does NOT require W^X. The compile-time path generates `.s` assembly files
that are assembled by Clang into `.o` files -- no JIT involved. Only Phase 4
(runtime code generators) needs W^X support.

This means we can get a `corepop` that compiles Pop-11 source before tackling W^X.
Runtime-generated closures and dynamically compiled code will require W^X, but
basic Poplog functionality can work without them for initial testing.

---

## Implementation Plan

### Phase 1: Compile-Time Path (cross-compile from RPi5, no JIT needed)

- [ ] Get AArch64 Linux port bootstrapping on RPi5 (prerequisite)
- [ ] Create `sysdefs_darwin.p` (new file in `syscomp/arm64/`)
- [ ] Create Darwin variant of `asmout.p` (or add conditionals): `@PAGE`/`@PAGEOFF`,
      `_` prefix, `.quad`
- [ ] Modify `genproc.p` for Clang relocations in generated code
- [ ] Adapt `extern_name_translate` to add leading `_` on Darwin
- [ ] Use RPi5's `popc` with Darwin config to cross-compile Pop-11 sources
- [ ] Transfer `.s` files to Mac
- [ ] Assemble on Mac with `clang -c` and fix syntax issues iteratively

### Phase 2: C Runtime on macOS

- [ ] Add `__APPLE__` conditionals to `c_core.c`:
      - Signal context: `uc_mcontext->__ss.__pc`
      - Skip `linux_setper` / `personality()` on Darwin
      - Replace `sbrk`/`brk` with `mmap`/`munmap` (use `_pop_brk`/`_pop_sbrk` pattern)
- [ ] Adapt `ext_arm.c` for Darwin (variadic calling convention)
- [ ] Add `darwin` case to `configure` script
- [ ] Update `Makefile.in` for Darwin linking:
      `clang -o corepop *.o -lSystem -syslibroot $(xcrun --show-sdk-path)`
- [ ] Fix `pglink` and `scripts/` for Mach-O conventions
- [ ] Fix `nm` / `ar` / `ranlib` usage for macOS

### Phase 3: Runtime Assembly on macOS

- [ ] Adapt all 10 `.s` files for Clang syntax:
      - `:lo12:sym` -> `sym@PAGEOFF`
      - `adrp x0, sym` -> `adrp x0, sym@PAGE`
      - Remove `.arch` directives
      - Add `.subsections_via_symbols` if needed
- [ ] Verify `EXTERN_NAME` macro produces `_`-prefixed symbols on Darwin
- [ ] Assemble + link on Mac -> first `corepop` binary
- [ ] Code sign: `codesign -s - corepop`
- [ ] Test basic Pop-11 REPL (compile-time only, no runtime codegen yet)

### Phase 4: W^X and Runtime Code Generation

- [ ] Implement `MAP_JIT` allocation wrapper in C:
      ```c
      void *pop_jit_alloc(size_t size) {
          return mmap(NULL, size, PROT_READ|PROT_WRITE|PROT_EXEC,
                      MAP_PRIVATE|MAP_ANONYMOUS|MAP_JIT, -1, 0);
      }
      ```
- [ ] Implement write-protect toggle wrapper:
      ```c
      void pop_jit_write_enable(void)  { pthread_jit_write_protect_np(false); }
      void pop_jit_write_disable(void) { pthread_jit_write_protect_np(true); }
      ```
- [ ] Add W^X calls around all code writes in:
      - `ass.p` (every `plant_instr` / code emission)
      - `array_cons.p`, `closure_cons.p`, `pdr_compose.p`
      - Garbage collector code movement paths
- [ ] Replace `__clear_cache` with `sys_icache_invalidate` where needed
      (or keep `__clear_cache` which also works on macOS via Clang runtime)
- [ ] Test runtime-generated closures and dynamically compiled code

### Phase 5: Full Bootstrap and Validation

- [ ] Native rebuild: use macOS `corepop` to rebuild Poplog from source on Mac
- [ ] Test Pop-11 REPL with basic expressions
- [ ] Test Prolog subsystem
- [ ] Test Common Lisp subsystem
- [ ] Test Standard ML subsystem
- [ ] Test external function calls (FFI)
- [ ] Test floating point operations
- [ ] Test process/coroutine switching
- [ ] Test signal handling
- [ ] Test garbage collection (critical for W^X correctness)

---

## Approach 2 (Deferred): LLVM IR Backend

### Why Deferred, Not Rejected

The LLVM IR approach is the right long-term architecture:
- Write once, run anywhere (RISC-V, WebAssembly, etc. for free)
- W^X handled automatically by LLVM JIT
- No hand-encoded instruction words
- LLVM optimizer produces high-quality code

But it requires:
- A working native port to bootstrap from (Approach 1 is a prerequisite)
- 10-18 months of work vs 1-2 months for the direct port
- Deep redesign of GC's relationship with generated code
- Significant LLVM API expertise

### If Pursued Later

| Component | Effort | Notes |
|-----------|--------|-------|
| M-code -> LLVM IR translator | 2-4 months | Replaces genproc.p |
| I-code -> LLVM ORC JIT | 3-6 months | Replaces ass.p, hardest part |
| GC compatibility | 1-2 months | Code movement vs fixed JIT buffers |
| Build system (CMake + LLVM) | 2-4 weeks | find_package(LLVM) |
| Runtime code gen (closures etc.) | 1-2 months | Via LLVM JIT API |
| Testing all 4 languages | 1-2 months | Pop-11, Prolog, Lisp, SML |
| **Total** | **~10-18 months** | Requires native port first |

---

## Key References

- **HelloSilicon**: https://github.com/below/HelloSilicon -- ARM64 asm on Apple Silicon
- **Apple AArch64 ABI**: https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms
- **JIT on Apple Silicon (W^X)**: https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon
- **MAP_JIT**: `man mmap` on macOS, `MAP_JIT` flag
- **pthread_jit_write_protect_np**: Thread-local W^X toggle
- **Mach-O relocations**: `@PAGE`, `@PAGEOFF`, `@GOT` -- LLVM AArch64 docs
- **Existing FreeBSD port**: `pop/src/syscomp/x86_64/sysdefs_freebsd.p` -- closest BSD template
- **Poplog upstream**: https://github.com/hebisch/poplog
