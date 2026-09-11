/* --- Test framework for Poplog libraries --------------------------------
 > File:            pop/lib/lib/poptest.p
 > Purpose:         The check/must-fail test harness, formalized
 > Author:          D.Kordsmeier (@truedat101) and Claude (@claude), Aug 2026
 > Documentation:   HELP * POPTEST
 > Related Files:   tools/test-libs.sh (runner), suites in tools/tests/
 >
 > Formalizes the harness developed for tools/test-json.sh and
 > tools/test-crypto.sh: value checks, must-mishap checks (with the
 > prmishap/exitto trap and stack cleanup), and a greppable summary
 > line ('SUMMARY: ALL PASS' / 'SUMMARY: N FAILURES') that shell
 > runners key on.
 */
compile_mode :pop11 +strict;

section $-poptest =>
    check check_true check_false check_mishaps
    test_reset test_summary test_failures;

vars ncheck = 0, nfail = 0, trapped;

define test_reset();
    0 ->> ncheck -> nfail;
enddefine;

define check(name, got, want);
    ncheck + 1 -> ncheck;
    if got = want then
        'PASS ' >< name =>
    else
        'FAIL ' >< name =>
        got =>
        want =>
        nfail + 1 -> nfail;
    endif;
enddefine;

define check_true(name, val);
    check(name, val and true, true);
enddefine;

define check_false(name, val);
    check(name, val and true, false);
enddefine;

;;; run p; pass if it mishaps.  The trap: replace the error printer for
;;; this dynamic extent, unwind back here with exitto, and discard
;;; whatever the interrupted procedure left on the open stack.
define check_mishaps(name, p);
    lvars sl = stacklength();
    dlocal prmishap =
        procedure(m, c);
            true -> trapped;
            exitto(check_mishaps);
        endprocedure;
    false -> trapped;
    p();
    setstacklength(sl);
    check(name, trapped, true);
enddefine;

define test_failures() -> n;
    nfail -> n;
enddefine;

;;; prints the greppable summary and makes the process exit status
;;; meaningful: deliberate check_mishaps trapping marks the process
;;; failed (pop_exit_ok), so reassert the suite's own verdict
define test_summary();
    if nfail == 0 then
        'SUMMARY: ALL PASS (' >< ncheck >< ' checks)' =>
        true -> pop_exit_ok;
    else
        'SUMMARY: ' >< nfail >< ' FAILURES (of ' >< ncheck >< ' checks)' =>
        false -> pop_exit_ok;
    endif;
enddefine;

endsection;
