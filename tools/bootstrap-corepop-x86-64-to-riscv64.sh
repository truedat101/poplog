#!/bin/sh
#
# bootstrap-corepop-x86-64-to-riscv64.sh
#
# Cross-build a RISC-V (rv64gc / LP64D / Linux ELF) Poplog `corepop` on an
# x86-64 host, mirroring tools/bootstrap-corepop-x86-64-to-aarch64.sh.  `corepop`
# is gitignored and never shipped; the first riscv64 one cannot be minted on the
# target itself (its popc/poplink are still x86-64), so it is cross-built here.
#
# Produces:
#   target/pop/new_corepop        -- the freshly linked core
#   target/pop/corepop.riscv64    -- a copy to keep / publish
#
# Then VERIFIES it is a RISC-V ELF, and (if qemu-riscv64[-static] is present)
# smoke-runs it under emulation.
#
# NB on the assembler: popc execs $POP__as as a literal command, so the
# -march=rv64gc flag MUST go in a wrapper script, not in POP__as directly.  The
# emitted .s also carry `.option arch, rv64gc`, but the wrapper is belt-and-braces.
#
set -eu

cd "$(dirname "$0")/.." || exit 2
[ -f Makefile ] || { echo "ERROR: no Makefile here -- run inside the Poplog repo." >&2; exit 2; }

CROSS="${CROSS:-riscv64-linux-gnu-}"

# Wrapper that injects -march=rv64gc and produces the real .o.
ASWRAP="$(mktemp /tmp/rv-as.XXXXXX.sh)"
cat > "$ASWRAP" <<EOF
#!/bin/sh
exec ${CROSS}as -march=rv64gc "\$@"
EOF
chmod +x "$ASWRAP"
export POP__as="$ASWRAP"

# A stale src.olb/src.wlb from a different arch must NOT be reused -- the linker
# rejects "file in wrong format" (e.g. EM: 183 = AArch64).  Force a clean object
# library for this arch.
rm -f target/obj/src.olb target/obj/src.wlb target/obj/termcap.* stamp_srclib

make POP_arch=riscv64 stamp_popc
make POP_arch=riscv64 stamp_srclib
make POP_arch=riscv64 \
     CC="${CROSS}gcc -no-pie -Wl,-export-dynamic -Wl,--no-as-needed" \
     stamp_new_corepop

cp target/pop/new_corepop target/pop/corepop.riscv64
rm -f "$ASWRAP"

echo "--- arch of target/pop/new_corepop ---"
readelf -h target/pop/new_corepop | grep -E 'Class:|Machine:' || true
if readelf -h target/pop/new_corepop 2>/dev/null | grep -q 'Machine: *RISC-V'; then
    echo "OK: target/pop/corepop.riscv64 is RISC-V."
else
    echo "ERROR: new_corepop is NOT RISC-V -- check the cross toolchain (CROSS=${CROSS})." >&2
    exit 1
fi

# Smoke-run under qemu-user if available (transparent binfmt or explicit).
QEMU="$(command -v qemu-riscv64 2>/dev/null || command -v qemu-riscv64-static 2>/dev/null || true)"
if [ -n "$QEMU" ]; then
    echo "--- smoke run under $QEMU ---"
    echo '1+1=>' | "$QEMU" -L /usr/riscv64-linux-gnu target/pop/new_corepop || \
        echo "(corepop crashed under qemu -- bring-up debugging needed; see" \
             "PORTING-RISCV64-LINUX.md and the project memory for the current" \
             "first-bug breadcrumb.)"
fi
