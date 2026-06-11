# Benchmark results (2026-06, corrected)

Micro-benchmarks of runtime-core mechanics -- procedure calls,
allocation/GC, incremental compilation, closures, strings.  They
characterise the *engine*, not applications.  Workloads are identical
across languages (`tools/bench-poplog.p`, `tools/bench-baseline.py`,
`tools/bench-baseline.pl`); times in centiseconds, lower is better.

> **Correction & methodology note.**  An earlier revision of this file
> reported the x86-64 Poplog as 5-10x slower than the arm64 backend.
> That measurement was an artifact: the benched `basepop11` was an
> *aarch64* binary left in the tree by earlier cross-compilation work,
> and Linux `binfmt_misc` silently ran it under `qemu-aarch64` -- which
> is also why it "matched" an explicit QEMU run exactly (it was the
> same configuration twice).  The bench script now prints `file` of
> the engine; always check it.  The genuine x86-64 numbers below are
> from the Nix-built tree (verified `ELF 64-bit ... x86-64`).

## Poplog across machines and backends

| configuration | nfib29 | intloop10M | lists | compile500 | gc20 | closures1M | strings |
|---|---|---|---|---|---|---|---|
| i7-9700K, x86-64 Linux (Nix build) | 1 | 7 | 1 | 1 | 1 | 3 | 0 |
| Apple M2, arm64 macOS (this port) | 2 | 5 | 1 | 2 | 3 | 3 | 1 |
| Raspberry Pi 5, arm64 Linux | 2 | 12 | 3 | 1 | 4 | 4 | 0 |
| i7, arm64 Poplog under qemu-aarch64 | 21 | 79 | 17 | 4 | 16 | 131 | 1 |
| i7, arm32 corepop under qemu-arm (rpi3-class armhf, upstream `corepop.arm`) | 20 | 323* | 13 | 7 | 11 | 106 | 1 |

\* 32-bit popints are ~29 bits: the 10M sum overflows into bignums, so
this row partly measures bignum arithmetic -- a real cost of 32-bit
Poplog, not an emulation artifact.

All three native builds are within ~2x of each other -- both backends
generate excellent code, and QEMU's translation tax (~10-30x here) is
visible only in the explicitly emulated rows.

## Cross-language baselines (same workloads)

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

Reading guide:

* **Poplog leads the best Python build 5x on calls and 5-10x on
  loops/lists on every platform** -- the value proposition is
  "interactive like Python, native-code fast".  Pop's `compile500`
  builds *machine code* where Python's `compile()` builds bytecode,
  so parity there is the stronger result.
* Python versions AND builds matter: on the same i7, calls cost
  13 (3.10 system) vs 5 (3.13 uv PGO).  Compare within a machine and
  name the interpreter build.
* `gc20` is the one row Python sometimes ties: refcounting makes
  `gc.collect()` cheap on an acyclic heap.

## Reproducing

    ./tools/bench-poplog.sh                  # prints engine arch -- CHECK IT
    python3 tools/bench-baseline.py          # or: uv run --python 3.13 ...
    perl tools/bench-baseline.pl
    # qemu (binfmt-mediated): QEMU_LD_PREFIX=<sysroot> <foreign binary> < tools/bench-poplog.p

Pending datapoints: a real Pi 3 (or MTK Genio-class arm64) for the
low-power tier.
