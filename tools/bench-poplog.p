;;; tools/bench-poplog.p -- portable Poplog micro-benchmarks.
;;; Run with any Poplog:  <poplog-wrapper> <engine> < tools/bench-poplog.p
;;; Times are centiseconds (systime); each test prints "name: N".
;;; Keep workloads identical across platforms for comparability.

define lconstant bench(name, p);
    lvars name, procedure p, _t = systime();
    p();
    pr(name); pr(': '); pr(systime() - _t); pr(newline);
enddefine;

;;; 1. procedure-call cost: naive fibonacci variant, ~1.3M calls
define lconstant nfib(n);
    if n < 2 then 1 else nfib(n - 1) + nfib(n - 2) + 1 endif
enddefine;
bench('nfib29-calls', procedure(); nfib(29) -> ; endprocedure);

;;; 2. tight integer loop, no calls
bench('intloop10M', procedure();
    lvars i, s = 0;
    for i from 1 to 10000000 do s + i -> s endfor;
endprocedure);

;;; 3. list allocation + traversal (GC pressure)
bench('lists', procedure();
    lvars i, l;
    repeat 200 times
        [] -> l;
        for i from 1 to 5000 do conspair(i, l) -> l endfor;
        applist(l, identfn); erasenum(5000);
    endrepeat;
endprocedure);

;;; 4. runtime compilation: 500 procedure compiles
bench('compile500', procedure();
    repeat 500 times
        pop11_compile([define lconstant tmp_b_p(x); x * 2 + 1; enddefine;])
    endrepeat;
endprocedure);

;;; 5. explicit GC cost on a populated heap
lvars keepalive = [% repeat 50000 times conspair(1, 2) endrepeat %];
bench('gc20', procedure();
    repeat 20 times sysgarbage() endrepeat;
endprocedure);
keepalive -> ;

;;; 6. closure create + call
bench('closures1M', procedure();
    lvars i, c;
    for i from 1 to 100000 do
        identfn(% i %) -> c;
        repeat 10 times c() -> endrepeat;
    endfor;
endprocedure);

;;; 7. string building
bench('strings', procedure();
    lvars i, s = 'x';
    repeat 14 times s <> s -> s endrepeat;
    for i from 1 to 200 do issubstring('zz', s) -> endfor;
endprocedure);

pr('bench-done'); pr(newline);
