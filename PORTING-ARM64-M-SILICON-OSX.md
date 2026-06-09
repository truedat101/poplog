# Porting Poplog to Apple M-Silicon (AArch64 macOS / Darwin)

> **Read [`PORTING-POPLOG.md`](PORTING-POPLOG.md) first.** This document is the
> *worked instance* of that recipe's **OS-layer track (Part 4)** for one specific
> target: Apple Silicon Macs. It assumes the architecture-agnostic model, the
> invariants checklist, and the validation ladder from the recipe, and only
> records what is *Darwin-specific*.

---

## 0. Which axis is this? — "Same ISA, new OS"

PORTING-POPLOG.md Part 0 decomposes every port into two largely-independent
tracks. Apple Silicon lands squarely on one of them:

| Track | Status for this port |
|---|---|
| **ISA backend** — register plan, the two code generators, the assembly runtime | **REUSE** — the AArch64 backend is done (see below) |
| **OS / platform layer** — object format, syscalls/libc, signals, memory map, external-call ABI, JIT permissions | **ALL NEW** — this is the entire job |

So this is the canonical **"reuse the ISA, write a new OS layer"** port
(PORTING-POPLOG.md Part 9, macOS bookend). Everything in **Part 3 of the recipe is
skipped** — we do not touch instruction selection, the frame layout, the register
assignment, or any Part 5 ISA invariant. The work is **Part 4**, top to bottom.

### The reuse baseline is real, not aspirational

The AArch64 / Raspberry Pi 5 Linux port **works today**. Per
[`PORTING-ARM64-VALIDATION-STATUS.md`](PORTING-ARM64-VALIDATION-STATUS.md)
(milestone 2026-06-08): all four languages run (Pop-11, Prolog, Lisp, ML), all
three images build (`clisp.psv`, `prolog.psv`, `pml.psv`), error reporting and
piped/interactive I/O work, and the console core is at **feature parity with
raspi32**. The hardest ISA problem — the stack-frame contract shared by both code
generators, the GC, and the frame walkers — is **solved and documented** in
[`PORTING-ARM64-FRAME-CONTRACT.md`](PORTING-ARM64-FRAME-CONTRACT.md), and it is
**OS-independent**: the same byte-identical frame works on Darwin.

The full worked ISA example is
[`PORTING-ARM64-LINUX-RPI5.md`](PORTING-ARM64-LINUX-RPI5.md). When this document
says "reuse," that is what we reuse.

### Bright spots already banked

Three things the recipe warns about are already in our favour:

- **Page size matches.** `arm64/sysdefs.p` already sets `VPAGE_OFFS = 16384`, and
  Apple Silicon's page size is 16 KB. The image-alignment math (PORTING-POPLOG.md
  4.3) needs no change for page size.
- **Cache flush works.** `CACHEFLUSH` uses `__clear_cache`, which the Clang/Darwin
  runtime implements (PORTING-POPLOG.md invariant 5.6). `sys_icache_invalidate()`
  is available as a Darwin-native alternative if needed.
- **The frame contract is solved.** The single highest-leverage invariant in the
  whole port (PORTING-POPLOG.md 5.1) is already honoured by `genproc.p` and
  `ass.p`, and is architecture/OS-agnostic.

### The one open scope boundary

Graphics (PORTING-POPLOG.md Part 7 rung 7) is **deferred past first light** — it is
**unbuilt on any AArch64 target** (the RPi5 build is `-nox`), and the C→Pop
**callback trampoline** it leans on (`aextern.s` `_pop_external_callback` /
`_exfunc_clos_action`) is implemented but has **never executed**. The macOS
graphics strategy — a native **ImGui + Metal** backend behind `--experimental-gfx`
for drawing + a native panel UI, with **XQuartz** as a legacy fallback — is **§6**.

---

## 1. Decision: direct native port via cross-compile from RPi5

**Chosen approach:** a direct native port, cross-compiling from the working
AArch64 Linux (RPi5) Poplog, extending the current `configure` + `Makefile.in`
build system with a `darwin` case. **No CMake/Bazel. LLVM IR deferred** (see
§8).

**Why:** the instruction *encodings* are identical between Linux and macOS
AArch64 — only assembly *syntax* (relocations, symbol prefixes), object format,
and the C runtime differ. With the ISA backend already proven on the Pi, the
remaining gap is the OS layer alone, which is exactly the path Hebisch used for
the original ARM32 port (cross-compiled from x86_64 Linux). It keeps Poplog
self-contained and is the fastest route to a running system.

The condensed case against the alternatives is in §8.

**Reference for Apple-Silicon assembly specifics:**
<https://github.com/below/HelloSilicon>.

---

## 2. Bootstrap strategy

### The problem

Poplog needs a working `corepop` binary for the target. The build chain is:

```
corepop (existing binary)
  -> compiles popc (the cross-compiler)
    -> popc compiles all Pop-11 sources -> .s assembly files
      -> assembler -> .o files
        -> linker -> new corepop
```

No macOS `corepop` exists, so we cross-compile the first one.

### The solution: cross-compile from RPi5

```
RPi5 (AArch64 Linux, WORKING Poplog — the reuse baseline)
  |
  |  1. Load Darwin-targeting sysdefs/asmout into popc
  |  2. popc compiles all Pop-11 sources (ISA backend unchanged)
  |
  +---> .s files (Clang syntax: @PAGE/@PAGEOFF, leading _, .quad)
  |
  +---> transfer to Mac (scp/rsync)
           |
           |  3. clang -c *.s         (assemble natively)
           |  4. clang -c *.c         (compile C runtime)
           |  5. clang -o corepop *.o -lSystem ...   (link)
           |  6. codesign -s - corepop
           |
           +---> macOS corepop  (first bootstrap binary)
                   |
                   +---> 7. native rebuild from here on
```

**Prerequisites:**
- A working Poplog on RPi5 — **DONE** (see §0).
- Darwin-targeting `sysdefs_darwin.p` + `asmout.p` Darwin output (Phase 1).
- macOS with Xcode command-line tools.

The instruction encodings are **identical**; only assembly syntax, object format,
and the C runtime differ.

---

## 3. Critical differences: Linux AArch64 vs macOS AArch64

This table *is* the OS-layer delta. Everything new in this port traces to a row
here.

| Aspect | Linux AArch64 | macOS AArch64 (Darwin) |
|--------|---------------|------------------------|
| **Object format** | ELF | Mach-O |
| **Assembler** | GNU as (`gas`) | Clang integrated assembler (LLVM) |
| **Symbol naming** | `printf` | `_printf` (underscore prefix) |
| **PC-relative addressing** | `adrp x0, sym; add x0, x0, :lo12:sym` | `adrp x0, sym@PAGE; add x0, x0, sym@PAGEOFF` |
| **Literal pools** | `:lo12:sym`, `:got:sym` | `sym@PAGE`, `sym@PAGEOFF`, `sym@GOT` |
| **Position-independent code** | Optional (`-fPIC`) | **Mandatory** (absolute addressing forbidden) |
| **Register x18** | Available | **Reserved by Apple** (do not use — already unused) |
| **Variadic functions** | Args in registers per AAPCS64 | **Args on stack** (PORTING-POPLOG.md 4.5) |
| **System calls** | `svc #0`, # in x8 | `svc #0x80`, # in x16 (private, may change) |
| **Dynamic linker** | `ld-linux-aarch64.so` | `dyld` |
| **Shared libraries** | `.so` (ELF) | `.dylib` (Mach-O) |
| **`sbrk`/`brk`** | Available | **Deprecated/unavailable** — use `mmap` |
| **W^X enforcement** | Not enforced | **Enforced** — `MAP_JIT` + `pthread_jit_write_protect_np` |
| **Code signing** | Not required | **Required** (even ad-hoc) |
| **Debugger** | `gdb` | `lldb` |
| **Stack alignment** | 16-byte | 16-byte (same) |
| **Frame pointer (x29)** | Recommended | **Mandatory** |
| **Page size / `VPAGE_OFFS`** | 16384 (Pi 5) | 16384 — **already matches** |
| **Entry point** | `_start` / `main` | `_main` (underscore prefix) |
| **Linking** | `gcc -o out ...` | `clang -o out ... -lSystem -syslibroot $(xcrun --show-sdk-path)` |

---

## 4. Files: reuse vs new

Mapped onto the PORTING-POPLOG.md appendix table. The headline: **no ISA-track
file changes its logic**; the `.s`/`asmout.p` edits are mechanical *format*
changes, and everything genuinely new is OS-layer.

### Reuse unchanged — ISA-track logic (PORTING-POPLOG.md Part 3)

- **`syscomp/arm64/genproc.p`, `src/arm64/ass.p`** — instruction selection, frame
  layout (`M_CREATE_SF`/`M_UNWIND_SF`, `I_CREATE_SF`/`I_UNWIND_SF`), register
  plan, dlocal slot order. **Do not touch the codegen logic.** Only the *emitted
  relocation syntax* changes, and that flows from `asmout.p` (below).
- **`src/arm64/*.s` runtime logic** (14 files: `aarith afloat alisp amain amisc
  amove aprocess aprolog asignals aextern` + the `_cons`/`pdr_compose`/`ass`
  helpers) — the AArch64 instruction sequences themselves are correct and proven.
- **All Part 5 invariants** — tag width (2-bit `popint`), LP64 byte-scaling
  (×8), the two-generator frame parity, no-branch-over-multi-instruction-load,
  cache coherency. These are **solved and OS-independent**; do not rediscover them.

### Mechanical syntax edits — same files, OS/format only (Part 4.1)

These are ISA-track files touched for an OS-track reason (object format). The
change is find-and-replace, not redesign:

- **`asmout.p`** — Darwin variant or conditionals: `extern_name_translate` adds a
  leading `_`; `:lo12:sym` → `sym@PAGEOFF`, `adrp x0, sym` → `adrp x0, sym@PAGE`;
  `.xword` → `.quad`; drop `.arch armv8-a` (Clang uses `-arch arm64`); emit
  `.subsections_via_symbols` if the linker needs it.
- **`src/arm64/*.s`** — the same `:lo12:`→`@PAGEOFF`, `adrp …@PAGE`, `_`-prefix
  via the `EXTERN_NAME` macro, no `.arch`. Mechanical, per file.

### New — OS-layer track (Part 4.2–4.5)

- **`syscomp/arm64/sysdefs_darwin.p`** (new). Template off the existing
  [`pop/src/syscomp/x86_64/sysdefs_freebsd.p`](pop/src/syscomp/x86_64/sysdefs_freebsd.p)
  (closest BSD/Mach precedent) merged with the current
  [`pop/src/syscomp/arm64/sysdefs.p`](pop/src/syscomp/arm64/sysdefs.p):
  - swap the OS flags — `ARM64_LINUX` → `ARM64_DARWIN`, `UNIX_ELF` → a `DARWIN`/
    `MACHO` flag, and the `OPERATING_SYSTEM` list from `[unix linux … elf …]` to
    the Mach-O/Darwin set;
  - keep `WORD_BITS=64`, `POPINT_BITS=61`, **`VPAGE_OFFS=16384`** (already right),
    and the register plan **unchanged**;
  - replace `GET_REAL_BREAK`/`SET_REAL_BREAK`'s `_extern sbrk` with an
    `mmap`-based break (macOS has no `sbrk` — mirror `c_core.c`'s `_pop_brk`);
  - keep `CACHEFLUSH` on `__clear_cache` (or switch to `sys_icache_invalidate`);
  - add a `W_XOR_X` flag so the codegen/runtime know writable+executable memory
    needs the JIT dance (Phase 4).
- **`pop/extern/lib/c_core.c`** — Darwin branches (Part 4.2): signal context via
  `uc_mcontext->__ss.__pc` (not `uc_mcontext.pc`); `mmap`/`munmap` memory break
  instead of `sbrk`/`brk`; skip `personality()`/`linux_setper` (no-op on Darwin);
  dynamic-export handling (`-Wl,-exported_symbols_list`, not
  `-Wl,--export-dynamic`).
- **`pop/extern/lib/ext_arm.c`** — `__APPLE__`/`__MACH__` guards alongside
  `__aarch64__`; the **all-stack variadic** convention for the forward
  external-call path (Part 4.5).
- **Build system** (`configure`, `Makefile.in`, `scripts/`) — detect `darwin`
  from `uname -s`; use `clang`; link `-lSystem -syslibroot $(xcrun
  --show-sdk-path)`; **PIE mandatory** (no `-no-pie`); Mach-O-aware `nm`/`ar`/
  `ranlib` and `pglink`.

---

## 5. Implementation phases

Each phase discharges a PORTING-POPLOG.md **Part 4** sub-section and gates a
**Part 7** validation-ladder rung. Do not chase a higher rung while a lower one
is red.

### Phase 1 — Object format & toolchain *(Part 4.1)*

- [ ] Create `syscomp/arm64/sysdefs_darwin.p` (§4).
- [ ] Add Darwin output to `asmout.p` (`@PAGE`/`@PAGEOFF`, `_` prefix, `.quad`,
      drop `.arch`); adapt `extern_name_translate`.
- [ ] Cross-compile all Pop-11 sources on RPi5 with the Darwin config → `.s`.
- [ ] Apply the mechanical syntax edits to `src/arm64/*.s`.
- [ ] Transfer to the Mac; `clang -c` each `.s`; iterate on syntax until clean.

### Phase 2 — C support layer *(Part 4.2)* → ladder rung 1 (`basepop11` starts)

- [ ] `c_core.c` Darwin branches: `mcontext` signal PC, `mmap` break, skip
      `personality()`.
- [ ] `ext_arm.c` Darwin variadic guards.
- [ ] `configure`/`Makefile.in` `darwin` case; clang link line; codesign step.
- [ ] Link the first macOS `corepop`; `codesign -s - corepop`; confirm it
      **starts** (banner / clean exit).

### Phase 3 — Image save/load *(Part 4.3)* → ladder rungs 2 (REPL) & 4 (image save/load)

- [ ] **Design risk — mandatory PIE vs `MAP_FIXED` fixed-address image.** Saved
      images are `mmap`'d `MAP_FIXED` to a *fixed* virtual address (non-PIE), but
      macOS mandates PIE. This is the recipe's explicit 4.3 warning and must be
      designed, not patched: reconcile the fixed-address image load with ASLR/PIE
      (e.g. a reserved fixed region requested at load, or relocation of the image
      base). Page alignment itself is already fine (`VPAGE_OFFS=16384`).
- [ ] Build, load, and **run** `startup.psv`.
- [ ] Pop-11 REPL: literals, lists/vectors/floats, operator precedence,
      `define`s, records, stack constructs.

### Phase 4 — W^X / JIT *(Part 4.4)* → stabilizes runtime-compiled code; gates rungs 3 & 5

**The single biggest Darwin-specific obstacle.** Poplog writes machine code into
memory then executes it (`ass.p`, `array_cons.p`, `closure_cons.p`,
`pdr_compose.p`, and the **GC**, which *moves* code). macOS forbids
writable+executable pages.

> **Mechanism PROVEN on Apple Silicon** (`pop/extern/lib/pop_jit.{c,h}`,
> `make jit-smoke`): `MAP_JIT` alloc → `pthread_jit_write_protect_np` write/execute
> toggle → `sys_icache_invalidate` → execute the JIT'd code (`jit ok: f(1) = 42`).
> So the open question is no longer *whether* W^X works but *bracketing every emit
> site*.

- [x] JIT allocator + write/execute + flush helpers — `pop_jit_alloc` /
      `pop_jit_write_enable` / `pop_jit_write_disable` / `pop_jit_flush`
      (`pop/extern/lib/pop_jit.c`: `MAP_JIT`, thread-local toggle, icache flush).
      Verified end-to-end on arm64 (`make jit-smoke`).
- [ ] Bracket **every** code-write site in the four runtime generators **and the
      GC code-movement paths** with `write_enable … write_disable + flush`. The
      toggle is thread-local, so all codegen + GC must run on one thread (Poplog
      is cooperatively single-threaded — holds).
- [ ] Route the code-segment allocation through `pop_jit_alloc`, gated by a
      `W_XOR_X` flag in `sysdefs_darwin.p` (Phase 1).
- [ ] Gates: process/coroutine machinery (rung 3) and the language images
      `clisp.psv`/`prolog.psv`/`pml.psv` (rung 5), which all use runtime codegen.

### Phase 5 — External-call ABI + full validation *(Part 4.5)* → ladder rungs 1–6 acceptance

- [ ] **Forward** path (Pop→C): all-stack variadic marshalling in `ext_arm.c` /
      `_call_external`; struct-by-value and float-result width.
- [ ] **Reverse** path (C→Pop callback) — the trickier trampoline. **Unexercised
      on any AArch64 target.** Deferred to graphics (rung 7, §6); the
      `--experimental-gfx` UI minimises reliance on it via forward-call polling,
      but it must work for non-UI callbacks and the XQuartz fallback.
- [ ] Run the full Part 7 ladder rungs 1–6 as the acceptance gate: REPL,
      coroutines, image save/load, all three language images running real
      programs, robust error reporting, interactive-PTY and piped (bare-EOF) I/O.
      Native rebuild on the Mac; verify GC under aggressive `popmemlim`.

---

## 6. Graphics strategy (Part 7, rung 7)

Poplog's GUI is **X/Xt all the way down**: `libXpw.so` (Poplog's own widget set,
built on Xt Intrinsics + Xlib), **XVed** (the windowed editor), `rc_graphic` (the
drawing library, calling `XpwDraw*` directly), and `pop_ui` (property sheets and
dialogs). There is no portable graphics seam *below* Xt. This is pure OS-layer
work, cleanly **separable and gated last**, and the system is fully usable without
it — a `--with_no_x` build gives **all four languages plus a complete terminal
VED** (VT100/ANSI, `pop/ved/src/vdvt100.p`). So graphics is **deferred past first
light** (rungs 1–6 above), then delivered by two backends:

- **Primary — native ImGui + Metal, behind `--experimental-gfx`.** A new,
  Apple-native backend delivering **drawing + a native panel UI** — Linux feature
  parity for graphical *output* and *widgets*.
- **Fallback — XQuartz (`--with_xt`).** Reuses the entire legacy Xpw/Xt/XVed stack
  unchanged, for anyone who needs the literal windowed **XVed** editor or
  X-specific behaviour.

> **Parity, stated honestly.** The ImGui path reaches Linux parity for *drawing*
> and *widget/panel* features; the **editor** parity in that configuration comes
> from **terminal VED**, not a windowed XVed (immediate-mode ImGui is the wrong
> tool for a programmer's editor — see 6.3). Full windowed-XVed parity is
> available via the XQuartz fallback.

### 6.1 Why ImGui + Metal is the primary path

It is the **native-backend option (the "GUI v2" of the deferred class) realised
with ImGui + Metal instead of raw AppKit** — which collapses a multi-month AppKit
widget rewrite into something tractable, with no X server and a maintained
dependency. Two concrete wins:

- **Primitives map ~1:1.** `rc_graphic`'s `XpwDrawLine/Point/Rectangle/Arc/String`
  correspond directly to ImGui `ImDrawList::AddLine/AddRectFilled/AddCircle/
  AddText`. `rc_graphic.p` is *documented as retargetable* ("will need to be
  re-defined if ported to a different graphics system") — that comment is the
  intended seam.
- **Immediate mode sidesteps our riskiest piece.** An immediate UI driven from the
  Pop side (`if pop_gfx_button("ok") then …`, polled per frame) uses only
  **forward** Pop→C calls — which already work on arm64 — instead of registering
  retained Xt callbacks. That lets the UI logic largely avoid the **reverse C→Pop
  callback trampoline** (`_pop_external_callback`, `aextern.s`), the one graphics
  dependency that has **never executed** on any AArch64 target (PORTING-POPLOG.md
  4.5; §0). The trampoline still must work for non-UI callbacks and is validated
  here, but it stops being the UI's critical path.

### 6.2 The one design tension: immediate vs retained

Poplog's graphics are **retained and idle** — Pop code draws imperatively, pixels
persist, and the process *blocks* until the next event. ImGui is **immediate** —
the UI is rebuilt every frame in a render loop. Bridge it, don't fight it:

- **Drawing → offscreen Metal texture.** Render `rc_graphic` primitives into a
  persistent render target once; display it with `ImGui::Image`. This maps cleanly
  onto Poplog's existing **`XpwPixmap`** concept and preserves draw-once-persist
  semantics.
- **Panels → immediate.** Rebuild buttons/dialogs/property-sheets each frame from
  Pop-side state (ImGui's home turf).
- **Render on demand.** Use the platform backend's wait-for-event path so an idle
  window and the REPL don't busy-spin or freeze each other (see 6.4).

### 6.3 Scope = Linux parity

| Feature | ImGui path | Note |
|---|---|---|
| `rc_graphic` drawing (lines, turtle, teaching graphics) | ✅ retarget onto `pop_gfx_*` | ~1:1 primitives; offscreen texture |
| Native panel UI (buttons, dialogs, property-sheet-style) | ✅ new native UI | a *new* GUI, **not** a port of `pop_ui`/Xt |
| Editor | terminal VED | windowed **XVed** only via the XQuartz fallback |

### 6.4 What ImGui does *not* remove

- **Event-loop ↔ Poplog-async integration.** A `pop_gfx_pump()` must cooperatively
  marry the render loop to Poplog's SIGIO/async-check machinery — the same job
  `XtPoplog.c`'s `XptPause` does for Xt. ImGui's 60 fps assumption makes this
  *worse* unless you commit to render-on-demand.
- **W^X on one thread.** `pthread_jit_write_protect_np` is thread-local (Phase 4),
  so the frame-loop thread must own the JIT toggle when a UI action triggers
  runtime codegen. Keep gfx and Pop on a single thread.
- **It reuses none of Xpw/Xt** — more new code than the XQuartz fallback, traded
  for native Metal and zero X dependency. The right trade for an opt-in flag.

### 6.5 Implementation shape

- **Build flag (scaffolded).** `configure` now recognises `--experimental-gfx` →
  `GFX_CONF=imgui` (implies no X), parallel to the existing `X_CONF` switch
  (`--with_no_x`/`--with_xt`/`--with_motif`), and substitutes it into
  `Makefile.in`, which selects `-nox` linking for the imgui config. The backend
  object + macOS frameworks (`GFX_OBJECT` / `imgui_backend.o` /
  Metal·MetalKit·AppKit·QuartzCore) are a marked **TODO** in `Makefile.in` until
  ImGui is vendored (`tools/fetch-imgui.sh`) and the build rule is written.
- **Vendoring (no submodules).** `tools/fetch-imgui.sh` pulls a *pinned* Dear ImGui
  release tarball into `pop/extern/imgui/` (gitignored) — no git submodule and no
  committed third-party source. Bump `IMGUI_REF` (or `--ref`) to update.
- **New ObjC++ glue** `pop/extern/lib/imgui_backend.mm` — exposes an `extern "C"`
  `pop_gfx_*` surface (`init / frame_begin / draw_* / button / text / poll /
  frame_end`) to Poplog's C FFI, implemented directly against ImGui's C++ API plus
  its **native Metal + Cocoa backends** (`imgui_impl_metal.mm`, `imgui_impl_osx.mm`)
  — **no GLFW/SDL, no cimgui**. (cimgui is only worth adding later if you want the
  *entire* ImGui API exposed to Pop rather than a curated surface.)
- **Retarget `rc_graphic`** onto `pop_gfx_*`; wire `pop_gfx_pump` into the
  async-check path; validate the reverse callback trampoline (needed for non-UI
  C→Pop) as part of bring-up.
- **Dependency footprint:** just **Dear ImGui source** (fetched, not committed) +
  Apple's Metal/MetalKit/AppKit/QuartzCore frameworks — no submodules, no cimgui,
  no GLFW/SDL. Self-contained apart from one pinned source fetch; far lighter than
  Motif/XQuartz. Exactly what `--experimental-` gating is for.

### 6.6 XQuartz fallback

`--with_xt` reuses **100%** of the existing Xpw/Xt/XVed stack. Crucially it needs
only **core X** (`-lXt -lX11 -lXmu -lXext`), **not Motif** — Poplog's Xpw widgets
subclass plain Xt — and XQuartz ships exactly those libraries (plus Athena). The
only new work is the **Mach-O dylib linking** (`.so`→`.dylib`, the link flags) and
making the **C→Pop callback trampoline** fire (required for every Xt event).
Runtime requires the user to install **XQuartz** (native arm64 since XQuartz 2.8.0,
universal binary; current stable 2.8.5, now in maintenance mode). This is the path
to literal windowed **XVed**.

---

## 7. What is already guaranteed vs what Darwin can still break

A focused read of PORTING-POPLOG.md Parts 5 (invariants) and 8 (debugging) for
this port:

**Already guaranteed (solved on RPi5, OS-independent — do not re-debug):**
- Tag width (`popint(n)=(n<<2)+3`, 2-bit) and LP64 byte-scaling (×8).
- The two-generator frame parity and dlocal slot order
  ([`PORTING-ARM64-FRAME-CONTRACT.md`](PORTING-ARM64-FRAME-CONTRACT.md)).
- No-branch-over-multi-instruction-load; relocatable `ass.p` output via table
  indirection.

**Darwin can still break (this port's real risk surface):**
- **W^X around every emit** (Phase 4) — the classic silent JIT failure mode if a
  single write site is unbracketed, and the GC code-move path is easy to miss.
- **Signal `mcontext` offset** — Darwin's layout differs from Linux; a wrong
  offset makes the error-signal handler read the wrong faulting PC.
- **PIE vs fixed-address image** (Phase 3).
- **All-stack variadic** marshalling (Phase 5).

**Debugging:** use **`lldb`**, not gdb. Otherwise the Part 8 playbook applies
unchanged — read the contract/struct before speculating, read the corrupt value
as a clue (ASCII bytes ⇒ string-over-pointer; varying value ⇒ overrun; constant
value ⇒ fixed mis-write), prefer passive logging breakpoints for Heisenbugs, and
localize heap corruption with an aggressive GC.

---

## 8. Rejected/deferred alternatives (condensed)

**LLVM IR backend — deferred, not rejected.** The right *long-term* architecture
(write-once-run-anywhere, W^X handled by the JIT, no hand-encoded instructions),
but it requires a working native port to bootstrap from (this port is the
prerequisite), a redesign of the GC's relationship to generated code (Poplog's GC
moves code; LLVM JIT doesn't), and ~10–18 months vs ~1–2 for the direct port. The
M-code→IR semantic gap (register-oriented vs SSA) is large. Revisit once native
ports exist to bootstrap from. Indicative effort: M-code→LLVM IR translator
(2–4 mo), I-code→ORC JIT (3–6 mo, hardest), GC compatibility (1–2 mo), build
(2–4 wk), runtime codegen (1–2 mo), 4-language testing (1–2 mo).

**CMake/Bazel — rejected.** CMake only helps if we go LLVM later; overkill for
adding a `darwin` case to the existing build. Bazel's action-graph model doesn't
fit Poplog's bootstrap-from-corepop flow.

---

## 9. References

- **PORTING-POPLOG.md** — the recipe this document instantiates (read first).
- **PORTING-ARM64-LINUX-RPI5.md** — the worked ISA-backend example (the reuse
  baseline).
- **PORTING-ARM64-FRAME-CONTRACT.md** — the frame layout (already honoured).
- **PORTING-ARM64-VALIDATION-STATUS.md** — verified end state on the Pi.
- **HelloSilicon**: <https://github.com/below/HelloSilicon> — ARM64 asm on Apple
  Silicon.
- **Apple AArch64 ABI**:
  <https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms>
- **JIT on Apple Silicon (W^X)**:
  <https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon>
- **Existing FreeBSD/Mach template**:
  `pop/src/syscomp/x86_64/sysdefs_freebsd.p`.
- **Poplog upstream**: <https://github.com/hebisch/poplog>.
