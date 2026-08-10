/* --- Date and time utilities --------------------------------------------
 > File:            pop/lib/lib/datetime.p
 > Purpose:         Epoch seconds <-> ISO 8601 (UTC), pure integer math
 > Documentation:   HELP * DATETIME
 > Related Files:   tools/tests/test_datetime.p, LIB * STRUTILS
 >
 > All conversions are UTC ("Z"); the civil-date conversions use the
 > standard days-from-civil / civil-from-days algorithms (Howard
 > Hinnant), so no OS date facilities are involved and behaviour is
 > identical on every platform.
 */
compile_mode :pop11 +strict;

uses strutils;

section $-datetime =>
    dt_now dt_fields dt_iso dt_parse_iso dt_days_from_civil;

define dt_now() -> t;
    sys_real_time() -> t;
enddefine;

define lconstant floordiv(a, b) -> q;
    a div b -> q;
    if (a rem b) /= 0 and ((a < 0) /== (b < 0)) then q - 1 -> q endif;
enddefine;

define lconstant floormod(a, b) -> r;
    a - floordiv(a, b) * b -> r;
enddefine;

;;; days since 1970-01-01 for a civil UTC date (proleptic Gregorian)
define dt_days_from_civil(y, m, d) -> days;
    lvars era, yoe, doy, doe;
    if m <= 2 then y - 1 -> y endif;
    floordiv(y, 400) -> era;
    y - era * 400 -> yoe;                               ;;; [0, 399]
    (153 * (if m > 2 then m - 3 else m + 9 endif) + 2) div 5 + d - 1 -> doy;
    yoe * 365 + yoe div 4 - yoe div 100 + doy -> doe;
    era * 146097 + doe - 719468 -> days;
enddefine;

;;; civil UTC date for days since 1970-01-01
define lconstant civil_from_days(z) -> (y, m, d);
    lvars era, doe, yoe, doy, mp;
    z + 719468 -> z;
    floordiv(z, 146097) -> era;
    z - era * 146097 -> doe;                            ;;; [0, 146096]
    (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365 -> yoe;
    yoe + era * 400 -> y;
    doe - (365 * yoe + yoe div 4 - yoe div 100) -> doy;
    (5 * doy + 2) div 153 -> mp;
    doy - (153 * mp + 2) div 5 + 1 -> d;
    if mp < 10 then mp + 3 else mp - 9 endif -> m;
    if m <= 2 then y + 1 -> y endif;
enddefine;

;;; epoch seconds -> {year month day hour minute second} (UTC)
define dt_fields(t) -> v;
    lvars days, secs, y, m, d;
    unless isintegral(t) then
        mishap(t, 1, 'dt_fields: integer epoch seconds needed')
    endunless;
    floordiv(t, 86400) -> days;
    floormod(t, 86400) -> secs;
    civil_from_days(days) -> (y, m, d);
    {% y, m, d, secs div 3600, (secs div 60) rem 60, secs rem 60 %} -> v;
enddefine;

define lconstant pad2(n);
    str_padl(n sys_>< nullstring, 2, `0`)
enddefine;

;;; epoch seconds -> 'YYYY-MM-DDTHH:MM:SSZ' (UTC)
define dt_iso(t) -> s;
    lvars v = dt_fields(t);
    subscrv(1, v) sys_>< nullstring <> '-' <> pad2(subscrv(2, v))
        <> '-' <> pad2(subscrv(3, v))
        <> 'T' <> pad2(subscrv(4, v))
        <> ':' <> pad2(subscrv(5, v))
        <> ':' <> pad2(subscrv(6, v)) <> 'Z' -> s;
enddefine;

define lconstant parse_int(str);
    lvars n = strnumber(str);
    unless isintegral(n) then
        mishap(str, 1, 'dt_parse_iso: bad number field')
    endunless;
    n
enddefine;

;;; 'YYYY-MM-DD' or 'YYYY-MM-DDTHH:MM:SS[Z]' (also accepts a space
;;; separator) -> epoch seconds, UTC
define dt_parse_iso(s) -> t;
    lvars y, mo, d, h = 0, mi = 0, sec = 0, rest;
    unless isstring(s) and length(s) >= 10
    and subscrs(5, s) == `-` and subscrs(8, s) == `-` then
        mishap(s, 1, 'dt_parse_iso: ISO 8601 date needed (YYYY-MM-DD...)')
    endunless;
    parse_int(substring(1, 4, s)) -> y;
    parse_int(substring(6, 2, s)) -> mo;
    parse_int(substring(9, 2, s)) -> d;
    unless mo >= 1 and mo <= 12 and d >= 1 and d <= 31 then
        mishap(s, 1, 'dt_parse_iso: month/day out of range')
    endunless;
    if length(s) > 10 then
        unless subscrs(11, s) == `T` or subscrs(11, s) == `\s` then
            mishap(s, 1, 'dt_parse_iso: expected T between date and time')
        endunless;
        substring(12, length(s) - 11, s) -> rest;
        if str_ends('Z', rest) then
            substring(1, length(rest) - 1, rest) -> rest
        endif;
        unless length(rest) == 8
        and subscrs(3, rest) == `:` and subscrs(6, rest) == `:` then
            mishap(s, 1, 'dt_parse_iso: time must be HH:MM:SS')
        endunless;
        parse_int(substring(1, 2, rest)) -> h;
        parse_int(substring(4, 2, rest)) -> mi;
        parse_int(substring(7, 2, rest)) -> sec;
        unless h <= 23 and mi <= 59 and sec <= 60 then
            mishap(s, 1, 'dt_parse_iso: time out of range')
        endunless;
    endif;
    dt_days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec -> t;
enddefine;

endsection;
