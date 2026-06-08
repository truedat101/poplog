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

This is cleaned up version of Poplog sources, currently only
core part.  It misses binary needed for bootstrap and extensions
(packages).  Packages are in separate repository:

  https://github.com/hebisch/poplog_packages

You can find bootstrap binaries at:

  https://poplog.fricas.org/corepops

There is buildable tarball for Intel/AMD 64-bit Linux at

  http://fricas.org/~hebisch/poplog

(this build version does not include newest changes to repository).

An **AArch64 (ARM64) Linux** port is also available, developed and validated on
the **Raspberry Pi 5**: all four languages (Pop-11, Prolog, Common Lisp,
Standard ML) run and report errors, and all three saved images build.  It is
written to the generic `armv8-a` baseline (no core-specific tuning) and flushes
the instruction cache via `__clear_cache`, so it should port readily to other
AArch64 Linux boards (e.g. MediaTek Genio, Qualcomm Snapdragon) -- the main
platform-specific knob is the kernel **page size** (saved images are
page-aligned; the Pi 5 uses 16 KB pages).  See `PORTING-ARM64-LINUX-RPI5.md`
(and its "Portability to other AArch64 platforms" section) for details.

For more detailed installation instructions see INSTALL.
