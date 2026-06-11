# Benchmark results (2026-06)

Micro-benchmarks of runtime-core mechanics -- procedure calls,
allocation/GC, incremental compilation, closures, strings.  They
characterise the *engine*, not applications.  Workloads are identical
across languages (`tools/bench-poplog.p`, `tools/bench-baseline.py`,
`tools/bench-baseline.pl`); times in centiseconds, lower is better.

## Poplog across machines and backends

| configuration | nfib29 | intloop10M | lists | compile500 | gc20 | closures1M | strings |
|---|---|---|---|---|---|---|---|
| Apple M2, arm64 macOS (this port) | 2 | 9 | 2 | 2 | 3 | 16 | 1 |
| Raspberry Pi 5, arm64 Linux | 2 | 12 | 3 | 1 | 4 | 4 | 0 |
| i7-9700K, x86-64 Linux | 21 | 77 | 17 | 5 | 17 | 134 | 1 |
| i7-9700K, **arm64 Poplog under qemu-aarch64** | 21 | 79 | 17 | 4 | 16 | 131 | 1 |
| i7-9700K, **arm32 corepop under qemu-arm** (rpi3-class armhf, upstream `corepop.arm` from poplog.fricas.org) | 20 | 323* | 13 | 7 | 11 | 106 | 1 |

\* 32-bit popints are ~29 bits: the 10M sum overflows into bignums, so
this row measures bignum arithmetic -- a real cost of 32-bit Poplog,
not an emulation artifact.

**The headline:** the arm64 build *emulated instruction-by-instruction*
on the i7 matches the native x86-64 build on the same machine.  QEMU's
translation overhead is typically 5-10x, so the x86_64 backend's
generated code is roughly that much worse than the arm64 backend's.
The fast machines here are not faster hardware so much as a better
backend: the $80 Pi 5 matches the M2 and beats the i7 build 7-30x.

## Cross-language baselines (same workloads)

| configuration | nfib29 | intloop10M | lists | compile500 | gc20 | closures1M |
|---|---|---|---|---|---|---|
| M2: Poplog | 2 | 9 | 2 | 2 | 3 | 16 |
| M2: Python 3.14 | 7 | 29 | 7 | 1 | 1 | 5 |
| M2: Perl 5.34 | 19 | 19 | - | - | - | - |
| Pi5: Poplog | 2 | 12 | 3 | 1 | 4 | 4 |
| Pi5: Python 3.13 | 25 | 131 | 25 | 2 | 3 | 20 |
| Pi5: Perl 5.40 | 93 | 82 | - | - | - | - |
| i7: Poplog (x86-64) | 21 | 77 | 17 | 5 | 17 | 134 |
| i7: Python 3.10 | 13 | 39 | 9 | 1 | 1 | 7 |
| i7: Python 3.13 (uv/PGO build) | 5 | 38 | 8 | 1 | 1 | 5 |
| i7: Perl 5.34 | 19 | 16 | - | - | - | - |

Reading guide:

* **On arm64, Poplog leads Python 3-12x** on calls/loops/lists -- the
  value proposition is "interactive like Python, native-code fast".
  Pop's `compile500` builds *machine code* where Python's `compile()`
  builds bytecode, so its parity there is the stronger result.
* **On x86-64, Poplog loses to Python and Perl** -- consistent with the
  QEMU finding: the x86_64 backend is the outlier, not the machine.
* Python versions AND builds matter: 3.13's specializing interpreter
  more than halves call cost vs 3.10 on the same i7 (13 -> 5 with the
  uv-managed PGO/LTO build; the unoptimized Nix build measured 7).
  Compare within a machine, and note the interpreter build.
* Python wins `gc20`/`closures1M` in places: refcounting makes
  `gc.collect()` cheap on an acyclic heap, and the M2 Poplog closure
  cost is a known macOS issue (per-creation icache flush via
  `mach_vm_region` walk -- see the perf TODO), as the Pi5's 4 shows.

## Reproducing

    ./tools/bench-poplog.sh                  # any built Poplog tree
    python3 tools/bench-baseline.py          # or: uv run --python 3.13 tools/bench-baseline.py
    perl tools/bench-baseline.pl
    # qemu (binfmt-mediated): QEMU_LD_PREFIX=<sysroot> <foreign binary> < tools/bench-poplog.p

Pending datapoints: a real Pi 3 (or MTK Genio-class arm64) for the
low-power tier; the x86_64 backend investigation.
