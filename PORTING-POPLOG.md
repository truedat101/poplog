# Porting Poplog to a New Platform — Recipe & Reference

> **Scope.** A forward-looking, architecture-agnostic guide to standing up a new
> Poplog port: *what* to build, *in what order*, the *contracts* you must honour,
> and the *traps* that cost the most time. It expands Waldek Hebisch's original
> [`PORTING.txt`](PORTING.txt) (the canonical outline — still worth reading first)
> and distils the AArch64 / Raspberry Pi 5 port. That port's blow-by-blow
> specifics are the worked example in
> [`PORTING-ARM64-LINUX-RPI5.md`](PORTING-ARM64-LINUX-RPI5.md) and
> [`PORTING-ARM64-FRAME-CONTRACT.md`](PORTING-ARM64-FRAME-CONTRACT.md); cite them
> when you need a concrete instance of anything below.

---

## 0. The mental model: two axes

A Poplog port decomposes into two largely-independent jobs. Decide which you are
signing up for **before touching anything**:

- **ISA backend** — register assignment, the two code generators, the assembly
  runtime. A new CPU architecture ⇒ this is (almost) all new work.
- **OS / platform layer** — object format, syscalls/libc, signals, memory
  mapping, the external-call ABI, JIT permissions. A new operating system ⇒ this
  is (almost) all new work.

Everything else — the Pop-11 system source, the four language compilers, the
libraries — is architecture- and OS-neutral and is simply **rebuilt**.

| Target | ISA backend | OS layer | Net effort |
|---|---|---|---|
| Same ISA + OS, new board | reuse | reuse | rebuild; check page size only |
| **New ISA, same OS** (e.g. RISC-V Linux) | **all new** | reuse | the "big backend" port |
| **Same ISA, new OS** (e.g. macOS / Apple Silicon) | reuse | **all new** | the "new OS" port |
| New ISA + new OS | all new | all new | both tracks |

Knowing your axis tells you which Parts below apply and which you can skip.
Worked bookends are in **Part 9**.

---

## 1. Prerequisites & the execution model

**You must be comfortable with:** the Pop-11 *system dialect* (`syspop11` — the
low-level subset with `_`-prefixed machine types and explicit memory ops),
assembly for the target, C, and cross-compilation. Porting always involves a
**host** (a machine already running Poplog, used to cross-compile) and the
**target** (the new machine).

**The one paragraph of architecture you cannot port without:** Poplog runs Pop
code on its **own user stack** (register **USP**) with the current procedure's
descriptor in **PB**, *not* the C stack. There are **two** code generators that
must emit byte-identical conventions:

- **`genproc.p` (popc, compile-time)** — compiles the system `.p` sources to an
  **assembler file**, linked at a **fixed address**. Builds `basepop11` and the
  saved images.
- **`ass.p` (the runtime VM)** — compiles code **into memory at run time** (the
  REPL, loaded files, Prolog/Lisp/ML eval). Its output is **relocatable** — the
  garbage collector moves it — so it may only reach other procedures by absolute
  address (popc-compiled code) or **indirection through the constant/variable
  tables** (which the GC fixes up).

> **The single highest-leverage invariant in the whole port:** these two
> generators must agree, bit-for-bit, on the stack-frame layout (see Part 5.1).
> When they diverge, image-compiled and runtime-compiled procedures can no longer
> call each other or be scanned by the shared GC — and the symptom appears far
> from the cause.

Tagged data: small integers are **popints**, `popint(n) = (n << 2) + 3` — a
**2-bit tag, value 3**. This is Poplog-wide, not per-platform; honour it exactly.

---

## 2. Plan the target (PORTING.txt §1)

Pin down, and write into a notes file before coding:

- **Word size & type sizes/alignment** — they must match the target C compiler
  exactly (popc structs are the interface to the OS; a mismatch corrupts every
  syscall struct). LP64 is the norm.
- **Endianness** (all current targets little-endian).
- **Page size** — `getconf PAGE_SIZE`. Drives image alignment (Part 4.3). 4 KB is
  typical; 16 KB on Apple Silicon and the Pi 5; 64 KB on some servers.
- **Register file & C ABI** — the calling convention, which registers are
  callee-saved (you steal some for USP/PB/temps), and the **stack-pointer
  alignment** requirement (e.g. AArch64 faults on a non-16-aligned SP access).
- **OS** — object format (ELF / Mach-O), how foreign calls and varargs are
  passed, the signal/`ucontext` layout, and whether the kernel enforces W^X / PIE.
- **A port symbol** to gate the new code (the ARM port used `ARM_LINUX`).

---

## 3. ISA-backend track *(skip if reusing an existing backend, e.g. Apple Silicon reuses AArch64)*

Create `pop/src/syscomp/<arch>/` (the popc side) and `pop/src/<arch>/` (the
assembly runtime).

### 3.1 `sysdefs.p` — the platform-definition file

Get the **basic-type lengths and alignments right first** — everything downstream
depends on it. Then specify: the port symbol, page size (`VPAGE_OFFS`, Part 4.3),
endianness, the OS flag set, `CACHEFLUSH` (Part 5.6), float-result convention, and
the **register plan** (which physical registers are USP, PB, the Pop temps, and
the GC-scanned `PD_REGMASK` bit map).

### 3.2 popc backend — `asmout.p` + `genproc.p`

- **`asmout.p`** adapts output to the target assembler (gas-family targets need
  only small syntax tweaks). Two functions are inherently architecture-specific:
  `asm_gen_exfunc_clos_code` (the instruction sequence wrapping a Pop procedure as
  a C-callable external function) and `asm_gen_poplink_code`.
- **`genproc.p`** is the bulk of popc. `mc_code_generator` → `generate` receives a
  list of abstract **M-instructions** (vectors whose first entry is the emitter
  procedure, the rest parameters); most of the work is one emitter per
  M-instruction (`M_ADD`, `M_CREATE_SF`, …).

  **Bring-up recipe (from the ARM port, still the fastest path):**
  1. Stub every M-instruction emitter to print an error.
  2. "Compile" simple sources to discover which M-instructions are actually used.
  3. Implement incrementally. **`M_CREATE_SF` is first and the hardest** — it
     emits the frame prologue (Part 5.1); budget for it.
  4. `mk_cross` builds cross-popc as soon as the emitters exist (even as stubs),
     so you can start testing early. Implement rare M-instructions only when they
     surface in testing.

### 3.3 The assembly runtime — the `.s` files (PORTING.txt §3)

~120 support routines across ~10 `.s` files in `pop/src/<arch>/`. Functional
groups (AArch64 names; yours will mirror them): `amain` (`main` → initialise →
`setpop`), `amisc` (frame walk, checks, dispatch), `amove` (block move/fill),
`aarith`/`afloat` (numeric helpers), `aextern` (the external-call bridge **both
directions** — Part 4.5), `asignals`, `aprolog`, `aprocess` (coroutine/process
stack swap).

**Bring-up recipe:** stub each routine as an **infinite loop**. When execution
reaches a stub, attach gdb, inspect the live arguments, then implement — so each
routine is exercised the moment it goes live. Compile all of `pop/src` with the
new popc, then cross-poplink to get the target corepop file set.

### 3.4 The runtime code generator — `ass.p` (+ `array_cons.p`, `closure_cons.p`, `pdr_compose.p`)

`ass.p` provides one emitter per **I-code** (analogous to genproc.p's
M-instructions, but it writes **machine code into memory**). The other three
generate array accessors, closures, and procedure compositions at run time.

Two non-negotiables here:

- **Relocatable output** — the GC relocates this code, so inter-procedure
  reaches must use absolute addresses (for fixed popc code/runtime support) or
  **indirection via the constant/variable tables**. On a load-store ISA with no
  wide absolute branch, that means *load the target into a register and branch
  indirect*.
- **Frame-layout parity with `genproc.p`** (Part 5.1). The same frame, the same
  dlocal slot order, or nothing interoperates.

---

## 4. OS-layer track *(skip if reusing the OS, e.g. RISC-V Linux reuses the Linux layer)*

### 4.1 Object format & linker
ELF vs Mach-O changes `asmout.p`'s section/symbol emission, the "wrap text in a
Pop object" preamble, and the link step (`poplink_cmd` / `cross-poplink`; you will
edit pathnames and the file/library set during bring-up).

### 4.2 C support — `c_core.c` and friends, per-OS branches
Memory (mmap/mprotect, the memory break), **signals** (the `ucontext` / `mcontext`
layout differs per OS — the error-signal handler reads the faulting PC and may
redirect it; the async-I/O path queues ASTs and trips the trap flag), and async
I/O (`select`/`ioctl` style). Compile these **on the target** with `mklibpop` so
they see the real system headers.

### 4.3 The saved-image format & load
Images are `mmap`'d **`MAP_FIXED`**, so the base address **and file offsets** must
be aligned to the **runtime** page size. Set `VPAGE_OFFS` to the target page size,
or to the **largest** size you intend to support (64 KB is a multiple of 4/16/64
KB → "build once, load anywhere", at the cost of a little padding). A 16 KB-aligned
image loads on a 4 KB kernel but **not** a 64 KB one. The load also assumes the
image goes to a **fixed virtual address** (non-PIE); a PIE-mandatory OS (macOS)
needs this rethought.

### 4.4 JIT execute permission (W^X)
Poplog **writes code then executes it**. If the kernel forbids writable+executable
pages you must map the code segment with the platform's JIT facility and toggle
write/execute around emission (macOS: `MAP_JIT` + `pthread_jit_write_protect_np()`
+ the `allow-jit` entitlement). On permissive Linux this is a non-issue.

### 4.5 External-call ABI nuances
The **forward** path (Pop→C, `_call_external`) marshals args via
`copy_external_arguments`; check variadic conventions (some ABIs — Apple's
AArch64 — pass *all* variadic args on the stack), struct-by-value, and the
float-result width. The **reverse** path (C→Pop callback) is a separate, trickier
trampoline (`_pop_external_callback` / `_exfunc_clos_action`) that reconstructs
Pop's register/stack state from a cold C entry; it is required for the GUI
(Part 7, step 7) and deserves its own validation pass.

---

## 5. Invariants & pitfalls (the checklist)

State of each as a rule to **preserve**, not a bug to rediscover.

1. **The two code generators must emit the identical frame.** `SF_OWNER` at
   `[sp+0]`, then `SF_LOCALS` (stkvars, then dlocals, then reg-locals), then
   `SF_RETURN_ADDR`; frame length even/aligned. **Dlocal slots follow the order
   the *shared* `Dlocal_frame_offset` (procedure.p) expects** — a multi-dlocal
   procedure whose save order disagrees passes self-consistently but reads the
   *wrong slot* under frame introspection (exception reporting, the GC, Prolog).
   See `PORTING-ARM64-FRAME-CONTRACT.md`.
2. **Tag width.** `popint(n) = (n<<2)+3`, a **2-bit** tag. A backend that assumes
   a 3-bit (or any other) tag corrupts every small integer and every popint-scaled
   offset. Audit every shift/mask that touches a tagged value.
3. **Byte scaling.** The user stack holds one item per machine word. Pop counts
   and offsets are popints; converting one to a byte offset scales by the word
   size — **8 on LP64**. Code adapted from a 32-bit port scales by 4; **double it**.
4. **No conditional store/branch over a multi-instruction load.** On load-store
   ISAs, materialising an address or large constant is *several* instructions
   (`MOVZ`+`MOVK`; `lui`+`addi`; a constant-pool load). If a conditional path
   skips it, the dependent op runs on a **stale register**. Emit the load *before*
   the compare/branch, and branch only over the single dependent op.
5. **Stack alignment.** Honour the ABI's SP alignment on every SP-relative access
   (AArch64: 16-byte, or it faults). The Pop frame must keep it aligned.
6. **Cache coherency for JIT'd code.** After emitting code, sync I/D caches:
   `CACHEFLUSH` → `__clear_cache(start,end)` (the compiler builtin reads the
   core's cache-line size and issues the right `dc`/`ic`/`dsb`/`isb`, or the
   arch's icache-flush syscall — e.g. RISC-V's `fence.i` is hart-local, so Linux
   needs the syscall). Missing this is the classic silent JIT-port failure.
7. **Relocatable runtime code.** `ass.p` output is GC-moved; reach other code by
   absolute address or table indirection only (Part 3.4).
8. **Forward ≠ reverse external calls.** The callback trampoline is a separate
   problem from the forward call; budget for it before attempting graphics.

---

## 6. Bootstrap & build hygiene (PORTING.txt §2–3)

> **The seed corepop — the chicken-and-egg you hit *first*, before the pipeline
> below.** Pop-11 is compiled *by Poplog*, so the build is *driven* by a `corepop`
> saved image (`popc`/`poplink`/`poplibr` are symlinks to it) at
> `target/pop/corepop` — without it `configure` aborts: *"corepop is missing in
> target tree."* It is **gitignored, never committed** (so **never** in a fresh
> clone — placing it is always a manual first step) and is **native machine code,
> hence architecture-specific**: an x86-64 corepop won't run on AArch64, and a
> 32-bit `corepop.arm` (armhf) is **not** an AArch64 corepop (a common trap).
> - **Arch already ported here** (x86-64 Linux, AArch64 Linux, Apple Silicon,
>   RISC-V RV64GC Linux): download a seed from this repo's GitHub Releases
>   (`corepop-<arch>-<os>` + `SHA256SUMS`;
>   <https://github.com/IoTone/poplog/releases>) → `target/pop/corepop`. The
>   same seeds are vendored under `nix/seeds/` for the Nix flake build.
> - **Established upstream arch** (i386, 32-bit ARM, FreeBSD…): download one from
>   `poplog.fricas.org/corepops/` → `target/pop/corepop`.
> - **Genuinely new arch**: there is **no download**, and you can't
>   mint the first one *natively* (the target's `popc`/`poplink` are still the
>   host's corepop — PORTING.txt §0: *"porting involves cross-compilation; one needs
>   running Poplog on some machine (the host)"*). **Cross-build it on the host:**
>   `make stamp_new_corepop` with the cross `CC`/`as` produces
>   `target/pop/new_corepop` for the target arch — the same cross-link that builds
>   `basepop11`, since `popc` is architecture-neutral Pop and the host corepop
>   happily emits the target's code. Seed it onto the target as
>   `target/pop/corepop` to make it **self-hosting** (a one-time, per-architecture
>   "compiler-compiler" seed), and **publish it** so others bootstrap without a
>   host: vendor it as `nix/seeds/corepop-<arch>-<os>`, then tag a `corepops-*`
>   release (`.github/workflows/corepops-release.yml` packages and checksums the
>   vendored seeds automatically).
>
> `basepop11` is the same species — the *full* core — so it's easy to overlook you
> still need a `corepop` once the images build. Worked example + script:
> [`PORTING-ARM64-LINUX-RPI5.md`](PORTING-ARM64-LINUX-RPI5.md) "Bootstrapping the
> arm64 `corepop`" / `tools/bootstrap-corepop-x86-64-to-aarch64.sh`.

Pipeline: **`mk_cross`** (cross-popc) → recompile `pop/src` with the new popc →
**cross-poplink** → corepop on the **target** (`mklibpop` compiles the C, final
link uses target system libraries) → `basepop11`.

> **Build hygiene — the rule that hides more bugs than any other:** popc and the
> compiled libraries are stamped. A stale stamp means your "rebuild" silently uses
> the **old codegen**, so a real fix looks like it did nothing. For a true rebuild
> after a codegen change, remove the relevant stamps (`stamp_popc`,
> `stamp_srclib`, `stamp_vedlib`) first. Re-verify fixes only after a clean
> rebuild.

---

## 7. The validation ladder (gate each before the next)

Bring the port up in this order; do not chase a higher gate while a lower one is
red.

1. **`basepop11` starts** — banner / immediate exit.
2. **REPL** — literals, lists/vectors/floats/radix, operators **with correct
   precedence**, assignment, function calls, user `define`s, subscripts, record
   fields, stack constructs (`{% … %}`, `stacklength`).
3. **Process / coroutine machinery** — `consproc`/`runproc`, suspend/resume,
   `uses objectclass` (exercises the process stack-swap).
4. **Image save/load** — `startup.psv` builds, **loads, and runs** (gates the
   page-alignment math and the save-time timestamp path).
5. **Language images** — `clisp.psv`, `prolog.psv`, `pml.psv` build and run real
   programs (e.g. Lisp `(fact 12)`, Prolog `append`/factorial, ML type inference).
6. **Robust I/O** — clean **error reporting**, **interactive** use under a PTY,
   and **piped** input including **bare EOF** (no trailing `halt`).
7. **Graphics** — `libXpw.so` + `xved.psv`; the **C→Pop callback path** (Part 4.5)
   is the real work here.

---

## 8. Debugging playbook

- **Read the contract/struct/source before speculating.** The most expensive
  detours come from theorising about heap corruption or async races when the
  cause is a frame offset, a tag width, or a one-line logic bug. Confirm the
  mechanism from the source first.
- **Run gdb on real hardware** via the launcher so the environment is correct:
  `./poplog gdb pop/pop/basepop11`, then `run`. (The launcher just sets env and
  `exec "$@"`, so you can pass `gdb --args …` through it.)
- **Identify a faulting routine** by its symbol; `addr2line -f -e basepop11 ADDR`
  maps popc-generated code back to the `.p` source.
- **Read the corrupt value as a clue:**
  - ASCII bytes in a register/pointer slot ⇒ a string was written over code/a
    pointer (heap corruption).
  - A wrong value that **varies** run-to-run ⇒ a stack/heap **overrun** (timing
    dependent), *not* a fixed corruptor.
  - A **constant** wrong value ⇒ a fixed mis-write / wrong offset.
- **Heisenbugs:** prefer **passive, auto-continue logging breakpoints**.
  Watchpoints and conditional breakpoints change timing and can make a
  race/overrun vanish or mutate.
- **Stub-with-infinite-loop** (Parts 3.2–3.3): the cheapest way to bring up code
  whose call sites you don't yet know.
- **Localise heap corruption with an aggressive GC:** lower `popmemlim` (or add a
  temporary per-file `sysgarbage()` hook) so the next collection reports
  `BAD STRUCTURE` near the corruptor rather than far downstream.

---

## 9. Worked examples (the two axes)

### RISC-V (RV64GC) Linux — **new ISA, reuse the OS** — ✅ done
Completed and validated on a StarFive VisionFive — see `PORTING-RISCV64-LINUX.md`
for the as-built backend and the bug list. The guidance below is what it took.
Rewrite all of Part 3 (new `.s`, new `genproc.p`/`asmout.p`/`ass.p`); reuse Part 4
(Linux/ELF/LP64). Watch for: **no condition flags at all** (every branch is
compare-and-branch — Pitfall 5.4 reappears via the multi-instruction
`lui`+`addi` immediate load); **`fence.i` is hart-local**, so the JIT i-cache sync
needs the Linux `__riscv_flush_icache` syscall (the `__clear_cache` abstraction in
`CACHEFLUSH` should still cover it); **4 KB pages** (`VPAGE_OFFS=4096`); the RISC-V
register ABI (`x1`=ra, `x2`=sp, callee-saved `s`-registers for USP/PB) and 16-byte
stack alignment.

### macOS / Apple Silicon (M-series) — **reuse the ISA, new OS**
Reuse all of Part 3 (same AArch64 backend, the frame contract, every Part 5
pitfall already solved). Rewrite Part 4: **Mach-O** (not ELF) object/link;
**Darwin `ucontext`/signal** layout; the **W^X / `MAP_JIT`** requirement
(Part 4.4 — the headline hurdle, because Poplog JITs at the REPL); the **all-stack
variadic** convention (Part 4.5); **mandatory PIE** vs the fixed-address image load
(Part 4.3). Bright spot: **16 KB pages already match** `VPAGE_OFFS=16384`, and
`__clear_cache` works on Darwin.

### Full case study
The complete AArch64 / Raspberry Pi 5 port — every stage, every bug, the file
inventory, and the portability notes for other AArch64 boards — is in
[`PORTING-ARM64-LINUX-RPI5.md`](PORTING-ARM64-LINUX-RPI5.md), with the frame
layout in [`PORTING-ARM64-FRAME-CONTRACT.md`](PORTING-ARM64-FRAME-CONTRACT.md) and
the verified end state in
[`PORTING-ARM64-VALIDATION-STATUS.md`](PORTING-ARM64-VALIDATION-STATUS.md).

---

## Appendix — file inventory at a glance

| Layer | Files | New per axis |
|---|---|---|
| Platform defs | `syscomp/<arch>/sysdefs.p` | ISA **and** OS touch this |
| popc backend | `syscomp/<arch>/{asmout.p, genproc.p}` | ISA (asmout also OS: format) |
| Assembly runtime | `src/<arch>/*.s` (~10 files, ~120 routines) | ISA |
| Runtime codegen | `src/<arch>/`… `ass.p`, `array_cons.p`, `closure_cons.p`, `pdr_compose.p` | ISA |
| C support | `extern/lib/c_core.c` et al. | OS |
| Image / build | `VPAGE_OFFS`, `poplink_cmd`, `mklibpop`, stamps | OS |
| Graphics | `pop/x/Xpw/*.c` → `libXpw.so`, `XtPoplog.c`, `pop/x/ved` → `xved.psv` | OS (callback path = ISA-sensitive) |
