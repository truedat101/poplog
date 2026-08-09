#!/bin/sh
# test-remote.sh — run the lib json + lib crypto acceptance suites on a
# remote Poplog machine (cross-architecture validation).
#
#   tools/test-remote.sh <ssh-host> [remote-poplog-dir]
#
# <ssh-host> is anything ssh accepts (an ~/.ssh/config alias like
# "raspi5", or user@10.0.0.111).  The remote dir (default: poplog,
# relative to the remote $HOME) must hold a built tree — the ./poplog
# wrapper and target/pop/basepop11.
#
# Copies the two libraries, the crypto shim source and the test
# scripts to the remote tree, then runs both suites there.  The crypto
# suite needs a C compiler and OpenSSL headers on the remote (Debian:
# libssl-dev); if the shim can't build, crypto is reported as SKIPPED
# and the json result stands alone.
set -e

host="${1:?usage: test-remote.sh <ssh-host> [remote-poplog-dir]}"
rdir="${2:-poplog}"
repo="$(cd "$(dirname "$0")/.." && pwd)"

echo "== $host: checking remote tree =="
ssh "$host" "[ -x $rdir/target/pop/basepop11 ] && [ -x $rdir/poplog ]" || {
    echo "test-remote: $host:$rdir is not a built Poplog tree" >&2; exit 2; }
ssh "$host" "uname -sm; mkdir -p $rdir/pop/extern/popcrypto"

echo "== $host: copying libraries + tests =="
scp -q "$repo/pop/lib/lib/json.p" "$repo/pop/lib/lib/crypto.p" \
    "$host:$rdir/pop/lib/lib/"
scp -q "$repo/pop/extern/popcrypto/popcrypto_shim.c" \
    "$host:$rdir/pop/extern/popcrypto/"
scp -q "$repo/tools/build-popcrypto.sh" "$repo/tools/test-json.sh" \
    "$repo/tools/test-crypto.sh" "$host:$rdir/tools/"
ssh "$host" "chmod +x $rdir/tools/build-popcrypto.sh $rdir/tools/test-json.sh $rdir/tools/test-crypto.sh"

status=0

echo "== $host: lib json suite =="
if ssh "$host" "$rdir/tools/test-json.sh" | tail -1 | grep -q 'ALL PASS'; then
    echo "json: ALL PASS"
else
    echo "json: FAILED"; status=1
fi

echo "== $host: lib crypto suite =="
if ! ssh "$host" "$rdir/tools/build-popcrypto.sh" >/dev/null 2>&1; then
    echo "crypto: SKIPPED (shim build failed -- needs cc + OpenSSL headers, e.g. libssl-dev)"
elif ssh "$host" "$rdir/tools/test-crypto.sh" | tail -1 | grep -q 'ALL PASS'; then
    echo "crypto: ALL PASS"
else
    echo "crypto: FAILED"; status=1
fi

exit $status
