#!/usr/bin/env bash
#
# fetch-imgui.sh -- vendor Dear ImGui source for the experimental macOS graphics
# backend (configure --experimental-gfx).
#
# NO git submodules: this pulls a *pinned* Dear ImGui release tarball into
# pop/extern/imgui/ (gitignored) so no third-party source is committed to the
# repo.  Re-run with --force (or a new --ref) to update.
#
#   ./tools/fetch-imgui.sh [--force] [--ref <tag>]
#
# Env overrides:
#   IMGUI_REF   release tag to fetch (default below); e.g. IMGUI_REF=v1.92.6
#   DEST        destination dir   (default pop/extern/imgui)
#
# We only COMPILE a small subset (see PORTING-ARM64-M-SILICON-OSX.md sec. 6.5):
#   core:     imgui.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp
#   backends: backends/imgui_impl_metal.mm  backends/imgui_impl_osx.mm
# i.e. native Metal + Cocoa -- no GLFW/SDL, and no cimgui (the pop_gfx_* surface
# is hand-wrapped in pop/extern/lib/imgui_backend.mm as extern "C").

set -euo pipefail

IMGUI_REF="${IMGUI_REF:-v1.92.2}"   # bump as desired; any v1.9x tag with the
                                    # Metal+OSX backends works
DEST="${DEST:-pop/extern/imgui}"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --force)      FORCE=1 ;;
        --ref)        shift; IMGUI_REF="${1:?--ref needs a tag}" ;;
        --ref=*)      IMGUI_REF="${1#--ref=}" ;;
        -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Run from the repo root regardless of where we were invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# Refuse to rm anything daft (DEST is normally a relative path under the repo).
case "$DEST" in
    ""|"/"|"/"*) echo "Refusing unsafe DEST='$DEST' (use a path under the repo)." >&2; exit 2 ;;
esac

STAMP="$DEST/.imgui-version"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$IMGUI_REF" ] && [ "$FORCE" -eq 0 ]; then
    echo "Dear ImGui $IMGUI_REF already vendored in $DEST (use --force to refetch)."
    exit 0
fi

URL="https://github.com/ocornut/imgui/archive/refs/tags/${IMGUI_REF}.tar.gz"
echo "Fetching Dear ImGui $IMGUI_REF"
echo "  from $URL"
echo "  into $DEST/"

rm -rf "$DEST"
mkdir -p "$DEST"

# Download + extract, stripping the leading imgui-<version>/ directory.
if ! curl -fsSL "$URL" | tar xz --strip-components=1 -C "$DEST"; then
    echo "ERROR: download/extract failed for $URL" >&2
    echo "       Verify the tag exists, or pass a valid one:" >&2
    echo "         ./tools/fetch-imgui.sh --ref vX.Y.Z" >&2
    echo "       Releases: https://github.com/ocornut/imgui/releases" >&2
    rm -rf "$DEST"
    exit 1
fi

# Sanity-check the files we actually compile are present.
missing=0
for f in imgui.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp \
         imgui.h imgui_internal.h \
         backends/imgui_impl_metal.mm backends/imgui_impl_osx.mm; do
    if [ ! -f "$DEST/$f" ]; then
        echo "ERROR: expected file missing after extract: $f" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "Vendored tree looks incomplete; aborting." >&2
    exit 1
fi

echo "$IMGUI_REF" > "$STAMP"

echo
echo "Done -- Dear ImGui $IMGUI_REF vendored in $DEST/ (gitignored)."
echo "Next:  ./configure --experimental-gfx && make"
