/* --- Laya typed decisions, local, behind the TypeSafe client -----------
 > File:            packages/laya/laya.p
 > Purpose:         Answer ts_eval locally with Laya on Apple Silicon (MLX)
 > Documentation:   packages/laya/README.md
 > Related Files:   packages/typesafe/typesafe.p, LIB * RUN_UNIX_PROGRAM
 >
 > NOT part of the Poplog release; out-of-tree like LIB TYPESAFE.
 >
 > Laya (https://github.com/mizorewww/laya-mlx) takes the same request as
 > the hosted /v1/systemone -- state plus a map of noul/choice/score
 > questions -- and returns the same answers.  So nothing new is needed at
 > the call site: this library swaps ts_transport for one that talks to a
 > `laya-mlx serve --stdio` child over a pipe, and ts_eval, ts_noul,
 > ts_choice and ts_score work unchanged.
 >
 > Why a child process and not HTTP: no port to choose, nothing listening
 > that another user could reach, and the child's lifetime is ours -- when
 > Poplog exits the pipe closes and the server sees end of input and exits.
 > Why not in-process: the model runs on Metal from Python, and a crash
 > there should not take the Poplog session with it.
 >
 > The protocol is JSON-RPC 2.0, one message per line.  An error carries
 > data.status, the HTTP status the same failure would get from the
 > server's HTTP transport, so typesafe's error handling applies as is.
 */
compile_mode :pop11 +strict;

uses typesafe;
uses json;
uses run_unix_program;

section $-laya
    ts_transport ts_require_key ts_model http_request
    json_parse json_generate
=>
    laya_command laya_model laya_router laya_dtype laya_extra_args
    laya_start laya_stop laya_running laya_pid laya_health
    laya_transport laya_install laya_uninstall
;

;;; ------------------------------------------------------------- settings
;;; The command is searched for on $PATH unless it starts with '/'.  Point
;;; LAYA_MLX at a venv's bin/laya-mlx to use one without activating it.

vars laya_command    = systranslate('LAYA_MLX') or 'laya-mlx';
vars laya_model      = 'aac6fef/laya-mlx';
vars laya_router     = false;   ;;; true: route by language over all three
vars laya_dtype      = 'float16';
vars laya_extra_args = [];      ;;; e.g. ['--device' 'cpu']

;;; ---------------------------------------------------------------- child

lvars indev = false, outdev = false, child = false, next_id = 0;

lconstant BUFSIZE = 65536;
lvars buf = inits(BUFSIZE), bufpos = 1, buflen = 0;

define laya_running();
    child and true
enddefine;

define laya_pid();
    child
enddefine;

;;; Reap the child and forget it, so the next call starts a fresh one.
define lconstant forget();
    if indev then sysclose(indev) endif;
    if outdev then sysclose(outdev) endif;
    if child then sys_wait(child) -> (,) endif;
    false ->> indev ->> outdev -> child;
    1 -> bufpos; 0 -> buflen;
enddefine;

define lconstant getc() -> c;
    lvars n;
    if bufpos > buflen then
        sysread(outdev, buf, BUFSIZE) -> n;
        if n == 0 then termin -> c; return endif;
        n -> buflen;
        1 -> bufpos;
    endif;
    fast_subscrs(bufpos, buf) -> c;
    bufpos + 1 -> bufpos;
enddefine;

;;; One response line without its newline; termin if the child has gone.
define lconstant read_line() -> line;
    lvars c, n = 0;
    repeat
        getc() -> c;
        if c == termin then
            if n == 0 then termin -> line; return endif;
            quitloop
        endif;
        quitif(c == `\n`);
        c; n + 1 -> n;
    endrepeat;
    consstring(n) -> line;
enddefine;

;;; Send PARAMS_JSON (already-encoded JSON, or false for none) as METHOD
;;; and return the parsed response, or termin if the child has gone.
define lconstant call(method, params_json) -> msg;
    lvars line, id;
    next_id + 1 ->> next_id -> id;
    lvars req = '{"jsonrpc":"2.0","id":' sys_>< id
                <> ',"method":"' <> method <> '"'
                <> (if params_json then ',"params":' <> params_json else '' endif)
                <> '}\n';
    syswrite(indev, req, length(req));
    ;;; load-bearing, as in LIB * JSONRPC: an unflushed pipe device holds
    ;;; the request back and both sides wait forever
    sysflush(indev);
    read_line() -> line;
    if line == termin then termin -> msg; return endif;
    json_parse(line) -> msg;
    unless msg('id') = id then
        mishap(line, 1, 'laya: response id does not match request ' sys_>< id)
    endunless;
enddefine;

define laya_start();
    returnif(child);
    lvars args =
        [% 'serve', '--stdio', '--dtype', laya_dtype,
           if laya_router then '--router' else '--model', laya_model endif,
           explode(laya_extra_args) %];
    ;;; stderr is inherited (false): load progress, warnings and tracebacks
    ;;; go where the user can see them, and never into the protocol
    run_unix_program(laya_command, args, true, true, false, false)
        -> (indev, outdev, , , child);
    ;;; The first answer waits for the model to load -- seconds, more on a
    ;;; first download -- so ask for it here, where a failure to start is
    ;;; reported as one rather than as a failed question.
    lvars msg = call('health', false);
    if msg == termin then
        forget();
        mishap(laya_command, 1,
               'laya: server exited while starting (see its output above)')
    endif;
enddefine;

define laya_stop();
    forget();
enddefine;

;;; property with 'status' and 'model' -- the checkpoint that will answer
define laya_health() -> p;
    laya_start();
    lvars msg = call('health', false);
    if msg == termin then
        forget();
        mishap(0, 'laya: server exited')
    endif;
    msg('result') -> p;
enddefine;

;;; ------------------------------------------------------------ transport
;;; http_request's signature, so it can stand in for it as ts_transport:
;;;     (method, url, body, headers, timeout) -> (body, headers, status)
;;; METHOD, URL, HEADERS and TIMEOUT mean nothing to a pipe.  There is no
;;; timeout: a call blocks until the model answers.

define laya_transport(method, url, body, headers, timeout)
                                            -> (rbody, rheaders, status);
    lvars msg, err;
    newmapping([], 4, false, true) -> rheaders;
    laya_start();
    call('systemone', body) -> msg;
    if msg == termin then
        ;;; The child died mid-call.  Forget it so the next call starts a
        ;;; new one, and fail this call cleanly: 503 is not retried by
        ;;; ts_eval, because a model that crashes on a request will very
        ;;; likely crash on it again.
        forget();
        'laya-mlx server exited during the request (see its output above)'
            -> rbody;
        503 -> status;
    elseif msg('error') ->> err then
        err('message') -> rbody;
        (err('data') and err('data')('status')) or 500 -> status;
    else
        json_generate(msg('result')) -> rbody;
        200 -> status;
    endif;
enddefine;

;;; Point ts_eval at the local model, or back at the hosted API.
define laya_install();
    laya_transport -> ts_transport;
    false -> ts_require_key;
    'laya' -> ts_model;     ;;; informational: the child chose its checkpoint
enddefine;

define laya_uninstall();
    http_request -> ts_transport;
    true -> ts_require_key;
    'jev-latest' -> ts_model;
enddefine;

laya_install();

endsection;
