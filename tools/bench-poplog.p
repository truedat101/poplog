;;; tools/bench-poplog.p -- Poplog micro-benchmarks, rigorous harness.
;;;
;;; Protocol (matches tools/bench-baseline.{py,pl}):
;;;   * Timer: systime() -- process CPU time, centiseconds.  All three engines
;;;     measure CPU TIME (Pop systime, Python process_time, Perl times), so the
;;;     metric is aligned AND robust to background load.  (Poplog's wall-clock
;;;     sys_microtime is unreliable on the Darwin port -- see bench docs.)
;;;   * Auto-calibration: each workload is repeated K times per timed batch,
;;;     K chosen so one batch >= BENCH_MINTIME (default 2 s) of CPU time -- so
;;;     the 10 ms systime resolution is a small fraction of each batch.
;;;   * WARMUP batches discarded, then RUNS timed batches recorded.
;;;   * Emits one machine-readable line per timed batch:
;;;         SAMPLE <workload> <batch-microseconds> <iterations-K>
;;;     (microseconds are exact integers: centiseconds x 10000).  CALIB/META
;;;     lines too.  tools/bench-aggregate.py turns these into median / 95% CI /
;;;     IQR / min statistics, per-iteration.
;;;
;;; Run:  <poplog-wrapper> <engine> < tools/bench-poplog.p
;;; Tunables via environment: BENCH_RUNS, BENCH_WARMUP, BENCH_MINTIME (seconds).

;;; never wrap output lines (the META line is long; tabs push it past the
;;; default ~78-column width, which would split a key=value field)
1000000 -> poplinewidth;

lvars
    RUNS       = strnumber(systranslate('BENCH_RUNS')    or '') or 30,
    WARMUP     = strnumber(systranslate('BENCH_WARMUP')  or '') or 3,
    MINTIME_CS = round((strnumber(systranslate('BENCH_MINTIME') or '') or 2.0) * 100);
        ;;; calibration target in centiseconds of CPU time

define lconstant now_cs(); systime() enddefine;

;;; run procedure p, k times
define lconstant runk(p, k);
    lvars procedure p, k;
    repeat k times p() endrepeat;
enddefine;

;;; choose K so one batch of k iterations takes >= MINTIME_CS centiseconds CPU
define lconstant calibrate(p) -> k;
    lvars procedure p, k = 1, t0, t1;
    repeat
        now_cs() -> t0;
        runk(p, k);
        now_cs() -> t1;
        quitif(t1 - t0 >= MINTIME_CS or k >= 100000000);
        ;;; grow K toward the target from the measured rate (min 2x, avoid 0)
        max(k * 2, k * (MINTIME_CS + 1) div max(t1 - t0, 1)) -> k;
    endrepeat;
enddefine;

;;; calibrate, warm up, then emit RUNS samples (batch us + K) for workload -name-
define lconstant measure(name, p);
    lvars name, procedure p, k, run, t0, t1;
    calibrate(p) -> k;
    repeat WARMUP times now_cs() -> t0; runk(p, k); now_cs() -> endrepeat;
    pr('CALIB\t'); pr(name); pr('\t'); pr(k); pr(newline);
    for run from 1 to RUNS do
        now_cs() -> t0;
        runk(p, k);
        now_cs() -> t1;
        ;;; batch microseconds (centiseconds x 10000) and K -- exact integers
        pr('SAMPLE\t'); pr(name); pr('\t'); pr((t1 - t0) * 10000);
        pr('\t'); pr(k); pr(newline);
    endfor;
enddefine;

;;; ---------------- workloads (one iteration = one full unit of work) --------

;;; 1. procedure-call cost: naive doubly-recursive nfib(29) ~ 1.35M calls
define lconstant nfib(n);
    if n < 2 then 1 else nfib(n - 1) + nfib(n - 2) + 1 endif
enddefine;
define lconstant w_nfib(); nfib(29) -> ; enddefine;

;;; 2. tight integer loop, 10M iterations
define lconstant w_intloop();
    lvars i, s = 0;
    for i from 1 to 10000000 do s + i -> s endfor;
enddefine;

;;; 3. list allocation + traversal (GC pressure): ~1M cons cells / iteration
define lconstant w_lists();
    lvars i, l;
    repeat 200 times
        [] -> l;
        for i from 1 to 5000 do conspair(i, l) -> l endfor;
        applist(l, identfn); erasenum(5000);
    endrepeat;
enddefine;

;;; 4. runtime compilation: 500 procedure compiles to MACHINE CODE / iteration
define lconstant w_compile();
    repeat 500 times
        pop11_compile([define lconstant tmp_b_p(x); x * 2 + 1; enddefine;])
    endrepeat;
enddefine;

;;; 5. explicit GC over a populated heap: 20 full GCs / iteration
;;;    (the 50k live pairs are held in -gc_heap- for the duration only)
lvars gc_heap = false;
define lconstant w_gc();
    repeat 20 times sysgarbage() endrepeat;
enddefine;

;;; 6. closure create + call: 100k closures x 10 calls = 1M calls / iteration
define lconstant w_closures();
    lvars i, c;
    for i from 1 to 100000 do
        identfn(% i %) -> c;
        repeat 10 times c() -> endrepeat;
    endfor;
enddefine;

;;; 7. string build (double 14x -> 16K) + 200 substring searches / iteration
define lconstant w_strings();
    lvars i, s = 'x';
    repeat 14 times s <> s -> s endrepeat;
    for i from 1 to 200 do issubstring('zz', s) -> endfor;
enddefine;

;;; ---------------- driver ---------------------------------------------------

pr('META\tengine=poplog\tversion='); pr(pop_internal_version);
pr('\truns='); pr(RUNS); pr('\twarmup='); pr(WARMUP);
pr('\tmintime_cs='); pr(MINTIME_CS); pr('\ttimer=systime-cpu\tresolution_us=10000');
pr(newline);

measure('nfib29',     w_nfib);
measure('intloop10M', w_intloop);
measure('lists',      w_lists);
measure('compile500', w_compile);

[% repeat 50000 times conspair(1, 2) endrepeat %] -> gc_heap;
measure('gc20', w_gc);
[] -> gc_heap;

measure('closures1M', w_closures);
measure('strings',    w_strings);

pr('bench-done poplog'); pr(newline);
