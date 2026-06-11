#!/usr/bin/env python3
"""Python baseline for tools/bench-poplog.p -- same seven workloads.

Mapping caveats (documented, not hidden):
  * nfib29       -- identical recursion; measures call overhead.
  * intloop10M   -- Python ints are boxed objects, like Pop items; fair.
  * lists        -- cons==2-tuples chained, traversal applies a function.
  * compile500   -- compile() of an equivalent small function source;
                    Python's compile is to bytecode, Pop's to machine code
                    (Pop does MORE work here, which makes its numbers more
                    impressive, not less).
  * gc20         -- gc.collect() over a populated heap; CPython is
                    refcounted + cycle collector, Pop is a real GC --
                    closest available analogue.
  * closures1M   -- 100k closure creations x 10 calls each.
  * strings      -- doubling concat to 16K then 200 substring searches.
Times printed in CENTISECONDS to match the Pop output.
"""
import time, gc, sys

def csecs(t0): return round((time.perf_counter() - t0) * 100)

def bench(name, f):
    t0 = time.perf_counter()
    f()
    print(f"{name}: {csecs(t0)}")

sys.setrecursionlimit(100000)

def nfib(n):
    return 1 if n < 2 else nfib(n - 1) + nfib(n - 2) + 1
bench("nfib29-calls", lambda: nfib(29))

def intloop():
    s = 0
    for i in range(1, 10000001):
        s = s + i
bench("intloop10M", intloop)

def lists():
    for _ in range(200):
        l = None
        for i in range(1, 5001):
            l = (i, l)
        p = l
        while p is not None:
            _x, p = p
bench("lists", lists)

SRC = "def tmp_b_p(x):\n    x = x * 2 + 1\n    return x\n"
def compile500():
    for _ in range(500):
        compile(SRC, "<bench>", "exec")
bench("compile500", compile500)

keep = [(1, 2) for _ in range(50000)]
def gc20():
    for _ in range(20):
        gc.collect()
bench("gc20", gc20)
del keep

def closures():
    for i in range(100000):
        c = (lambda v: lambda: v)(i)
        for _ in range(10):
            c()
bench("closures1M", closures)

def strings():
    s = "x"
    for _ in range(14):
        s = s + s
    for _ in range(200):
        s.find("zz")
bench("strings", strings)

print("bench-done python", sys.version.split()[0])
