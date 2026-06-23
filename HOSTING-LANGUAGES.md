# Hosting a New Language on Poplog — Recipe & Reference

> **Scope.** How to add a new language (a tiny FORTH, a specialised Prolog, a DSL)
> *on top of* Poplog: the architecture that makes it cheap, the three effort
> tiers, the actual API to target, and where the canonical guidance lives.
>
> This is the mirror image of [`PORTING-POPLOG.md`](PORTING-POPLOG.md): **porting**
> works *below* the Poplog VM (a new CPU/OS); **hosting a language** works *above*
> it (a new front-end). Crucially, the two never meet — a hosted language is
> **platform-neutral** and inherits every port (x86-64, the AArch64/RPi5 port,
> any future RISC-V/macOS port) **for free, with zero assembly or codegen work.**

---

## 1. The big idea: target the VM, not the metal

Poplog is, at heart, a **language toolkit**. The four shipped languages (Pop-11,
Prolog, Common Lisp, Standard ML) are *all* front-ends over one shared engine.
You write your language in **Pop-11**, as: a **reader** → a **parser** → calls to
the **VM-builder procedures** that *plant* abstract VM instructions. The Poplog
VM does the rest.

What you get **for free** by planting VM code instead of emitting machine code:

- **Native code generation** (via exactly the runtime code generator, `ass.p`,
  that the ports implement — your language is compiled, not just interpreted),
- the **garbage collector**, the **open stack**, **closures**, **recursion**,
- the **incremental compiler**, the **dynamic linker / external interface**,
- the **REPL**, **saved-image** building, and **subsystem switching**.

### The VM-builder API (`pop/src/vm_plant.p`, `vm_control.p`; doc: REF VMCODE)

About 40 procedures. The ones you use constantly:

| Plant… | Procedure |
|---|---|
| a literal constant | `sysPUSHQ(item)` |
| the value of a variable | `sysPUSH(word)` |
| pop into a variable | `sysPOP(word)` |
| call a named procedure | `sysCALL(word)` |
| call a literal procedure | `sysCALLQ(item)` |
| start / end a procedure | `sysPROCEDURE(pdprops, nargs)` … `sysENDPROCEDURE()` → *the compiled procedure* |
| locals / dynamic locals | `sysLVARS`, `sysLOCAL`, `sysNEW_LVAR` |
| control flow | `sysLABEL`, `sysNEW_LABEL`, `sysGOTO`, `sysIFSO`, `sysIFNOT`, `sysGO_ON`, `sysAND`, `sysOR` |
| permanent assignment | `sysPASSIGN(item, token)` |
| compile + run a planted form | `sysCOMPILE`, `sysEXECUTE` |
| install a syntax/macro word | `sysSYNTAX` |

**The whole model in eight lines** — build, *at run time*, the equivalent of
`define add1(x); x fi_+ 1 enddefine`:

```pop11
vars add1;
sysPROCEDURE(false, 1);      ;;; begin a 1-arg procedure (the arg arrives on the stack)
    sysPUSHQ(1);             ;;;   push the literal 1      -> stack:  x  1
    sysCALL("fi_+");         ;;;   fast integer add        -> stack:  x+1
sysENDPROCEDURE() -> add1;   ;;; add1 is now a real, native, GC-managed procedure
add1(41) =>                  ;;; ** 42
```

Your compiler is just *"walk the parse tree, emit the right `sys…` calls."*
(Exact argument forms for each procedure are in **REF VMCODE**.)

### The reader you can reuse or replace

The Pop-11 **itemiser** (`incharitem` over `proglist`; doc: REF POPCOMPILE) gives
you tokenising with a customisable character table — reuse it (FORTH:
whitespace-delimited words map straight onto it) or write your own reader
(Prolog ships its own operator-precedence reader). Either way it feeds your
parser.

---

## 2. Three effort tiers

| Tier | What you get | Effort |
|---|---|---|
| **1. Embedded interpreter** | A plain Pop-11 program: a dictionary + an eval loop, running *inside* Pop-11. No VM compilation. | **days** |
| **2. VM-compiling front-end** | Parse → plant `sys…` code → genuinely native-compiled definitions, closures, recursion, full interop with Pop-11 and the other languages. *The Poplog way.* | **~1–3 weeks** (small language) |
| **3. Full subsystem** | Tier 2 + a registered subsystem: its own REPL, file extension, prompt, banner, and a saved image `mylang.psv`; `poplog mylang` and live subsystem-switching. | **+1–3 days** of mostly-boilerplate |

Tiers stack: get tier 1 working as a throwaway, grow it into tier 2, then wrap
tier 3 around it.

---

## 3. Tier 3 — registering a subsystem (doc: REF SUBSYSTEM)

A subsystem is a record in `sys_subsystem_table` with fields `SS_NAME` (word),
`SS_FILE_EXTN`, `SS_PROMPT`, `SS_TITLE`, `SS_SEARCH_LISTS`, and `SS_PROCEDURES`.
`SS_PROCEDURES` is an 8-slot procedure vector in this fixed order (the Lisp
template, `pop/lisp/src/subsystem_procedures.p`):

```pop11
constant myforth_subsystem_procedures =
    {% forth_compile,    ;;; SS_COMPILER   <- the only substantial one
       identfn,          ;;; SS_RESET       (between top-level reads)
       identfn,          ;;; SS_SETUP       (on startup)
       Forth_banner,     ;;; SS_BANNER
       identfn,          ;;; SS_INITCOMP    (compile std prelude)
       erase,            ;;; SS_POPARG1     (handle a command-line arg)
       identfn,          ;;; SS_VEDSETUP    (editor; no-op if you skip Ved)
       identfn,          ;;; SS_XSETUP      (X;     no-op if you skip graphics)
    %};
```

Only `SS_COMPILER` (your tier-2 compiler) is real work; the rest can be
`identfn`/`erase` stubs to start. Construct the subsystem record with these
fields and add it to `sys_subsystem_table` (see REF SUBSYSTEM §3 and the
templates), then provide the one-liner that switches the compiler in:

```pop11
define global macro forth;          ;;; typing `forth` at a Pop-11 prompt enters it
    "forth" -> sys_compiler_subsystem(`c`);
enddefine;
```

Build the image the same way the language images are built (a `mkimage` invocation
loading your sources, `-install ... mylang.psv`; cf. the `clisp`/`prolog`/`pml`
Makefile rules).

---

## 4. Worked sketches

### Tiny FORTH — the easiest possible target
FORTH is a stack language and **Poplog *is* a stack machine**, so the impedance is
near zero:

- The FORTH **data stack** *is* Poplog's open stack. `dup`, `swap`, `drop`(`erase`),
  `+`(`fi_+`) are Pop-11 built-ins — primitive words are ~one line each.
- A **colon definition** `: sq dup * ;` compiles to a procedure: `sysPROCEDURE(false,0)`,
  then for each body word a `sysCALL(word)` (or `sysPUSHQ` for a literal), then
  `sysENDPROCEDURE()` → store in the word's dictionary entry.
- The **dictionary** maps onto Pop-11 **identifiers** (each word is an ident
  holding its procedure).
- **`IMMEDIATE`** words (compile-time actions: `IF`/`THEN`, `DO`/`LOOP`) map onto
  Poplog **syntax words** (`sysSYNTAX` / the macro mechanism) — exactly the
  compile-vs-execute duality Poplog already has.

Tier 1 in a day or two; a compiled tier-2/3 FORTH subsystem (REPL, control words,
an image) in **~1–2 weeks**.

### A specialised Prolog variant — the biggest head start
Prolog already exists and is itself **51 Pop-11 files** (`pop/plog/src/`: the
reader, term representation, unification, the clause database, the WAM glue).
Two routes:

- **Extend the shipped Prolog** — add built-ins, operators, directives:
  **hours to days**, because it is open Pop-11 you just add to.
- **A real variant** — reuse the term reader + unification + clause store, swap
  the **control** (different search order, tabling/memoisation, CLP, a custom
  resolution rule): **days to a few weeks**, scaling with how much of the engine
  you replace. `prolog_subsystem_procedures.p` and `plogcore.p` are the templates.

---

## 5. Where the guidance lives

| Need | Source |
|---|---|
| The VM instruction set / `sys…` API | **`pop/ref/vmcode`** (REF VMCODE) — *the* document for compiling to Poplog |
| The subsystem mechanism (`SS_*`, registration) | **`pop/ref/subsystem`** (REF SUBSYSTEM); overview in `HELP SUBSYSTEMS` |
| The compiler / reader interface (`proglist`, itemiser) | **`pop/ref/popcompile`** (REF POPCOMPILE) |
| Worked templates | the four shipped subsystems: `pop/lisp/`, `pop/pml/`, `pop/plog/` (each = a `*_subsystem_procedures` file + a compiler + a `mkimage` rule) |
| Design rationale | the classic "Poplog two-level VM" literature (Gibson / Sloman) |

---

## 6. Where to start (checklist)

1. Read **REF VMCODE** and skim `pop/src/vm_plant.p`; try the 8-line `add1`
   example above at a live Pop-11 prompt to confirm the model.
2. Build a **tier-1 interpreter** (reader loop + dictionary) to nail the
   semantics with no compiler in the way.
3. Replace the interpreter core with **VM planting** (tier 2) — one `sys…`
   emitter per construct; definitions become real procedures.
4. Wrap a **subsystem** (tier 3) using the Lisp template in §3; stub
   `SS_*` procedures with `identfn`/`erase`, then flesh out the banner/prompt and
   build `mylang.psv`.
5. It runs unchanged on every Poplog port — no platform work.
