/* --- Friendly regular-expression surface --------------------------------
 > File:            pop/lib/lib/regexp.p
 > Purpose:         match / all / split / replace over the core engine
 > Author:          D.Kordsmeier (@truedat101) and Claude (@claude), Aug 2026
 > Documentation:   HELP * REGEXP_LIB, REF * REGEXP (pattern syntax)
 > Related Files:   tools/tests/test_regexp.p, src/regexp_compile.p
 >
 > A convenience layer over Poplog's built-in regular expression
 > engine (the one Ved search uses).  Pattern syntax is REF REGEXP's
 > Ved style: ordinary characters are literal; operators are written
 > with a @ prefix — @. any char, @* zero-or-more of the previous,
 > @[a-z@] character class, @< @> word boundaries, @a @z start/end
 > anchors.  (It is not PCRE; it is the pattern language forty years
 > of Poplog documentation already uses.)
 >
 > Compiled patterns are cached, so repeated calls with the same
 > pattern string cost one property lookup.
 */
compile_mode :pop11 +strict;

section $-regexp =>
    regexp_search regexp_matches regexp_first
    regexp_all regexp_split regexp_replace;

lconstant cache = newmapping([], 32, false, true);

define lconstant compiled(pattern) -> p;
    lvars err;
    unless isstring(pattern) then
        mishap(pattern, 1, 'regexp: pattern string needed')
    endunless;
    cache(pattern) -> p;
    unless p then
        regexp_compile(pattern) -> (err, p);
        if err then
            mishap(pattern, err, 2, 'regexp: bad pattern')
        endif;
        p -> cache(pattern);
    endunless;
enddefine;

;;; search s from byte position i; returns (start, nchars), both false
;;; if there is no match
define regexp_search(pattern, s, i) -> (start, nchars);
    unless isstring(s) and isinteger(i) and i >= 1 then
        mishap(s, i, 2, 'regexp_search: string and positive start needed')
    endunless;
    ;;; the engine requires 1 <= i <= length(s); beyond that (and on the
    ;;; empty string) there is simply no match
    if length(s) == 0 or i > length(s) then
        false ->> start -> nchars;
    else
        compiled(pattern)(i, s, false, false) -> (start, nchars);
    endif;
enddefine;

define regexp_matches(pattern, s);
    lvars start, nchars;
    regexp_search(pattern, s, 1) -> (start, nchars);
    start and true
enddefine;

;;; first matching substring, or false
define regexp_first(pattern, s) -> m;
    lvars start, nchars;
    regexp_search(pattern, s, 1) -> (start, nchars);
    if start then substring(start, nchars, s) else false endif -> m;
enddefine;

;;; every (non-overlapping) matching substring, left to right; a
;;; zero-length match advances by one so the walk always terminates
define regexp_all(pattern, s) -> l;
    lvars i = 1, start, nchars, n = 0;
    while i <= length(s) + 1 do
        regexp_search(pattern, s, i) -> (start, nchars);
        quitunless(start);
        substring(start, nchars, s);
        n + 1 -> n;
        if nchars == 0 then start + 1 else start + nchars endif -> i;
    endwhile;
    conslist(n) -> l;
enddefine;

;;; split s around matches of pattern (a zero-length match splits
;;; nowhere and the walk advances)
define regexp_split(pattern, s) -> l;
    lvars i = 1, frm = 1, start, nchars, n = 0;
    while i <= length(s) + 1 do
        regexp_search(pattern, s, i) -> (start, nchars);
        quitunless(start);
        if nchars == 0 then
            start + 1 -> i;
        else
            substring(frm, start - frm, s);
            n + 1 -> n;
            start + nchars ->> i -> frm;
        endif;
    endwhile;
    substring(frm, length(s) - frm + 1, s);
    conslist(n + 1) -> l;
enddefine;

;;; replace every match of pattern in s with the literal string new
define regexp_replace(pattern, s, new) -> r;
    lvars i = 1, frm = 1, start, nchars, total = 0;
    unless isstring(new) then
        mishap(new, 1, 'regexp_replace: replacement string needed')
    endunless;
    while i <= length(s) + 1 do
        regexp_search(pattern, s, i) -> (start, nchars);
        quitunless(start);
        appdata(substring(frm, start - frm, s), identfn);
        total + (start - frm) -> total;
        appdata(new, identfn);
        total + length(new) -> total;
        if nchars == 0 then
            if start <= length(s) then
                subscrs(start, s);
                total + 1 -> total;
            endif;
            start + 1 -> i;
        else
            start + nchars -> i;
        endif;
        i -> frm;
    endwhile;
    appdata(substring(frm, length(s) - frm + 1, s), identfn);
    total + (length(s) - frm + 1) -> total;
    consstring(total) -> r;
enddefine;

endsection;
