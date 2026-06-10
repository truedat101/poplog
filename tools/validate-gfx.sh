#!/usr/bin/env bash
#
# validate-gfx.sh -- regression for the native graphics stack (macOS).
#
# Runs the TEACH RC_GRAPHIC walkthrough (every example from the teach
# file + turtle-state invariants + the rc_mouse canvas machinery)
# against a gfx-enabled basepop11.  Needs a GUI session: windows open
# briefly on screen.
#
#   ./tools/validate-gfx.sh [build-repo-root]

set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
POP="$ROOT/target/pop/basepop11"

[ -x "$POP" ] || { echo "FATAL: $POP missing (make all first)"; exit 2; }
if ! nm "$POP" 2>/dev/null | grep -q pop_gfx_init; then
    echo "SKIP: basepop11 built without graphics (configure --experimental-gfx)"
    exit 0
fi

OUT=$(perl -e 'alarm 180; exec @ARGV' "$ROOT/poplog" "$POP" \
        < "$ROOT/tools/teach-rc-graphic-walkthrough.p" 2>&1)
if grep -qa 'teach-walkthrough-PASSED' <<<"$OUT"; then
    echo "GFX VALIDATED: TEACH RC_GRAPHIC walkthrough passed."
    exit 0
else
    echo "GFX VALIDATION FAILED:"
    grep -aE 'MISHAP|Error|DECLARING' <<<"$OUT" | head -10
    exit 1
fi
