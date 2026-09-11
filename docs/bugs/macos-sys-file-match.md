# macOS arm64: `sys_file_match` matches nothing, and hangs inside `[% %]`

**Status:** FIXED 2026-08-14 (struct layer; residual hangs are the separate
coroutine gate, see `macos-coroutines.md`) · **Severity:** medium ·
**Area:** `pop/src/unixdefs.ph` struct layouts · **Filed 2026-08-14 while
adding sitemap generation to gen-docs**

## Root cause and fix (2026-08-14)

The darwin port inherited the classic Berkeley `struct DIRECT` and
`struct STATB` layouts, but arm64 macOS only speaks Apple's
64-bit-inode ABI: `dirent` is `u64 ino; u64 seekoff; u16 reclen;
u16 namlen; u8 type; name@21`, and `struct stat` puts 16-bit
mode/nlink *before* the 64-bit inode and uses `timespec` pairs
(sizeof 144). With the old offsets `DIR_NAMLEN` landed inside
`d_seekoff` (read 0 → every name decoded empty → nothing matched) and
`ST_SIZE` landed on `st_atimespec` (so `sysfilesize` returned the
atime and `sysisdirectory` was always false). Fixed by darwin-specific
`deftype`/`struct DIRECT`/`struct STATB` branches in
`pop/src/unixdefs.ph`. **A clean rebuild is required** — an incremental
`make all` after a .ph change produced a binary that still carried the
old offsets (stale popc-toolchain artifacts); `rm -rf target`, reseed
corepop, `./configure && make all`.

Verified after the fix: `sys_file_stat('/etc/hosts', …)` returns
size 264 / mode 33188 / real mtime; `sysisdirectory('/tmp')` true;
top-level globs enumerate correctly (2/2, 5/5, 50/50 including through
the `/tmp` symlink).

The **remaining** hangs — repeaters driven from inside procedures, and
`...`-recursive patterns — are the process/coroutine port gate, split
out to `macos-coroutines.md`. Everything below is the original report.

---

## Symptoms (macos-arm64, engine built 2026-08-01 from master)

Two distinct failures, both absent on Linux (x86_64 and aarch64, where the
same code enumerates the whole 921-file corpus correctly):

1. **Silent empty match.** At top level, patterns that must match return
   `termin` on the first repeater call:

   ```pop11
   sys_file_match('pop/help/*', '', false, false)() =>   ;;; ** <termin>
   sys_file_match('tools/ci/*', '', false, false)() =>   ;;; ** <termin>
   ```

   Both directories have many entries. `lib fileutils`'s `dir_files`
   therefore returns `[]` for everything.

2. **Infinite loop when the userstack is non-empty.** The identical call
   made inside an open list constructor spins forever at ~100 % CPU:

   ```pop11
   uses fileutils;
   vars l = [% dir_files('tools/ci/*') %];   ;;; never returns
   ```

   `sample` shows all time in `c__031ussave` (userstack save), suggesting
   the matcher's stack discipline is unbalanced and interacts with
   pre-existing userstack content.

This is how `tools/gen-docs.p` hangs on macOS: its `collect()` calls
`dir_files` inside `[% ... %]`. The docs site builds only because CI runs it
on Linux.

## Repro

```sh
cat > /tmp/smrepro.p <<'EOF'
uses fileutils;
npr('top level: ' sys_>< length(dir_files('pop/help/*')));  ;;; 0 (wrong)
vars l = [% dir_files('pop/help/*') %];                     ;;; hangs here
npr('never reached');
EOF
./poplog target/pop/basepop11 /tmp/smrepro.p
```

## Notes for the fix

- Failure 1 means the underlying directory enumeration
  (`sys_matchin_dir` / `readdir` path in the darwin port) yields nothing,
  so start there; failure 2 is likely the same code mis-managing the
  userstack on its (early) exit path.
- `sysopen`/autoloading/`sys_file_stat` all work on macOS — the breakage is
  specific to the match/enumerate path.
- Until fixed: anything needing directory listings on macOS can shell out
  (`lib shell`'s `shell_lines('ls -1 ...')`) — but library code should not
  have to know the platform, so this deserves an engine-level fix.
