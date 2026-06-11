# Nix packaging

Build and run Poplog with Nix (flakes):

```sh
nix build .#poplog          # or: nix build path:$PWD#poplog in a non-git tree
./result/bin/pop11          # Pop-11 REPL
./result/bin/clisp          # Common Lisp
./result/bin/prolog         # Prolog
./result/bin/pml            # Standard ML
./result/bin/ved file       # terminal VED
```

Supported systems: `x86_64-linux` (tested), `aarch64-linux` (seed
pending), `aarch64-darwin` (experimental: codesign/entitlement story
under Nix not yet exercised).

## Bootstrap seeds

Poplog builds itself with a prior binary `corepop`; per-platform seeds
are vendored under `nix/seeds/corepop-<system>` and patchelf'd so they
can run inside the build sandbox (they link only libc/libm/libdl).
Any previously built corepop for the platform works as a seed -- to
refresh one, copy `target/pop/new_corepop` from a successful build.
When release artifacts exist, replace the vendored files with
`fetchurl` fixed-output derivations in `nix/poplog.nix` (`seed`).

## Notes

* Hardening is disabled wholesale: Poplog generates and executes its
  own machine code and lays memory out at fixed addresses (no PIE).
* The build overrides `POP__as`/`POP__ar`/`POP__ranlib` -- the sandbox
  has no `/usr/bin/{as,ar,ranlib}`.
* Saved images record their base images' absolute save-time paths;
  the engine falls back to searching `popsavepath` by filename
  (`Init_arg_search`), which is what makes the store-installed images
  relocatable.
* Graphics (`--experimental-gfx`, macOS) is not wired into the Nix
  build yet.
