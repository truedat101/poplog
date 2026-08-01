---
name: pop11
description: Persistent Pop-11 scripting sessions — define native-compiled helpers once, fire repeat tasks at microsecond cost, checkpoint/restore session state across restarts. Use for repeated tasks in long sessions, compute-heavy scripting, and live incremental development of helper procedures.
---

# Pop-11 persistent scripting sessions

Pop-11 (Poplog) is an incrementally-compiled language: every `define` is
compiled to **native machine code** in ~10 µs, and the session's whole heap
(state + compiled procedures) can be **saved to a ~200 KB image and restored
in ~8 ms**. This skill keeps ONE live Pop-11 session running across your tool
calls, so instead of paying interpreter startup + imports + re-definition on
every scripted task, you define helpers once and each later task costs
~1–2 ms.

**Use this skill when** a session involves repeated similar tasks (scan these
logs each time X happens; recompute this report; transform each batch),
compute-heavy scripting (recursion, tight loops — Pop-11 runs 3–7× faster
than CPython on these), or when the user asks for Pop-11 / Poplog.
**Prefer plain Python** for one-off glue needing rich libraries (JSON APIs,
images, data science) — Pop-11 has no JSON/image libraries yet.

## Setup

**Usually none.** If this skill was installed by `install.sh` (or the curl
one-liner), the engine location is already persisted in
`~/.cache/pop11-skill/config.json` and `popsession` finds it automatically —
do NOT hunt for a Poplog install or set any environment variable; just run
`popsession start`. If that fails with "cannot find a built Poplog tree",
only then point it at a make-built checkout (a tree containing `./poplog`
and `./target/pop/basepop11` — note: NOT the layout of classic V16 installs):

```sh
popsession start --poplog-root /path/to/built/poplog-checkout
```

(or `export POPLOG_ROOT=...`). All commands below live in this skill's
`bin/` directory.

## The session lifecycle

```sh
popsession start                          # boot the live session (~50 ms)
popsession send -c 'CODE'                 # run a chunk (also: -f file.p, or stdin)
popsession send -f helpers.p              # good pattern: write a .p file, send it
popsession checkpoint /path/state.psv     # hibernate-able snapshot (~200 KB)
popsession restore  /path/state.psv       # new session with all state + compiled procs
popsession status | stop
```

Everything you `define` or assign persists between `send`s. Exit code 1 means
the chunk raised a mishap (Pop-11 error) — the diagnostics (with file/line)
are printed and **the session survives**; fix the code and resend. One-shot
scripts (no session) run with `pop11run file.p` or `pop11run -c 'code'`.

**Workflow: define helpers early, then call them.** First send a chunk of
`define`s for the session's recurring work; subsequent sends are one-line
calls. Redefining a procedure mid-session is instant and affects all later
calls — iterate on a helper freely. Checkpoint before risky work or at
milestones; `restore` rolls the whole session back.

## Pop-11 crash course (what you need to write correct chunks)

```pop11
;;; comments start with three semicolons
vars x = 5;                       ;;; global variable (lvars inside procedures)
x + 1 -> x;                       ;;; ASSIGNMENT POINTS RIGHT: value -> variable
npr('text');                      ;;; print line;  x =>  prints "** value" (debug)
npr('n=' sys_>< x);               ;;; sys_>< concatenates anything into a string

define double(n);                 ;;; procedures: result = last expression value
    n * 2                         ;;; (no `return`; value left on the stack)
enddefine;

define pair();  1; 2;  enddefine; ;;; multiple results: leave several values
pair() -> b -> a;                 ;;; collect in reverse (b=2, a=1)

if x > 3 then npr('big') elseif x = 3 then npr('=') else npr('small') endif;
for i from 1 to 10 do ... endfor;
repeat ... quitif(cond); ... endrepeat;
while cond do ... endwhile;

'a string'                        ;;; single quotes = string
"aword"                           ;;; double quotes = word (symbol) — NOT a string
[1 2 3]                           ;;; list;  hd(l), tl(l), length(l), l(2) indexes
{1 2 3}                           ;;; vector
newproperty([], 50, false, true) -> tbl;   ;;; hash table: tbl(key) / val -> tbl(key)
```

File and process idioms:

```pop11
;;; read a file line by line
vars dev = sysopen('/path/file', 0, "line");
vars rep = line_repeater(dev, inits(1024));      ;;; NB: 1024 = max line length
vars line;
repeat
    rep() -> line;
    quitif(line == termin);
    if issubstring('ERROR', 1, line) then ... endif;
endrepeat;

sysobey('ls /tmp > /tmp/out');                   ;;; run a shell command
vars r = sys_obey_linerep('curl -s URL | jq -r ".field"');  ;;; stream cmd output
;;; r() yields lines until termin — the zero-dependency JSON/HTTP bridge
```

Common mishap decoder: `DECLARING VARIABLE x` (warning: you used an undefined
name — usually a typo or missing define); `NUMBER(S) NEEDED` (arithmetic on a
non-number, often that undef); `STRING NEEDED` (passed a word `"x"` where a
string `'x'` was expected — check quote type); `MISHAP ... INCORRECT DEFINE
SYNTAX` (check header parentheses and `enddefine`). Every closing keyword is
required: `endif`, `endfor`, `endwhile`, `enddefine`, `endrepeat`.

## HTTPS: popcurl (native) or curl CLI

```sh
build-popcurl        # once: compiles the libcurl shim, generates the loader
```

```pop11
load '~/.cache/pop11-skill/popcurl.p';       ;;; expand ~ to $HOME yourself
http_get('https://example.com/', '/tmp/page.html') -> status;   ;;; 200
http_post(url, body, 'application/json', '/tmp/resp.json') -> status;
```

If there's no C compiler, fall back to `sysobey('curl -s ... -o file')` or
`sys_obey_linerep` — same capability, one extra process.

## JSON

No native JSON library yet. Bridge via `jq`:
`sys_obey_linerep('jq -r ".path[]" /file.json')` and consume lines. Write
complex jq programs to a file (`jq -f prog.jq`) to avoid shell-quoting pain.

## Caveats

- Send chunks via `-f file.p` when they contain quotes — avoids shell escaping.
- `line_repeater`'s buffer truncates longer lines; size `inits(n)` generously.
- Words vs strings (`"x"` vs `'x'`) is the #1 beginner error.
- The session is single-threaded; a long-running chunk blocks later sends
  (use `--timeout` on sends that may run long).
- Checkpoint images restore heap state, not open files/network handles.
