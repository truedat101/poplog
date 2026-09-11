# bench-skill — session-retention benchmark (Pop-11 vs Python as an assistant scripting engine)

Validation instrument for the **Pop-11 Claude-skill** idea. The claim under
test is *not* raw speed. It is:

> An assistant that **retains a live Pop-11 session** — incrementally
> compiling helper procedures once, then firing repeat tasks at it for the
> rest of the session — beats the process-per-task scripting model, and the
> session itself (state + native-compiled code) can be **saved and restored**
> across restarts via Poplog saved images.

## What it measures

`harness.py` models a long session firing repeated small tasks in four modes:

| Mode | What it is |
|---|---|
| `py-cold` | one `python3` process per task — how assistant scripting works today |
| `py-warm` | one persistent Python exec-server on a pipe (the fair comparison) |
| `pop-cold` | one `basepop11` process per task |
| `pop-warm` | one persistent `basepop11` REPL on a pipe; definitions incrementally compiled to **native code** once, then reused; mid-session **live redefinition** also timed |

Two task profiles, repeated `--runs` times over rotating ~100 KB log slices:

* **glue** — scan a log slice (count ERROR lines) + tight sum loop + print
* **compute** — `nfib(24)` + print (call/recursion heavy)

Cold numbers are full wall-clock process lifecycles (that is what a session
actually loses); warm numbers are send→sentinel round-trips on the live pipe.
Setup (definitions + first call, which triggers autoloading) and redefinition
are reported separately for the warm modes.

## Run it

```sh
python3 tools/bench-skill/harness.py --poplog-root /path/to/built/poplog-tree \
    [--runs 40] [--json results.json]
```

`--poplog-root` needs `./poplog` (env wrapper) and `./target/pop/basepop11`.

## First collection (Apple M5-class, macOS arm64, CPython 3.14, 2026-07-31)

Median per task, 40 runs, wall-clock:

| Mode | glue | compute | setup (once) | live redefine |
|---|---|---|---|---|
| py-cold | 23.0 ms | 19.6 ms | (paid every task) | (paid every task) |
| pop-cold | 10.3 ms | 10.3 ms | (paid every task) | (paid every task) |
| py-warm | 7.5 ms | 3.2 ms | 24–27 ms | 0.08 ms |
| **pop-warm** | **1.4 ms** | **1.6 ms** | 27–32 ms | **0.06 ms** |

Modelled 1-hour session (a task every 30 s = 120 tasks): py-cold **2.4–2.8 s**,
pop-warm **0.2 s**. Retention is the big lever for *both* engines (3× for
Python, 7× for Pop-11); pop-warm is then 2–5× under py-warm, with the glue gap
mostly the compiled-native tight loop.

**Saved-image hibernation** (measured separately, same machine): a session with
compiled procedures + mutated heap state `syssave`d to a **~200 KB** `.psv`;
`basepop11 -state.psv` restored it — state intact, procedures still native —
in a **7.8 ms** total process lifecycle. A retained session survives restarts;
a warm Python process does not.

## Interpretation guide (honest edges)

* The **retention win is generic** — Python also gets 3× warmer with an
  exec-server. Pop-11's differentiators are: warm tasks are 2–5× cheaper
  still; redefinition produces *native* code at ~60 µs; and the session is
  **checkpointable** (saved images) — resume tomorrow with zero re-setup.
* The warm pipe protocol here is a benchmark instrument, not a hardened
  runtime: an error mid-chunk can desynchronise the sentinel. A production
  skill needs a framed prompt protocol with error capture.
* Per-task absolute stakes are milliseconds; the session-retention narrative
  is about *architecture* (state + compiled helpers accumulating across a
  session), not about reclaiming minutes. Engine-level numbers live in
  [BENCHMARKS.md](../../BENCHMARKS.md).
