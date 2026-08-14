# macOS arm64: `sys_file_match` matches nothing, and hangs inside `[% %]`

**Status:** open · **Severity:** medium (breaks `dir_files` and everything
built on it — `gen-docs` cannot run on macOS) · **Area:** file-name matching
(`pop/lib/auto/sys_file_match.p` / `sys_matchin_dir` machinery) ·
**Filed 2026-08-14 while adding sitemap generation to gen-docs**

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
