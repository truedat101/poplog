
section;

global constant macro (

    POPC_SYSDEFS_LOADED = true,


;;; === SYSTEM NAME (PC) ==============================================


    MACHINE = [[pc]],

    PC = true,
    ;;; TEMP: keep ARM64_LINUX so the shared headers (external.ph,
    ;;; unixdefs.ph) resolve to the LP64 AArch64 branches, which are
    ;;; ABI-close to RISC-V LP64D, until proper RISCV64_LINUX branches
    ;;; are added there.  RISCV64_LINUX is the real flag for this port.
    ARM64_LINUX = true,
    RISCV64_LINUX = true,


;;; === PROCESSOR (RISC-V rv64gc, LP64D) ============================


    PROCESSOR = [[riscv64]],

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

    ;;; Stack alignment in bits (RISC-V LP64 ABI requires 16-byte / 128-bit)
    STACK_ALIGN_BITS = 128,

    CODE_POINTER_TYPE = "byte", ;;; type of pointer to machine code
    BIT_POINTER_TYPE = "byte",  ;;; type of pointer for bitfield access

    ;;; FRAME_LEN_32BIT = true,


;;; === OPERATING SYSTEM (UNIX BSD) ==================================


    UNIX = true,
    BERKELEY = 4.3,
    LINUX = 2.0,
    UNIX_ELF = true,
    POSIX1 = 198808,            ;;; probably later than this ...
    OPERATING_SYSTEM = [[unix linux ^LINUX elf posix {^POSIX1}]],

    SHARED_LIBRARIES = true,

    BSD_MMAP  = true,     ;;; has -mmap- and -mprotect- facilities
    BSD_MPROTECT  = true,

    VPAGE_OFFS = 4096,    ;;; virtual page size in bytes = the system page size.
                          ;;; Standard RISC-V Linux (Sv39/Sv48) uses 4 KB base
                          ;;; pages; saved images are mmap'd MAP_FIXED, which
                          ;;; requires base + file offset to be system-page-
                          ;;; aligned.  (Revisit if a target kernel uses a larger
                          ;;; page size, as the Pi 5's 16 KB did.)

    ;;; LOWEST_ADDRESS:
    LOWEST_ADDRESS = 0,

    ;;; Procedures to get and set the memory break and return the REAL end of
    ;;; memory. (We always need the real end to ensure that the end of the
    ;;; user stack is always at the true end of memory, so that user stack
    ;;; underflow produces a memory access violation.)

    GET_REAL_BREAK =
        [procedure(); _extern sbrk(_0)@(b.r->vpage) endprocedure],

    SET_REAL_BREAK =
        [procedure(_break) -> _break;
            lvars _break = _break@(w.r->vpage);
            if _extern brk(_break@(w->b)) == _-1 then
                _-1 -> _break
            endif
        endprocedure],

    ;;; Flush the instruction cache.
    ;;; rv_cacheflush (extern/lib/c_core.c) = fence rw,rw + __clear_cache +
    ;;; fence.i.  A bare range __clear_cache left freshly-written closure code
    ;;; stale in the i-cache on the JH7100 U74 under heavy GC address reuse
    ;;; (churned short-lived closures -> SIGILL on a valid auipc).  The leading
    ;;; fence drains the code stores to the point of unification before the
    ;;; kernel range flush, and the trailing fence.i is a local belt-and-braces.
    CACHEFLUSH = [
        procedure(_ptr, _nbytes);
            lvars _ptr, _nbytes;
            _extern rv_cacheflush(_ptr, _nbytes) -> ;
        endprocedure
    ],

;;; === OTHER =========================================================

    ;;; ANSI C returns floats as single, not double
    ANSI_C = true,
    ;;; RISC-V LP64D returns a single float as 32 bits in fa0
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
    ;;; Disabled for arm64 port: the M_DEBUG path can leak stack items in
    ;;; some M-handlers, producing ITEMS LEFT ON STACK mishaps.
    M_DEBUG = false,

    ;;; Result of external call may need sign extension

    SIGN_EXTEND_EXTERN = true,

);

endsection;     /* $- */
