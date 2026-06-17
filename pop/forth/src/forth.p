/* --- A Forth for Poplog ------------------------------------------------
 > File:        pop/forth/src/forth.p
 > Purpose:     A Forth where colon-definitions transpile to native Pop-11
 >              procedures (real machine code via the Poplog compiler).
 >
 > Forth's data stack IS the Poplog user stack, so Forth words are just
 > open-stack Pop-11 procedures.  `: name ... ;` builds Pop-11 source for the
 > body and pop11_compiles it -> a native procedure installed in the dict.
 > Control words (if/else/then, begin/until/while/repeat, recurse) map to
 > Pop-11 control constructs; the Forth flag (-1/0) gates them via f_flagtrue.
 */

compile_mode :pop11 +strict;

vars forth_proc;     ;;; word -> procedure         (execution)
vars forth_pname;    ;;; word -> pop11 src name     (compilation of colon-defs)
vars forth_toks;     ;;; remaining token list
vars forth_gensym;
newproperty([], 300, false, "perm") -> forth_proc;
newproperty([], 300, false, "perm") -> forth_pname;
0 -> forth_gensym;

;;; ---- primitives: open-stack Pop-11 procedures ----
define f_dup(x);    x, x          enddefine;
define f_drop(x);                 enddefine;
define f_swap(x,y); y, x          enddefine;
define f_over(x,y); x, y, x       enddefine;
define f_rot(x,y,z); y, z, x      enddefine;
define f_nip(x,y);  y             enddefine;
define f_tuck(x,y); y, x, y       enddefine;
define f_2dup(x,y); x, y, x, y    enddefine;
define f_2drop(x,y);              enddefine;
define f_qdup(x);   if x /== 0 then x, x else x endif enddefine;
define f_depth();   stacklength() enddefine;

define f_plus(x,y);   x + y   enddefine;
define f_minus(x,y);  x - y   enddefine;
define f_times(x,y);  x * y   enddefine;
define f_div(x,y);    x div y enddefine;
define f_mod(x,y);    x mod y enddefine;
define f_negate(x);   negate(x) enddefine;
define f_1plus(x);    x + 1   enddefine;
define f_1minus(x);   x - 1   enddefine;
define f_2times(x);   x * 2   enddefine;
define f_2div(x);     x div 2 enddefine;
define f_abs(x);      abs(x)  enddefine;
define f_min(x,y);    min(x,y) enddefine;
define f_max(x,y);    max(x,y) enddefine;

;;; comparisons push the Forth flag -1 (true) / 0 (false)
define f_eq(x,y);  if x =  y then -1 else 0 endif enddefine;
define f_ne(x,y);  if x =  y then 0 else -1 endif enddefine;
define f_lt(x,y);  if x <  y then -1 else 0 endif enddefine;
define f_gt(x,y);  if x >  y then -1 else 0 endif enddefine;
define f_le(x,y);  if x <= y then -1 else 0 endif enddefine;
define f_ge(x,y);  if x >= y then -1 else 0 endif enddefine;
define f_0eq(x);   if x =  0 then -1 else 0 endif enddefine;
define f_0lt(x);   if x <  0 then -1 else 0 endif enddefine;
define f_0gt(x);   if x >  0 then -1 else 0 endif enddefine;

;;; bitwise (also serve as flag logic)
define f_and(x,y);  x && y          enddefine;
define f_or(x,y);   x || y          enddefine;
define f_xor(x,y);  (x || y) &&~~ (x && y) enddefine;
define f_invert(x); ~~x             enddefine;

;;; control-flow flag test (pops Forth flag, gives a Pop-11 boolean)
define f_flagtrue(x); x /== 0 enddefine;

;;; I/O
define f_dot(x);   pr(x); cucharout(`\s`) enddefine;  ;;; print + space
define f_cr();     cucharout(`\n`)    enddefine;
define f_emit(x);  cucharout(x)       enddefine;     ;;; char code
define f_space();  cucharout(`\s`)    enddefine;
define f_dots();
    lvars n = stacklength(), i;
    pr('<'); pr(n); pr('> ');
    fast_for i from n by -1 to 1 do pr(subscr_stack(i)); pr(`\s`) endfor;
enddefine;

;;; ---- dictionary registration ----
define forth_prim(name, p, pname);
    lvars name, p, pname, w = consword(name);
    p -> forth_proc(w);
    pname -> forth_pname(w);
enddefine;

forth_prim('dup',f_dup,'f_dup');        forth_prim('drop',f_drop,'f_drop');
forth_prim('swap',f_swap,'f_swap');     forth_prim('over',f_over,'f_over');
forth_prim('rot',f_rot,'f_rot');        forth_prim('nip',f_nip,'f_nip');
forth_prim('tuck',f_tuck,'f_tuck');     forth_prim('2dup',f_2dup,'f_2dup');
forth_prim('2drop',f_2drop,'f_2drop');  forth_prim('?dup',f_qdup,'f_qdup');
forth_prim('depth',f_depth,'f_depth');
forth_prim('+',f_plus,'f_plus');        forth_prim('-',f_minus,'f_minus');
forth_prim('*',f_times,'f_times');      forth_prim('/',f_div,'f_div');
forth_prim('mod',f_mod,'f_mod');        forth_prim('negate',f_negate,'f_negate');
forth_prim('1+',f_1plus,'f_1plus');     forth_prim('1-',f_1minus,'f_1minus');
forth_prim('2*',f_2times,'f_2times');   forth_prim('2/',f_2div,'f_2div');
forth_prim('abs',f_abs,'f_abs');        forth_prim('min',f_min,'f_min');
forth_prim('max',f_max,'f_max');
forth_prim('=',f_eq,'f_eq');            forth_prim('<>',f_ne,'f_ne');
forth_prim('<',f_lt,'f_lt');            forth_prim('>',f_gt,'f_gt');
forth_prim('<=',f_le,'f_le');           forth_prim('>=',f_ge,'f_ge');
forth_prim('0=',f_0eq,'f_0eq');         forth_prim('0<',f_0lt,'f_0lt');
forth_prim('0>',f_0gt,'f_0gt');
forth_prim('and',f_and,'f_and');        forth_prim('or',f_or,'f_or');
forth_prim('xor',f_xor,'f_xor');        forth_prim('invert',f_invert,'f_invert');
forth_prim('.',f_dot,'f_dot');          forth_prim('cr',f_cr,'f_cr');
forth_prim('emit',f_emit,'f_emit');     forth_prim('space',f_space,'f_space');
forth_prim('.s',f_dots,'f_dots');

;;; ---- tokeniser ----
define lconstant Iswhite(c); c == `\s` or c == `\t` or c == `\n` or c == `\r` enddefine;

define forth_tokenize(s) -> toks;
    lvars s, toks = [], i = 1, n = datalength(s), start, tok;
    while i fi_<= n do
        while i fi_<= n and Iswhite(fast_subscrs(i,s)) do i fi_+ 1 -> i endwhile;
        quitif(i fi_> n);
        i -> start;
        while i fi_<= n and not(Iswhite(fast_subscrs(i,s))) do i fi_+ 1 -> i endwhile;
        substring(start, i fi_- start, s) -> tok;
        if tok = '\\' then           ;;; \ line comment: skip to end of line
            while i fi_<= n and fast_subscrs(i,s) /== `\n` do i fi_+ 1 -> i endwhile;
        else
            tok :: toks -> toks;
        endif;
    endwhile;
    rev(toks) -> toks;
enddefine;

define forth_next() -> tok;
    lvars tok;
    if forth_toks == [] then false -> tok
    else fast_destpair(forth_toks) -> (tok, forth_toks)
    endif
enddefine;

define lconstant Skip_comment();
    lvars tok;
    repeat forth_next() -> tok; quitif(tok == false or tok = ')') endrepeat
enddefine;

;;; ---- colon-definition compiler (transpile -> native) ----
define lconstant Compile_colon();
    lvars name = forth_next(), tok, num;
    unless name then mishap(0, 'FORTH: : with no name') endunless;
    forth_gensym fi_+ 1 -> forth_gensym;
    lvars pname = 'FW_' >< forth_gensym;
    lvars src = 'define ' >< pname >< '();\n';
    repeat
        forth_next() -> tok;
        unless tok then mishap(name, 1, 'FORTH: unterminated : definition') endunless;
        quitif(tok = ';');
        if     tok = 'if'     then src >< 'if f_flagtrue() then ' -> src;
        elseif tok = 'else'   then src >< ' else ' -> src;
        elseif tok = 'then'   then src >< ' endif; ' -> src;
        elseif tok = 'begin'  then src >< 'repeat ' -> src;
        elseif tok = 'until'  then src >< ' quitif(f_flagtrue()) endrepeat; ' -> src;
        elseif tok = 'while'  then src >< ' quitunless(f_flagtrue()); ' -> src;
        elseif tok = 'repeat' then src >< ' endrepeat; ' -> src;
        elseif tok = 'recurse' then src >< pname >< '(); ' -> src;
        elseif tok = 'exit'   then src >< ' return(); ' -> src;
        elseif tok = '('      then Skip_comment();
        elseif strnumber(tok) ->> num then src >< (tok >< '; ') -> src;
        elseif forth_pname(consword(tok)) ->> num then src >< (num >< '(); ') -> src;
        else mishap(tok, 1, 'FORTH: unknown word in : definition');
        endif;
    endrepeat;
    src >< '\nenddefine;\n' -> src;
    pop11_compile(stringin(src));
    valof(consword(pname)) -> forth_proc(consword(name));
    pname -> forth_pname(consword(name));
enddefine;

;;; ---- outer interpreter ----
define forth_interp(tok);
    lvars tok, w, num, p;
    if tok = ':' then Compile_colon();
    elseif tok = '(' then Skip_comment();
    elseif strnumber(tok) ->> num then num;            ;;; push number
    elseif forth_proc(consword(tok) ->> w) ->> p then p();   ;;; execute word
    else mishap(tok, 1, 'FORTH: unknown word');
    endif
enddefine;

define forth_run(src);
    dlocal forth_toks = forth_tokenize(src);
    lvars tok;
    until forth_toks == [] do
        forth_next() -> tok;
        forth_interp(tok);
    enduntil;
enddefine;

;;; load and run a .fth source file
define forth_load(file);
    lvars dev = discin(file), c, n = 0;
    repeat
        dev() -> c;
        quitif(c == termin);
        c; n fi_+ 1 -> n;       ;;; leave char on stack, count
    endrepeat;
    forth_run(consstring(n));
enddefine;

;;; banner when loaded interactively
';;; Poplog Forth loaded.  forth_run(\'2 3 + .\')  |  forth_load(\'prog.fth\')' =>
