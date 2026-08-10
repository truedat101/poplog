/* --- popcrypto_shim.c ---------------------------------------------------
 * Author: D.Kordsmeier (@truedat101) with Claude (Anthropic), Aug 2026
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

/* AES-256-GCM seal: 32-byte key, 12-byte nonce; writes ptlen bytes of
 * ciphertext to ct and a 16-byte tag; returns ciphertext length or -1 */
int pcr_gcm_encrypt(const unsigned char *key, const unsigned char *nonce,
                    const void *pt, long ptlen,
                    unsigned char *ct, unsigned char *tag)
{
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    int len = 0, ctlen = 0, ok;
    if (!ctx) return -1;
    ok = EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) == 1
      && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL) == 1
      && EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce) == 1
      && EVP_EncryptUpdate(ctx, ct, &len, pt, (int)ptlen) == 1;
    ctlen = len;
    ok = ok && EVP_EncryptFinal_ex(ctx, ct + ctlen, &len) == 1;
    ctlen += len;
    ok = ok && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag) == 1;
    EVP_CIPHER_CTX_free(ctx);
    return ok ? ctlen : -1;
}

/* AES-256-GCM open: returns plaintext length, or -1 if the tag does
 * not authenticate (or any other failure) */
int pcr_gcm_decrypt(const unsigned char *key, const unsigned char *nonce,
                    const void *ct, long ctlen,
                    const unsigned char *tag, unsigned char *pt)
{
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    int len = 0, ptlen = 0, ok;
    if (!ctx) return -1;
    ok = EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) == 1
      && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL) == 1
      && EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce) == 1
      && EVP_DecryptUpdate(ctx, pt, &len, ct, (int)ctlen) == 1;
    ptlen = len;
    ok = ok && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16,
                                   (void *)tag) == 1
            && EVP_DecryptFinal_ex(ctx, pt + ptlen, &len) == 1;
    ptlen += len;
    EVP_CIPHER_CTX_free(ctx);
    return ok ? ptlen : -1;
}

/* PBKDF2-HMAC with the named digest; 0 on success, -1 on failure */
int pcr_pbkdf2(const char *alg, const void *pass, long passlen,
               const void *salt, long saltlen, long iters,
               unsigned char *out, long outlen)
{
    const EVP_MD *md = EVP_get_digestbyname(alg);
    if (!md || iters < 1) return -1;
    return PKCS5_PBKDF2_HMAC((const char *)pass, (int)passlen,
                             (const unsigned char *)salt, (int)saltlen,
                             (int)iters, md, (int)outlen, out) == 1 ? 0 : -1;
}

const char *pcr_version(void)
{
    return OpenSSL_version(OPENSSL_VERSION);
}
