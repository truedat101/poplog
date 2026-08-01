#!/usr/bin/env python3
"""Session-retention benchmark: Pop-11 vs Python as a Claude scripting engine.

Models a long assistant session firing repeated small tasks, in four modes:

  py-cold    one python3 process per task (how Claude scripts today)
  py-warm    one persistent python exec-server, tasks sent over a pipe
  pop-cold   one basepop11 process per task
  pop-warm   one persistent basepop11 REPL, tasks sent over a pipe
             (procedures incrementally compiled to native code ONCE,
              then reused; mid-session redefinition also measured)

Two task profiles, each repeated --runs times over rotating log slices:

  glue       scan a ~100 KB log slice + tight sum loop + print summary
  compute    nfib(24) + print   (recursion/call-heavy)

The point is NOT raw speed: it is the cost of *retaining a session* versus
re-paying startup + imports + definitions on every task, and the cost of
*live redefinition* while the session stays up.

Usage:
  python3 tools/bench-skill/harness.py --poplog-root /path/to/poplog-tree \
      [--runs 40] [--workdir DIR] [--json OUT.json]

--poplog-root must contain ./poplog (env wrapper) and ./target/pop/basepop11.
Cold-mode numbers include each engine's full process lifecycle, measured
wall-clock (that is what a session actually loses). Warm-mode numbers measure
send -> sentinel round-trip on the live session's pipe.

Caveat: the warm protocol is a benchmark instrument, not a hardened runtime
(a Pop-11 mishap or Python exception mid-chunk can desynchronise the
sentinel; a production skill needs a framed prompt protocol).
"""

import argparse, json, os, random, signal, statistics, subprocess, sys, tempfile, time

SENTINEL = "__DONE__"
NSLICES = 8
LINES_PER_SLICE = 1500
SUMLOOP = 200000
NFIB_N = 24

# ---------------------------------------------------------------- data

def gen_slices(workdir):
    random.seed(42)
    paths = []
    for s in range(NSLICES):
        p = os.path.join(workdir, f"slice{s}.log")
        with open(p, "w") as f:
            for i in range(LINES_PER_SLICE):
                lvl = "ERROR" if random.random() < 0.05 else "INFO"
                f.write(f"2026-07-31T12:{i%60:02d}:{i%60:02d} {lvl} "
                        f"worker-{i%8} request id={i} latency_ms={random.randint(1,500)}\n")
        paths.append(p)
    return paths

# ---------------------------------------------------------------- chunks

POP_SETUP = """
vars ne, tot;
define scan_log(file);
    lvars dev, rep, line, nerr = 0, total = 0;
    sysopen(file, 0, "line") -> dev;
    line_repeater(dev, inits(1024)) -> rep;
    repeat
        rep() -> line;
        quitif(line == termin);
        total + 1 -> total;
        if issubstring('ERROR', 1, line) then nerr + 1 -> nerr endif;
    endrepeat;
    nerr; total;
enddefine;
define nfib(n);
    if n < 2 then 1 else nfib(n - 1) + nfib(n - 2) + 1 endif
enddefine;
scan_log('%(slice0)s') -> tot -> ne;
"""

POP_GLUE = """
vars s, i;
scan_log('%(slice)s') -> tot -> ne;
0 -> s;
for i from 1 to %(sumloop)d do s + i -> s endfor;
npr(ne sys_>< '/' sys_>< tot sys_>< ' sum=' sys_>< s);
"""

POP_COMPUTE = "npr(nfib(%(n)d));\n"

POP_REDEF = """
define scan_log(file);
    lvars dev, rep, line, nerr = 0, total = 0;
    sysopen(file, 0, "line") -> dev;
    line_repeater(dev, inits(1024)) -> rep;
    repeat
        rep() -> line;
        quitif(line == termin);
        total + 1 -> total;
        if issubstring('WARN', 1, line) or issubstring('ERROR', 1, line) then
            nerr + 1 -> nerr
        endif;
    endrepeat;
    nerr; total;
enddefine;
"""

PY_SETUP = """
def scan_log(path):
    ne = tot = 0
    with open(path) as f:
        for line in f:
            tot += 1
            if "ERROR" in line: ne += 1
    return ne, tot

def nfib(n):
    return 1 if n < 2 else nfib(n - 1) + nfib(n - 2) + 1

scan_log(%(slice0)r)
"""

PY_GLUE = """
ne, tot = scan_log(%(slice)r)
s = 0
for i in range(1, %(sumloop)d + 1): s += i
print(f"{ne}/{tot} sum={s}")
"""

PY_COMPUTE = "print(nfib(%(n)d))\n"

PY_REDEF = """
def scan_log(path):
    ne = tot = 0
    with open(path) as f:
        for line in f:
            tot += 1
            if "WARN" in line or "ERROR" in line: ne += 1
    return ne, tot
"""

PY_EXEC_SERVER = r"""
import sys, traceback
buf = []
for line in sys.stdin:
    if line.rstrip("\n") == "__EXEC__":
        try:
            exec("\n".join(buf), globals())
        except Exception:
            traceback.print_exc()
        print("__DONE__", flush=True)
        buf = []
    else:
        buf.append(line.rstrip("\n"))
"""

# ---------------------------------------------------------------- engines

def poplog_env(poplog_root):
    wrapper = os.path.join(poplog_root, "poplog")
    out = subprocess.run([wrapper, "/usr/bin/env"], capture_output=True,
                         text=True, check=True).stdout
    env = dict(os.environ)
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            env[k] = v
    return env


class WarmSession:
    """A persistent engine on a pipe with a sentinel round-trip protocol."""

    def __init__(self, argv, env, wrap_chunk):
        self.p = subprocess.Popen(argv, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT,
                                  env=env, text=True, bufsize=1)
        self.wrap = wrap_chunk

    def send(self, code, timeout=30):
        t0 = time.perf_counter()
        self.p.stdin.write(self.wrap(code))
        self.p.stdin.flush()
        signal.alarm(timeout)
        try:
            while True:
                line = self.p.stdout.readline()
                if not line:
                    raise RuntimeError("engine died mid-task")
                if line.strip() == SENTINEL:
                    break
        finally:
            signal.alarm(0)
        return (time.perf_counter() - t0) * 1000

    def close(self, quit_code):
        try:
            self.p.stdin.write(quit_code)
            self.p.stdin.flush()
            self.p.wait(timeout=10)
        except Exception:
            self.p.kill()


def pop_warm(basepop, env):
    return WarmSession([basepop], env,
                       lambda c: c + f"\nnpr('{SENTINEL}'); sysflush(popdevout);\n")


def py_warm(server_path):
    return WarmSession([sys.executable, "-u", server_path], None,
                       lambda c: c + "\n__EXEC__\n")


def timed_run(argv, env=None):
    t0 = time.perf_counter()
    r = subprocess.run(argv, capture_output=True, env=env)
    dt = (time.perf_counter() - t0) * 1000
    if r.returncode != 0:
        raise RuntimeError(f"cold task failed: {argv}\n{r.stderr[:400]}")
    return dt

# ---------------------------------------------------------------- benchmark

def stats(ts):
    ts = sorted(ts)
    return {"median": statistics.median(ts),
            "p95": ts[min(len(ts) - 1, int(len(ts) * 0.95))],
            "min": ts[0], "total": sum(ts)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--poplog-root", default=os.environ.get("POPLOG_ROOT"))
    ap.add_argument("--runs", type=int, default=40)
    ap.add_argument("--workdir")
    ap.add_argument("--json")
    args = ap.parse_args()
    if not args.poplog_root:
        sys.exit("need --poplog-root or $POPLOG_ROOT (tree with ./poplog and ./target/pop/basepop11)")

    basepop = os.path.join(args.poplog_root, "target", "pop", "basepop11")
    env = poplog_env(args.poplog_root)
    workdir = args.workdir or tempfile.mkdtemp(prefix="bench-skill-")
    os.makedirs(workdir, exist_ok=True)
    slices = gen_slices(workdir)
    signal.signal(signal.SIGALRM,
                  lambda *a: (_ for _ in ()).throw(TimeoutError("engine hung")))

    subst = {"slice0": slices[0], "sumloop": SUMLOOP, "n": NFIB_N}
    tasks = {"glue": (POP_GLUE, PY_GLUE), "compute": (POP_COMPUTE, PY_COMPUTE)}

    # cold-mode script files, one per slice per task type
    cold = {}
    for tname, (ptmpl, pytmpl) in tasks.items():
        for i, sl in enumerate(slices):
            s = dict(subst, slice=sl)
            pp = os.path.join(workdir, f"{tname}{i}.p")
            with open(pp, "w") as f:
                f.write(POP_SETUP % s + ptmpl % s + "sysexit();\n")
            py = os.path.join(workdir, f"{tname}{i}.py")
            with open(py, "w") as f:
                f.write(PY_SETUP % s + pytmpl % s)
            cold[(tname, i, "pop")] = pp
            cold[(tname, i, "py")] = py
    server = os.path.join(workdir, "exec_server.py")
    with open(server, "w") as f:
        f.write(PY_EXEC_SERVER)

    results = {"machine": os.uname().machine, "runs": args.runs, "modes": {}}
    R = args.runs

    for tname, (ptmpl, pytmpl) in tasks.items():
        print(f"\n=== task: {tname} (x{R}) ===")
        m = {}

        m["py-cold"] = stats([timed_run([sys.executable, cold[(tname, i % NSLICES, "py")]])
                              for i in range(R)])
        m["pop-cold"] = stats([timed_run([basepop, cold[(tname, i % NSLICES, "pop")]], env)
                               for i in range(R)])

        s = py_warm(server)
        setup_ms = s.send(PY_SETUP % subst)
        m["py-warm"] = stats([s.send(pytmpl % dict(subst, slice=slices[i % NSLICES]))
                              for i in range(R)])
        m["py-warm"]["setup"] = setup_ms
        m["py-warm"]["redef"] = s.send(PY_REDEF)
        s.close("__EXEC__\n")

        s = pop_warm(basepop, env)
        setup_ms = s.send(POP_SETUP % subst)
        m["pop-warm"] = stats([s.send(ptmpl % dict(subst, slice=slices[i % NSLICES]))
                               for i in range(R)])
        m["pop-warm"]["setup"] = setup_ms
        m["pop-warm"]["redef"] = s.send(POP_REDEF)
        s.close("sysexit();\n")

        results["modes"][tname] = m
        print(f"{'mode':10s} {'median':>9s} {'p95':>9s} {'min':>9s} {'total':>10s} {'setup':>8s} {'redef':>8s}")
        for mode, st in m.items():
            extra = (f"{st['setup']:7.1f}ms {st['redef']:7.2f}ms"
                     if "setup" in st else f"{'—':>8s} {'—':>8s}")
            print(f"{mode:10s} {st['median']:8.2f}ms {st['p95']:8.2f}ms "
                  f"{st['min']:8.2f}ms {st['total']:9.1f}ms {extra}")

    # one-hour model: a task every 30 s => 120 tasks
    print("\n=== modelled 1-hour session (120 tasks, per profile) ===")
    print(f"{'mode':10s} {'glue':>12s} {'compute':>12s}")
    for mode in ("py-cold", "py-warm", "pop-cold", "pop-warm"):
        row = []
        for tname in tasks:
            st = results["modes"][tname][mode]
            total = st["median"] * 120 + st.get("setup", 0)
            row.append(f"{total/1000:10.2f} s")
        print(f"{mode:10s} {row[0]:>12s} {row[1]:>12s}")

    if args.json:
        with open(args.json, "w") as f:
            json.dump(results, f, indent=1)
        print(f"\nresults -> {args.json}")
    print(f"workdir: {workdir}")


if __name__ == "__main__":
    main()
