/* --- A Forth for Poplog -------------------------------------------------
 > File:        pop/lib/lib/forth.p
 > Purpose:     Load the Poplog Forth subsystem and switch to it
 > Related:     $usepop/pop/forth/src/forth.p
 >
 > At the Pop-11 prompt,  `uses forth;`  loads the Forth subsystem (if it
 > isn't already loaded) and switches the interactive compiler to it, so
 > you land in the Forth REPL.  Type `bye` (or `pop11`) to return.
 */

#_TERMIN_IF DEF POPC_COMPILING

section;

uses subsystem;

unless is_subsystem_loaded("forth") then
    pop11_compile('$usepop/pop/forth/src/forth.p');
endunless;

;;; enter the Forth subsystem as the interactive top level
"forth" -> sys_compiler_subsystem(`c`);

endsection;
