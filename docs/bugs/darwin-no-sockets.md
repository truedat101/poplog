# Darwin build: unix sockets not enabled (http suites are Linux-only)

**Status:** open · **Severity:** medium (feature gap, not a crash) ·
**Area:** `pop/lib/lib/unix_sockets.p` gate vs Darwin sysdefs ·
**Filed 2026-08-15 while closing out the userstack-growth bug**

## Symptom

```
;;; MISHAP - SOCKETS NOT SUPPORTED IN THIS SYSTEM
;;; FILE : pop/lib/lib/unix_sockets.p LINE NUMBER: 14
```

`lib unix_sockets` gates on `#_IF not(DEF BERKELEY or DEFV SYSTEM_V >=
4.0)`, and the arm64 Darwin sysdefs define neither, so everything above
it — `lib http_server`, `lib http_client`'s server-side tests,
`examples/http_hello.p` — mishaps at load time on macOS.
`tools/test-libs.sh` therefore SKIPs `test_http_*` on Darwin.

## Fix direction

macOS *is* a BSD: the socket syscalls exist and are Berkeley-shaped.
The work is (a) auditing `unix_sockets.ph` struct layouts against the
Darwin ABI (sockaddr has the `sa_len` byte, like other modern BSDs —
this is the same class of fix as the dirent/stat struct work in
`macos-sys-file-match.md`), (b) defining the appropriate flag (or a
Darwin branch) in `syscomp/arm64/sysdefs_darwin.p`, and (c) running
`test_http_server` / `test_http_client` as acceptance.

Until then: http server/client work stays Linux-only; everything else
in the stdlib is now green on macOS.
