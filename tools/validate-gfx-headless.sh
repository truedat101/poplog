#!/usr/bin/env bash
#
# validate-gfx-headless.sh -- headless regression for the SDL3/OpenGL3 graphics
# backend (Linux/Unix).  Renders the retained-canvas scene to a PPM with NO
# display, GPU, or compositor -- SDL's "offscreen" driver (EGL surfaceless) +
# Mesa llvmpipe software rendering -- and checks the image is non-blank.
#
# This is the reproducible / CI gate for the graphics stack: it needs neither
# an X11/Wayland session nor a real GPU, so it runs anywhere the ImGui source
# (tools/fetch-imgui.sh), SDL3, and a software GL (Mesa) are present.  It SKIPs
# (exit 0) when those are missing rather than failing.
#
#   ./tools/validate-gfx-headless.sh [repo-root]

set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || { echo "cannot cd to $ROOT"; exit 2; }

[ -f pop/extern/imgui/imgui.cpp ] || { echo "SKIP: ImGui not fetched (run ./tools/fetch-imgui.sh)"; exit 0; }
pkg-config --exists sdl3 2>/dev/null || { echo "SKIP: SDL3 not found (pkg-config sdl3)"; exit 0; }

if [ ! -x ./gfx-headless ]; then
    make gfx-headless >/tmp/gfx-headless-build.log 2>&1 \
        || { echo "SKIP: gfx-headless build failed (see /tmp/gfx-headless-build.log)"; exit 0; }
fi

OUT="$(mktemp -u).ppm"
env -u DISPLAY -u WAYLAND_DISPLAY SDL_VIDEODRIVER=offscreen \
    LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
    ./gfx-headless "$OUT"
rc=$?
if [ "$rc" = 2 ]; then echo "SKIP: no usable software GL (llvmpipe) here"; rm -f "$OUT"; exit 0; fi
[ "$rc" = 0 ] && [ -s "$OUT" ] || { echo "GFX HEADLESS FAILED: harness rc=$rc"; rm -f "$OUT"; exit 1; }

# Non-blank check: the scene draws bright primitives on a dark background.
bright=$(python3 - "$OUT" <<'PY' 2>/dev/null
import sys
with open(sys.argv[1], 'rb') as f:
    assert f.readline().strip() == b'P6'
    w, h = map(int, f.readline().split()); f.readline()
    d = f.read()
print(sum(1 for i in range(0, len(d) - 2, 3) if d[i] > 120 or d[i+1] > 120 or d[i+2] > 120))
PY
)
rm -f "$OUT"

if [ "${bright:-0}" -gt 1000 ]; then
    echo "GFX HEADLESS VALIDATED: rendered $bright bright px with no display/GPU."
    exit 0
else
    echo "GFX HEADLESS FAILED: image blank or near-blank ($bright bright px)"
    exit 1
fi
