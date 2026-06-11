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

## Use cases

The flake exposes `packages`, `apps`, and a `devShell`:

```sh
# Run a language front-end directly (no checkout needed):
nix run .#pop11             # or .#prolog .#clisp .#pml .#ved
nix run .                   # bare run starts the Pop-11 REPL
echo '6 * 7 =>' | nix run .#pop11        # ** 42

# Ephemeral shell with every front-end on PATH:
nix shell .#poplog -c pop11 myfile.p

# Dev shell for hacking on Poplog sources:
nix develop                 # pop11/clisp/prolog/pml/ved on PATH, $usepop set
```

Compiling a source file: use a front-end (`pop11 file.p`), not the bare
`basepop11` -- run with no subsystem, `basepop11` looks for its own
startup file and reports `basepop11.p` not found. `exload`/`exacc`
(calling C from Pop) works from the store build: it shells out to the
system compiler at run time, so a C toolchain must be on PATH (on macOS
`/usr/bin/clang` always is).

Supported systems: `x86_64-linux` and `aarch64-darwin` (both tested
end-to-end: all four languages run from the store path), and
`aarch64-linux` (seed vendored from a validated RPi5 build; flake
untested -- no aarch64-linux Nix host yet).

macOS note: no entitlements are required -- the W^X machinery uses
mach_vm_remap + mprotect on anonymous pages, not MAP_JIT, so the
linker's ad-hoc signature suffices (the link epilogue refreshes it
when a codesign is available, and tolerates its absence).

## Experimental graphics (Linux)

`packages.<linux>.poplog-gfx` builds basepop11 with the native graphics
backend (`--experimental-graphics` -> Dear ImGui + SDL3 + OpenGL3).  The
ImGui source is fetched as a `fetchFromGitHub` FOD; SDL3 (3.2.20) is why
the flake pins nixpkgs 25.05.

```sh
nix build .#poplog-gfx          # Linux only (Metal backend on macOS is separate)
nm result/poplog/target/pop/basepop11 | grep -c pop_gfx   # -> 27
echo "uses rc_graphic; rc_start();" | result/bin/pop11     # opens a window
```

The binary links nix's `libSDL3` + `libglvnd`; **SDL3 picks the display
transport at run time** (Wayland if `WAYLAND_DISPLAY`, else X11, else
`kmsdrm`) -- there is no hard X11 dependency.

Running it needs a GL driver `libglvnd` can reach:

* **NixOS** -- seamless; the configured GPU driver is wired into the GL
  stack (`hardware.graphics.enable`).  This is the smooth path.
* **Non-NixOS (Ubuntu, etc.)** -- the system GPU driver lives outside the
  nix store, so a nix GL binary needs the driver injected, the usual way
  being [nixGL](https://github.com/nix-community/nixGL):
  `nixGL result/bin/pop11 myfile.p`.
* **Headless / CI** -- software render with Mesa llvmpipe over EGL
  (`SDL_VIDEO_X11_FORCE_EGL=1 LIBGL_ALWAYS_SOFTWARE=1`), no GPU required.

The SDL3+OpenGL3 backend itself is verified rendering the full Poplog
surface (lines/rects/circles/arcs/text + ImGui panels) on Linux/X11.
The `nix build` is verified end-to-end (console smoke passes from the
store path); driving its GL on a given box is the standard nix-graphics
deployment story above.

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
