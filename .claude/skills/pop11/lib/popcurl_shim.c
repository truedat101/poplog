/* popcurl_shim.c — non-variadic C surface over libcurl for Pop-11.
 *
 * Why a shim: curl_easy_setopt is variadic, and on Apple arm64 variadic
 * arguments are passed on the stack while the Poplog FFI passes registers —
 * so the real entry points are not directly callable. Every function here
 * has a fixed prototype.
 *
 * Build: bin/build-popcurl  (cc -O2 -shared -o popcurl.{dylib,so} ... -lcurl)
 *
 * Returns: HTTP status (2xx/3xx/4xx/5xx) on a completed transfer,
 *          -1/-2 on init/file errors, -(1000+CURLcode) on transfer errors.
 */
#include <curl/curl.h>
#include <stdio.h>
#include <string.h>

static int perform_to_file(CURL *h, const char *outpath) {
    FILE *f = fopen(outpath, "wb");
    if (!f) { curl_easy_cleanup(h); return -2; }
    curl_easy_setopt(h, CURLOPT_WRITEDATA, f);
    curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(h, CURLOPT_TIMEOUT, 60L);
    curl_easy_setopt(h, CURLOPT_USERAGENT, "popcurl/0.1");
    CURLcode rc = curl_easy_perform(h);
    long code = 0;
    curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &code);
    fclose(f);
    curl_easy_cleanup(h);
    return rc == CURLE_OK ? (int)code : -(1000 + (int)rc);
}

int pc_get(const char *url, const char *outpath) {
    CURL *h = curl_easy_init();
    if (!h) return -1;
    curl_easy_setopt(h, CURLOPT_URL, url);
    return perform_to_file(h, outpath);
}

int pc_post(const char *url, const char *body, const char *content_type,
            const char *outpath) {
    CURL *h = curl_easy_init();
    if (!h) return -1;
    struct curl_slist *hdrs = NULL;
    char buf[256];
    snprintf(buf, sizeof buf, "Content-Type: %s", content_type);
    hdrs = curl_slist_append(hdrs, buf);
    curl_easy_setopt(h, CURLOPT_URL, url);
    curl_easy_setopt(h, CURLOPT_HTTPHEADER, hdrs);
    curl_easy_setopt(h, CURLOPT_COPYPOSTFIELDS, body);
    int r = perform_to_file(h, outpath);
    curl_slist_free_all(hdrs);
    return r;
}

const char *pc_version(void) { return curl_version(); }
