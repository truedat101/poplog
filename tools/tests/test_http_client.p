;;; test_http_client.p — suite for LIB * HTTP_CLIENT
;;; Full circle: the Pop-11 HTTP client is exercised against the
;;; Pop-11 HTTP server (examples/http_hello.p), launched via
;;; LIB * SHELL.  Run from the repo root.
uses poptest;
uses shell;
uses json;
uses http_client;

lconstant port = 19000 + (sys_real_time() rem 500);
lconstant base = 'http://127.0.0.1:' >< (port sys_>< nullstring);

vars job, out, hdrs, status, obj;

;;; serve exactly 6 requests, then the server exits by itself
shell_bg('./poplog target/pop/basepop11 examples/http_hello.p '
         >< (port sys_>< nullstring) >< ' 6') -> job;

;;; wait for the server (each successful probe consumes request 1)
vars probe_ok;
define lconstant try_up(url);
    lvars sl = stacklength();
    dlocal prmishap =
        procedure(m, c); false -> probe_ok; exitto(try_up) endprocedure;
    true -> probe_ok;
    http_get(url);
    setstacklength(sl);
enddefine;

vars tries = 0;
repeat
    try_up(base >< '/hello');
    quitif(probe_ok);
    tries + 1 -> tries;
    quitif(tries > 50);
    syssleep(10);
endrepeat;
check_true('server came up', probe_ok);

;;; request 2: the general form — body, response headers, status
http_request('GET', base >< '/hello', '', [], 5) -> (out, hdrs, status);
check('get body', out, 'hello from Pop-11\n');
check('get status', status, 200);
check('response header parsed', hdrs('content-type'),
      'text/plain; charset=utf-8');
check_true('connection header present', hdrs('connection') and true);

;;; request 3: query string + custom request header travel intact
http_request('GET', base >< '/greet?name=pop11', '',
             ['X-Probe: yes'], 5) -> (out, hdrs, status);
json_parse(out) -> obj;
check('query passed', obj('query'), 'name=pop11');
check('json content type', hdrs('content-type'), 'application/json');

;;; request 4: POST body round trip
http_post(base >< '/echo', 'client says hi', 'text/plain')
    -> (out, status);
check('post echo', out, 'client says hi');
check('post status', status, 200);

;;; request 5: 404 is a status, not an error
http_get(base >< '/nowhere') -> (out, status);
check('404 status', status, 404);

;;; request 6: last one — lets the server exit
http_get(base >< '/hello') -> (out, status);
check('final request', status, 200);

shell_wait(job) -> (out, status);
check('server exited cleanly', status, 0);

;;; transport errors mishap (nothing is listening here any more)
check_mishaps('connection refused',
    procedure; http_get(base >< '/hello') endprocedure);
check_mishaps('bad host',
    procedure;
        http_request('GET', 'http://nonexistent.invalid/', '', [], 2)
    endprocedure);

check_true('client version', issubstring('curl', 1, http_client_version()) and true);

test_summary();
