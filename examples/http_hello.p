/* examples/http_hello.p -- a web service in pure Pop-11.

   LIB HTTP_SERVER + LIB JSON composed: routing on method+path, query
   and body access, JSON responses, and the built-in safety nets
   (unknown route -> 404, handler mishap -> 500 without killing the
   server).

   Run:    ./poplog target/pop/basepop11 examples/http_hello.p 8080
   Try:    curl localhost:8080/hello
           curl 'localhost:8080/greet?name=poplog'
           curl -d 'some data' localhost:8080/echo
           curl localhost:8080/info

   The optional second argument limits how many requests to serve
   before exiting (used by tools/tests/test_http_server.p).
*/

uses http_server;
uses json;

vars port = 8080, count = false, args = poparglist;

if args /== [] then strnumber(hd(args)) -> port endif;
unless isinteger(port) then 8080 -> port endunless;
if args /== [] and tl(args) /== [] then strnumber(hd(tl(args))) -> count endif;

define handler(req) -> resp;
    lvars path = req('path'), obj;
    if path = '/hello' then
        http_text('hello from Pop-11\n') -> resp;
    elseif path = '/greet' then
        newmapping([], 4, false, true) -> obj;
        req('query') -> obj('query');
        req('method') -> obj('method');
        http_json(obj) -> resp;
    elseif path = '/echo' then
        http_response(200, 'application/octet-stream', req('body')) -> resp;
    elseif path = '/info' then
        newmapping([], 4, false, true) -> obj;
        'poplog' -> obj('server');
        pop_internal_version -> obj('version');
        http_json(obj) -> resp;
    elseif path = '/boom' then
        mishap(0, 'deliberate handler failure');    ;;; server answers 500
    else
        false -> resp;                              ;;; server answers 404
    endif;
enddefine;

'serving on port ' >< port >< '...' =>
http_serve_n(port, handler, count);
'done.' =>
