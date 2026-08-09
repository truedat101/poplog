/* --- popcrypto_shim.c ---------------------------------------------------
 * Minimal libcrypto (OpenSSL) shim for Poplog -- see LIB * CRYPTO.
 *
 * Why a shim: keeps the Pop-11 exload surface to a few non-variadic,
 * explicit-length functions (the same reasoning as the popcurl shim --
 * variadic C calls are hazardous through the FFI, notably on Apple
 * arm64), and hides EVP object lifecycle from Pop-11 entirely.
 *
 * Build: tools/build-popcrypto.sh  ->  popcrypto.{so|dylib} next to
 * this file.  All buffers are caller-allocated; digest/HMAC outputs
 * need at most 64 bytes (SHA-512).
 */
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>

/* digest of data[0..len) with named algorithm ("sha256", "sha1",
 * "sha512", "md5", ...); writes raw bytes to out, returns the digest
 * length, or -1 (unknown algorithm / failure) */
int pcr_digest(const char *alg, const void *data, long len,
               unsigned char *out)
{
    const EVP_MD *md = EVP_get_digestbyname(alg);
    unsigned int n = 0;
    if (!md) return -1;
    if (!EVP_Digest(data, (size_t)len, out, &n, md, NULL)) return -1;
    return (int)n;
}

/* HMAC(alg, key, data); writes raw bytes to out, returns MAC length
 * or -1 */
int pcr_hmac(const char *alg, const void *key, long keylen,
             const void *data, long len, unsigned char *out)
{
    const EVP_MD *md = EVP_get_digestbyname(alg);
    unsigned int n = 0;
    if (!md) return -1;
    if (!HMAC(md, key, (int)keylen, data, (size_t)len, out, &n))
        return -1;
    return (int)n;
}

/* fill buf[0..n) with cryptographically secure random bytes;
 * 0 on success, -1 on RNG failure */
int pcr_random(unsigned char *buf, long n)
{
    return RAND_bytes(buf, (int)n) == 1 ? 0 : -1;
}

const char *pcr_version(void)
{
    return OpenSSL_version(OPENSSL_VERSION);
}
