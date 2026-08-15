#!/bin/sh
# test-libs.sh — run the Pop-11 library test suites in tools/tests/.
#
#   tools/test-libs.sh [engine-command] [suite ...]
#
# Each suite is a tools/tests/test_<name>.p file using LIB * POPTEST;
# a suite passes when it prints 'SUMMARY: ALL PASS'.  With no suite
# arguments, all suites run.  Exit status is the number of failing
# suites (0 = all green).
set -e

repo="$(cd "$(dirname "$0")/.." && pwd)"

engine=""
if [ $# -gt 0 ]; then
    case "$1" in
        *test_*.p|*/tests/*) : ;;   # first arg is a suite, not an engine
        *) engine="$1"; shift ;;
    esac
fi
if [ -z "$engine" ]; then
    [ -x "$repo/target/pop/basepop11" ] || {
        echo "test-libs: no target/pop/basepop11 (build first, or pass an engine)" >&2; exit 2; }
    engine="$repo/poplog $repo/target/pop/basepop11"
fi
# riscv64 Poplog must run with ASLR off (see PORTING-RISCV64-LINUX.md)
case "$(uname -m)" in
    riscv64) engine="setarch -R $engine" ;;
esac

if [ $# -gt 0 ]; then
    suites="$*"
else
    suites=$(ls "$repo"/tools/tests/test_*.p)
fi

bad=0
for s in $suites; do
    name=$(basename "$s" .p)
    # shellcheck disable=SC2086  # $engine may be "wrapper binary"
    out=$($engine "$s" 2>&1) || true
    line=$(printf '%s\n' "$out" | grep -o 'SUMMARY: .*' | tail -1)
    if printf '%s' "$line" | grep -q 'ALL PASS'; then
        echo "PASS  $name  ($line)"
    else
        echo "FAIL  $name"
        printf '%s\n' "$out" | grep -E '^\*\*|MISHAP|;;;' | tail -25
        bad=$((bad+1))
    fi
done
[ $bad -eq 0 ] && echo "test-libs: all suites green" || echo "test-libs: $bad suite(s) failing"
exit $bad
