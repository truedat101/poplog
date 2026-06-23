/* --- Poplog AArch64 / macOS (Darwin, Mach-O) — platform definitions --------
 > File:     pop/src/syscomp/arm64/sysdefs_darwin.p
 > Purpose:  Machine + OS definitions for the Apple Silicon (AArch64 macOS) port.
 >
 > This is the Darwin/Mach-O ALTERNATE to `arm64/sysdefs.p` (which is AArch64
 > Linux/ELF).  popc always loads "<arch>/sysdefs.p" by fixed name
 > (make_popc.p:31), so the OS variant is chosen by SWAPPING this file in, exactly
 > as the x86_64 FreeBSD / i386 Solaris variants are.  The Darwin cross-build does
 >     cp pop/src/syscomp/arm64/sysdefs_darwin.p pop/src/syscomp/arm64/sysdefs.p
 > before building cross-popc (keep the original — it is the Linux primary).
 >
 > Everything ISA-level below is IDENTICAL to `arm64/sysdefs.p` (same AArch64
 > backend, frame contract, register plan); only the OPERATING SYSTEM section is
 > Darwin-specific.  See PORTING-ARM64-M-SILICON-OSX.md (the "same ISA, new OS"
 > axis).  ** UNVERIFIED until cross-compiled by popc on the Pi/host. **
 >
 > Companion changes this file REQUIRES (none optional — they are build-blockers):
 >   - external.ph (~line 77): add a `#_ELSEIF DEF DARWIN` branch — `.dylib`,
 >     no `-ldl` (dyld/libSystem) — else it `#_ELSE_ERROR`s (no UNIX_ELF here).
 >   - c_core.c (~line 1650): enable `_pop_brk`/`_pop_sbrk` for Darwin (today they
 >     are `#ifdef AIX`), and map the break RW — macOS forbids W^X heap pages, so
 >     drop the PROT_EXEC the AIX path uses.
 >   - asmout.p: Mach-O output (gated on UNIX_MACHO) — leading `_`, @PAGE/@PAGEOFF,
 >     `.quad`, no `.arch`.
 */

section;

global constant macro (

    POPC_SYSDEFS_LOADED = true,


;;; === SYSTEM NAME (PC) ==============================================


    MACHINE = [[pc]],

    PC = true,
    ARM64_DARWIN = true,        ;;; port symbol (cf. ARM64_LINUX)


;;; === PROCESSOR (ARM AArch64) =======================================


    PROCESSOR = [[arm64]],

    ;;; Values for machine and C data types are defined in mcdata.p,
    ;;; and can be overidden here if necessary

    WORD_BITS       = 64,

    POPINT_BITS     = 61,

    SHORT_ALIGN_BITS = 16,       ;;; alignment in bits for short access
    INT_ALIGN_BITS   = 32,       ;;; alignment in bits for int access
    DOUBLE_ALIGN_BITS = 64,      ;;; alignment in bits for double access

    STRUCT_SHORT_ALIGN_BITS = 16,   ;;; bit alignment for short
    STRUCT_INT_ALIGN_BITS   = 32,   ;;; bit alignment for int
    STRUCT_DOUBLE_ALIGN_BITS = 64,  ;;; bit alignment for double

    ;;; Stack alignment in bits (AArch64 requires 16-byte / 128-bit)
    STACK_ALIGN_BITS = 128,

    CODE_POINTER_TYPE = "byte", ;;; type of pointer to machine code
    BIT_POINTER_TYPE = "byte",  ;;; type of pointer for bitfield access


;;; === OPERATING SYSTEM (Darwin / Apple macOS, Mach-O) ==============


    UNIX = true,
    BERKELEY = 4.3,             ;;; Darwin is 4.4BSD-derived; 4.3 matches the
                                ;;; tested ports — raise only if a path needs it.
    DARWIN = 25.0,              ;;; Darwin kernel version (25 == macOS 15.x)
    UNIX_MACHO = true,          ;;; object format is Mach-O, NOT ELF
                                ;;; (the counterpart to UNIX_ELF elsewhere)
    POSIX1 = 198808,            ;;; probably later than this ...
    OPERATING_SYSTEM = [[unix darwin ^DARWIN macho posix {^POSIX1}]],

    SHARED_LIBRARIES = true,    ;;; .dylib via dyld

    BSD_MMAP  = true,           ;;; has -mmap- and -mprotect- facilities
    BSD_MPROTECT  = true,

    ;;; W xor X: macOS / Apple Silicon forbids simultaneously writable+executable
    ;;; pages.  Runtime code generation (ass.p et al.) and the GC's code-movement
    ;;; must use MAP_JIT + the write-protect toggle in pop/extern/lib/pop_jit.{c,h}.
    ;;; Forward-looking flag for that work (Phase 4); no consumer yet.
    W_XOR_X = true,

    VPAGE_OFFS = 16384,   ;;; virtual page size in bytes = the system page size.
                          ;;; Apple Silicon uses 16 KB pages (same as the Pi 5);
                          ;;; saved images are mmap'd MAP_FIXED, so the base
                          ;;; address + file offset must be system-page-aligned.

    ;;; LOWEST_ADDRESS:
    ;;; NB (Phase 3): macOS is PIE-mandatory and leaves the low region unmapped,
    ;;; so the fixed-address MAP_FIXED image load needs revisiting
    ;;; (PORTING-ARM64-M-SILICON-OSX.md Phase 3). Kept 0 for this first draft —
    ;;; matches AIX, which also uses the mmap-based break below.
    LOWEST_ADDRESS = 0,

    ;;; Procedures to get and set the memory break and return the REAL end of
    ;;; memory.  macOS has no usable sbrk/brk, so use the mmap-based
    ;;; _pop_brk/_pop_sbrk from c_core.c (must be enabled for Darwin there).

    GET_REAL_BREAK =
        [procedure(); _extern _pop_sbrk(_0)@(b.r->vpage) endprocedure],

    SET_REAL_BREAK =
        [procedure(_break) -> _break;
            lvars _break = _break@(w.r->vpage);
            if _extern _pop_brk(_break@(w->b)) == _-1 then
                _-1 -> _break
            endif
        endprocedure],

    ;;; Flush the instruction cache via the clamped C helper (c_core.c):
    ;;; IC IVAU faults on uncommitted (PROT_NONE) reserve pages, and Poplog
    ;;; flush ranges can cross them (e.g. during image restore).
    CACHEFLUSH = [
        procedure(_ptr, _nbytes);
            lvars _ptr, _nbytes;
            _extern _pop_cache_flush(_ptr, _nbytes) -> ;
        endprocedure
    ],

;;; === OTHER =========================================================

    ;;; ANSI C returns floats as single, not double
    ANSI_C = true,
    ;;; AArch64 returns a float as 32-bits in s0
    C_FLOAT_RESULT_SINGLE = true,

    ;;; list of procedures to be optimised as subroutine calls
    ;;; format of entries is
    ;;;     [<pdr name> <nargs> <nresults> <subroutine name>]

    SUBROUTINE_OPTIMISE_LIST =
        [[
            [prolog_newvar  0 1 _prolog_newvar]
            [datakey        1 1 _datakey]
            [prolog_deref   1 1 _prolog_deref]
            [conspair       2 1 _conspair]
        ]],

    ;;; Old-style I_PUSH/POP_FIELD(_ADDR) instructions in ass.p
    OLD_FIELD_INSTRUCTIONS = true,

    ;;; Include M-code listing in assembly language files
    ;;; Off (as on arm64 Linux): the M_DEBUG path can leak stack items in some
    ;;; M-handlers, producing ITEMS LEFT ON STACK mishaps.
    M_DEBUG = false,

    ;;; Result of external call may need sign extension
    SIGN_EXTEND_EXTERN = true,

);

endsection;     /* $- */
