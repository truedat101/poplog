/* --- popcurl_shim.c -----------------------------------------------------
 * Author: D.Kordsmeier (@truedat101) and Claude (@claude), Aug 2026
 * libcurl shim for Poplog -- see LIB * HTTP_CLIENT.
 *
 * Same design rules as the popcrypto shim: a few non-variadic,
 * explicit-length entry points (curl_easy_setopt itself is variadic,
 * which is exactly what we keep away from the FFI), with results held
 * in static buffers read back via accessors.  Poplog is single-
 * threaded, so one outstanding request at a time is fine; the shim is
 * not reentrant and does not need to be.
 *
 * Build: tools/build-popcurl.sh -> popcurl.{so|dylib} next to this
 * file.  (Distinct from the pop11 Claude skill's private popcurl,
 * which predates this and lives with the skill.)
 */
#include <curl/curl.h>
#include <stdlib.h>
#include <string.h>

static char  *body_buf = NULL;
static size_t body_len = 0;
static char  *hdr_buf = NULL;
static size_t hdr_len = 0;
static char   errbuf[CURL_ERROR_SIZE + 1];

static size_t grow(char **buf, size_t *len, const void *data, size_t n)
{
    char *p = realloc(*buf, *len + n + 1);
    if (!p) return 0;
    memcpy(p + *len, data, n);
    *buf = p;
    *len += n;
    p[*len] = '\0';
    return n;
}

static size_t on_body(void *data, size_t sz, size_t nm, void *ud)
{
    (void)ud;
    return grow(&body_buf, &body_len, data, sz * nm);
}

static size_t on_header(void *data, size_t sz, size_t nm, void *ud)
{
    (void)ud;
    return grow(&hdr_buf, &hdr_len, data, sz * nm);
}

static void reset(void)
{
    free(body_buf); body_buf = NULL; body_len = 0;
    free(hdr_buf);  hdr_buf = NULL;  hdr_len = 0;
    errbuf[0] = '\0';
}

/* Perform METHOD on URL.  body/bodylen: request body (len 0 = none).
 * headers: \n-separated "Name: value" lines ("" = none).  timeout in
 * seconds (0 = library default).  Returns the HTTP status code, or -1
 * on a transport error (see pcu_error).  Response body and headers
 * are then available from the accessors below until the next call. */
int pcu_perform(const char *method, const char *url,
                const void *body, long bodylen,
                const char *headers, long timeout)
{
    CURL *h;
    struct curl_slist *hlist = NULL;
    CURLcode rc;
    long status = 0;

    reset();
    h = curl_easy_init();
    if (!h) { strcpy(errbuf, "curl_easy_init failed"); return -1; }

    curl_easy_setopt(h, CURLOPT_URL, url);
    curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, method);
    curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(h, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, on_body);
    curl_easy_setopt(h, CURLOPT_HEADERFUNCTION, on_header);
    curl_easy_setopt(h, CURLOPT_ERRORBUFFER, errbuf);
    curl_easy_setopt(h, CURLOPT_ACCEPT_ENCODING, "");
    if (timeout > 0)
        curl_easy_setopt(h, CURLOPT_TIMEOUT, timeout);
    if (bodylen > 0) {
        curl_easy_setopt(h, CURLOPT_POSTFIELDS, body);
        curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, bodylen);
    }
    if (headers && headers[0]) {
        char *copy = strdup(headers), *line, *save = NULL;
        for (line = strtok_r(copy, "\n", &save); line;
             line = strtok_r(NULL, "\n", &save))
            if (line[0]) hlist = curl_slist_append(hlist, line);
        free(copy);
        if (hlist) curl_easy_setopt(h, CURLOPT_HTTPHEADER, hlist);
    }

    rc = curl_easy_perform(h);
    if (rc == CURLE_OK)
        curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &status);
    else if (!errbuf[0])
        strncpy(errbuf, curl_easy_strerror(rc), CURL_ERROR_SIZE);

    if (hlist) curl_slist_free_all(hlist);
    curl_easy_cleanup(h);
    return rc == CURLE_OK ? (int)status : -1;
}

long pcu_body_len(void)               { return (long)body_len; }
void pcu_body_copy(unsigned char *out){ if (body_len) memcpy(out, body_buf, body_len); }
long pcu_hdrs_len(void)               { return (long)hdr_len; }
void pcu_hdrs_copy(unsigned char *out){ if (hdr_len) memcpy(out, hdr_buf, hdr_len); }
const char *pcu_error(void)           { return errbuf; }
const char *pcu_version(void)         { return curl_version(); }
