# Poplog engine micro-benchmarks

**Revision 2026-06 (corrected).** Micro-benchmarks of Poplog's runtime-core
mechanics — procedure calls, integer arithmetic, allocation/GC, incremental
compilation, closures, and string handling — with Python and Perl baselines on
the same workloads. These characterise the *engine*, not applications, and are
deliberately small and single-threaded.

> **Re-collection in progress (2026-06).** The harness has been rebuilt to a
> statistically rigorous protocol — CPU-time across all engines, auto-calibrated
> batches, warm-up, **N repeated runs**, and **median + bootstrap 95 % CI** with
> coefficient-of-variation, via `tools/bench.sh` (see [Methodology](#methodology)
> and [Reproducing](#reproducing)). **The numeric tables below are still the
> earlier single-run values and will be replaced** with median + CI figures
> collected with the new harness on each machine (decks cleared, governor fixed).
> Treat the current numbers as *indicative ordering*, not final.
>
> **Scope.** These characterise the *engine*, not applications, and are
> deliberately small and single-threaded. Every protocol detail, unit, and
> cross-language asymmetry is disclosed so the numbers read (and reproduce)
> correctly. See [Threats to validity](#threats-to-validity).

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

The harness (`tools/bench.sh`, driving `bench-poplog.p` / `bench-baseline.py` /
`bench-baseline.pl`, aggregated by `bench-aggregate.py`) follows a deliberately
conservative microbenchmark protocol:

* **Metric: CPU time, identical across engines.** Poplog `systime()`, Python
  `time.process_time()`, Perl `(times())[0,1]` — all **process CPU time
  (user+system)**. Using CPU time (not wall clock) makes the three engines
  *directly comparable* AND robust to background load, which matters most when
  "clearing the decks." (Poplog's wall-clock `sys_microtime` is unreliable on
  the Darwin port — it returns stale values inside compute-heavy procedures —
  so CPU time is also the *reliable* choice.)
* **Auto-calibration.** Each workload is repeated **K** times per timed batch,
  K chosen automatically so a batch lasts ≥ `BENCH_MINTIME` (default **2 s**) of
  CPU time. The per-iteration cost is the batch time ÷ K. This keeps the 10 ms
  timer resolution a tiny fraction of each batch on every engine, fast or slow.
* **Warm-up + repetition.** `BENCH_WARMUP` batches (default 3) are discarded to
  settle caches/allocation, then **`BENCH_RUNS` batches (default 30)** are
  recorded per workload.
* **Statistics.** The aggregator reports, per workload, **min, median, mean,
  coefficient of variation (CoV %), and a bootstrap 95 % CI on the median**
  (10 000 resamples). Cross-engine comparison reports the **ratio of medians
  with a bootstrap 95 % CI** — *a CI that excludes 1.0 is significant at ≈5 %*.
  Medians (not means) are headline because timing distributions are
  right-skewed by OS interference; pure-stdlib so it runs even on a Pi.
* **System-under-test capture.** `bench.sh` records CPU, logical cores, RAM,
  cache sizes, governor (and warns if it isn't `performance`), load average
  (warns if busy), and `file` of the engine (the binfmt/arch guard from
  [Threats to validity](#threats-to-validity)).
* **Identical workloads** across all three engines; cross-language mapping
  caveats are in [Workloads](#workloads).

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

Clear the decks first (close browsers/apps; on Linux set the CPU governor to
`performance`), then run the full suite on each machine:

```sh
./tools/bench.sh                         # SUT capture + all engines + stats + comparison
./tools/bench.sh /path/to/basepop11      # benchmark a specific engine
PYTHON=python3.13 ./tools/bench.sh        # pick the Python build (name it in the report!)
BENCH_RUNS=50 BENCH_MINTIME=3 ./tools/bench.sh   # more rigour (longer runtime)
```

Quick single-engine check, or feeding the aggregator directly:

```sh
./tools/bench-poplog.sh                  # Poplog only, with stats; prints engine arch -- CHECK IT
./poplog ./target/pop/basepop11 < tools/bench-poplog.p | python3 tools/bench-aggregate.py
python3 tools/bench-aggregate.py run1.samples run2.samples   # compare saved sample files
# QEMU (binfmt-mediated): QEMU_LD_PREFIX=<sysroot> <foreign binary> < tools/bench-poplog.p
```

`bench.sh` prints `file` of the engine before running, so a wrong-architecture
engine (the failure mode in Threats to validity #6) is caught immediately.
Workloads are fixed in the three `tools/bench-*` scripts; keep them identical
across platforms for comparability. To compare several Python builds on one
machine, run the baseline under each and pass all the `.samples` files to
`bench-aggregate.py`.

## Pending datapoints

* **Re-collect every table** with `tools/bench.sh` (median + 95 % CI) on each
  machine with the decks cleared, replacing the indicative single-run numbers.
* A **real Raspberry Pi 3** (or MediaTek Genio-class arm64) for the low-power
  tier, to replace the QEMU arm32/arm64 stand-ins with native silicon.
* A reliable **wall-clock** µs timer for Poplog (fix or work around the Darwin
  `sys_microtime` bug) if a wall-time cross-check is ever wanted alongside the
  CPU-time numbers.
