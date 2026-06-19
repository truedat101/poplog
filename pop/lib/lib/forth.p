/* --- A Forth for Poplog -------------------------------------------------
 > File:        pop/lib/lib/forth.p
 > Purpose:     Load the Poplog Forth subsystem; define the `forth` command
 > Related:     $usepop/pop/forth/src/forth.p
 >
 > At the Pop-11 prompt:
 >      uses forth;     ;;; load the Forth subsystem (once)
 >      forth;          ;;; enter it -- you land in the Forth REPL
 > Inside Forth, `bye` (or `pop11`) returns you to Pop-11.
 >
 > Load (this file) and enter (the `forth` command) are kept separate on
 > purpose: switching the compiler subsystem redirects the *current* input,
 > which is only the terminal when the switch is run from a typed command --
 > doing it while this library file is still being read would divert the
 > file's own remaining source into Forth.
 */

#_TERMIN_IF DEF POPC_COMPILING

section;

uses subsystem;

unless is_subsystem_loaded("forth") then
    pop11_compile('$usepop/pop/forth/src/forth.p');
endunless;

;;; the interactive enter command -- type `forth();` at the Pop-11 prompt to
;;; drop into the REPL.  It must be a RUNTIME procedure call (not a macro that
;;; loops at compile time, which would desync the Pop-11 reader's look-ahead
;;; and break the return).  `bye`/`pop11` returns you to Pop-11.
;;; (.fth FILES are compiled through the registered subsystem via `load`.)
define global vars procedure forth();
    forth_repl();
enddefine;

endsection;
