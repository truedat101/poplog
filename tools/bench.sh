#!/usr/bin/env bash
#
# tools/bench.sh -- full, rigorous benchmark run for one machine.
#
#   1. captures the system-under-test (CPU, RAM, cache, governor, load),
#   2. runs the Poplog engine + (if present) python3 and perl baselines,
#      each emitting per-iteration samples,
#   3. aggregates them into median / 95% CI / CoV statistics + a cross-engine
#      comparison (tools/bench-aggregate.py).
#
# All engines measure CPU time with auto-calibrated batches; see the headers
# of tools/bench-poplog.p and BENCHMARKS.md.  Close other apps first -- the
# script warns if the machine looks busy.
#
#   ./tools/bench.sh [engine]              (default engine: target/pop/basepop11)
# Tunables: BENCH_RUNS BENCH_WARMUP BENCH_MINTIME (s)  PYTHON=python3.13 ...
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${1:-$ROOT/target/pop/basepop11}"
PYTHON="${PYTHON:-python3}"
OUT="$(mktemp -d /tmp/poplog-bench.XXXXXX)"
RUNS="${BENCH_RUNS:-30}"; WARMUP="${BENCH_WARMUP:-3}"; MINTIME="${BENCH_MINTIME:-2.0}"
export BENCH_RUNS BENCH_WARMUP BENCH_MINTIME

line() { printf '%s\n' "------------------------------------------------------------"; }

# ---------------------------------------------------------------- SUT capture
echo "== System under test =="
echo "host:      $(hostname) / $(uname -mrs)"
if [ -r /proc/cpuinfo ]; then                                   # Linux
    echo "cpu:       $(grep -m1 -E 'model name|Model' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
    echo "cores:     $(nproc) logical"
    echo "ram:       $(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
    if command -v lscpu >/dev/null; then
        lscpu | awk -F: '/cache:/{gsub(/^ +/,"",$2); printf "cache:     %s = %s\n",$1,$2}'
    fi
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    echo "governor:  ${gov:-unknown}${gov:+ $([ "$gov" = performance ] || echo '(consider: performance)')}"
    # DRAM type needs root (dmidecode); attempt, skip silently if denied
    dram=$(sudo -n dmidecode -t memory 2>/dev/null | awk -F: '/Type:/{gsub(/^ +/,"",$2); if($2!="Unknown"){print $2; exit}}')
    [ -n "${dram:-}" ] && echo "dram:      $dram"
else                                                            # macOS
    echo "cpu:       $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    echo "cores:     $(sysctl -n hw.ncpu) logical ($(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)P+$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null)E)"
    echo "ram:       $(echo "$(sysctl -n hw.memsize)/1073741824" | bc) GiB"
    echo "cache:     L1d=$(sysctl -n hw.l1dcachesize 2>/dev/null) L2=$(sysctl -n hw.l2cachesize 2>/dev/null) L3=$(sysctl -n hw.l3cachesize 2>/dev/null) bytes"
    echo "governor:  n/a (macOS)"
fi
echo "engine:    $ENGINE"
echo "binary:    $(file -b "$ENGINE" 2>/dev/null | cut -d, -f1-2)"   # arch check (binfmt guard)
echo "protocol:  runs=$RUNS warmup=$WARMUP mintime=${MINTIME}s, CPU-time, auto-calibrated"
# hygiene warning (uptime uses ", " on Linux, " " on macOS -- take the 1-min field either way)
load=$(uptime | sed 's/.*load average[s]*: *//' | tr ',' ' ' | awk '{print $1}')
echo "loadavg:   $load $(awk -v l="$load" 'BEGIN{print (l+0>0.5)?"(busy -- close other apps for a clean run)":"(idle, good)"}')"
line

# ---------------------------------------------------------------- run engines
# POPLOG_CMD overrides how the engine is invoked (e.g. a nix-built front-end:
#   POPLOG_CMD=/nix/store/...-poplog/bin/pop11 ./tools/bench.sh <that-basepop11>
# The engine path argument is still used for the arch check above.
echo "Running Poplog ..."
if [ -n "${POPLOG_CMD:-}" ]; then
    sh -c "$POPLOG_CMD" < "$ROOT/tools/bench-poplog.p" > "$OUT/1-poplog.samples" 2>/dev/null
else
    "$ROOT/poplog" "$ENGINE" < "$ROOT/tools/bench-poplog.p" > "$OUT/1-poplog.samples" 2>/dev/null
fi

if command -v "$PYTHON" >/dev/null; then
    echo "Running $($PYTHON --version 2>&1) ..."
    "$PYTHON" "$ROOT/tools/bench-baseline.py" > "$OUT/2-python.samples" 2>/dev/null
fi
if command -v perl >/dev/null; then
    echo "Running Perl $(perl -e 'print $]') ..."
    perl "$ROOT/tools/bench-baseline.pl" > "$OUT/3-perl.samples" 2>/dev/null
fi
line

# ---------------------------------------------------------------- aggregate
"$PYTHON" "$ROOT/tools/bench-aggregate.py" "$OUT"/*.samples
echo
echo "raw samples kept in: $OUT"
