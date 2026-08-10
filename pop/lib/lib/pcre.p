/* --- Perl-compatible regular expressions --------------------------------
 > File:            pop/lib/lib/pcre.p
 > Purpose:         PCRE2 pattern matching with capture groups
 > Documentation:   HELP * PCRE
 > Related Files:   pop/extern/poppcre/poppcre_shim.c,
 >                  tools/build-poppcre.sh, tools/tests/test_pcre.p
 >
 > Full modern regex syntax — \d, +, ?, {n,m}, groups, alternation,
 > (?i), lookaround — via a small PCRE2 shim.  LIB * REGEXP is the
 > zero-dependency alternative using the built-in Ved engine; this
 > library is for when you want the syntax the rest of the world
 > writes.  Build the shim once with tools/build-poppcre.sh, then:
 > uses pcre;
 */
compile_mode :pop11 +strict;

section $-pcre =>
    pcre_search pcre_matches pcre_first pcre_groups
    pcre_all pcre_split pcre_replace pcre_version;

;;; fail at load time with a useful message if the shim isn't built
unless sys_file_exists(sysfileok('$usepop/pop/extern/poppcre/poppcre.so'))
or sys_file_exists(sysfileok('$usepop/pop/extern/poppcre/poppcre.dylib'))
then
    mishap(0, 'lib pcre: shim not built -- run tools/build-poppcre.sh first')
endunless;

exload poppcre
    #_IF sys_file_exists(sysfileok('$usepop/pop/extern/poppcre/poppcre.dylib'))
    ['$usepop/pop/extern/poppcre/poppcre.dylib']
    #_ELSE
    ['$usepop/pop/extern/poppcre/poppcre.so']
    #_ENDIF
(language C)
    lconstant
        pcp_search(pat, subj, len, start) :int,
        pcp_start(i)    :int,
        pcp_len(i)      :int,
        pcp_groups()    :int,
        pcp_error()     :exptr,
        pcp_version()   :exptr,
    ;
endexload;

define lconstant cstr(s);
    s <> consstring(0, 1)
enddefine;

;;; raw search; Pop-11 1-based positions in and out
define lconstant do_search(pat, s, i) -> found;
    lvars rc;
    unless isstring(pat) and isstring(s) and isinteger(i) and i >= 1 then
        mishap(pat, s, 2, 'pcre: pattern/subject strings and positive start needed')
    endunless;
    if i > length(s) + 1 then
        false -> found;
        return;
    endif;
    exacc pcp_search(cstr(pat), s, length(s), i - 1) -> rc;
    if rc < 0 then
        mishap(pat, exacc_ntstring(exacc pcp_error()), 2, 'pcre: error')
    endif;
    rc == 1 -> found;
enddefine;

define pcre_search(pat, s, i) -> (start, nchars);
    if do_search(pat, s, i) then
        exacc pcp_start(0) + 1 -> start;
        exacc pcp_len(0) -> nchars;
    else
        false ->> start -> nchars;
    endif;
enddefine;

define pcre_matches(pat, s);
    do_search(pat, s, 1)
enddefine;

define pcre_first(pat, s) -> m;
    lvars start, nchars;
    pcre_search(pat, s, 1) -> (start, nchars);
    if start then substring(start, nchars, s) else false endif -> m;
enddefine;

;;; whole match + capture groups as a vector of strings (false for a
;;; group that did not participate), or false if no match
define pcre_groups(pat, s) -> v;
    lvars n, i, gs, gl;
    unless do_search(pat, s, 1) then
        false -> v;
        return;
    endunless;
    exacc pcp_groups() -> n;
    {% for i from 0 to n do
           exacc pcp_start(i) -> gs;
           exacc pcp_len(i) -> gl;
           if gs >= 0 then substring(gs + 1, gl, s) else false endif;
       endfor %} -> v;
enddefine;

define pcre_all(pat, s) -> l;
    lvars i = 1, start, nchars, n = 0;
    while i <= length(s) + 1 do
        pcre_search(pat, s, i) -> (start, nchars);
        quitunless(start);
        substring(start, nchars, s);
        n + 1 -> n;
        if nchars == 0 then start + 1 else start + nchars endif -> i;
    endwhile;
    conslist(n) -> l;
enddefine;

define pcre_split(pat, s) -> l;
    lvars i = 1, frm = 1, start, nchars, n = 0;
    while i <= length(s) + 1 do
        pcre_search(pat, s, i) -> (start, nchars);
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

;;; every match replaced by the literal string new
define pcre_replace(pat, s, new) -> r;
    lvars i = 1, frm = 1, start, nchars, total = 0;
    unless isstring(new) then
        mishap(new, 1, 'pcre_replace: replacement string needed')
    endunless;
    while i <= length(s) + 1 do
        pcre_search(pat, s, i) -> (start, nchars);
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

define pcre_version() -> s;
    exacc_ntstring(exacc pcp_version()) -> s;
enddefine;

endsection;
