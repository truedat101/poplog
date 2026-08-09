/* --- Cryptographic primitives for Poplog --------------------------------
 > File:            pop/lib/lib/crypto.p
 > Purpose:         Digests, HMAC and secure random bytes via libcrypto
 > Documentation:   HELP * CRYPTO
 > Related Files:   pop/extern/popcrypto/popcrypto_shim.c,
 >                  tools/build-popcrypto.sh, tools/test-crypto.sh
 >
 > A thin Pop-11 face over OpenSSL's libcrypto, loaded through a small
 > non-variadic C shim (never hand-rolled primitives).  Build the shim
 > once with tools/build-popcrypto.sh, then:  uses crypto;
 */
compile_mode :pop11 +strict;

section $-crypto =>
    crypto_digest crypto_digest_hex crypto_hmac crypto_hmac_hex
    crypto_random crypto_version sha256;

;;; fail at load time with a useful message if the shim isn't built
unless sys_file_exists(sysfileok('$usepop/pop/extern/popcrypto/popcrypto.so'))
or sys_file_exists(sysfileok('$usepop/pop/extern/popcrypto/popcrypto.dylib'))
then
    mishap(0, 'lib crypto: shim not built -- run tools/build-popcrypto.sh first')
endunless;

exload popcrypto
    #_IF sys_file_exists(sysfileok('$usepop/pop/extern/popcrypto/popcrypto.dylib'))
    ['$usepop/pop/extern/popcrypto/popcrypto.dylib']
    #_ELSE
    ['$usepop/pop/extern/popcrypto/popcrypto.so']
    #_ENDIF
(language C)
    lconstant
        pcr_digest(alg, data, len, out)             :int,
        pcr_hmac(alg, key, keylen, data, len, out)  :int,
        pcr_random(buf, n)                          :int,
        pcr_version()                               :exptr,
    ;
endexload;

;;; Pop-11 strings are not guaranteed null-terminated: C-string
;;; arguments (algorithm names) get an explicit terminator
define lconstant cstr(s);
    s <> consstring(0, 1)
enddefine;

lconstant hexdigits = '0123456789abcdef';

define lconstant hexof(s) -> h;
    lvars i, c;
    for i from 1 to length(s) do
        subscrs(i, s) -> c;
        subscrs((c << -4) + 1, hexdigits);
        subscrs((c && 15) + 1, hexdigits);
    endfor;
    consstring(2 * length(s)) -> h;
enddefine;

;;; digest/MAC outputs need at most 64 bytes (SHA-512)
lconstant OUTMAX = 64;

define crypto_digest(alg, data) -> raw;
    lvars n, out = inits(OUTMAX);
    unless isstring(alg) and isstring(data) then
        mishap(alg, data, 2, 'crypto_digest: two strings needed')
    endunless;
    exacc pcr_digest(cstr(alg), data, length(data), out) -> n;
    if n < 0 then
        mishap(alg, 1, 'crypto_digest: unknown algorithm')
    endif;
    substring(1, n, out) -> raw;
enddefine;

define crypto_digest_hex(alg, data) -> hex;
    hexof(crypto_digest(alg, data)) -> hex
enddefine;

define crypto_hmac(alg, key, data) -> raw;
    lvars n, out = inits(OUTMAX);
    unless isstring(alg) and isstring(key) and isstring(data) then
        mishap(alg, key, data, 3, 'crypto_hmac: three strings needed')
    endunless;
    exacc pcr_hmac(cstr(alg), key, length(key), data, length(data), out) -> n;
    if n < 0 then
        mishap(alg, 1, 'crypto_hmac: unknown algorithm')
    endif;
    substring(1, n, out) -> raw;
enddefine;

define crypto_hmac_hex(alg, key, data) -> hex;
    hexof(crypto_hmac(alg, key, data)) -> hex
enddefine;

define crypto_random(n) -> s;
    unless isinteger(n) and n > 0 then
        mishap(n, 1, 'crypto_random: positive integer needed')
    endunless;
    inits(n) -> s;
    unless exacc pcr_random(s, n) == 0 then
        mishap(n, 1, 'crypto_random: secure RNG unavailable')
    endunless;
enddefine;

define crypto_version() -> s;
    exacc_ntstring(exacc pcr_version()) -> s
enddefine;

;;; the 90% call gets a short name
define sha256(data) -> hex;
    crypto_digest_hex('sha256', data) -> hex
enddefine;

endsection;
