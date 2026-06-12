#!/bin/sh
# tools/bench-poplog.sh -- quick Poplog-only benchmark: run the engine and
# print per-iteration statistics (median / 95% CI / CoV) for one engine.
# For the full cross-language run with system-under-test capture, use
# tools/bench.sh.
#   ./tools/bench-poplog.sh [engine]      (default: target/pop/basepop11)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${1:-$ROOT/target/pop/basepop11}"
echo "== Poplog benchmark =="
echo "host:   $(hostname) / $(uname -ms)"
if [ -r /proc/cpuinfo ]; then
    grep -m1 -E 'model name|Model' /proc/cpuinfo | sed 's/^/cpu:    /'
else
    sysctl -n machdep.cpu.brand_string 2>/dev/null | sed 's/^/cpu:    /'
fi
echo "engine: $ENGINE"
# binfmt_misc silently runs foreign-arch binaries under qemu -- a wrong-arch
# engine produces plausible-looking but meaningless numbers.  Always verify.
echo "binary: $(file -b "$ENGINE" 2>/dev/null | cut -d, -f1-2)"
"$ROOT/poplog" "$ENGINE" < "$ROOT/tools/bench-poplog.p" 2>/dev/null \
    | "${PYTHON:-python3}" "$ROOT/tools/bench-aggregate.py"
