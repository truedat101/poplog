#!/bin/sh
#
# bootstrap-corepop-x86-64-to-aarch64.sh
#
# Cross-build an AArch64 Poplog `corepop` (the minimal bootstrap core that
# `popc`/`poplink`/`poplibr` symlink to) on an x86-64 host.  `corepop` is
# gitignored and never shipped, and you cannot mint the first arm64 one on the
# target itself (its popc/poplink are still x86-64) -- so it is cross-built here,
# the same way `basepop11` is.  Run it from anywhere; it operates on the repo it
# lives in.
#
# Produces:
#   target/pop/new_corepop      -- the freshly linked core
#   target/pop/corepop.arm64    -- a copy to keep / publish
#
# It then VERIFIES that new_corepop really is an AArch64 ELF, so a wrong-toolchain
# build fails loudly instead of yielding an x86-64 binary you mistake for arm64.
#
# DEPLOYMENT IS DELIBERATELY LEFT TO YOU -- the right destination differs per
# machine / CI / target, so this script does not copy anything off-box.  To make
# a target self-hosting, install the verified core there as its `corepop`, e.g.:
#   scp target/pop/corepop.arm64  USER@HOST:/path/to/poplog/target/pop/corepop
# Then on the target, confirm it and run the validation ladder:
#   readelf -h target/pop/corepop | grep Machine     # -> AArch64
#   tools/validate-raspi5.sh
# See PORTING-ARM64-LINUX-RPI5.md, section "Bootstrapping the arm64 corepop".
#
set -eu

# Operate on the repo this script lives in, regardless of the current directory.
cd "$(dirname "$0")/.." || exit 2
[ -f Makefile ] || { echo "ERROR: no Makefile here -- run inside the Poplog repo." >&2; exit 2; }

# Cross toolchain.  Override CROSS for non-Debian layouts, e.g.
#   CROSS=aarch64-unknown-linux-gnu- ./tools/bootstrap-corepop-x86-64-to-aarch64.sh
CROSS="${CROSS:-aarch64-linux-gnu-}"
export POP__as="${POP__as:-$(command -v "${CROSS}as" 2>/dev/null || echo "${CROSS}as")}"

make CC="${CROSS}gcc -no-pie -Wl,-export-dynamic -Wl,--no-as-needed" stamp_new_corepop
cp target/pop/new_corepop target/pop/corepop.arm64

# --- Validate the architecture; never trust the build silently. ---
echo "--- arch of target/pop/new_corepop ---"
readelf -h target/pop/new_corepop | grep -E 'Class:|Machine:' || true
if readelf -h target/pop/new_corepop 2>/dev/null | grep -q 'Machine: *AArch64'; then
    echo "OK: target/pop/corepop.arm64 is AArch64."
    echo "    Install it on the target as target/pop/corepop to make it self-hosting"
    echo "    (deployment is yours to do); see PORTING-ARM64-LINUX-RPI5.md."
else
    echo "ERROR: new_corepop is NOT AArch64 -- check the cross toolchain (CROSS=${CROSS})." >&2
    exit 1
fi
