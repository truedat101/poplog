#!/usr/bin/env bash
#
# build-msilicon.sh -- assemble and link the macOS arm64 corepop.
#
#   ./tools/build-msilicon.sh [--sync pi-host] [--images] [--validate]
#
# The Mac side of the cross-bootstrap (PORTING-ARM64-M-SILICON-OSX.md §2):
# the Darwin-targeting popc/poplink on the build host (default: a Raspberry
# Pi 5 at dietpi@raspi5, ~/poplog-darwin) emit Mach-O assembler, captured by
# POP__as/POP__ar wrappers; this script assembles them with clang, builds
# the C runtime, links, and codesigns.  Once a Mac-native popc.psv exists
# (self-hosting) the sync step disappears.
#
#   --sync HOST   rsync fresh .s artifacts from HOST first
#   --images      rebuild the saved images (startup/clisp/prolog/pml)
#   --validate    run tools/validate-msilicon.sh afterwards
#
# Workdir: ~/poplog-mac-build (created if missing); the linked corepop is
# also installed into <repo>/target/pop/corepop (the configure seed slot).

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$HOME/poplog-mac-build"
SYNC=""; IMAGES=0; VALIDATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --sync) SYNC="$2"; shift ;;
        --images) IMAGES=1 ;;
        --validate) VALIDATE=1 ;;
        *) echo "unknown arg $1"; exit 2 ;;
    esac; shift
done

mkdir -p "$BUILD"/{libasm,libobj,asm,obj,psv}
cd "$BUILD"

if [ -n "$SYNC" ]; then
    echo "-- syncing artifacts from $SYNC --"
    rsync -a --delete "$SYNC:poplog-darwin/capture-lib/asm/" libasm/
    rsync -a "$SYNC:poplog-darwin/capture/asm/poplink_*.a" asm/
fi
[ -n "$(ls libasm 2>/dev/null)" ] || { echo "no library .s in $BUILD/libasm -- run with --sync HOST"; exit 2; }

echo "-- assembling $(ls libasm | wc -l | tr -d ' ') library modules + $(ls asm/poplink_*.a | wc -l | tr -d ' ') poplink units --"
rm -f libobj/*.o
ls libasm | sed 's/\.[^.]*$//' | sort -u | xargs -P 8 -I{} sh -c \
    'clang -c -arch arm64 -x assembler "$(ls libasm/{}.* | head -1)" -o libobj/{}.o'
for f in asm/poplink_*.a; do
    clang -c -arch arm64 -x assembler "$f" -o "${f%.a}.o"
done

echo "-- C runtime (libpop.a) --"
LIBPOP_SRC="c_bignum c_callback c_core c_sysinit ext_arm pop_encoding pop_poll pop_stat pop_timer pop_vararg_fix"
for f in $LIBPOP_SRC pop_seed_loader; do
    clang -c -arch arm64 -g -Wall -O "$ROOT/pop/extern/lib/$f.c" -o "obj/$f.o"
done
rm -f libpop.a
ar rc libpop.a $(for f in $LIBPOP_SRC; do echo "obj/$f.o"; done) && ranlib libpop.a

echo "-- archive + link --"
rm -f src.olb; ar rc src.olb libobj/*.o && ranlib src.olb
SDK=$(xcrun --show-sdk-path)
clang -arch arm64 -isysroot "$SDK" -o corepop \
    obj/pop_seed_loader.o \
    asm/poplink_1.o asm/poplink_2.o asm/poplink_3.o \
    src.olb \
    asm/poplink_4.o asm/poplink_dat.o \
    -L. -lpop -lm -lncurses
codesign -s - --entitlements "$ROOT/tools/corepop-jit.entitlements" -f corepop

# env wrapper (idempotent)
if [ ! -x poplog ]; then
    cat > poplog <<WRAP
#!/bin/sh
usepop=$ROOT
popsrc=\$usepop/pop/src; popsys=$BUILD; popexternlib=\$popsys; popobjlib=\$popsys
export usepop popsrc popsys popexternlib popobjlib
popautolib=\$usepop/pop/lib/auto; popdatalib=\$usepop/pop/lib/data
popliblib=\$usepop/pop/lib/lib; popvedlib=\$usepop/pop/lib/ved
poppackages=\$usepop/pop/packages
export popautolib popdatalib popliblib popvedlib poppackages
poplocal=\$usepop/..; poplocalauto=\$poplocal/local/auto
poplocalbin=\$usepop/poplocalbin; popcontrib=\$usepop/pop/packages/contrib
export poplocal poplocalauto poplocalbin popcontrib
poplib=\${poplib=\$HOME}; popsavelib=\$popsys/psv
popcomppath=':\$poplib:\$poplocalauto:\$popautolib:\$popliblib'
popsavepath=':\$poplib:\$poplocalbin:\$popsavelib'
export poplib popsavelib popsavepath popcomppath
exec "\$@"
WRAP
    chmod +x poplog
fi

echo "-- smoke test --"
R=$(echo '6 * 7 =>' | ./poplog ./corepop | head -1)
echo "   $R"
case "$R" in *42*) ;; *) echo "SMOKE TEST FAILED"; exit 1;; esac

mkdir -p "$ROOT/target/pop" && cp corepop "$ROOT/target/pop/corepop"
echo "   corepop -> $ROOT/target/pop/corepop (configure seed slot)"

if [ "$IMAGES" = 1 ]; then
    echo "-- images --"
    rm -f psv/*.psv
    "$ROOT/tools/validate-msilicon.sh" "$BUILD" --rebuild >/dev/null 2>&1 || true
    ls -la psv/ | grep -v '^total\|^d'
fi
[ "$VALIDATE" = 1 ] && exec "$ROOT/tools/validate-msilicon.sh" "$BUILD"
echo "done."
