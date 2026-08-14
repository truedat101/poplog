;;; test_http_server.p — suite for LIB * HTTP_SERVER
;;; Launches examples/http_hello.p in a second Poplog process (via
;;; LIB * SHELL) and exercises it with curl.  Run from the repo root.
uses poptest;
uses shell;
uses json;

lconstant port = 18400 + (sys_real_time() rem 500);
lconstant base = 'http://127.0.0.1:' >< (port sys_>< nullstring);

vars job, out, status, obj;

;;; serve exactly 6 requests, then the process exits by itself
shell_bg('./poplog target/pop/basepop11 examples/http_hello.p '
         >< (port sys_>< nullstring) >< ' 6') -> job;

;;; wait for the port to answer (up to ~5s)
vars tries = 0, up = false;
until up or tries > 50 do
    shell_run('curl -s -m 2 ' >< base >< '/hello') -> (out, status);
    if status == 0 then true -> up else syssleep(10) endif;
    tries + 1 -> tries;
enduntil;
check_true('server came up', up);
check('hello body', out, 'hello from Pop-11\n');

shell_run('curl -s "' >< base >< '/greet?name=poplog"') -> (out, status);
json_parse(out) -> obj;
check('greet query', obj('query'), 'name=poplog');
check('greet method', obj('method'), 'GET');

shell_run('curl -s -d "round trip body" ' >< base >< '/echo') -> (out, status);
check('echo body', out, 'round trip body');

shell_run('curl -s -o /dev/null -w "%{http_code}" ' >< base >< '/nope')
    -> (out, status);
check('unknown route 404', out, '404');

shell_run('curl -s -o /dev/null -w "%{http_code}" ' >< base >< '/boom')
    -> (out, status);
check('handler mishap 500', out, '500');

;;; the /boom mishap must not have killed the server
shell_run('curl -s ' >< base >< '/hello') -> (out, status);
check('server survived 500', out, 'hello from Pop-11\n');

;;; that was request 6 of 6 — the server process should now exit cleanly
shell_wait(job) -> (out, status);
check('served-count exit', status, 0);
check_true('server logged done', issubstring('done.', 1, out) and true);

test_summary();
