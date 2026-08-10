/* --- File utilities -----------------------------------------------------
 > File:            pop/lib/lib/fileutils.p
 > Purpose:         Whole-file read/write, line access, stat, globbing
 > Documentation:   HELP * FILEUTILS
 > Related Files:   tools/tests/test_fileutils.p, LIB * STRUTILS
 */
compile_mode :pop11 +strict;

uses strutils;

section $-fileutils =>
    file_to_string string_to_file file_append file_lines
    file_size file_mtime dir_files;

define file_to_string(file) -> s;
    lvars rep = discin(file), c, n = 0;
    until (rep() ->> c) == termin do
        c;
        n + 1 -> n;
    enduntil;
    consstring(n) -> s;
enddefine;

define string_to_file(s, file);
    lvars out = discout(file);
    appdata(s, out);
    out(termin);
enddefine;

define file_append(s, file);
    lvars old;
    if sys_file_exists(file) then
        file_to_string(file) -> old;
        string_to_file(old <> s, file);
    else
        string_to_file(s, file);
    endif;
enddefine;

define file_lines(file) -> l;
    str_lines(file_to_string(file)) -> l;
enddefine;

;;; sys_file_stat fills a caller-supplied vector: element 1 is the byte
;;; size, element 2 the modification time (epoch seconds)
define lconstant statfield(file, i) -> v;
    lvars vec = sys_file_stat(file, initv(2));
    if vec then subscrv(i, vec) else false endif -> v;
enddefine;

define file_size(file) -> n;
    statfield(file, 1) -> n;
enddefine;

define file_mtime(file) -> t;
    statfield(file, 2) -> t;
enddefine;

;;; expand a glob pattern to a sorted list of matching paths
define dir_files(pattern) -> l;
    lvars rep = sys_file_match(pattern, '', false, false), f, n = 0;
    until (rep() ->> f) == termin do
        f;
        n + 1 -> n;
    enduntil;
    syssort(conslist(n), alphabefore) -> l;
enddefine;

endsection;
