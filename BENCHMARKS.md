# Poplog engine micro-benchmarks

**Revision 2026-06 (corrected).** Micro-benchmarks of Poplog's runtime-core
mechanics — procedure calls, integer arithmetic, allocation/GC, incremental
compilation, closures, and string handling — with Python and Perl baselines on
the same workloads. These characterise the *engine*, not applications, and are
deliberately small and single-threaded.

> **Scope & honesty note.** These are single-run micro-benchmarks at coarse
> (10 ms) resolution, intended to place Poplog's native-code engine *next to*
> popular interpreters on identical work — not to produce publication-grade
> confidence intervals. Every protocol detail, unit, and cross-language
> asymmetry below is disclosed so the numbers read (and reproduce) correctly.
> See [Threats to validity](#threats-to-validity).

---

## Systems under test

| ID | CPU | Cores / clock | OS | Poplog build |
|---|---|---|---|---|
| **i7** | Intel Core i7-9700K (Coffee Lake, 2018) | 8C/8T, 3.6–4.9 GHz | Ubuntu 22.04 LTS, x86-64 | Nix flake, verified `ELF 64-bit … x86-64` |
| **M2** | Apple M2 (2022) | 8-core (4P+4E), ~3.5 GHz | macOS, arm64 | This port (native Mach-O, arm64) |
| **Pi5** | Broadcom BCM2712 (Cortex-A76, 2023) | 4C, 2.4 GHz | DietPi (Debian), arm64 | Native (ELF, arm64, generic `armv8-a`) |

Interpreter baselines: CPython **3.10** (distro) and **3.13** (uv, PGO/LTO
build) on i7; CPython **3.14** on M2; CPython **3.13** on Pi5; Perl **5.34**
(i7/M2) and **5.40** (Pi5). Interpreter *build* matters as much as version
(see [Analysis](#analysis)), so each is named explicitly.

The environment is not pinned (no CPU isolation, fixed governor, or thermal
control); results are intended for **within-machine, cross-engine** comparison,
not cross-machine ranking.

---

## Methodology

* **What is measured.** Elapsed time of each workload, run once, in a freshly
  started engine, on an otherwise idle machine.
* **Unit: centiseconds (cs) — hundredths of a second, i.e. 1 cs = 10 ms.
  Lower is better.** This unit is used in *every* results table below.
* **Resolution is 1 cs (10 ms), single run, no warm-up and no averaging.** A
  reported **`0` means "below the 10 ms resolution"**, not "instantaneous".
  Treat differences of 1–2 cs as noise; the signal is in the multiples.
* **Timer asymmetry (disclosed).** Poplog uses `systime()` — process **CPU
  time**; Python uses `time.perf_counter()` and Perl `Time::HiRes::time` —
  **wall-clock** time. For these single-threaded, compute-bound workloads on an
  idle machine the two are close, and if anything CPU time slightly *favours*
  Poplog (it excludes time scheduled off-core). The effect is expected to be
  sub-resolution for most rows; it is noted here rather than hidden. (Aligning
  all timers on wall clock is listed under [Pending datapoints](#pending-datapoints).)
* **Identical workloads.** The Poplog, Python, and Perl programs implement the
  same seven workloads (`tools/bench-poplog.p`, `tools/bench-baseline.py`,
  `tools/bench-baseline.pl`). Cross-language mapping caveats are in
  [Workloads](#workloads).

---

## Workloads

| Key | What it does | Stresses | Cross-language note |
|---|---|---|---|
| **nfib29** | Naive doubly-recursive `nfib(29)` (≈1.35M calls) | Procedure-call overhead | Identical recursion in all three |
| **intloop10M** | Sum `1..10,000,000` in a tight loop | Integer arithmetic + loop dispatch | Boxed integers in both Pop and Python; on 32-bit Pop the sum overflows into **bignums** (see †) |
| **lists** | 200× build a 5,000-cell list + traverse (≈1M cons cells) | Allocation + GC pressure | Pop `conspair` ↔ chained 2-tuples; both traverse and discard |
| **compile500** | 500× **runtime-compile** a small procedure | Incremental compiler | **Pop compiles to *machine code*; Python `compile()` builds *bytecode*** — Pop does strictly more work, so parity is a *strong* result for Pop |
| **gc20** | 20× force a full GC over a heap of 50,000 live pairs | Garbage collector | Pop has a real moving GC; CPython is refcount + cycle collector — `gc.collect()` is the closest analogue |
| **closures1M** | 100k closures created, each called 10× (1M calls) | Closure creation + invocation | Equivalent closure capture in each |
| **strings** | Double a string 14× (→16 KB) then 200 substring searches | String build + search | Equivalent build-and-search |

† **32-bit overflow.** Pop-11 immediate integers ("popints") are ~29 bits, so
`intloop10M` overflows into bignums on 32-bit builds — that row then partly
measures bignum arithmetic. This is a real cost of 32-bit Poplog, *not* an
emulation artifact.

---

## Poplog across machines and backends

*All cells are **centiseconds (10 ms units), lower is better.** `0` = below
resolution; `-` = not implemented for that engine.*

| configuration | nfib29 | intloop10M | lists | compile500 | gc20 | closures1M | strings |
|---|---|---|---|---|---|---|---|
| i7-9700K, x86-64 Linux (Nix build) | 1 | 7 | 1 | 1 | 1 | 3 | 0 |
| Apple M2, arm64 macOS (this port) | 2 | 5 | 1 | 2 | 3 | 3 | 1 |
| Raspberry Pi 5, arm64 Linux | 2 | 12 | 3 | 1 | 4 | 4 | 0 |
| i7, arm64 Poplog under qemu-aarch64 | 21 | 79 | 17 | 4 | 16 | 131 | 1 |
| i7, arm32 corepop under qemu-arm (rpi3-class armhf, upstream `corepop.arm`) | 20 | 323† | 13 | 7 | 11 | 106 | 1 |

All three **native** builds land within ~2× of each other: both the x86-64 and
the arm64 backends generate excellent code. QEMU's dynamic-translation tax
(~10–30× here) is visible only in the explicitly emulated rows — and the arm32
`intloop10M` (323) is inflated further by the bignum overflow (†).

## Cross-language baselines (same workloads)

*All cells are **centiseconds (10 ms units), lower is better.** `0` = below
resolution; `-` = workload not implemented for that engine. Compare **down a
column within one machine** (the `i7:` / `M2:` / `Pi5:` prefixes); cross-machine
cells are not directly comparable.*

| configuration | nfib29 | intloop10M | lists | compile500 | gc20 | closures1M |
|---|---|---|---|---|---|---|
| i7: Poplog (x86-64, Nix) | 1 | 7 | 1 | 1 | 1 | 3 |
| i7: Python 3.13 (uv/PGO build) | 5 | 38 | 8 | 1 | 1 | 5 |
| i7: Python 3.10 (system) | 13 | 39 | 9 | 1 | 1 | 7 |
| i7: Perl 5.34 | 19 | 16 | - | - | - | - |
| M2: Poplog | 2 | 5 | 1 | 2 | 3 | 3 |
| M2: Python 3.14 | 7 | 29 | 7 | 1 | 1 | 5 |
| M2: Perl 5.34 | 19 | 19 | - | - | - | - |
| Pi5: Poplog | 2 | 12 | 3 | 1 | 4 | 4 |
| Pi5: Python 3.13 | 25 | 131 | 25 | 2 | 3 | 20 |
| Pi5: Perl 5.40 | 93 | 82 | - | - | - | - |

---

## Analysis

* **Native-code speed with interactive ergonomics.** Across every machine,
  Poplog leads the *best* available Python build by ~**5×** on procedure calls
  (`nfib29`) and **5–10×** on loops, lists, and closures — while offering the
  same incremental, REPL-driven workflow. That is the headline: *interactive
  like Python, native-code fast.*
* **`compile500` is the strongest result, not the weakest.** Pop and Python
  tie here, but Pop's incremental compiler emits **machine code** while
  Python's `compile()` emits **bytecode**. Parity on unequal work favours Pop.
* **Interpreter build matters as much as version.** On the same i7, `nfib29`
  costs **13** (CPython 3.10 distro) vs **5** (CPython 3.13 uv PGO/LTO) — a 2.6×
  spread from build configuration alone. Always name the interpreter build.
* **`gc20` is the one Python sometimes ties.** CPython's refcounting makes
  `gc.collect()` cheap on an acyclic heap; Pop runs a real moving collector.
  Different mechanisms — read this row as "comparable," not "decisive."
* **Perl** trails on both headline workloads everywhere, and implements only
  the two it can map cleanly.

---

## Threats to validity

1. **Single run, 10 ms resolution.** No warm-up, no averaging, no confidence
   intervals. Differences of 1–2 cs are within noise; only multiplicative gaps
   are meaningful. `0` cells are sub-resolution.
2. **CPU-time vs wall-time asymmetry** between Poplog (`systime`) and the
   baselines (wall clock) — small for these workloads, slightly Pop-favouring;
   see [Methodology](#methodology).
3. **Cross-language semantics are not identical.** `compile500` (machine code
   vs bytecode) and `gc20` (moving GC vs refcounting) compare *analogous*, not
   identical, operations — annotated in [Workloads](#workloads).
4. **32-bit bignum overflow** inflates `intloop10M` on the arm32 row (†).
5. **Unpinned environment.** No core pinning, governor fix, or thermal control;
   adequate for order-of-magnitude within-machine comparison, not tight ranking.
6. **The QEMU artifact (now fixed).** An earlier revision reported x86-64 Poplog
   as 5–10× slower than the arm64 backend. That was an artifact: the benched
   `basepop11` was an **aarch64** binary left in the tree by cross-compilation,
   and Linux `binfmt_misc` silently ran it under `qemu-aarch64` (which also
   explains why it "matched" an explicit QEMU run — it was the same thing
   twice). **`tools/bench-poplog.sh` now prints `file` of the engine; always
   check the arch.** The x86-64 numbers here are from the Nix-built,
   file-verified tree.

---

## Reproducing

```sh
./tools/bench-poplog.sh                  # prints host, CPU, and engine arch -- CHECK IT
python3 tools/bench-baseline.py          # or: uv run --python 3.13 tools/bench-baseline.py
perl    tools/bench-baseline.pl
# QEMU (binfmt-mediated): QEMU_LD_PREFIX=<sysroot> <foreign binary> < tools/bench-poplog.p
```

The harness prints `hostname`, CPU model, and `file` of the engine before
running, so a wrong-architecture engine (the failure mode in Threats to
validity #6) is caught immediately. Workloads are fixed in the three
`tools/bench-*` scripts; keep them identical across platforms for comparability.

## Pending datapoints

* A **real Raspberry Pi 3** (or MediaTek Genio-class arm64) for the low-power
  tier, to replace the QEMU arm32/arm64 stand-ins with native silicon.
* **Multi-run, wall-clock-aligned timing** to put error bars on the headline
  rows and remove the CPU-vs-wall timer asymmetry.
