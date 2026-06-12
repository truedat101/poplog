#!/usr/bin/env python3
"""tools/bench-aggregate.py -- statistics for the Poplog benchmark harness.

Reads one or more sample files produced by tools/bench-poplog.p /
bench-baseline.py / bench-baseline.pl (lines of `SAMPLE <workload>
<batch-microseconds> <iterations-K>`, plus META), and reports, per engine and
per workload, the per-iteration time with proper dispersion:

    n, min, median, mean, stdev, CoV%, and a bootstrap 95% CI on the median.

With >=2 engines it also prints a comparison table: each engine's median
relative to a reference (default: the one whose name contains "poplog"),
as a ratio with a bootstrap 95% CI -- if the CI excludes 1.0 the difference
is significant at ~5%.

Pure standard library (median/mean/stdev + a hand-rolled bootstrap), so it
runs anywhere Python does -- including a Raspberry Pi without numpy/scipy.

Usage:
    python3 tools/bench-aggregate.py [--ref poplog] [--boot 10000] FILE...
    ... | python3 tools/bench-aggregate.py            # single engine on stdin
"""
import argparse
import random
import statistics as st
import sys

WORKLOAD_ORDER = ["nfib29", "intloop10M", "lists", "compile500",
                  "gc20", "closures1M", "strings"]


def parse(stream, label_hint):
    """Return (label, {workload: [per_iter_seconds, ...]}, meta)."""
    data, meta, label = {}, {}, label_hint
    for line in stream:
        parts = line.rstrip("\n").split("\t")
        if parts[0] == "META":
            meta = dict(kv.split("=", 1) for kv in parts[1:] if "=" in kv)
            label = f"{meta.get('engine', label_hint)}" \
                    + (f" {meta['version']}" if "version" in meta else "")
        elif parts[0] == "SAMPLE" and len(parts) >= 4:
            workload, batch_us, k = parts[1], float(parts[2]), int(parts[3])
            if k > 0:
                data.setdefault(workload, []).append(batch_us / 1e6 / k)
    return label, data, meta


def fmt_t(seconds):
    """Human time with 3 significant figures."""
    if seconds < 1e-6:   return f"{seconds*1e9:.3g} ns"
    if seconds < 1e-3:   return f"{seconds*1e6:.3g} us"
    if seconds < 1.0:    return f"{seconds*1e3:.3g} ms"
    return f"{seconds:.3g} s"


def bootstrap_median_ci(xs, n_boot, alpha=0.05):
    if len(xs) < 2:
        return (xs[0], xs[0]) if xs else (0.0, 0.0)
    meds = []
    for _ in range(n_boot):
        sample = [xs[random.randrange(len(xs))] for _ in xs]
        meds.append(st.median(sample))
    meds.sort()
    lo = meds[int((alpha / 2) * n_boot)]
    hi = meds[int((1 - alpha / 2) * n_boot)]
    return lo, hi


def bootstrap_ratio_ci(num, den, n_boot, alpha=0.05):
    """Bootstrap 95% CI for median(num)/median(den)."""
    ratios = []
    for _ in range(n_boot):
        a = st.median([num[random.randrange(len(num))] for _ in num])
        b = st.median([den[random.randrange(len(den))] for _ in den])
        if b > 0:
            ratios.append(a / b)
    ratios.sort()
    if not ratios:
        return (float("nan"), float("nan"))
    return (ratios[int((alpha / 2) * len(ratios))],
            ratios[int((1 - alpha / 2) * len(ratios))])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", help="sample files (default: stdin)")
    ap.add_argument("--ref", default="poplog",
                    help="reference engine substring for ratios (default: poplog)")
    ap.add_argument("--boot", type=int, default=10000, help="bootstrap resamples")
    ap.add_argument("--seed", type=int, default=12345)
    args = ap.parse_args()
    random.seed(args.seed)

    engines = []  # list of (label, data, meta)
    if args.files:
        for path in args.files:
            with open(path) as fh:
                engines.append(parse(fh, path))
    else:
        engines.append(parse(sys.stdin, "stdin"))

    # de-duplicate workload set, preserving canonical order then any extras
    seen = set(w for _, d, _ in engines for w in d)
    workloads = [w for w in WORKLOAD_ORDER if w in seen] + \
                [w for w in seen if w not in WORKLOAD_ORDER]

    # ---- per-engine statistics ----
    for label, data, meta in engines:
        runs = meta.get("runs", "?")
        timer = meta.get("timer", "?")
        print(f"\n== {label}  (runs={runs}, timer={timer}) ==")
        print(f"{'workload':<12} {'n':>3} {'min':>10} {'median':>10} "
              f"{'mean':>10} {'CoV%':>6}  95% CI (median)")
        for w in workloads:
            xs = data.get(w)
            if not xs:
                continue
            med = st.median(xs)
            mean = st.fmean(xs)
            cov = (st.pstdev(xs) / mean * 100) if mean else 0.0
            lo, hi = bootstrap_median_ci(xs, args.boot)
            print(f"{w:<12} {len(xs):>3} {fmt_t(min(xs)):>10} "
                  f"{fmt_t(med):>10} {fmt_t(mean):>10} {cov:>5.1f}%  "
                  f"[{fmt_t(lo)}, {fmt_t(hi)}]")

    # ---- cross-engine comparison ----
    if len(engines) < 2:
        return
    ref = next((e for e in engines if args.ref in e[0].lower()), engines[0])
    ref_label, ref_data, _ = ref
    others = [e for e in engines if e is not ref]

    print(f"\n== Comparison: median per-iteration, ratio vs '{ref_label}' "
          f"(>1 = slower than ref; CI excluding 1.0 = significant) ==")
    header = f"{'workload':<12} {ref_label:>14}"
    for label, _, _ in others:
        header += f" | {label:>26}"
    print(header)
    for w in workloads:
        rxs = ref_data.get(w)
        if not rxs:
            continue
        row = f"{w:<12} {fmt_t(st.median(rxs)):>14}"
        for label, data, _ in others:
            xs = data.get(w)
            if not xs:
                row += f" | {'-':>26}"
                continue
            ratio = st.median(xs) / st.median(rxs)
            lo, hi = bootstrap_ratio_ci(xs, rxs, args.boot)
            cell = f"{fmt_t(st.median(xs))} {ratio:.2f}x[{lo:.2f},{hi:.2f}]"
            row += f" | {cell:>26}"
        print(row)


if __name__ == "__main__":
    main()
