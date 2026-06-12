POPLOG is a free, open source, multi-language software development
environment providing incremental compilers for a number of interactive
programming languages, notably:

* Pop-11
    The core language of Poplog, including a rich interface to the X
    window system and a powerful Object Oriented programming extension,
    Objectclass, developed by Steve Leach now a standard part of the
    language (comparable to CLOS as an extension of LISP). 
* Prolog
    Standard prolog with the "Edinburgh" syntax.
* Common Lisp
    Compatible with most of CLTL2 (Common Lisp the language, 2nd
    Edition) by G.L. Steele
* Standard ML
    A powerful, strongly typed, polymorphic, functional language.

Poplog provides support for multi-paradigm software development in a
rapid prototyping environment, because of the use of (fast) incremental
compilers for all the languages.  There is substantial AI and teaching
material using Poplog, some included in this repository, some
in separate packages repository, some available on the net.

---

## The four languages, live

All four incremental compilers share one virtual machine and one saved image,
and interoperate freely.  Captured from the Apple Silicon (macOS) build:

| Pop-11 — the core language | Prolog — Edinburgh syntax |
| :---: | :---: |
| ![Pop-11 REPL](docs/images/repl-pop11.png) | ![Prolog REPL](docs/images/repl-prolog.png) |
| **Common Lisp — CLTL2** | **Standard ML — type inference** |
| ![Common Lisp REPL](docs/images/repl-clisp.png) | ![Standard ML REPL](docs/images/repl-pml.png) |

## Platforms

Poplog builds and runs natively on a growing set of platforms
(status as of June 2026):

| OS | Architecture | Status | Notes |
| --- | --- | --- | --- |
| **Linux** | x86-64 | ✅ Supported | Reference platform |
| **Linux** | AArch64 (ARM64) | ✅ Supported | Validated on Raspberry Pi 5 — all four languages + saved images.  Generic `armv8-a`, no core-specific tuning, so it ports readily to other ARM64 boards (MediaTek Genio, Qualcomm Snapdragon) |
| **macOS** | Apple Silicon (arm64) | ✅ Supported | Native Mach-O port — self-hosting, all four languages, terminal VED, C↔Pop callbacks, and native graphics |
| **Linux** | ARM32 (`armv7`/`armv6`) | 🚧 TODO | Raspberry Pi 3 / 32-bit ARM — not yet ported |
| **Solaris** | SPARC (v8/v9) | 🚧 TODO | Classic Poplog platform; historical academic ports, not yet revived in this fork |

The 🚧 rows are real Poplog targets with no native build in this fork yet — see
the [platform-coverage table in BENCHMARKS.md](BENCHMARKS.md#platform-coverage)
for how they show up (TODO) across the benchmark columns.

Per-platform porting notes: `PORTING-ARM64-LINUX-RPI5.md` and
`PORTING-ARM64-M-SILICON-OSX.md`.

## Packaging (Nix)

A self-contained **Nix flake** builds and bootstraps the whole system — all
four languages and their saved images — from source, with no manual seed or
toolchain setup.  Tested end-to-end on `x86_64-linux` and `aarch64-darwin`;
`aarch64-linux` ships a vendored seed.

```sh
nix build .#poplog          # build; then ./result/bin/{pop11,clisp,prolog,pml,ved}
nix run   .#pop11           # run a REPL directly (or .#prolog / .#clisp / .#pml)
nix shell .#poplog          # drop all five front-ends onto $PATH
nix develop                 # dev shell for hacking on Poplog sources
nix build .#poplog-gfx      # experimental graphics: Metal on macOS, SDL3+OpenGL3 on Linux
```

The flake exposes `packages`, `apps`, and a `devShell` for every supported
system.  On macOS the build is signed ad-hoc with **no entitlements required**.

**First-build cost:** Nix builds the whole toolchain closure from source, so
the first build pulls **~1.1 GB** of cached dependencies and lands a **~1.2 GiB**
on-disk closure (the Poplog out-path is ~95 MB; the rest is shared deps), taking
a couple of minutes to build.  Subsequent builds of the same source fetch
nothing.  Full details — use cases, costs, the bootstrap-seed story, and the
graphics variant — are in **[`nix/README.md`](nix/README.md)**.

## Native graphics (experimental)

Historically Poplog's graphics were tied to the X window system (Xpw / `xved`).
There is now an **optional native graphics backend** built on
[Dear ImGui](https://github.com/ocornut/imgui), selected at build time with
`./configure --experimental-graphics` (it implies "no X"):

* **macOS** — Metal + Cocoa: a native window with no X server or XQuartz.
* **Linux / Unix** — SDL3 + OpenGL3.  SDL3 selects the display transport at run
  time — **Wayland**, X11, or KMS/DRM — so there is **no hard X11 dependency**;
  it also renders **headless** via Mesa software (llvmpipe) for CI.

The classic `rc_graphic` turtle library and `rc_mouse` are ported onto it, so
existing Pop-11 graphics code runs unchanged.  Graphics are strictly **opt-in**:
the default build (and `nix build .#poplog`) is console-only.

| `rc_graphic` turtle on macOS (Metal) | Headless render on Linux (SDL3 + llvmpipe, no display) |
| :---: | :---: |
| ![macOS native graphics](docs/images/graphics-macos.png) | ![Linux headless graphics](docs/images/graphics-linux-headless.png) |

The right-hand image was rendered on Linux with **no display, GPU, or
compositor** (`tools/validate-gfx-headless.sh`) — the reproducible CI gate for
the graphics stack.

A few runnable demos live in [`examples/`](examples/) (`pop11
examples/tenprint.p` on a graphics build) — for instance the classic
[10 PRINT](https://10print.org/) maze and "POPLOG" drawn out of small letters:

| `examples/tenprint.p` | `examples/poplog_letters.p` |
| :---: | :---: |
| ![10 PRINT maze](docs/images/ex-tenprint.png) | ![POPLOG in letters](docs/images/ex-poplog-letters.png) |

## Performance

Poplog's incremental compilers emit fast native code on every backend.  For
cross-platform and cross-language benchmark numbers (x86-64, Apple M-series,
Raspberry Pi 5, with Python and Perl baselines for context), see
**[BENCHMARKS.md](BENCHMARKS.md)**.

---

This is cleaned up version of Poplog sources, currently only
core part.  It misses binary needed for bootstrap and extensions
(packages).  Packages are in separate repository:

  https://github.com/hebisch/poplog_packages

You can find bootstrap binaries at:

  https://poplog.fricas.org/corepops

There is buildable tarball for Intel/AMD 64-bit Linux at

  http://fricas.org/~hebisch/poplog

(this build version does not include newest changes to repository).

The **AArch64 Linux** port (see the Platforms table above) is written to the
generic `armv8-a` baseline and flushes the instruction cache via
`__clear_cache`, so it ports readily to other ARM64 boards -- the main
platform-specific knob is the kernel **page size** (saved images are
page-aligned; the Pi 5 uses 16 KB pages).  See `PORTING-ARM64-LINUX-RPI5.md`
(and its "Portability to other AArch64 platforms" section) for details.

For more detailed installation instructions see INSTALL.
