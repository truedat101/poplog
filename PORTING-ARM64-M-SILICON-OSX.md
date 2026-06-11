# Porting Poplog to Apple M-Silicon (AArch64 macOS / Darwin)

> **Read [`PORTING-POPLOG.md`](PORTING-POPLOG.md) first.** This document is the
> *worked instance* of that recipe's **OS-layer track (Part 4)** for one specific
> target: Apple Silicon Macs. It assumes the architecture-agnostic model, the
> invariants checklist, and the validation ladder from the recipe, and only
> records what is *Darwin-specific*.

---

## ✅ STATUS (2026-06-10): PORT COMPLETE — self-hosting, all four languages, VED, callbacks, native graphics

Everything below this section is the original porting plan, kept as the
design record.  The port has landed on the `12-mac-os-x-m-silicon-port`
branch; the actual state is:

**Building on a Mac (Apple Silicon) is now the standard flow** — no
cross-build host involved:

```sh
./configure --with_no_x                  # add --experimental-gfx for graphics
make all                                 # popc → src → corepop → basepop11 → images
./poplog ./target/pop/basepop11          # Pop-11; +target/psv/{clisp,prolog,pml}.psv
```

The only bootstrap input is a seed `corepop` in `target/pop/` (any prior
Mac corepop works; generation-2 self-rebuild is verified).  Validation:
`tools/validate-msilicon.sh` (12-gate, four languages, PTY VED) and
`tools/validate-gfx.sh` (TEACH RC_GRAPHIC walkthrough) both pass; the
RPi5 Linux ladder stays 12/12 with all shared-code changes.

**What works:** the full `make all` system (basepop11 + terminal VED +
startup/clisp/prolog/pml images), saved images, GC fully enabled,
fork/exec (`sysobey`), dynamic loading (`exload` of `.dylib`s), C→Pop
callbacks (`exfunc_export`), and native graphics (Dear ImGui + Metal:
`HELP POPGFX`, `LIB RC_GRAPHIC`/`RC_MOUSE`, `TEACH RC_GRAPHIC`).

**Mainline arm64 bugs found en route** (latent on Linux too; upstream
candidates): genproc dlocal save-slot order vs the GC scan window (the
"GC corruption" — every dlocal-saved pop value went unrelocated);
`ext_arm.c` `ET_OFF` 98→90 (every compound external arg dereferenced;
ddecimal args broken); `external.ph` `EFC_CODE_SIZE` 16→32 on aarch64
(exfunc record fields inside the code); `ass.p` `lit_buff`
element-size overflow at >256 pooled literals; `Flush_procedure` wild
ranges when `PD_EXECUTE` is outside the record; `pdr_compose` missing
PB canonicalisation (Darwin-only).

**Darwin mechanisms that make it work** (details in the phases below):
`__POPSEED` segment + in-place RX remap loader; ASLR-off re-exec;
fixed break reserve at `0x8000000000` with a dual-mapped RX execution
view at +2³⁶ (rebuilt in fork children via `pthread_atfork`);
exec-fault redirect; variadic-ABI wrappers; host-OS sysdefs selection;
poplink_cmnd with seed-loader object + codesign epilogue.

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

No macOS `corepop` exists, so we cross-compile the first one. This is the same
one-time, per-architecture seed step every new platform hits — there is no
`arm64-darwin` corepop to download, exactly as there was none for AArch64 Linux.
See the **seed corepop** box in [`PORTING-POPLOG.md`](PORTING-POPLOG.md) §6.

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

### The verified cross-link recipe (captured from RPi5, 2026-06)

The cross seam is **`poplink`**, not `popc`. `popc` compiles `.p → .w` (Mach-O
codegen, bundled into `src.wlb`); `pglink -core` then runs `poplink`, which turns
the library + system tables into assembler and *would* assemble + link — except
the Pi has no Mach-O toolchain. Pointing `POP__as` / `POP__cc` at capture wrappers
makes poplink emit the artifacts **without** assembling, so the Mac finishes.

What `pglink -core` (i.e. `poplink -p … $popobjlib/src.wlb -ex ( )`) produces —
all **Mach-O**, verified by markers (`@PAGE`/`@PAGEOFF` present; no
`:lo12:`/`.arch`/`.xword`) and by `clang -c -arch arm64` (5/5 + 292 modules):

| Unit | Role |
|------|------|
| `poplink_1.a … poplink_4.a` | linked library code + glue (`poplink_3.a` ≈ 515 KB of `adrp …@PAGE` code) |
| `poplink_dat.a` | data / symbol tables (image date, idents) |
| `poplink_cmnd` | the generated, location-independent link script (below) |
| `src.olb` | bulk library object archive — built separately by `poplibr -c <name>.olb` (the `POP__ar` step), **not** by `poplink`; any stale **ELF** `src.olb` must be regenerated as Mach-O on the Mac |

`poplink_cmnd` as captured — the hardcoded flags are the only OS delta:

```sh
$POP__cc -no-pie -Wl,-export-dynamic -Wl,--no-as-needed -o $IM \
    poplink_1.o poplink_2.o poplink_3.o $popobjlib/src.olb \
    poplink_4.o poplink_dat.o -L$popexternlib/ -lpop -lm -lc
```

**Darwin swap:** drop `-no-pie` (PIE is mandatory), drop the GNU-ld
`-export-dynamic` / `--no-as-needed`; add `-lSystem -syslibroot $(xcrun
--show-sdk-path)`; then `codesign -s - corepop`.

Mac finish (steps 1 verified; 2–4 pending the C runtime):
1. `clang -c -arch arm64` every `.a` → Mach-O `.o`  — **done, 5 tables + 292 modules, 0 fail**
2. build `libpop.a` from the C runtime (`c_core.c` etc. with the Darwin branches)
3. link per the swapped `poplink_cmnd`; settle whether a `-core` image even needs
   `src.olb` (poplink already folds the library into `poplink_1..4`) from the
   undefined-symbol set
4. `codesign -s - corepop`

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

- [x] Create `syscomp/arm64/sysdefs_darwin.p` (§4).
- [x] Add Darwin output to `asmout.p` (`@PAGE`/`@PAGEOFF`, `_` prefix, `.quad`,
      drop `.arch`); adapt `extern_name_translate`. Also: numeric `PD_LENGTH`
      (clang can't evaluate forward shifted label-diffs), poplink-stub `sub`
      instead of `(l-offs)@PAGE` addend.
- [x] Cross-compile all Pop-11 sources on RPi5 with the Darwin config → `.s`
      (292 modules, 0 mishaps; all assemble with `clang -c -arch arm64`).
- [x] Apply the mechanical syntax edits to `src/arm64/*.s` (all 10 runtime
      files; `tools/port-arm64-s-*.py`). ELF path byte-identical via macros.
- [x] Transfer to the Mac; `clang -c` each `.s` — clean (306/306).
- [x] **ELF regression 12/12** — the `UNIX_MACHO`/`DARWIN` gating left Linux intact.

### Phase 2 — C support layer *(Part 4.2)* → ladder rung 1 (`basepop11` starts)

- [x] `c_core.c` Darwin branches: `mcontext` signal PC (`uc_mcontext->__ss.__pc`),
      `mmap` break, skip `personality()`/`linux_setper`, `<siginfo.h>`/`ucontext`.
- [x] `c_core.h` Darwin: detect `__APPLE__` as UNIX, `#undef bool`.
- [x] Build `libpop.a` on macOS — all 9 C files compile (`clang -c -arch arm64`).
- [x] Build a Mach-O `src.olb`; **the corepop link resolves 0 undefined symbols**
      (was 128 → fixed by the `.s` port + `EXTERN_NAME()` for bare C calls).
- [ ] **BLOCKED on Phase 3:** the link fails on *illegal text-relocations*, not
      symbols (see Phase 3). `configure`/`Makefile.in` darwin case + codesign
      still to wire once the link completes.

### Phase 3 — Image save/load *(Part 4.3)* → ladder rungs 2 (REPL) & 4 (image save/load)

**The PIE / text-relocation wall — CONFIRMED, and it blocks the corepop link
itself (not just `.psv` load).** With 0 undefined symbols, the corepop link dies on:

```
ld: Found illegal text-relocations   (4098 in poplink_3.o, 98 in src.olb, …)
  text-relocation in '…' to 'c_nil', 'c_procedure__key', 'c_lisp_Ssymbol__string' …
```

*Root cause.* A Poplog procedure is one contiguous GC object `[record][code]`.
The **record** holds absolute pointer fields (`.quad <symbol>` → keys, idents,
other procedures); the **code** is now PC-relative (the `.s` port fixed that).
Under arm64 Mach-O, **PIE is unconditionally mandatory** (`-no_pie` is *"ignored
for arm64*"*, `-read_only_relocs,suppress` *"cannot be used in this
configuration"*), so every absolute pointer needs a load-time rebase — which
Mach-O forbids in read-only `__TEXT`. The record can't move to `__DATA` (where
dyld *would* rebase it) without splitting it from the executable code it must
stay contiguous with for the GC.

*What Poplog has (investigated):* **no general relocation machinery.** Only the
*callstack* is relocated on `.psv` restore (`sr_sys.p:1001-1014`, via
`@(w){_callstack_reloc}`); the heap/image is `mmap`'d `MAP_FIXED` to a fixed VA
(`sr_sys.p:312`) assuming ASLR is off. `objmod_pad_key` is a GC boundary marker,
not a reloc record. Codegen (`asmout.p` `outdatum`/`asm_outword`,
`genstruct.p:154`) emits absolute symbols only — no PIC/offset mode, no flag.

*Options (least→most invasive):*
- **A. Reserve a fixed region** (`mmap MAP_FIXED_NOREPLACE` at a chosen high VA;
  abort if denied). Doesn't help the *executable's* own `__TEXT` relocs — the
  corepop binary still won't link. Only relevant to later `.psv` loads. **Insufficient alone.**
- **B. Relocation table + self-relocate at load** (the agent's pick, ~3-5 days).
  Emit a reloc table (offsets of every absolute pointer) at image-save; at load,
  if `base != expected`, add the slide to each. Reuses Poplog's key-driven GC
  traversal. But the corepop *binary* still needs its `__TEXT` pointers legal —
  so this needs pairing with putting those pointers somewhere writable/rebasable.
- **C. Split the procedure layout on Mach-O** — record's pointer fields in a
  rebasable `__DATA`/`__DATA_CONST` section, code in `__TEXT`, PD_EXECUTE linking
  them. dyld then rebases the records for free and the link succeeds. **Open
  feasibility question:** does the GC require `[record][code]` *memory*
  contiguity (it walks `start + PD_LENGTH` to the next object), or only the
  record→code *pointer*? Since the ported code carries no embedded pointers, the
  GC need only scan records and skip code — if static seed procedures aren't
  walked by contiguous `PD_LENGTH` traversal, C is the cleanest path to *first
  light*. **Verify this next** (`getstore.p`/`gcmain.p` seed-procedure handling).

*Feasibility of C — ANSWERED (GC investigation):* the **seed/corepop procedures
are registered NON_POP + CONSTANT and are never GC-swept** (`gcmain.p:500-509`
skips CONSTANT/NON_POP segments; the loaded image is registered NON_POP at
`unixextern.p:1571`), and GC scans only the *record*, never the code
(`gccopy.p:131` `SCAN_PD_TABLE` stops at `PD_EXECUTE`). **So the GC linear sweep
does *not* force `record↔code` contiguity for the seed.** BUT two other things
do: (i) the linear sweep of the *moving heap* uses `next = current + PD_LENGTH`
(`gcmain.p:333`, `gcncopy.p:462`, `gccopy.p:253`), and (ii) **runtime
procedure-copy** allocates one `PD_LENGTH`-word block and `_moveq`s record+code
together (`procedure.p:216`, `closure_cons.p:66-69`). Plus the code must stay
executable (`__TEXT`/RX), which `__DATA`/`__DATA_CONST` is not. So a split layout
is **not viable for first light** — record and code must stay contiguous and the
code stays in an executable segment.

*Recommended — Option B, a startup relocation pass over the seed image.* Keep
`[record][code]` contiguous in an executable segment; rebase the record pointer
fields in place at startup, before first Pop execution:
1. **Reloc table:** have popc/poplink emit, alongside the image, the list of
   word offsets of every absolute `.quad <symbol>` pointer field (asmout
   `outdatum`/`asm_outword` already centralise pointer emission — tag them).
2. **Writable-then-exec seed → MAP_JIT (tested).** The seed can't live in dyld's
   RO `__TEXT` (it rejects the relocs at *link* time), and `mprotect(RW→RX)` on a
   plain linked segment is **refused on Apple Silicon** — verified: a custom
   `__DATA,__poptext` section with code + `mprotect(PROT_READ|PROT_EXEC)` gives
   `EACCES` ("Permission denied"). **So the seed code must run from a `MAP_JIT`
   region.** Shape: link the seed as a *data blob* (e.g. `__DATA`, so dyld even
   rebases the intra-blob pointers, or just raw offsets); at startup copy it into
   a `MAP_JIT` mapping, relocate pointers to that base, toggle RX via
   `pthread_jit_write_protect_np` (the proven Phase-4 helper), and enter. This is
   effectively making the corepop load its own image the way a `.psv` should load
   on macOS — so Phase 3's machinery is shared with image save/load.
3. **Apply slide:** `delta = actual_base − linked_base`; add `delta` to each
   tagged pointer (mirrors the existing callstack reloc `@(w){_callstack_reloc}`,
   `sr_sys.p:1011`); `sys_icache_invalidate`; protect RX. Empty/zero table on
   Linux (base matches) ⇒ no-op, ELF path unaffected.

This is the agent-estimated ~3-5 day core of Phase 3 and also unblocks general
`.psv` portability (same machinery). Page alignment is already fine
(`VPAGE_OFFS=16384`). The writable-seed mechanism is **settled: MAP_JIT**, since
`mprotect(RW→RX)` is refused even on a custom segment with `maxprot=rwx` (EACCES,
tested). MAP_JIT also needs the `com.apple.security.cs.allow-jit` entitlement at
codesign and an `mmap` with `PROT_READ|PROT_WRITE|PROT_EXEC`
(`tools/corepop-jit.entitlements`).

**The loader mechanism is PROVEN** (`tools/phase3-jit-reloc-loader-poc.c`): a
blob whose pointer fields are stored as blob-relative *offsets* + a reloc table
of those field offsets → `mmap(MAP_JIT)` → `pthread_jit_write_protect_np(0)` →
copy + add the JIT base to each tagged field → `pthread_jit_write_protect_np(1)`
→ `sys_icache_invalidate` → execute. Verified: entry code runs from MAP_JIT and
the relocated pointer resolves to the JIT base.

**Offset emission — also proven** (`.quad target - seed_base`): a cross-`.o`
subtractor relocation resolves to a link-time *constant* offset with **no
text-relocation** (tested: value 16 for a target 16 bytes past `seed_base`). So
the two halves of the scheme — the loader and the offset codegen — are both
de-risked. Note: the 983 distinct text-reloc symbols are all *intra-seed* Pop
labels (`c_`/`xc_`/`p_`/`_L…`); the only external-C references are in *code*
(`bl`/`adr_l`, already handled), so data pointer fields are uniformly intra-seed.

**Remaining build (piece 1, codegen):**
1. **Contiguity + markers:** route all Pop objects into one contiguous section
   (e.g. `__DATA,__popseed`, gated `UNIX_MACHO`) so `seed_base..seed_end` is a
   single copyable region; emit `seed_base`/`seed_end` globals (or use the
   linker's `section$start$…`). This also makes the link succeed (the `.quad`s
   become `__DATA`, dyld-rebasable) even before offsets land.
2. **Offset pointers:** in `outdatum`/`asm_outword`, when the datum is a *label*
   (always an intra-seed pointer), emit `<label> - seed_base` instead of
   `<label>`.
3. **Reloc table:** collect the field offsets and emit them as a table the loader
   reads. Emitted where the seed is consolidated — this is a **poplink**-level
   change (it lays out the final image), not asmout alone; or plant a per-field
   label and emit `.quad <field> - seed_base` rows.

*(Alternative if the reloc-table emission proves heavy: keep absolute `.quad`s in
`__DATA`, let dyld rebase, and have the loader read dyld's rebase info (chained
fixups) as the reloc table + a range check for intra-seed — simpler codegen,
fiddlier loader. The offset scheme above matches the proven PoC, so prefer it.)*

**Piece 2 (loader):** wire the proven sequence into `c_sysinit.c` startup
(locate `__popseed`, MAP_JIT-copy-relocate, hand off to `Sys$-Poplog_Main`);
leave out-of-blob pointers absolute. Artifacts staged at `~/poplog-mac-build`
(poplink_*.o, src.olb, libpop.a); the corepop link is 0-undefined — only this
relocation layer remains.
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
