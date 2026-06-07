#!/usr/bin/env bash
#
# ci-watch.sh -- tiny local CI daemon for the Poplog AArch64 cross-build.
#
# Watches pop/src for *.p / *.ph / *.s changes and, when the tree goes quiet,
# rebuilds basepop11 with the required cross-compile flags.  If a changed file
# is under syscomp/ (the popc code generator) it also drops stamp_popc so the
# new codegen actually takes effect -- a stale popc.psv silently masks codegen
# bugs, so this is important.  On a good build it can rsync to the Pi and run a
# one-line smoke test.
#
# No external deps (poll-based; inotifywait not required).
#
# Usage:
#   tools/ci-watch.sh            # watch + rebuild loop (Ctrl-C to stop)
#   tools/ci-watch.sh --once     # one rebuild (+ smoke test) and exit
#
# Env knobs:
#   POLL=2        seconds between polls
#   RASPI=raspi5  ssh host for the smoke test
#   PI_SYNC=1     rsync + smoke-test on the Pi after a good build (0 to skip)
#   SMOKE='2+2=>' program piped to the Pi smoke test (expects "** 4")
#   POP__as       cross assembler (default /usr/bin/aarch64-linux-gnu-as)
#
set -uo pipefail

ROOT="${POP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || { echo "cannot cd to $ROOT"; exit 1; }

export POP__as="${POP__as:-/usr/bin/aarch64-linux-gnu-as}"
CC_OVERRIDE='aarch64-linux-gnu-gcc -no-pie -Wl,-export-dynamic -Wl,--no-as-needed'
TARGET="$ROOT/target/pop/basepop11"
POLL="${POLL:-2}"
RASPI="${RASPI:-raspi5}"
PI_SYNC="${PI_SYNC:-1}"
SMOKE="${SMOKE:-2+2=>}"
BUILD_LOG="$ROOT/tools/ci-watch.build.log"

ts()  { date '+%H:%M:%S'; }
say() { printf '\033[1;36m[ci %s]\033[0m %s\n' "$(ts)" "$*"; }
ok()  { printf '\033[1;32m[ci %s] %s\033[0m\n' "$(ts)" "$*"; }
err() { printf '\033[1;31m[ci %s] %s\033[0m\n' "$(ts)" "$*"; }

# mtime+path snapshot of the watched sources.
snapshot() {
    find pop/src -type f \( -name '*.p' -o -name '*.ph' -o -name '*.s' \) \
        -printf '%T@\t%p\n' 2>/dev/null | sort
}

# Rebuild.  $1 = "codegen" if a syscomp/ file changed (also drops stamp_popc).
rebuild() {
    local codegen="${1:-}"
    local stamps=(stamp_srclib stamp_vedlib)
    if [ "$codegen" = codegen ]; then
        stamps=(stamp_popc "${stamps[@]}")
        say "codegen change -> full rebuild (rm ${stamps[*]})"
    else
        say "runtime change -> rebuild (rm ${stamps[*]})"
    fi
    rm -f "${stamps[@]}"

    local start; start=$(date +%s)
    if make CC="$CC_OVERRIDE" "$TARGET" >"$BUILD_LOG" 2>&1; then
        local secs=$(( $(date +%s) - start ))
        ok "build OK (${secs}s) -> $(ls -la "$TARGET" | awk '{print $5" bytes"}')"
        # surface any stale-.olb duplication (the known linker gotcha)
        local dup
        dup=$(ar t target/obj/src.olb 2>/dev/null | sort | uniq -d | head -1)
        [ -n "$dup" ] && err "WARNING: duplicate .olb members (stale objects), e.g. $dup"
        [ "$PI_SYNC" = 1 ] && pi_smoke
        return 0
    else
        err "BUILD FAILED -- last errors:"
        grep -inE 'error|mishap|undefined ref|relocation|cannot' "$BUILD_LOG" | tail -8
        echo "    (full log: $BUILD_LOG)"
        return 1
    fi
}

pi_smoke() {
    say "sync -> $RASPI + smoke test"
    if ! rsync -az --delete --exclude='.git' --exclude='corepop.amd64' \
            --exclude='.claude' --exclude='target/psv' ./ "$RASPI:~/poplog/" >/dev/null 2>&1; then
        err "rsync to $RASPI failed (skipping smoke test)"
        return 1
    fi
    local out
    out=$(printf '%s\n' "$SMOKE" | timeout 40 ssh -o BatchMode=yes "$RASPI" \
            'cd ~/poplog && target/pop/basepop11 %nort %noinit' 2>&1)
    if printf '%s' "$out" | grep -q '\*\* 4'; then
        ok "smoke test PASS ($SMOKE -> $(printf '%s' "$out" | grep '\*\*' | tr -d '\n'))"
    else
        err "smoke test FAIL -- output:"
        printf '%s\n' "$out" | tail -6
    fi
}

# Wait until the source tree is unchanged for one full poll, then echo
# "codegen" if any differing file is under syscomp/, else "runtime".
wait_for_quiet_change() {
    local prev cur changed
    prev="$1"
    while :; do
        sleep "$POLL"
        cur=$(snapshot)
        if [ "$cur" != "$prev" ]; then
            changed=$(comm -13 <(printf '%s' "$prev") <(printf '%s' "$cur") | cut -f2-)
            # settle: keep polling until two consecutive snapshots match
            local settle="$cur"
            while sleep "$POLL"; do
                cur=$(snapshot)
                [ "$cur" = "$settle" ] && break
                changed=$(printf '%s\n%s\n' "$changed" \
                    "$(comm -13 <(printf '%s' "$settle") <(printf '%s' "$cur") | cut -f2-)")
                settle="$cur"
            done
            SNAP="$cur"
            if printf '%s\n' "$changed" | grep -q 'syscomp/'; then echo codegen; else echo runtime; fi
            return 0
        fi
    done
}

if [ "${1:-}" = --once ]; then
    rebuild codegen   # --once does a clean full build
    exit $?
fi

say "watching pop/src (*.p *.ph *.s), poll ${POLL}s, target=$TARGET"
say "Pi smoke test: $([ "$PI_SYNC" = 1 ] && echo "on ($RASPI)" || echo off).  Ctrl-C to stop."
trap 'echo; say "stopped."; exit 0' INT
SNAP=$(snapshot)
while :; do
    kind=$(wait_for_quiet_change "$SNAP")
    rebuild "$kind" || true
done
