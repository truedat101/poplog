# Upstream candidates: arm64 bugs found during the macOS port

Target: https://github.com/hebisch/poplog (Waldek Hebisch's tree, the
source of the AArch64 backend this branch builds on).

The macOS/Apple-Silicon port (branch `12-mac-os-x-m-silicon-port`)
shook out several bugs that are **not macOS-specific**: they live in
shared arm64 (or fully generic) code and are latent or live on arm64
Linux.  Group A below is upstreamable on its own merits, independent of
any interest in the Darwin port itself (Group B).

Validation baseline for every Group A item: RPi5 arm64 Linux
`validate-raspi5.sh` 12/12 before and after; macOS 12-gate ladder and
the gfx walkthrough green.

---

## Group A — generic arm64 (and one fully generic) bug fixes

### A1. genproc.p: dlocal save slots inverted vs the GC scan window
Commit `f28d443` · `pop/src/syscomp/arm64/genproc.p`

`M_CREATE_SF` assigned dlocal save slots in **ascending** frame order
(its comment assumed "non-pop dlocals first" — the SPARC ordering).
The non-SPARC `m_trans.p` builds `all_dlocals` as
`pop_dlocals <> nonpop_dlocals` and the shared contract —
`PD_GC_OFFSET_LEN`/`PD_GC_SCAN_LEN` and runtime `Dlocal_frame_offset`
(table index k → slot `Ndlocals-1-k`) — maps list order to
**descending** slots, leaving pop dlocals adjacent to the pop register
saves where the GC's `App_calls` window scans.

Consequences on arm64 Linux (verified on a validated RPi5 build:
dlocal-save a heap closure into `cucharout` across `sysgarbage()` →
stale pointer): every GC failed to relocate dlocal-saved pop values;
`Copyscan` treated non-pop dlocal saves as pop pointers;
`M_PD_SAVES_NEXTFREE` zeroing hit the wrong slot.  In practice this is
the long-standing "popc/Copyscan flakiness under compile load" on
arm64, and it corrupted any GC where a movable value was dlocal-saved
(e.g. lisp output streams).  Fix: assign/restore the dlocal slots
descending in `M_CREATE_SF`/`M_UNWIND_SF`.

### A2. ext_arm.c: K_EXTERN_TYPE read at the wrong key offset
Commit `689b52b` · `pop/extern/lib/ext_arm.c`

`ET_OFF` was 98 ("12 fields * 8 + 2"), mis-counting the two `int`
fields (`K_FLAGS`, `K_GC_TYPE`) as `full`s.  The 64-bit key layout
puts `K_EXTERN_TYPE` at 2×4 + 10×8 + 2 = **90**; offset 98 reads a
byte of `K_CONS_R`, which is non-zero for most keys, so **every
compound external argument was classified "dereference"**: external
pointers worked by accident, exfunc closures were passed by content
(first 8 code bytes as the "function pointer"), and `ET_DDEC` never
matched, so ddecimal (float) arguments to C functions were broken on
arm64.  Verified against the key records in a built image
(`+90`: exfunc=0/NORMAL, exptr=1/DEREF).

### A3. external.ph: EFC_CODE_SIZE wrong for aarch64
Commit `689b52b` · `pop/src/external.ph`

The aarch64 exfunc-closure template
(`syscomp/arm64/asmout.p` `asm_gen_exfunc_clos_code`) emits 4 xwords
(instructions + the 8-aligned action literal = 32 bytes), but
`EFC_CODE_SIZE` stayed 16, so `EFC_ARG`/`EFC_ARG_DEST` (and the
record's GC size) pointed **inside the code**.  C→Pop callbacks could
never have worked on arm64 (unexercised: arm64 Linux is built -nox,
and X callbacks are the main consumer).  With A2+A3 the callback chain
passes end-to-end (`exfunc_export` closure called from C, three round
trips).

### A4. ass.p: literal-pool buffer overflow at the 257th literal
Commit `cfb27a4` · `pop/src/arm64/ass.p`

`Do_consprocedure` allocated `lit_buff = initintvec(512)` — intvec has
**32-bit elements** (2048 bytes) — but `load_literal` stores with
8-byte word indexing (`lit_buff!(w)[_lit_count]`).  Literal #257+
overflowed the vector, spraying addresses over the adjacent heap
object; the `_lt _512` capacity check was the coincidence 512×4 ==
256×8.  Rare on Linux (MOVZ/MOVK covers most values) but reachable;
on any port with high addresses the pool path is hot.  Fix:
`initlongvec(2048)`.

### A5. procedure.p: Flush_procedure flushes a wild range for shared-code closures
Commit `e6fd5a9` · `pop/src/procedure.p` (fully generic)

`Flush_procedure` computes the flush length as record-end −
`PD_EXECUTE`.  For procedures whose `PD_EXECUTE` points outside their
own record (closures executing shared template code), that length is
wild (observed: 545 GB), and the icache-flush walks into unrelated
mappings.  Harmless-by-luck on compact ELF layouts; faults on Darwin.
Fix: skip the flush unless `PD_EXECUTE` lies within
`[record, record+PD_LENGTH)` — code outside the record was flushed
when it was created.

### A6. ass.p: pass-0 measures with zero _pdr_offset/_strsize
Commit `832ebb3` · `pop/src/arm64/ass.p` (currently Darwin-gated)

Pass 0 measured the instruction stream with `_pdr_offset = 0` and
`_strsize = 0`, but instruction *selection* depends on both
(`I_CREATE_SF` immediate-vs-two-instruction forms, PB-relative load
forms).  When the final values differ enough (>4KB structure tables),
the measured and planted streams diverge and every pool-relative LDR
mis-addresses.  The re-measure (pass 0b) is gated `DEF DARWIN` in this
branch because only Darwin's address ranges force pooled literals
everywhere, but the bug is latent on ELF; upstream may prefer it
ungated.

### A7. lisp/clos.p: mid-file autoload re-imports cancelled words
Commit `55236b4` · `pop/lisp/src/clos.p` (fully generic)

`clos.p` cancels `define_method` etc. and then references autoloadable
`ncrev`: the autoload's `section;...endsection;` round-trip re-imports
the cancelled globals, and the later constant declaration mishaps.
Fix: `uses` the autoloadable dependencies before the `syscancel`.
(On the RPi5 the autoload silently failed instead, leaving a latent
broken CLOS — worth checking upstream lisp builds.)

---

## Group B — the Darwin port itself

Everything else on the branch is the macOS OS-layer port: Mach-O
emission, the `__POPSEED` loader, the dual-mapped W^X heap (+ fork
re-remap), ASLR handling, variadic-ABI wrappers, dlsym name mangling,
host-OS sysdefs selection, the Darwin link recipe, the native
graphics backend, and the `rc_graphic`/`rc_mouse` ports.  See
`PORTING-ARM64-M-SILICON-OSX.md` (status banner at the top) for the
complete map.  These are offered as a piece if upstream wants Darwin
support; A1–A7 stand alone.
