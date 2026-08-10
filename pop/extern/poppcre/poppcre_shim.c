/* --- poppcre_shim.c -----------------------------------------------------
 * Author: D.Kordsmeier (@truedat101) and Claude (@claude), Aug 2026
 * PCRE2 shim for Poplog -- see LIB * PCRE.
 *
 * Non-variadic, explicit-length entry points with results held in
 * static state (Poplog is single-threaded; the shim is deliberately
 * not reentrant).  The most recently compiled pattern is cached, so
 * the scan loops in LIB PCRE compile once per pattern, not per call.
 *
 * Build: tools/build-poppcre.sh -> poppcre.{so|dylib} next to this
 * file.
 */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <stdio.h>
#include <string.h>

static pcre2_code       *code = NULL;
static pcre2_match_data *md = NULL;
static char              cached_pat[4096];
static char              errbuf[256];
static int               rc_groups = 0;   /* groups matched in last search */

static int compile(const char *pat)
{
    int errcode;
    PCRE2_SIZE erroff;

    if (code && cached_pat[0] && strcmp(pat, cached_pat) == 0)
        return 0;

    if (code) { pcre2_code_free(code); code = NULL; }
    if (md)   { pcre2_match_data_free(md); md = NULL; }
    cached_pat[0] = '\0';

    code = pcre2_compile((PCRE2_SPTR)pat, PCRE2_ZERO_TERMINATED, 0,
                         &errcode, &erroff, NULL);
    if (!code) {
        char msg[200];
        pcre2_get_error_message(errcode, (PCRE2_UCHAR *)msg, sizeof msg);
        snprintf(errbuf, sizeof errbuf, "%s (at offset %lu)",
                 msg, (unsigned long)erroff);
        return -1;
    }
    md = pcre2_match_data_create_from_pattern(code, NULL);
    if (!md) {
        strcpy(errbuf, "cannot allocate match data");
        pcre2_code_free(code); code = NULL;
        return -1;
    }
    if (strlen(pat) < sizeof cached_pat)
        strcpy(cached_pat, pat);
    return 0;
}

/* match subject[start..len) against pat (start is a 0-based byte
 * offset).  Returns 1 on match, 0 on no match, -1 on error (see
 * pcp_error).  Offsets of the whole match and each capture group are
 * then available from pcp_start/pcp_len until the next call. */
int pcp_search(const char *pat, const void *subj, long len, long start)
{
    int rc;

    errbuf[0] = '\0';
    if (compile(pat) < 0) return -1;

    rc = pcre2_match(code, (PCRE2_SPTR)subj, (PCRE2_SIZE)len,
                     (PCRE2_SIZE)start, 0, md, NULL);
    if (rc == PCRE2_ERROR_NOMATCH) { rc_groups = 0; return 0; }
    if (rc < 0) {
        pcre2_get_error_message(rc, (PCRE2_UCHAR *)errbuf, sizeof errbuf);
        rc_groups = 0;
        return -1;
    }
    rc_groups = rc - 1;         /* rc counts the whole match too */
    return 1;
}

/* 0-based byte offset of group i of the last match (0 = whole match);
 * -1 when the group did not participate */
long pcp_start(int i)
{
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
    if (ov[2 * i] == PCRE2_UNSET) return -1;
    return (long)ov[2 * i];
}

long pcp_len(int i)
{
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
    if (ov[2 * i] == PCRE2_UNSET) return -1;
    return (long)(ov[2 * i + 1] - ov[2 * i]);
}

/* capture groups that participated in the last successful match */
int pcp_groups(void)
{
    return rc_groups;
}

const char *pcp_error(void)
{
    return errbuf;
}

const char *pcp_version(void)
{
    static char v[64];
    pcre2_config(PCRE2_CONFIG_VERSION, v);
    return v;
}
