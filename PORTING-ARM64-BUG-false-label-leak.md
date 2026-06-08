# ARM64 Port — codegen stack-leak bug — ✅ RESOLVED (2026-06-02)

**Status: FIXED.** Both phenomena (B: the ≈291-file `items-left` stack leak; A:
the raw values reaching the asm layer) had a **single root cause and a one-line
fix**, after which all three masking band-aids were removed and the Phase 5 gate
(clean `stamp_srclib` with the *original fatal* items-left check) passes: full
source library builds **exit 0, zero mishaps, zero assembler errors**.

### Root cause (one line)

`pop/src/syscomp/arm64/genproc.p`, `outinst`, the `#`-comment branch:

```
asmf_printf(false, '\t//');     ;;; BUG: format '\t//' has no %p, so the
                                ;;;      `false` arg is never consumed and
                                ;;;      leaks onto the Pop-11 user stack
```

`asmf_printf` → `printf`; the format `'\t//'` contains no `%p`, so the spurious
`false` is never consumed. Every procedure's code list begins with a `{#}`
comment instruction (`conspair({#}, [])`), so **one `false` leaked per
procedure**. The fix:

```
asmf_printf('\t//');            ;;; pass no value arg
```

### Why this one bug produced both A and B

The leaked `false` items accumulated on the user stack as each file compiled
(**B** — `items-left after file`, scaling with procedure count: lispcore 136,
getstore 52, …). That same stack corruption shifted what the downstream
structure/closure emission popped, so wrong values (`false`, the `%OP_CALL`
closure, a vector) were handed to `outdatum` and masked into labels/null
pointers by the band-aids (**A**). After the fix, a full build produces
**0 items-left** *and* **0 raw values reaching `outdatum`** (was 16: 9 `false`
+ 7 null). One cause, both symptoms.

### Follow-on cleanup (all verified by a clean fatal-gate build)

- Removed the `outdatum` substitution band-aid (`arm64/asmout.p`) → replaced
  with a **defensive `mishap`** if any raw Pop-11 value ever reaches it again.
- Removed the `gen_prop_entries` "tolerate-false" band-aid (`genstruct.p`) →
  restored the original `datalength() -> tab_size`.
- Removed the `get_addressable_op` boolean fallback (`arm64/genproc.p`).
- Restored `do_asm.p` to its original **fatal** `ITEMS LEFT ON STACK` check
  (dropped the WIP warn-and-drain + ARM64-DIAG probes) — so a green
  `stamp_srclib` now means a *correct* build.

Net source change: **−45 / +16 lines** (more band-aid removed than added).

### What was refuted along the way (kept for the record)

The earlier theories below — that `genstructure`/`label_of` fails to map `false`
to a label (perm-const seed), or that A and B were separate bugs in the
literal-emission path — were **both wrong**. `genstructure(false)` returns the
correct label `c_false` 2928/2928; A and B were one stack-discipline bug. The
historical analysis is retained below for context only.

---

## (Superseded) earlier framing — two bugs, A tiny

The shared `genstructure`/`label_of` chain and the standard-immediate seed are
**exonerated**; `genstructure(false)` returns the correct label 2928/2928.

Companion to `PORTING-ARM64-VALIDATION-STATUS.md` (running log) and
`PORTING-ARM64-LINUX-RPI5.md` (overall plan). This file documents *one* bug in
depth so the fix can be made and verified.

---

## ⚠⚠ Update 2 (2026-06-02, `.s` diff + substitution inventory) — A and B are SEPARATE, and A is tiny

Comparing arm64-vs-x86_64 emitted assembly, plus a whole-library inventory of
every value the `outdatum` band-aid substitutes, shows the two phenomena are
**not the same bug** and the asm corruption is far narrower than feared:

- **arm64 codegen is structurally sound.** It uses a correct per-procedure
  **constant pool** (AArch64 can't materialise 64-bit addresses inline, so
  literals are loaded PC-relative via `ldr x20,[…]`). `false`/`true`/`[]`
  resolve to the correct labels (`c_false`, …). Most `.xword 0` entries are
  **legitimate** (rawstruct zero-init, stackmark) and identical on x86_64.

- **Phenomenon (A) — raw value at `outdatum` → null pointer — is TINY.**
  Whole-library inventory: **16** raw values reach `outdatum`; **9** are
  `false→c_false` (correct output), and only **7 are genuinely corrupting
  null pointers**: **6× the `%OP_CALL` closure → `0`** and **1× a vector → `0`**.
  So the band-aids corrupt **7 pointer slots in the entire core image**, not
  ~285 files' worth.

- **Phenomenon (B) — `items-left` stack leak — is the real Phase 5 blocker and
  is UNRELATED to (A).** It is large (≈285 files, scales with file size:
  `lispcore.p` 136, `getstore.p` 52, …) and the leaked values **never reach
  `outdatum`** — they sit on the Pop-11 user stack. **Confirmed arm64-specific:**
  the same files compiled on x86_64 (identical shared `do_asm.p`) leave **0**
  items. `generate`, `m_optimise`, and `outdatum` are all stack-balanced, so the
  imbalance is in the **per-procedure emission around them** — prime suspect: the
  part of `mc_code_generator` (arm64 `genproc.p`) that runs *after* `generate()`
  and emits the literal table / pdr record (`asm_outword` calls ~1984/2049/2052).

**Revised priorities:**
1. **(B) items-left** — the actual blocker. Localise with a `stacklength()` delta
   probe around `mc_code_generator`'s post-`generate` emission and the arm64
   literal-table loop. (Per-procedure imbalance of ~1 item, accumulating.)
2. **(A) null pointers** — only 7 slots; fix by making `genstructure`/the pool
   emission produce a real label for the `OP_CALL` closure and the leaked vector
   (these specific structures return raw where `false` correctly returns a
   label). Then remove the band-aids.

The rest of this file (below) is earlier analysis; treat the "literal-emission
path" framing as refined by this update — (A) and (B) are distinct.

---

## ⚠ Correction (2026-06-02) — what the probe proved, and what it refuted

A probe was added to `genstructure` (print `label_of`'s return for every
`item == false`) and to `setup_selected_consts` (print whether the perm-const
seed resolved), then `popc` was rebuilt and the **same files compiled on both
arm64 and x86_64**. Results:

1. **`genstructure(false)` is NOT the bug.** In a full arm64 `stamp_srclib`
   build it is called **2928 times and returns the correct label `c_false`
   every single time** (`item==lab=<false>`, i.e. it takes the proper
   label-generating path). Zero raw-`false` returns. The same holds on x86_64.

2. **The perm-const seed failing is a RED HERRING.** `word_identifier('false',
   pop_section, false)` returns `false` and `struct_label_prop(false)` is
   `false` *immediately after* `setup_selected_consts` on **both** arches —
   yet by the time `genstructure(false)` runs, `struct_label_prop(false)` is
   `c_false` on **both** arches (it is cached/established after the seed step).
   So this path is identical x86_64↔arm64 and cannot explain the divergence.

3. **`asmf_pr` is shared** (`lib.p:51`): `sys_syspr(false)` prints `<false>`
   on both arches. So x86_64 cannot be passing raw `false` to the asm layer
   either — **x86_64 never produces a raw `false` at emission**, while arm64
   sometimes does. The divergence is therefore in **arm64-specific code**
   (`syscomp/arm64/{genproc,asmout,sysdefs}.p`), reached via the literal path.

4. **The `items-left` stack leak (≈291 files) still reproduces** after all the
   above — it is the real Phase 5 blocker and is *not* explained by
   `genstructure(false)`.

Net: the structure walkers (`genstructure`, `label_of`, `gen_vectorclass`,
`generate_closure`) and the standard-immediate seed are **exonerated**. The
bug lives in how the arm64 backend plants **quoted literals** (the constant
table of a compiled procedure) — see *Refined locus* below.

---

## One-line statement

When `popc` cross-compiles the source library for arm64, the **quoted-literal
emission path** in the arm64 backend (planting a compiled procedure's constant
table — `pas_PUSHQ`/`getstr`/`push_str` and the `mc_code_generator`
`asm_outword` loop) mishandles literals that contain the standard immediates
**`false`/`true`/`[]`** or the closures freezing them (e.g.
`OP_CALL = do_call(%false,false%)`): it leaves those values on the Pop-11 stack
(the `items-left` leak) and/or hands a raw value to the asm layer. Three
band-aids then convert the raw values into **null pointers** so the assembler
accepts the file — which is exactly why the resulting binary cannot run.

> The shared `genstructure`/`label_of` chain correctly maps `false → c_false`
> (proven, 2928/2928); see the *Correction* box above. The defect is
> arm64-specific and downstream of structure labelling.

---

## Why it matters

- The `items-left after file` stack leak (≈291 files) and the
  null-pointer-riddled binary ride the **same literal-emission path** and very
  likely share one root (not yet proven identical).
- It cannot be worked around at the asm-output layer without writing garbage
  into the image (the current band-aids do exactly that). It must be fixed in
  the arm64 backend's literal emission.
- It blocks Phase 5 (clean `stamp_srclib`) and therefore everything after it
  (QEMU validation, RPi5 native build).

---

## Confirmed causal chain (top → bottom)

Captured by temporarily replacing the `outdatum` band-aid in
`pop/src/syscomp/arm64/asmout.p` with `mishap(v, 1, 'ARM64-LOCATE …')` and
cross-compiling. Two representative backtraces (verbatim DOING chain):

```
;;; INVOLVING:  <false>
;;; DOING : … outdatum applist generate_closure genstructure
;;;             applist maplist generate_closure genstructure
;;;             gen_vectorclass genstructure getstr push_str pas_PUSHQ
;;;             trans_vmcode m_translate gen_procedure genstructure
;;;             gen_perm_inits gen_assembler do_compile do_popc compile_file …

;;; INVOLVING:  <procedure '%OP_CALL'>
;;; DOING : … outdatum applist generate_closure genstructure
;;;             gen_perm_inits gen_assembler do_compile do_popc compile_file …
```

1. **`generate_closure`** — `pop/src/syscomp/m_trans.p:2226`
   (`$-Popas$-generate_closure`). For each closure literal it maps
   `genstructure` over the frozvals (lines 2262-2266):

   ```
   maplist(frozvals, procedure() -> i;
                         lvars f = genstructure(), i;
                         unless _intval(f) ->> i then f -> i endunless
                     endprocedure) -> frozvals;
   ```

   The result list is later emitted, field by field, via `asm_outword` →
   `outdatum`. `genstructure` is expected to return a **label**; for an integer
   frozval `_intval` extracts the immediate; for everything else `f` (the label)
   is kept.

2. **`genstructure(item)` — EXONERATED by the probe.**
   `pop/src/syscomp/genstruct.p:330`. The original suspicion was that
   `label_of(false, false)` returns `false`, so `item == lab` would be true and
   genstructure would return the raw boolean. **Measurement shows this does not
   happen:** `label_of(false)` returns `c_false` (= `asm_symlabel('false')`),
   `item == lab` is `false`, and genstructure takes the normal label path —
   2928/2928 times in a full build. So `false` is correctly turned into a label
   here. The raw value the locator caught at `outdatum` therefore enters the
   emission **after** this point, on a different (arm64-specific) edge of the
   chain.

3. **The arch-specific edge — `pas_PUSHQ` / `getstr` / `push_str`** in
   `pop/src/syscomp/arm64/genproc.p` (visible in the first backtrace:
   `… getstr push_str pas_PUSHQ trans_vmcode m_translate …`). These plant a
   **quoted literal** (an entry of the compiled procedure's constant table).
   The literal here is a vectorclass that contains the `OP_CALL` closure whose
   frozvals include `false`. The shared walkers (`gen_vectorclass`,
   `generate_closure`) are correct on x86_64, so the divergence is in how the
   arm64 backend hands the literal to / collects it from those walkers, or in
   the literal-table `asm_outword` calls in `mc_code_generator`
   (`genproc.p` ~lines 1984/2049/2052). This is the **unconfirmed** node.

4. **Two phenomena, possibly one cause:**
   - **(A) raw value at `outdatum`** — caught by the locator; masked by the
     band-aids into a null pointer (corrupts the binary).
   - **(B) `items-left` on the Pop-11 stack** — ≈291 files; the Phase 5
     blocker. `generate`/`m_optimise` are stack-balanced (their probes never
     fired), so the imbalance is in the literal-emission/`asm_outword` plumbing
     above, not in M-code translation.
   Whether (A) and (B) share one root is **not yet proven**, but the leaked
   values match (`<false>`, `<procedure %OP_CALL>`) and both ride the same
   literal-emission path.

---

## The three band-aids that mask it (must be REMOVED as part of the fix)

All three were added to keep the build "green"; each turns a leaked raw value
into a placeholder/null and is *why the binary is corrupt*:

| File / proc | Commit | What it does |
|---|---|---|
| `pop/src/syscomp/arm64/asmout.p` `outdatum` | 3e3dd24 | Substitutes leaked `false`/`true`/`[]` → `asm_symlabel('false'/'true'/'nil')`, and a leaked **procedure/vector → `0` (null pointer)**. `outdatum` itself is stack-balanced, so it masks but does not itself leak. |
| `pop/src/syscomp/genstruct.p` `gen_prop_entries` | 3e3dd24 | "tolerate a false-leak in the table arg": `() -> _tab; if isvector(_tab) … else 0`. |
| `pop/src/syscomp/arm64/genproc.p` `get_addressable_op` (~line 479) | — | "defensive fallback if a Pop-11 boolean leaks here from the genstructure chain"; emits a placeholder. |

Note: the `asm_symlabel('false')` substitution in `outdatum` happens to produce
the *correct* label for the boolean cases — which is a strong hint that the
proper fix is simply to make `label_of`/`genstructure` return that same
`asm_symlabel`-equivalent label up front. The procedure/vector → `0` cases are
the ones that produce null pointers and a dead binary.

---

## Evidence summary

- **Not an M-handler bug.** The `accea93` ARM64-DIAG probes inside
  `generate` (genproc) and `do_premove`/`m_optimise` never fired — those phases
  are stack-balanced. (This corrects the earlier "broken M-instruction handler"
  theory in the status doc.)
- **`POPINT_BITS` is correct (61, == x86_64).** Ruled out as the divergence.
- **Per-file attribution** (loop-top `consvector` drains each iteration, so file
  N+1's loop-top count == items file N left): all 285 files leak ≥1; leak scales
  with file size. Top: `lispcore.p` (136), `arm64/asignals.s` (107),
  `pop11_syntax.p` (99), `vm_plant.p` (73), `intvec.p` (64).
- **A bare `constant` decl does not leak**; the leak appears with
  procedure/closure literals. The per-file baseline `<false>` is one such.
- **`genstructure(false)` returns the correct label `c_false` 2928/2928** in a
  full build (probe) — exonerated. Same on x86_64.
- **`asmf_pr` is shared** (`lib.p:51`); it would emit `<false>` on x86_64 too,
  so x86_64 never produces a raw `false` at emission. The divergence is in the
  arm64 backend's literal-emission path, reached via `pas_PUSHQ`/`getstr`.

---

## Open question (refined locus — confirm before patching)

The shared structure chain is exonerated; the bug is on the arm64 literal path.
Confirm which of these is the actual defect:

1. **`getstr`/`push_str`/`pas_PUSHQ` in `arm64/genproc.p`** mis-handle a quoted
   vectorclass/closure literal — e.g. push the structure (or its components)
   onto the user stack without the matching consume, so the walker's output
   isn't collected the way `mc_code_generator` expects. *(Prime suspect for the
   `items-left` leak (B).)*
2. **The literal-table emission `asm_outword` calls in `mc_code_generator`**
   (`genproc.p` ~1984/2049/2052) emit the constant table with the wrong arity
   or feed a raw structure where x86_64 feeds a label. *(Prime suspect for the
   raw-value-at-`outdatum` (A).)*
3. A `sysdefs.p` size/offset constant (e.g. closure header length, word offset)
   makes the arm64 literal/closure layout walk produce an off-by-one in the
   field list. *(Would explain both A and B at once.)*

**Decisive next steps:**
- **Compare emitted assembly directly.** Build a *clean* x86_64 `popc` and a
  clean arm64 `popc` (band-aids temporarily disabled / `outdatum` set to
  `mishap`), compile the **same** closure-bearing file (e.g. `errors.p`,
  `arctan2.p`), and diff the `.s`. x86_64's `.s` shows the correct constant
  table; the first structural difference is the fix target.
- **Localize the stack imbalance (B).** Add a `stacklength()` delta probe around
  the arm64 `pas_PUSHQ`/`getstr` handlers and around the per-literal
  `asm_outword` loop in `mc_code_generator`, then compile a minimal closure
  literal — the handler whose delta is non-zero is the leak.

## Fix plan (supersedes the band-aids)

1. Confirm the refined-locus node above (asm diff + stacklength probe).
2. Fix the arm64 literal-emission handler so quoted closure/vectorclass
   literals are planted with the correct field list and stack discipline (match
   what x86_64's backend produces for the same literal).
3. **Remove all three band-aids** (table above). With the root fixed, no raw
   value should reach `outdatum`; if one does, `outdatum` should `mishap`, not
   substitute.
4. Revert `pop/src/syscomp/do_asm.p`'s warn-and-drain to a hard mishap so a
   green `stamp_srclib` means a *correct* build (the Phase 5 gate).
5. Rebuild `stamp_popc` → `stamp_srclib`; confirm **zero** `items-left`
   warnings and no `0`/placeholder substitutions; then proceed to
   `stamp_new_corepop` and QEMU (Stage 7).

---

## Fast reproducers

Single leaked `<false>` (no full build needed):

```sh
cd pop/src
POP__as=/usr/bin/aarch64-linux-gnu-as ../../poplog ../../target/pop/popc \
    -c -nosys -od /tmp allbutfirst.p allbutlast.p
# → allbutlast.p loop-top reports {<false>} == the item allbutfirst left
```

Full attribution + backtrace:

```sh
rm -f stamp_popc target/pop/popc.psv && make stamp_popc          # picks up ARM64-DIAG probes
rm -f stamp_srclib target/obj/src.{wlb,olb} target/obj/termcap.{wlb,olb}
POP__as=/usr/bin/aarch64-linux-gnu-as make stamp_srclib 2>&1 | tee /tmp/build-srclib-diag.log
grep 'ARM64-DIAG loop-top' /tmp/build-srclib-diag.log   # per-file leak counts
```

To re-capture the backtrace, temporarily add to `outdatum` (arm64/asmout.p),
as the first statement inside its `fast_for` loop:

```
if isboolean(v) or isprocedure(v) or isvector(v) or ispair(v) then
    mishap(v, 1, 'ARM64-LOCATE: RAW VALUE REACHED outdatum (expected a label)')
endif;
```

then `rm -f stamp_popc target/pop/popc.psv && make stamp_popc` and compile any
file with a closure literal. **Revert it afterward** (`git checkout
pop/src/syscomp/arm64/asmout.p`) and rebuild `stamp_popc` — the mishap aborts
real builds.
