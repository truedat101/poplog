# AArch64 Procedure Stack-Frame Contract (derive-before-you-code)

**Purpose.** Before touching `arm64/genproc.p` again, write down the *contract*
the rest of Poplog requires a procedure stack frame to satisfy, derive it from
the architecture-independent sources, and design the AArch64 realization to
match. This is the step that was skipped at the start of the port: the arm64
backend was templated from **ARM32** (wrong: ILP32, relaxed alignment) and
patched locally, instead of from the **contract + x86_64** (right: LP64, the
other modern ABI). Everything below is sourced, not guessed.

---

## 1. The contract is defined in arch-independent code

These files define the frame and are **shared / untouched** by the port. The
backend must conform to them; they do not bend to the backend.

| Source | Defines |
|---|---|
| `syscomp/symdefs.p:479` `struct STACK_FRAME` | field order + which word the frame pointer points at |
| `syscomp/m_trans.p:214` `sp_offset` | frame slot *N* is at byte offset `N*WORD_OFFS` from SP (`WORD_OFFS=8`) |
| `syscomp/m_trans.p:223` `sp_index_opnd` | every frame local is addressed **`{SP, N*8}`** — SP is the frame pointer |
| `syscomp/m_trans.p:228` `caller_return_instr` | how `SF_RETURN_ADDR` is read/written (SP-relative `M_MOVE`, unless `M_CALLER_RETURN` is defined) |
| `syscomp/m_trans.p:242` `caller_sp_instr` | `_caller_sp = SP + sp_offset(frame_len)` — the walker steps one frame by `frame_len` words |
| `syscomp/m_trans.p:2040-2099` | computes `pd_frame_len`, `PD_GC_OFFSET_LEN`, `PD_GC_SCAN_LEN`, and **pads the frame to `STACK_ALIGN_WORDS`** |

Consumers that read frames via this contract (all shared, all currently broken
on arm64): the call-stack walkers (`errors.p` `sys_pr_message`, `control.p`,
`iscaller.p`, `caller_valof.p`, `plogcore.p`), the GC frame scan (`gccopy.p`,
`gcncopy.p`, using `PD_GC_OFFSET_LEN`/`PD_GC_SCAN_LEN`), and `_caller_sp`.

---

## 2. The canonical frame layout (LP64), byte offsets relative to SP

`struct STACK_FRAME` (grows-down, non-SPARC; `INV` = identity) declares, in
increasing address order:

```
SF_DUMMY        ;;; word 0  — "hack to double-align start rel to ptr"
SF_PROC_BASE[0] ;;; (zero-length marker)
SF_RETURN_ADDR  ;;; word 1  — return address INTO this procedure
SF_OWNER        ;;; word 2  — procedure record   <<< frame pointer points HERE (>->)
SF_LOCALS[]     ;;; word 3+ — on-stack locals (pop/non-pop stkvars, dlocals, saved regs)
```

The frame pointer is the value `_caller_sp` returns and `SP` holds during the
body. It points at **`SF_OWNER`**. Therefore, with `sp_offset(N)=N*8`:

```
   higher addresses (toward caller)
   ┌───────────────────────────────┐
   │ SF_LOCALS[k] ...              │  [SP + 8 + 8k]   saved regs / dlocals / stkvars
   │ SF_LOCALS[0]                 │  [SP + 8]
   │ SF_OWNER  (procedure record) │  [SP + 0]   <<< SP / frame pointer
   │ SF_RETURN_ADDR (into THIS pd)│  [SP - 8]
   │ SF_DUMMY (align pad)         │  [SP - 16]
   └───────────────────────────────┘
   lower addresses (toward callee)
```

Key consequences:

- **Slots are 8 bytes, packed.** Not 16. (The 16-byte slots are the bug.)
- **SP *is* the frame pointer.** No separate FP register is required by the
  contract; locals are `[SP, #N*8]`.
- `SF_OWNER` at `[SP+0]`; `SF_RETURN_ADDR` at `[SP-8]`; `SF_DUMMY` at `[SP-16]`
  (the negative slots sit in the callee's region — they are filled at the
  caller↔callee boundary, see §4).
- `SF_LOCALS` grow **upward** from `[SP+8]` (they were pushed *before* the owner,
  which is pushed last and lands lowest).

---

## 3. Alignment is already solved by the shared code — for free

`m_trans.p:2065-2095`, active because arm64 `sysdefs.p` sets
`STACK_ALIGN_BITS = 128`:

```
STACK_ALIGN_WORDS = STACK_ALIGN_BITS div WORD_BITS   ;;; = 128/64 = 2 words = 16 bytes
pad = pd_frame_len rem STACK_ALIGN_WORDS
;;; if pad /= 0: add (STACK_ALIGN_WORDS - pad) non-pop stkvars, bump pd_frame_len,
;;; PD_GC_OFFSET_LEN, and the offsets of pop on-stack lvars.
```

So **`pd_frame_len` is already rounded to an even number of 8-byte words = a
16-byte multiple.** If the backend allocates exactly `pd_frame_len` words in one
`sub sp, sp, #(pd_frame_len*8)`, SP stays 16-aligned automatically, *and* every
`[SP, #N*8]` access is legal (SP 16-aligned; 8-byte offsets are fine on AArch64
— the ISA only requires SP itself to be 16-aligned, not the slots).

**The premise that drove the 16-byte slots — "each push must be 16 bytes for
alignment" (`genproc.p:624-626`) — is false.** Per-item 16-byte pushes were
never needed; one rounded allocation of an already-padded `pd_frame_len`
suffices. This is the central error.

---

## 4. The one genuine AArch64 difference: the return address (`bl`/LR vs `call`/stack)

This is the only place AArch64 truly differs from x86_64, and it must be
designed deliberately.

- **x86_64:** `call` pushes the return address onto the stack *before* the
  callee's prologue runs. That pushed word *is* the callee's `SF_RETURN_ADDR`
  slot. `ret` pops it. `M_CALLER_RETURN` is **not** defined, so the shared code
  reads/writes that slot SP-relative via `M_MOVE` — and it just works because
  the slot physically exists where `call` put it.
- **AArch64:** `bl` puts the return address in **LR (x30)**, nothing is pushed.
  `ret` reads LR. So the `SF_RETURN_ADDR` stack slot is **not** filled by the
  call instruction. The backend must bridge LR ↔ the `SF_RETURN_ADDR` slot so
  that (a) the frame walkers see a valid return address at `[SP-8]` of the
  callee region, and (b) returns still work.

Two viable designs (decide this explicitly):

- **(D1) Materialize the slot.** Have the prologue store LR into the
  `SF_RETURN_ADDR` slot of the frame it is establishing, and the epilog reload
  LR from it before `ret`. This makes the on-stack layout *identical* to
  x86_64, so the shared SP-relative `caller_return_instr` path is correct with
  zero backend special-casing. Cost: one extra `str`/`ldr` of LR per call,
  placed at the correct `[SP + sp_offset(SF_RETURN_ADDR + frame_len)]`.
- **(D2) Define `M_CALLER_RETURN`.** Implement the `M_CALLER_RETURN` M-op in the
  arm64 backend to read/write LR (or a dedicated saved-LR slot) instead of the
  generic SP-relative slot. Keeps the contract but routes return-address access
  through an arch hook. Cost: a new M-handler + making the walkers' assumption
  about a physical `SF_RETURN_ADDR` slot still hold (they read it SP-relative,
  so the slot must still exist for *introspection* even if `ret` uses LR).

**D1 is recommended:** it makes arm64 frames byte-for-byte match the x86_64
layout the shared code already understands, minimizing arch-specific surface.
The cost (a paired LR store/load) is exactly what AArch64 leaf/non-leaf
prologues normally do anyway (`stp x29,x30,...`).

---

## 5. What the current arm64 backend does wrong (so we know what to replace)

Measured from `charout`'s prologue and `genproc.p`:

```
;;; current arm64 (WRONG): 16-byte slots, LR and owner mis-placed
sub sp, sp, #16 ; str x30, [sp]      ;;; LR at a 16-byte slot
str x20, [sp, #-16]!                 ;;; owner at another 16-byte slot
```
Resulting frame: `owner, pad, return, pad` (doubled, mis-ordered) — vs the
contract's packed `…SF_LOCALS, SF_OWNER@SP, SF_RETURN_ADDR@SP-8`.

Specific defects, all flowing from the 16-byte-slot premise:
1. `push_operand`/`pop_operand` (`genproc.p:~631`) use `[sp,#-16]!` (16-byte).
2. `M_CREATE_SF`/`M_UNWIND_SF` push items one at a time (16-byte slots) instead
   of one rounded `sub sp` + offset stores; `M_UNWIND_SF` already needed an
   ad-hoc `sf_var_bytes` patch (commit `ab99219`) to even balance — a symptom of
   fighting the wrong model.
3. The owner and saved LR land at offsets that do not equal `field_##("SF_OWNER")`
   / `field_##("SF_RETURN_ADDR")`, so `_sframe!SF_OWNER` reads a cleared-register
   slot (`popint 0`) — the observed crash.
4. Frame-local addressing in the body is self-consistent with the 16-byte
   layout (which is why call/return + arithmetic work), but diverges from the
   shared `sp_offset` (8-byte) that `_caller_sp`, the walkers, and the GC use.

---

## 6. Target design (to implement only after this doc is agreed)

Mirror x86_64's `M_CREATE_SF`/`M_UNWIND_SF` structure, in AArch64, **8-byte
packed, SP-relative, single rounded allocation**, plus the LR bridge (D1):

Confirmed sequence (offsets are bytes from the post-allocation SP; all derived
from the shared macros, never hardcoded):

- `M_CREATE_SF` (LR=x30 holds the return-into-caller on entry):
  1. `sub sp, sp, #(pd_frame_len*8)` — one allocation; `pd_frame_len` is already
     even (§3), so SP stays 16-aligned. (`pd_frame_len` is the shared value;
     m_trans.p already padded it.)
  2. `str x30, [sp, #((pd_frame_len-1)*8)]` — fill the `SF_RETURN_ADDR` slot (D1).
  3. Store saved callee regs / dlocal slots / pop-stkvars into their `SF_LOCALS`
     slots at `[sp, #sp_offset(##_SF_LOCALS + k)]`; init pop slots to `popint 0`.
  4. Load PB (`current_pdr_label`) and `str PB, [sp, #sp_offset(0)]` (`SF_OWNER`).
- `M_UNWIND_SF` (reverse; leave LR ready, then `M_RETURN` = `ret`):
  1. `ldr x30, [sp, #((pd_frame_len-1)*8)]` — reload return address into LR.
  2. Restore saved callee regs / dlocals from their slots.
  3. Reload PB from the caller's `SF_OWNER` = `[sp, #(pd_frame_len*8)]`
     (mirrors x86_64's `movq {SP 8}, PB`, adjusted because arm64 also allocated
     the return slot).
  4. `add sp, sp, #(pd_frame_len*8)`. Then `M_RETURN` plants `ret` (uses LR).
- `push_operand`/`pop_operand`: keep them, but make them **8-byte** SP-relative
  stores into pre-computed frame offsets, *not* `[sp,#-16]!`. (Q3 confirmed they
  are only ever called from `M_CREATE_SF`/`M_UNWIND_SF`, so they can be folded
  into the single-allocation scheme rather than self-adjusting SP.)
- **Do not hardcode offsets.** Use `field_##("SF_OWNER")`,
  `field_##("SF_RETURN_ADDR")`, `##_SF_LOCALS`, and `sp_offset(...)` so the
  backend can never drift from `STACK_FRAME`.

Note `emit_stp_push`/`emit_ldp_pop` (reg save/restore via `stp`/`ldp`) already
pack 8 bytes per register in 16-aligned pairs — they are compatible and can be
reused to fill the `SF_LOCALS` register slots, as long as their offsets are
computed from `sp_offset`, not an independent `sub sp`.

### Verification ladder (each step gated on the Pi, native gdb)

1. `make stamp_srclib` still builds clean (no codegen regression).
2. `new_corepop` links; a tiny proc's prologue disassembles to the layout in §2.
3. In gdb: at any frame, `_caller_sp` → SP; `[SP+0]` is a valid procedure record
   (matches the running proc); `[SP-8]` is a code address.
4. The call-stack walk in `sys_pr_message` reads real owners → the swallowed
   exception finally **prints** (reveals the next real bug, for free).
5. `assert.p` runs to `sysexit(0)`.
6. GC of a deep call stack survives (`PD_GC_*` offsets correct).

---

## 7. Open questions — RESOLVED (on paper, from the sources)

**Q1 — D1 vs D2: use D1 (materialize the slot). Confirmed *required*, not just
preferred.** The frame walkers, GC scan, and `_caller_return` read the
`SF_RETURN_ADDR` *physical* slot SP-relative. Only the *top* frame's return
address is in LR; every deeper frame's return address can only live on the
stack. So a D2-style "route return-address access to LR" cannot serve deeper
frames or the GC — the slot must be physically filled. D1 it is.

**Q2 — exact slot: `[SP + (pd_frame_len − 1)*8]`.** `field_##("SF_OWNER") = 0`
(the `>->` point), `field_##("SF_RETURN_ADDR") = −1` (declared one word *below*
SF_OWNER), `field_##("SF_LOCALS") = +1`. `caller_return_instr` reads
`sp_index_opnd(field_##("SF_RETURN_ADDR") + frame_len) = {SP, (frame_len−1)*8}`,
and `pd_frame_len` *includes* this slot (m_trans.p:2061 adds
`− field_##("SF_RETURN_ADDR") = +1`). So the prologue stores LR at byte offset
`(pd_frame_len − 1)*8` from the post-allocation SP.

**Q2b — `_caller_sp` arithmetic is identical to x86_64.** x86: caller's `call`
pushes the 8-byte return, callee allocates `(pd_frame_len−1)` words → total SP
delta `pd_frame_len*8`. arm64 D1: callee allocates the *full* `pd_frame_len`
words (including the return slot the `bl` did not push) → same total
`pd_frame_len*8`. Either way `_caller_sp = SP + pd_frame_len*8` lands on the
caller's `SF_OWNER`. **The resulting frame is byte-identical to x86_64**; only
*who* writes the return slot differs (x86 `call` vs arm64 prologue `str x30`).
Net: the shared `caller_sp_instr`, walkers, and GC need **zero** arm64 changes.

**Q3 — no dynamic stack pushes outside `M_CREATE_SF`.** In `arm64/genproc.p`,
`push_operand`/`pop_operand` are called *only* from `M_CREATE_SF` (1671 dlocals,
1694 pop-stkvars, 1708 owner) and `M_UNWIND_SF` (1824). dlocal *value* swapping
(`Gen_dlocal_context`) reads/writes the frame slots that `M_CREATE_SF` already
allocated — it does not move SP. The Pop value stack uses x19 (USP), not SP.
**So the whole frame can be one rounded `sub sp` and SP is invariant through the
body** — exactly the precondition §3 needs.

**Q4 — `M_CALLER_RETURN` is undefined everywhere.** Only the `#_IF DEF` guard
exists (m_trans.p:230); no backend defines it. So both arches already use the
generic SP-relative `SF_RETURN_ADDR` path, and D1 (which fills that slot) needs
**no new M-op**.

**Q5 — C-call / `_call_sys` SP alignment holds.** `pd_frame_len` is padded to an
even word count (§3), so every `sub sp,#(pd_frame_len*8)` keeps SP 16-aligned;
nothing pushes 8-byte mid-body (Q3); `_call_sys` itself saves a 48-byte
(16-multiple) frame via `stp x29,x30,[sp,#-48]!`. So SP is 16-aligned at every
`bl`/`blr`/C-call boundary, as the AArch64 ABI requires.

### Net effect of these resolutions

The AArch64 backend change is **localized to `M_CREATE_SF` / `M_UNWIND_SF` /
`push_operand` / `pop_operand` in `arm64/genproc.p`** and is a faithful
transcription of x86_64's structure plus a single LR↔slot bridge. No shared
code, no new M-ops, no separate frame-pointer register, no changes to the
walkers or GC.

---

## Appendix — references

- Canonical (working) backend: `syscomp/x86_64/genproc.p` `M_CREATE_SF` (1803),
  `M_UNWIND_SF` (1859).
- Struct: `syscomp/symdefs.p:479`. Offsets/len: `m_trans.p` 214, 223, 228, 242,
  2040-2099. Alignment: the `STACK_ALIGN_BITS` block (2065).
- Current arm64: `syscomp/arm64/genproc.p` `M_CREATE_SF`, `M_UNWIND_SF`,
  `push_operand` (~631); `arm64/amisc.s` (`_SF_OWNER = @@SF_OWNER`, the walker).
