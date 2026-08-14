;;; test_shell.p — suite for LIB * SHELL (run via tools/test-libs.sh)
uses poptest;
uses shell;

vars out, err, status, job;

shell_run('echo hi') -> (out, status);
check('run stdout', out, 'hi\n');
check('run status 0', status, 0);

shell_run('echo oops 1>&2') -> (out, status);
check('run merges stderr', out, 'oops\n');

shell_run('exit 7') -> (out, status);
check('run exit code', status, 7);
check('run exit output empty', out, '');

shell_run_full('echo good; echo bad 1>&2; exit 3') -> (out, err, status);
check('full stdout', out, 'good\n');
check('full stderr', err, 'bad\n');
check('full status', status, 3);

shell_lines('printf "a\\nb\\n"') -> (out, status);
check('lines', out, ['a' 'b']);

;;; big output must not deadlock the pipe
shell_run('head -c 200000 /dev/zero | tr "\\0" x') -> (out, status);
check('big output length', length(out), 200000);
check('big output status', status, 0);

;;; background job
shell_bg('sleep 1; echo done') -> job;
shell_wait(job) -> (out, status);
check('bg wait output', out, 'done\n');
check('bg wait status', status, 0);

;;; kill a running job: SIGTERM decodes to 143.  Give sh time to exec
;;; the command first (killing mid-startup gives sh's own exit code).
shell_bg('sleep 30') -> job;
syssleep(50);
shell_kill(job);
shell_wait(job) -> (out, status);
check('killed status', status, 143);

;;; timeout fires (sh may add a 'Terminated' notice to merged stderr,
;;; so assert on what matters: the command was cut short)
shell_timeout('sleep 30; echo late', 1) -> (out, status);
check('timeout status', status, 143);
check_false('timeout cut short', issubstring('late', 1, out) and true);

;;; timeout does not delay a fast command (watchdog is detached)
lconstant t0 = sys_real_time();
shell_timeout('echo quick', 30) -> (out, status);
check('timeout passthrough', out, 'quick\n');
check('timeout passthrough status', status, 0);
check_true('timeout returns promptly', sys_real_time() - t0 < 10);

check_mishaps('non-string cmd', procedure; shell_run(42) endprocedure);
check_mishaps('bad secs', procedure; shell_timeout('x', 0) endprocedure);

test_summary();
