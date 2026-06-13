#!/bin/sh
# riscv-qemu.sh -- stage a RISC-V (rv64gc) Linux machine in QEMU for the Poplog
# RISC-V port (see PORTING-RISCV64-LINUX.md).  Console / no-GUI.
#
# The config approximates a Scaleway RISC-V instance: rv64gc, 4 cores, 8 GB,
# so what builds here should carry over to real hardware.  Override with env:
#   SMP=4  MEM=8G  CPU=rv64  IMG=...  (defaults below)
#
# Subcommands:
#   smoke   boot OpenSBI only (no distro) -- proves qemu+firmware work (~5s)
#   fetch   download an Ubuntu riscv64 preinstalled-server image
#   boot    boot the distro image (serial console; login ubuntu/ubuntu)
#
# QEMU comes from PATH if present, else from nixpkgs (`nix shell`).  This is the
# *staging* harness only; on a Linux host the lighter dev loop is qemu-user +
# binfmt + a riscv64-linux-gnu cross toolchain (no VM boot) -- see the doc.

set -eu

SMP="${SMP:-4}"
MEM="${MEM:-8G}"
CPU="${CPU:-rv64}"                 # qemu rv64 = RV64GC (G + C)
DIR="${DIR:-$HOME/.cache/poplog-riscv}"
IMG="${IMG:-$DIR/ubuntu-riscv64.img}"
# Adjust to the current Ubuntu riscv64 point release if this 404s:
IMG_URL="${IMG_URL:-https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.2-preinstalled-server-riscv64.img.xz}"

# Locate qemu-system-riscv64 / qemu-img: PATH, else run them from nixpkgs.
if command -v qemu-system-riscv64 >/dev/null 2>&1; then
    QEMU_RISCV="qemu-system-riscv64"
    QEMU_IMG="qemu-img"
else
    QEMU_RISCV="nix shell nixpkgs#qemu -c qemu-system-riscv64"
    QEMU_IMG="nix shell nixpkgs#qemu -c qemu-img"
fi

common_args() {
    echo "-machine virt -cpu $CPU -smp $SMP -m $MEM -nographic -bios default"
}

case "${1:-}" in
  smoke)
    # No kernel/disk: OpenSBI prints its banner then halts.  Proves the
    # qemu + firmware + machine wiring before any distro is downloaded.
    echo ">> OpenSBI smoke boot (Ctrl-A X to quit if it hangs)"
    exec $QEMU_RISCV $(common_args)
    ;;
  fetch)
    mkdir -p "$DIR"
    echo ">> fetching $IMG_URL"
    curl -L --fail -o "$IMG.xz" "$IMG_URL"
    echo ">> decompressing"
    xz -d -f "$IMG.xz"
    mv -f "$DIR"/ubuntu-*.img "$IMG" 2>/dev/null || true
    echo ">> resizing rootfs to 16G (optional headroom for a build)"
    $QEMU_IMG resize "$IMG" 16G 2>/dev/null || \
        echo "   (qemu-img unavailable; resize skipped)"
    echo ">> done: $IMG"
    ;;
  boot)
    [ -f "$IMG" ] || { echo "no image at $IMG -- run: $0 fetch"; exit 1; }
    echo ">> booting $IMG  ($CPU, ${SMP} cores, $MEM)  -- login ubuntu/ubuntu"
    echo ">> serial console; quit with Ctrl-A then X"
    exec $QEMU_RISCV $(common_args) \
        -drive file="$IMG",format=raw,if=virtio \
        -device virtio-net-device,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::10022-:22
    ;;
  *)
    echo "usage: $0 {smoke|fetch|boot}"
    echo "  SMP=$SMP MEM=$MEM CPU=$CPU  (override via env)"
    exit 2
    ;;
esac
