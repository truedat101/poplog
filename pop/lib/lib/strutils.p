/* --- String utilities ---------------------------------------------------
 > File:            pop/lib/lib/strutils.p
 > Purpose:         Everyday string operations: split/join/trim/replace...
 > Documentation:   HELP * STRUTILS
 > Related Files:   tools/tests/test_strutils.p
 >
 > All procedures are pure Pop-11 and byte-oriented (see LIB * UTF8 for
 > code-point-aware operations).  Names carry a str_ prefix to keep the
 > global namespace clean.
 */
compile_mode :pop11 +strict;

section $-strutils =>
    str_split str_join str_trim str_ltrim str_rtrim
    str_starts str_ends str_replace str_lines
    str_repeat str_padl str_padr str_lower str_upper;

define lconstant white(c);
    c == `\s` or c == `\t` or c == `\n` or c == `\r`
enddefine;

;;; split s on separator sep (a character or non-empty string);
;;; adjacent separators yield empty fields, like every modern split
define str_split(s, sep) -> l;
    lvars i, start = 1, seplen, n = 0;
    if isinteger(sep) then consstring(sep, 1) -> sep endif;
    unless isstring(s) and isstring(sep) and length(sep) > 0 then
        mishap(s, sep, 2, 'str_split: string and non-empty separator needed')
    endunless;
    length(sep) -> seplen;
    while (issubstring(sep, start, s) ->> i) do
        substring(start, i - start, s);
        n + 1 -> n;
        i + seplen -> start;
    endwhile;
    substring(start, length(s) - start + 1, s);
    conslist(n + 1) -> l;
enddefine;

define str_join(l, sep) -> s;
    lvars item, first = true, n = 0;
    if isinteger(sep) then consstring(sep, 1) -> sep endif;
    for item in l do
        unless first then appdata(sep, identfn); n + length(sep) -> n endunless;
        false -> first;
        appdata(item, identfn);
        n + length(item) -> n;
    endfor;
    consstring(n) -> s;
enddefine;

define str_ltrim(s) -> s;
    lvars i = 1, n = length(s);
    while i <= n and white(subscrs(i, s)) do i + 1 -> i endwhile;
    substring(i, n - i + 1, s) -> s;
enddefine;

define str_rtrim(s) -> s;
    lvars n = length(s);
    while n >= 1 and white(subscrs(n, s)) do n - 1 -> n endwhile;
    substring(1, n, s) -> s;
enddefine;

define str_trim(s) -> s;
    str_rtrim(str_ltrim(s)) -> s;
enddefine;

define str_starts(prefix, s);
    length(prefix) <= length(s)
    and substring(1, length(prefix), s) = prefix
enddefine;

define str_ends(suffix, s);
    length(suffix) <= length(s)
    and substring(length(s) - length(suffix) + 1, length(suffix), s) = suffix
enddefine;

;;; replace every occurrence of old (non-empty) with new
define str_replace(s, old, new) -> r;
    lvars i, start = 1, n = 0, oldlen = length(old);
    unless oldlen > 0 then
        mishap(old, 1, 'str_replace: non-empty search string needed')
    endunless;
    while (issubstring(old, start, s) ->> i) do
        appdata(substring(start, i - start, s), identfn);
        n + (i - start) -> n;
        appdata(new, identfn);
        n + length(new) -> n;
        i + oldlen -> start;
    endwhile;
    appdata(substring(start, length(s) - start + 1, s), identfn);
    n + (length(s) - start + 1) -> n;
    consstring(n) -> r;
enddefine;

;;; split into lines: accepts \n and \r\n, no trailing empty line for a
;;; final newline
define str_lines(s) -> l;
    lvars line;
    [% for line in str_split(s, `\n`) do
           if str_ends('\r', line) then
               substring(1, length(line) - 1, line)
           else
               line
           endif
       endfor %] -> l;
    ;;; a trailing newline should not produce a phantom empty last line
    if l /== [] and last(l) = nullstring and str_ends('\n', s) then
        allbutlast(1, l) -> l
    endif;
enddefine;

define str_repeat(s, n) -> r;
    lvars i;
    unless isinteger(n) and n >= 0 then
        mishap(n, 1, 'str_repeat: non-negative count needed')
    endunless;
    for i from 1 to n do appdata(s, identfn) endfor;
    consstring(n * length(s)) -> r;
enddefine;

define str_padl(s, n, c) -> r;
    if length(s) >= n then s -> r
    else str_repeat(consstring(c, 1), n - length(s)) <> s -> r
    endif;
enddefine;

define str_padr(s, n, c) -> r;
    if length(s) >= n then s -> r
    else s <> str_repeat(consstring(c, 1), n - length(s)) -> r
    endif;
enddefine;

define str_lower(s) -> r;
    lvars i, c;
    for i from 1 to length(s) do
        subscrs(i, s) -> c;
        if c >= `A` and c <= `Z` then c + 32 else c endif;
    endfor;
    consstring(length(s)) -> r;
enddefine;

define str_upper(s) -> r;
    lvars i, c;
    for i from 1 to length(s) do
        subscrs(i, s) -> c;
        if c >= `a` and c <= `z` then c - 32 else c endif;
    endfor;
    consstring(length(s)) -> r;
enddefine;

endsection;
