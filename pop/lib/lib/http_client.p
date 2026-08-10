/* --- HTTP client --------------------------------------------------------
 > File:            pop/lib/lib/http_client.p
 > Purpose:         HTTP(S) requests with headers, status and timeouts
 > Author:          D.Kordsmeier (@truedat101) with Claude (Anthropic), Aug 2026
 > Documentation:   HELP * HTTP_CLIENT
 > Related Files:   pop/extern/popcurl/popcurl_shim.c,
 >                  tools/build-popcurl.sh, tools/tests/test_http_client.p
 >
 > The client half of the HTTP story (LIB * HTTP_SERVER is the other):
 > a Pop-11 face over libcurl via a small non-variadic shim, so HTTPS,
 > redirects, compression and proxy environment variables all come from
 > libcurl for free.  Build the shim once with tools/build-popcurl.sh,
 > then:  uses http_client;
 */
compile_mode :pop11 +strict;

uses strutils;

section $-http_client =>
    http_request http_get http_post http_client_version;

;;; fail at load time with a useful message if the shim isn't built
unless sys_file_exists(sysfileok('$usepop/pop/extern/popcurl/popcurl.so'))
or sys_file_exists(sysfileok('$usepop/pop/extern/popcurl/popcurl.dylib'))
then
    mishap(0, 'lib http_client: shim not built -- run tools/build-popcurl.sh first')
endunless;

exload popcurl
    #_IF sys_file_exists(sysfileok('$usepop/pop/extern/popcurl/popcurl.dylib'))
    ['$usepop/pop/extern/popcurl/popcurl.dylib']
    #_ELSE
    ['$usepop/pop/extern/popcurl/popcurl.so']
    #_ENDIF
(language C)
    lconstant
        pcu_perform(method, url, body, bodylen, headers, timeout) :int,
        pcu_body_len()          :int,
        pcu_body_copy(out)      :void,
        pcu_hdrs_len()          :int,
        pcu_hdrs_copy(out)      :void,
        pcu_error()             :exptr,
        pcu_version()           :exptr,
    ;
endexload;

define lconstant cstr(s);
    s <> consstring(0, 1)
enddefine;

define lconstant fetch_body() -> s;
    lvars n = exacc pcu_body_len();
    inits(n) -> s;
    if n > 0 then exacc pcu_body_copy(s) endif;
enddefine;

define lconstant fetch_hdrs() -> s;
    lvars n = exacc pcu_hdrs_len();
    inits(n) -> s;
    if n > 0 then exacc pcu_hdrs_copy(s) endif;
enddefine;

;;; parse the raw response-header block into a property (names
;;; lowercased); with redirects curl reports every hop's headers, so
;;; keep values from the final block
define lconstant parse_headers(raw) -> prop;
    lvars line, colon, name, val;
    newmapping([], 16, false, true) -> prop;
    for line in str_lines(raw) do
        if str_starts('HTTP/', line) then
            ;;; a hop's status line: start that hop's block afresh
            newmapping([], 16, false, true) -> prop;
        elseif issubstring(':', 1, line) ->> colon then
            str_lower(str_trim(substring(1, colon - 1, line))) -> name;
            str_trim(substring(colon + 1, length(line) - colon, line)) -> val;
            val -> prop(name);
        endif;
    endfor;
enddefine;

;;; the general request.  METHOD e.g. 'GET'; BODY a string ('' = none);
;;; HEADERS a list of 'Name: value' strings ([] = none); TIMEOUT in
;;; seconds (false = library default).  Returns the response body, a
;;; property of response headers (lowercased names) and the HTTP
;;; status.  Transport failures (DNS, refused, timeout...) mishap with
;;; libcurl's message.
define http_request(method, url, body, headers, timeout) -> (respbody, resphdrs, status);
    lvars hstr;
    unless isstring(method) and isstring(url) and isstring(body)
    and islist(headers) then
        mishap(method, url, 2, 'http_request: method/url/body strings and header list needed')
    endunless;
    str_join(headers, '\n') -> hstr;
    exacc pcu_perform(cstr(method), cstr(url), body, length(body),
                      cstr(hstr), if timeout then timeout else 0 endif)
        -> status;
    if status < 0 then
        mishap(url, exacc_ntstring(exacc pcu_error()), 2,
               'http_request: transport error')
    endif;
    fetch_body() -> respbody;
    parse_headers(fetch_hdrs()) -> resphdrs;
enddefine;

define http_get(url) -> (respbody, status);
    lvars hdrs;
    http_request('GET', url, nullstring, [], false)
        -> (respbody, hdrs, status);
enddefine;

define http_post(url, body, ctype) -> (respbody, status);
    lvars hdrs;
    http_request('POST', url, body, [% 'Content-Type: ' <> ctype %], false)
        -> (respbody, hdrs, status);
enddefine;

define http_client_version() -> s;
    exacc_ntstring(exacc pcu_version()) -> s;
enddefine;

endsection;
