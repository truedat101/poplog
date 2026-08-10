/* --- UTF-8 string layer -------------------------------------------------
 > File:            pop/lib/lib/utf8.p
 > Purpose:         Code-point-aware operations over UTF-8 byte strings
 > Author:          D.Kordsmeier (@truedat101) and Claude (@claude), Aug 2026
 > Documentation:   HELP * UTF8
 > Related Files:   tools/tests/test_utf8.p, LIB * JSON (produces UTF-8)
 >
 > Poplog strings are byte strings; this library treats their contents
 > as UTF-8.  Validation is strict (RFC 3629): overlong encodings,
 > surrogate code points, values above U+10FFFF, truncated and stray
 > continuation bytes are all rejected.  Everything except utf8_valid
 > mishaps on malformed input.
 */
compile_mode :pop11 +strict;

section $-utf8 =>
    utf8_valid utf8_length utf8_code utf8_explode utf8_substring
    utf8_appcodes consutf8;

;;; decode the code point starting at byte i; returns (code, nbytes),
;;; or (false, false) if malformed
define lconstant decode_at(i, s) -> (code, nbytes);
    lvars len = length(s), b, b2, need, j, lo;
    false ->> code -> nbytes;
    subscrs(i, s) -> b;
    if b < 16:80 then
        b -> code; 1 -> nbytes;
        return;
    elseif b >= 16:C2 and b <= 16:DF then
        b && 16:1F -> code; 2 -> need; 16:80 -> lo;
    elseif b >= 16:E0 and b <= 16:EF then
        b && 16:0F -> code; 3 -> need; 16:800 -> lo;
    elseif b >= 16:F0 and b <= 16:F4 then
        b && 16:07 -> code; 4 -> need; 16:10000 -> lo;
    else
        ;;; stray continuation byte, overlong lead C0/C1, or F5..FF
        false -> code;
        return;
    endif;
    if i + need - 1 > len then false -> code; return endif;
    for j from i + 1 to i + need - 1 do
        subscrs(j, s) -> b2;
        unless b2 >= 16:80 and b2 <= 16:BF then
            false -> code; return
        endunless;
        (code << 6) || (b2 && 16:3F) -> code;
    endfor;
    if code < lo                                    ;;; overlong
    or (code >= 16:D800 and code <= 16:DFFF)        ;;; surrogate
    or code > 16:10FFFF then
        false -> code;
        return;
    endif;
    need -> nbytes;
enddefine;

define lconstant bad(s);
    mishap(s, 1, 'utf8: malformed UTF-8 string')
enddefine;

define utf8_valid(s);
    lvars i = 1, len = length(s), code, nb;
    while i <= len do
        decode_at(i, s) -> (code, nb);
        unless code then return(false) endunless;
        i + nb -> i;
    endwhile;
    true
enddefine;

;;; number of code points
define utf8_length(s) -> n;
    lvars i = 1, len = length(s), code, nb;
    0 -> n;
    while i <= len do
        decode_at(i, s) -> (code, nb);
        unless code then bad(s) endunless;
        i + nb -> i;
        n + 1 -> n;
    endwhile;
enddefine;

;;; the i-th code point (1-based)
define utf8_code(i, s) -> code;
    lvars at = 1, len = length(s), nb, k = 0;
    unless isinteger(i) and i >= 1 then
        mishap(i, 1, 'utf8_code: positive index needed')
    endunless;
    while at <= len do
        decode_at(at, s) -> (code, nb);
        unless code then bad(s) endunless;
        k + 1 -> k;
        if k == i then return endif;
        at + nb -> at;
    endwhile;
    mishap(i, s, 2, 'utf8_code: index past end of string');
enddefine;

;;; push every code point (use with utf8_length, or consutf8 to rebuild)
define utf8_explode(s);
    lvars i = 1, len = length(s), code, nb;
    while i <= len do
        decode_at(i, s) -> (code, nb);
        unless code then bad(s) endunless;
        code;
        i + nb -> i;
    endwhile;
enddefine;

define utf8_appcodes(s, p);
    lvars i = 1, len = length(s), code, nb;
    while i <= len do
        decode_at(i, s) -> (code, nb);
        unless code then bad(s) endunless;
        p(code);
        i + nb -> i;
    endwhile;
enddefine;

;;; substring by code points: n code points starting at the i-th
define utf8_substring(i, n, s) -> sub;
    lvars at = 1, len = length(s), code, nb, k = 0, fromb = false, upto;
    unless isinteger(i) and i >= 1 and isinteger(n) and n >= 0 then
        mishap(i, n, 2, 'utf8_substring: positive index and non-negative count needed')
    endunless;
    len + 1 -> upto;
    while at <= len do
        decode_at(at, s) -> (code, nb);
        unless code then bad(s) endunless;
        k + 1 -> k;
        if k == i then at -> fromb endif;
        if k == i + n then at -> upto; quitloop endif;
        at + nb -> at;
    endwhile;
    if n == 0 then nullstring -> sub; return endif;
    unless fromb and (k >= i + n - 1) then
        mishap(i, n, s, 3, 'utf8_substring: range past end of string')
    endunless;
    substring(fromb, upto - fromb, s) -> sub;
enddefine;

;;; build a UTF-8 string from n code points on the stack
define consutf8(n) -> s;
    lvars codes, code, nbytes = 0;
    unless isinteger(n) and n >= 0 then
        mishap(n, 1, 'consutf8: non-negative count needed')
    endunless;
    conslist(n) -> codes;
    for code in codes do
        unless isinteger(code) and code >= 0 and code <= 16:10FFFF
        and not(code >= 16:D800 and code <= 16:DFFF) then
            mishap(code, 1, 'consutf8: invalid code point')
        endunless;
        if code < 16:80 then
            code; nbytes + 1 -> nbytes;
        elseif code < 16:800 then
            16:C0 || (code << -6); 16:80 || (code && 16:3F);
            nbytes + 2 -> nbytes;
        elseif code < 16:10000 then
            16:E0 || (code << -12); 16:80 || ((code << -6) && 16:3F);
            16:80 || (code && 16:3F);
            nbytes + 3 -> nbytes;
        else
            16:F0 || (code << -18); 16:80 || ((code << -12) && 16:3F);
            16:80 || ((code << -6) && 16:3F); 16:80 || (code && 16:3F);
            nbytes + 4 -> nbytes;
        endif;
    endfor;
    consstring(nbytes) -> s;
enddefine;

endsection;
