/* popsqlite_shim.c — non-variadic C surface over sqlite3 for Pop-11.
 *
 * Why a shim (the sqlite3 API is already non-variadic): it flattens the
 * awkward-for-FFI parts — out-parameters (sqlite3_open's sqlite3**,
 * prepare's stmt**), the SQLITE_TRANSIENT destructor pointer on binds,
 * int64 rowids, and NULL-pointer results — into a surface of plain ints
 * and strings. Databases and statements are small integer handles
 * (>= 1; 0 means failure — read psq_errmsg), so the Pop-11 side never
 * holds a raw pointer. Single-threaded by design, like the session.
 *
 * Build: bin/build-popsqlite  (cc -O2 -shared -o popsqlite.{dylib,so}
 *        ... -lsqlite3)
 *
 * Column indices are 0-based (sqlite3_column_*), bind indices 1-based
 * (sqlite3_bind_*) — same as the sqlite C API; the generated Pop-11
 * loader hides both behind whole-row procedures.
 */
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>

#define MAX_DB   32
#define MAX_STMT 256

static sqlite3      *dbs[MAX_DB + 1];
static sqlite3_stmt *stmts[MAX_STMT + 1];
static char last_err[512];
static char rowid_buf[32];

static void set_err(const char *msg) {
    snprintf(last_err, sizeof last_err, "%s", msg ? msg : "unknown error");
}

const char *psq_version(void) { return sqlite3_libversion(); }

/* Most recent error: per-db if the handle is live, else the saved one
 * (covers failed open/prepare where no live handle exists). */
const char *psq_errmsg(int db) {
    if (db >= 1 && db <= MAX_DB && dbs[db]) return sqlite3_errmsg(dbs[db]);
    return last_err;
}

int psq_open(const char *path) {
    int h;
    for (h = 1; h <= MAX_DB && dbs[h]; h++) ;
    if (h > MAX_DB) { set_err("too many open databases"); return 0; }
    sqlite3 *db = NULL;
    if (sqlite3_open(path, &db) != SQLITE_OK) {
        set_err(db ? sqlite3_errmsg(db) : "out of memory");
        if (db) sqlite3_close(db);
        return 0;
    }
    dbs[h] = db;
    return h;
}

int psq_close(int db) {
    if (db < 1 || db > MAX_DB || !dbs[db]) return SQLITE_MISUSE;
    /* finalize any statements still open on this db */
    for (int s = 1; s <= MAX_STMT; s++)
        if (stmts[s] && sqlite3_db_handle(stmts[s]) == dbs[db]) {
            sqlite3_finalize(stmts[s]);
            stmts[s] = NULL;
        }
    int rc = sqlite3_close(dbs[db]);
    if (rc == SQLITE_OK) dbs[db] = NULL;
    return rc;
}

int psq_exec(int db, const char *sql) {
    if (db < 1 || db > MAX_DB || !dbs[db]) return SQLITE_MISUSE;
    char *err = NULL;
    int rc = sqlite3_exec(dbs[db], sql, NULL, NULL, &err);
    if (err) { set_err(err); sqlite3_free(err); }
    return rc;
}

int psq_prepare(int db, const char *sql) {
    if (db < 1 || db > MAX_DB || !dbs[db]) { set_err("bad db handle"); return 0; }
    int s;
    for (s = 1; s <= MAX_STMT && stmts[s]; s++) ;
    if (s > MAX_STMT) { set_err("too many open statements"); return 0; }
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(dbs[db], sql, -1, &st, NULL) != SQLITE_OK) {
        set_err(sqlite3_errmsg(dbs[db]));
        return 0;
    }
    if (!st) { set_err("empty statement"); return 0; }
    stmts[s] = st;
    return s;
}

static sqlite3_stmt *st_of(int s) {
    return (s >= 1 && s <= MAX_STMT) ? stmts[s] : NULL;
}

int psq_step(int s) {          /* 100 = row, 101 = done, else error rc */
    sqlite3_stmt *st = st_of(s);
    return st ? sqlite3_step(st) : SQLITE_MISUSE;
}

int psq_reset(int s) {
    sqlite3_stmt *st = st_of(s);
    return st ? sqlite3_reset(st) : SQLITE_MISUSE;
}

int psq_finalize(int s) {
    sqlite3_stmt *st = st_of(s);
    if (!st) return SQLITE_MISUSE;
    int rc = sqlite3_finalize(st);
    stmts[s] = NULL;
    return rc;
}

int psq_col_count(int s) {
    sqlite3_stmt *st = st_of(s);
    return st ? sqlite3_column_count(st) : 0;
}

const char *psq_col_name(int s, int i) {
    sqlite3_stmt *st = st_of(s);
    const char *n = st ? sqlite3_column_name(st, i) : NULL;
    return n ? n : "";
}

/* Everything comes back as text ("" for SQL NULL — disambiguate with
 * psq_col_is_null). Text round-trips are lossless under sqlite's dynamic
 * typing, and keeping doubles/int64 out of the FFI surface sidesteps
 * per-port float-ABI questions; typed accessors can come in v0.2. */
const char *psq_col_text(int s, int i) {
    sqlite3_stmt *st = st_of(s);
    const unsigned char *t = st ? sqlite3_column_text(st, i) : NULL;
    return t ? (const char *)t : "";
}

int psq_col_is_null(int s, int i) {
    sqlite3_stmt *st = st_of(s);
    return (st && sqlite3_column_type(st, i) == SQLITE_NULL) ? 1 : 0;
}

int psq_bind_text(int s, int i, const char *v) {
    sqlite3_stmt *st = st_of(s);
    return st ? sqlite3_bind_text(st, i, v, -1, SQLITE_TRANSIENT)
              : SQLITE_MISUSE;
}

int psq_changes(int db) {
    if (db < 1 || db > MAX_DB || !dbs[db]) return 0;
    return sqlite3_changes(dbs[db]);
}

const char *psq_last_rowid(int db) {
    if (db < 1 || db > MAX_DB || !dbs[db]) return "0";
    snprintf(rowid_buf, sizeof rowid_buf, "%lld",
             (long long)sqlite3_last_insert_rowid(dbs[db]));
    return rowid_buf;
}
