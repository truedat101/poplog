/* --- Copyright University of Birmingham 2005. All rights reserved. ------
 > File:            $usepop/pop/lib/lib/emacsreadline.p
 > Was:             $poplocal/local/lib/emacsreadline.p
 > Purpose:         Make readline work for emacs users
 > Author:          Aaron Sloman, Nov 10 1994 (see revisions)
 > Documentation:   See HELP * READLINE
 > Related Files:
 */

/*

Because of the way the emacs package in $popcontrib/emacs
communicates with Pop-11, a readline() command in a file other than the
interactive file will not read from the emacs interactive buffer.

This version of readline is defined so as to work in that context.

*/


section;

;;; prevent recompilation
if isdefined("emacsreadline") then [endsection;] -> proglist endif;

;;; save the old value of readline in case it is needed.
global constant procedure emacs_saved_readline = readline;


define emacsreadline() -> list;
    lvars item, list,
        procedure rep = incharitem(charin);     ;;; item repeater

    dlocal popnewline = true, popprompt = pop_readline_prompt;

    ;;; Make a list of items to the next newline.  Also stop at -termin- (end
    ;;; of input): a non-interactive stream (e.g. piped input) can reach EOF
    ;;; with no closing newline, and the original `== newline` test alone then
    ;;; loops forever re-reading termin -- which steadily fills, then overruns,
    ;;; the user stack.  Return termin (as the standard readline does) when EOF
    ;;; is hit with nothing read, so the caller's toplevel sees end-of-input.
    [% until (rep() ->> item) == newline do
        quitif(item == termin);
        item
     enduntil %] -> list;
    if item == termin and null(list) then termin -> list endif;

enddefine;

emacsreadline -> readline;

/*
;;; test it
emacsreadline() =>

*/

endsection;

/* --- Revision History ---------------------------------------------------
--- Aaron Sloman, Jan 15 2005
        Moved into system dir
--- Aaron Sloman, Jan  4 1996
    Fixed to use pop_readline_prompt instead of the fixed prompt.
 */
