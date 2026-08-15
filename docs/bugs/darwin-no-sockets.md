# Darwin build: unix sockets not enabled (http suites were Linux-only)

**Status:** FIXED 2026-08-15 · **Severity:** medium (feature gap) ·
**Area:** lib-level `sysdefs.ph`/`sigdefs.ph` + `unix_sockets.p` ABI ·
**Filed 2026-08-15 while closing out the userstack-growth bug**

## Root cause and fix (same day)

Two layers, both lib-side (no engine change needed):

1. **`pop/lib/include/sysdefs.ph` had no `darwin` branch.** The
   lib-level flags are derived from `sys_os_type` (`[unix darwin 25.0
   macho posix …]`) at compile time, and with no branch Darwin got
   neither `BERKELEY` nor `BSD_SOCKETS`, so `lib unix_sockets`'s
   `#_IF not(DEF BERKELEY or DEFV SYSTEM_V >= 4.0)` gate mishapped.
   (The *engine-side* `syscomp/arm64/sysdefs_darwin.p` had defined
   `BERKELEY = 4.3` all along — the two sysdefs are separate worlds.)
   Now: `DARWIN` + `BERKELEY = 4.3`, which also gives Darwin the
   correct classic-BSD **signal numbers** in `sigdefs.ph` (it had been
   falling to the `MAXSIG = 15` default — no lib-level `SIG_CHLD`!);
   Darwin joins the FreeBSD/NetBSD sub-branch (WINCH 28, INFO 29,
   USR1 30, USR2 31, MAXSIG 31, no SIG_LOST).

2. **4.4BSD sockaddr layout.** Darwin's `sockaddr` starts with a
   one-byte `sa_len` followed by a ONE-BYTE family; the lib's typespecs
   declared `family :short` at offset 0, which on little-endian writes
   the family value into the `sa_len` slot and 0 into the family —
   the kernel rejects every bind/connect. `unix_sockets.p` now has
   Darwin variants of `sockaddr_un`/`sockaddr_in` (len byte + byte
   family; all later offsets unchanged), sets the len fields, and
   `sockaddr_to_name` reads the family through the typespec so both
   layouts decode.

Linux is untouched (it has its own top-level branches everywhere the
shared headers changed).

## Verified

`tools/test-libs.sh` on macos-arm64: **all 10 suites green**, including
`test_http_server` (a Pop-11 HTTP server serving real TCP requests on
macOS: routing, query/JSON, POST echo, 404, mishap→500 recovery, clean
exit) and `test_http_client` — the suites this gap kept Linux-only.
INET + UNIX socket create/bind/getsockname smoke both families.
