# macOS arm64: large user-stack growth SIGBUSes, ASLR-dependent

**Status:** open · **Severity:** medium (probabilistic: ~4/5 process
launches in the bad layout during the 2026-08-14 session; small
workloads never touch it) · **Area:** fixed-address memory layout
(porting doc Phase 3: `LOWEST_ADDRESS = 0 … MAP_FIXED image load needs
revisiting`) · **Found 2026-08-14 while validating the coroutine fix**

## Symptom

Pushing a large number of items onto the user stack (~200k words — e.g.
`lib fileutils`'s `file_to_string`, which stacks every character before
`consstring`) dies with a NULL write, and the error-delivery machinery
then faults recursively:

```
[wx-decline] addr=0 base=8000000000 brk=8000048000 exec=0
[fatal] sig=10 pc=…Error_signal addr=0 lr=…__pop_errsig …
```

Whether a given PROCESS fails is decided at launch: the same binary and
script pass or fail all sizes together depending on that run's address
-space layout (observed 1-in-5 pass rate one hour, all-pass earlier the
same day). Repro:

```pop11
define pushn(n);
    lvars i;
    for i from 1 to n do `x` endfor;
    erase(consstring(n));
enddefine;
pushn(200000);
```

Run it a handful of times; in bad layouts even the first sizes fail.

## Analysis pointers

- The engine claims fixed regions (heap base 0x8000000000, user stack
  near `_userhi`); macOS is PIE-mandatory and places system mappings by
  ASLR, so a colliding/absent reservation makes stack extension hand
  back an unusable address → the NULL write.
- This is exactly the porting doc's open Phase-3 item; the durable fix
  is reserving the full user-stack range up front (single big
  `mmap(PROT_NONE)` + `mprotect` growth) instead of trusting
  incremental fixed-address extension.
- NOT related to the coroutine `_ussave` work (bisected: reverted
  builds and the shipped tarball engine show the same flake).
- Consequence today: `gen-docs` on macOS still fails (its
  `file_to_string` over 900+ files guarantees hitting the bad path);
  keep generating docs on Linux until this is fixed.
