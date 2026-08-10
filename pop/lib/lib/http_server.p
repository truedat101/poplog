/* --- HTTP/1.1 server ----------------------------------------------------
 > File:            pop/lib/lib/http_server.p
 > Purpose:         Serve HTTP from pure Pop-11 over LIB * UNIX_SOCKETS
 > Documentation:   HELP * HTTP_SERVER
 > Related Files:   tools/tests/test_http_server.p, examples/http_hello.p,
 >                  LIB * JSON, REF * SOCKETS
 >
 > A deliberately small, single-threaded server: one accept loop, one
 > request per connection (Connection: close).  The handler receives a
 > request property and returns a response built with http_response /
 > http_text / http_json; returning false sends 404, and a mishap in
 > the handler sends 500 (the server survives).  Composes with
 > LIB * JSON for API work.
 */
compile_mode :pop11 +strict;

uses unix_sockets;
uses strutils;

section $-http =>
    http_serve http_serve_n http_response http_text http_json;

uses json;      ;;; after section: json_generate is a global export

define lconstant reason(status);
    if status == 200 then 'OK'
    elseif status == 201 then 'Created'
    elseif status == 204 then 'No Content'
    elseif status == 301 then 'Moved Permanently'
    elseif status == 302 then 'Found'
    elseif status == 400 then 'Bad Request'
    elseif status == 403 then 'Forbidden'
    elseif status == 404 then 'Not Found'
    elseif status == 405 then 'Method Not Allowed'
    elseif status == 500 then 'Internal Server Error'
    else 'Response'
    endif
enddefine;

define http_response(status, ctype, body) -> resp;
    unless isinteger(status) and isstring(ctype) and isstring(body) then
        mishap(status, ctype, body, 3,
               'http_response: status int, content-type and body strings needed')
    endunless;
    {% status, ctype, body %} -> resp;
enddefine;

define http_text(body) -> resp;
    http_response(200, 'text/plain; charset=utf-8', body) -> resp;
enddefine;

define http_json(item) -> resp;
    http_response(200, 'application/json', json_generate(item)) -> resp;
enddefine;

;;; --- request reading ----------------------------------------------------

define lconstant read_line(dev) -> line;
    lvars buf = inits(1), c, n = 0;
    repeat
        quitif(sysread(dev, buf, 1) == 0);          ;;; EOF
        subscrs(1, buf) -> c;
        quitif(c == `\n`);
        unless c == `\r` then c; n + 1 -> n endunless;
    endrepeat;
    consstring(n) -> line;
enddefine;

define lconstant read_n(dev, want) -> s;
    lvars buf = inits(4096), n, i, got = 0;
    while got < want do
        sysread(dev, buf, min(4096, want - got)) -> n;
        quitif(n == 0);
        for i from 1 to n do subscrs(i, buf) endfor;
        got + n -> got;
    endwhile;
    consstring(got) -> s;
enddefine;

;;; parse one request from dev into a property, or false if the
;;; connection closed / the request line is unparseable
define lconstant read_request(dev) -> req;
    lvars line, parts, path, q, headers, name, val, colon, clen;
    read_line(dev) -> line;
    str_split(str_trim(line), `\s`) -> parts;
    unless length(parts) >= 2 then
        false -> req;
        return;
    endunless;
    newmapping([], 8, false, true) -> req;
    str_upper(hd(parts)) -> req('method');
    hd(tl(parts)) -> path;
    if issubstring('?', 1, path) ->> q then
        substring(q + 1, length(path) - q, path) -> req('query');
        substring(1, q - 1, path) -> path;
    else
        nullstring -> req('query');
    endif;
    path -> req('path');
    ;;; headers, names lowercased
    newmapping([], 16, false, true) ->> headers -> req('headers');
    repeat
        read_line(dev) -> line;
        quitif(line = nullstring);
        if issubstring(':', 1, line) ->> colon then
            str_lower(str_trim(substring(1, colon - 1, line))) -> name;
            str_trim(substring(colon + 1, length(line) - colon, line)) -> val;
            val -> headers(name);
        endif;
    endrepeat;
    ;;; body, when Content-Length says so
    if headers('content-length') and strnumber(headers('content-length')) ->> clen then
        read_n(dev, clen) -> req('body');
    else
        nullstring -> req('body');
    endif;
enddefine;

;;; --- handler invocation with a 500 safety net --------------------------

vars trapped;

define lconstant try_handler(handler, req) -> resp;
    lvars sl = stacklength();
    dlocal prmishap =
        procedure(m, c);
            true -> trapped;
            exitto(try_handler);
        endprocedure;
    false -> trapped;
    handler(req);
    if trapped or stacklength() <= sl then
        setstacklength(sl);
        "mishap" -> resp;
        true -> pop_exit_ok;    ;;; a served 500 is handled, not fatal
    else
        -> resp;
        setstacklength(sl);
    endif;
enddefine;

define lconstant send_response(dev, resp);
    lvars status, ctype, body, head;
    if resp == "mishap" then
        500 -> status;
        'text/plain' -> ctype;
        'internal server error\n' -> body;
    elseif not(resp) then
        404 -> status;
        'text/plain' -> ctype;
        'not found\n' -> body;
    elseif isvector(resp) and datalength(resp) == 3 then
        explode(resp) -> (status, ctype, body);
    else
        500 -> status;
        'text/plain' -> ctype;
        'handler returned an unusable response\n' -> body;
    endif;
    'HTTP/1.1 ' >< status >< ' ' >< reason(status)
        >< '\r\nContent-Type: ' >< ctype
        >< '\r\nContent-Length: ' >< length(body)
        >< '\r\nConnection: close\r\n\r\n' -> head;
    syswrite(dev, head, length(head));
    if length(body) > 0 then syswrite(dev, body, length(body)) endif;
enddefine;

;;; --- the server ---------------------------------------------------------

;;; serve on port; handler(request_property) -> response.  count limits
;;; how many requests are served (false = forever).  Request properties:
;;; 'method' 'path' 'query' 'body', and 'headers' (a property with
;;; lowercased names).
define http_serve_n(port, handler, count);
    lvars ctl, conn, served = 0, req;
    unless isinteger(port) and isprocedure(handler) then
        mishap(port, handler, 2, 'http_serve: port and handler procedure needed')
    endunless;
    sys_socket(`i`, `S`, false) -> ctl;
    [* ^port] -> sys_socket_name(ctl, 5);
    repeat
        sys_socket_accept(ctl, false) -> conn;
        read_request(conn) -> req;
        if req then
            send_response(conn, try_handler(handler, req));
        endif;
        sysclose(conn);
        served + 1 -> served;
        quitif(count and served >= count);
    endrepeat;
    sysclose(ctl);
enddefine;

define http_serve(port, handler);
    http_serve_n(port, handler, false);
enddefine;

endsection;
