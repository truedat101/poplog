;;; test_fileutils.p — suite for LIB * FILEUTILS (run via tools/test-libs.sh)
uses poptest;
uses fileutils;

lconstant tf = systmpfile(false, 'poptest_fu', '');

string_to_file('hello\nworld\n', tf);
check('round trip', file_to_string(tf), 'hello\nworld\n');
check('file_lines', file_lines(tf), ['hello' 'world']);
check('file_size', file_size(tf), 12);
check_true('file_mtime is integer', isintegral(file_mtime(tf)));
file_append('more\n', tf);
check('append', file_to_string(tf), 'hello\nworld\nmore\n');
string_to_file('', tf);
check('empty write', file_to_string(tf), '');
check('missing size', file_size('/nonexistent/nope'), false);
check('missing mtime', file_mtime('/nonexistent/nope'), false);

;;; binary safety: NUL and high bytes survive a round trip
lconstant bin = consstring(0, 255, 10, `x`, 4);
string_to_file(bin, tf);
check('binary round trip', file_to_string(tf), bin);

;;; globbing: this suite file is found by its own pattern
lconstant here = dir_files('tools/tests/test_*.p');
check_true('dir_files finds suites',
           length(here) >= 1 and member('tools/tests/test_fileutils.p', here));
check('dir_files no match', dir_files('/nonexistent/*.zzz'), []);

sysdelete(tf) -> ;

test_summary();
