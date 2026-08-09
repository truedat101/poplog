#!/bin/sh
# test-crypto.sh — acceptance tests for LIB * CRYPTO (pop/lib/lib/crypto.p).
#
#   tools/test-crypto.sh [engine-command]
#
# Builds the shim if needed, then checks published test vectors
# (FIPS 180 digests, RFC 4231 / RFC 2202 HMACs) plus the RNG and
# must-fail cases.
set -e

repo="$(cd "$(dirname "$0")/.." && pwd)"
"$repo/tools/build-popcrypto.sh"

if [ -n "$1" ]; then
    engine="$1"
else
    [ -x "$repo/target/pop/basepop11" ] || {
        echo "test-crypto: no target/pop/basepop11 (build first, or pass an engine)" >&2; exit 2; }
    engine="$repo/poplog $repo/target/pop/basepop11"
fi

tmp="${TMPDIR:-/tmp}/test-crypto.$$.p"
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" <<'EOF'
uses crypto;

vars failures = 0;

define check(name, got, want);
    if got = want then
        'PASS ' >< name =>
    else
        'FAIL ' >< name =>
        got =>
        want =>
        failures + 1 -> failures;
    endif;
enddefine;

vars trapped;
define mishaps(p);
    lvars sl = stacklength();
    false -> trapped;
    dlocal prmishap = procedure(m, c); true -> trapped; exitto(mishaps) endprocedure;
    p();
    setstacklength(sl);
    trapped
enddefine;

;;; --- digests (FIPS 180 / RFC 1321 vectors) ---
check('sha256 empty', sha256(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
check('sha256 abc', sha256('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
check('sha1 abc', crypto_digest_hex('sha1', 'abc'),
      'a9993e364706816aba3e25717850c26c9cd0d89d');
check('sha512 abc', crypto_digest_hex('sha512', 'abc'),
      'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a' ><
      '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
check('md5 abc', crypto_digest_hex('md5', 'abc'),
      '900150983cd24fb0d6963f7d28e17f72');
check('raw length', length(crypto_digest('sha256', 'abc')), 32);
;;; binary-safe input: embedded null byte
check('sha256 embedded nul',
      sha256(consstring(`a`, 0, `b`, 3)) /= sha256('ab'), true);

;;; --- HMAC (RFC 4231 test case 2, RFC 2202 sha1 case 2) ---
check('hmac-sha256 jefe',
      crypto_hmac_hex('sha256', 'Jefe', 'what do ya want for nothing?'),
      '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
check('hmac-sha1 jefe',
      crypto_hmac_hex('sha1', 'Jefe', 'what do ya want for nothing?'),
      'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79');
check('hmac raw length', length(crypto_hmac('sha256', 'k', 'd')), 32);

;;; --- random ---
check('random length', length(crypto_random(16)), 16);
check('random varies', crypto_random(16) = crypto_random(16), false);
check('random length 1', length(crypto_random(1)), 1);

;;; --- version ---
check('version string', isstring(crypto_version()) and
      length(crypto_version()) > 0, true);

;;; --- must fail ---
check('reject bad algorithm',
      mishaps(procedure; crypto_digest('nope256', 'x').erase endprocedure), true);
check('reject non-string',
      mishaps(procedure; crypto_digest('sha256', 42).erase endprocedure), true);
check('reject bad hmac alg',
      mishaps(procedure; crypto_hmac('nope', 'k', 'd').erase endprocedure), true);
check('reject random 0',
      mishaps(procedure; crypto_random(0).erase endprocedure), true);

if failures == 0 then
    'SUMMARY: ALL PASS' =>
else
    'SUMMARY: ' >< failures >< ' FAILURES' =>
endif;
EOF

# shellcheck disable=SC2086  # $engine may be "wrapper binary"
out="$($engine "$tmp" 2>&1)" || true
echo "$out" | grep -E '^\*\* (PASS|FAIL|SUMMARY)' | sed 's/^\*\* //'
echo "$out" | grep -q 'SUMMARY: ALL PASS'
