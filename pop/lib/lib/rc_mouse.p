/* --- Apple M-silicon Poplog. Distributed under the Free Poplog licence. ---
 > File:            pop/lib/lib/rc_mouse.p
 > Purpose:         Facilities for tracking the mouse in rc_window
 > Documentation:   TEACH * RC_GRAPHIC, HELP * RC_GRAPHIC, HELP * POPGFX
 > Related Files:   LIB * RC_GRAPHIC, LIB * POPGFX
 >
 > A port of C.x/x/pop/lib/rc_mouse.p (Aaron Sloman et al) onto the
 > native graphics backend, for Poplog builds without X (macOS).  The
 > public interface follows the original: rc_mouse_do runs an event
 > loop dispatching through rc_button_procedures/rc_move_procedures,
 > and rc_mouse_draw draws with rubber-banding.  Differences:
 >  - events are synthesised by polling (gfx_mouse/gfx_mouse_down)
 >    rather than delivered by Xt callbacks; rc_mouse_setup and
 >    rc_mouse_disable are retained as no-ops;
 >  - the data argument passed to button procedures is the button
 >    number directly (an integer, X numbering: 1 left, 2 middle,
 >    3 right; negative on release) -- not an external pointer;
 >  - rubber-banding uses the canvas mark/rewind facility
 >    (gfx_mark/gfx_rewind) instead of GXxor rasterops;
 >    rc_rubber_function is accepted but unused.
 */

compile_mode :pop11 +strict;

section;

uses rc_graphic;

vars rc_rubber_function;            ;;; compatibility only
unless isinteger(rc_rubber_function) then 6 -> rc_rubber_function endunless;

vars
    rc_button_procedures = [],      ;;; run on button events
    rc_move_procedures = [],        ;;; run on move events
    rc_mousing = false;

define lconstant do_button_actions(widget, item, data);
    lvars proc, widget, item, data;
    if rc_mousing then
        for proc in rc_button_procedures do
            recursive_valof(proc)(widget, item, data);
        endfor;
    endif;
enddefine;

define lconstant do_move_actions(widget, item, data);
    lvars proc, widget, item, data;
    if rc_mousing then
        for proc in rc_move_procedures do
            recursive_valof(proc)(widget, item, data);
        endfor;
    endif;
enddefine;

define rc_mouse_setup(widget);
    ;;; events are polled on this backend; nothing to install
    lvars widget;
enddefine;

define rc_mouse_disable(widget);
    lvars widget;
enddefine;

    /*  poll the backend and synthesise button/move events through
        do_button_actions/do_move_actions until done() returns true.
        Buttons use X numbering: 1 left, 2 middle, 3 right; release
        events carry the negated number. */
define lconstant rc_mouse_poll(done);
    lvars procedure done;
    lconstant gfx_button = {0 2 1};         ;;; X button -> gfx button
    lvars b, lastx = false, lasty = false, x, y;
    lvars lastdown = {% false, false, false %};
    until done() do
        quitunless(gfx_step());             ;;; window closed
        gfx_mouse() -> y -> x;
        round(x) -> x; round(y) -> y;
        unless x = lastx and y = lasty then
            x -> lastx; y -> lasty;
            do_move_actions(rc_window, "move", 0);
        endunless;
        for b from 1 to 3 do
            lvars now = gfx_mouse_down(subscrv(b, gfx_button));
            unless now == subscrv(b, lastdown) then
                now -> subscrv(b, lastdown);
                do_button_actions(rc_window, "button",
                                  if now then b else -b endif);
            endunless;
        endfor;
        syssleep(1);
    enduntil;
enddefine;

define rc_mouse_do(first_input, other_input, test_exit);
    lvars first = true, procedure (first_input, other_input, test_exit);
    lvars rc_mouse_done = false;

    ;;; When a mouse button is first pressed call first_input.
    ;;; Thereafter call other_input on every move or button event.
    ;;; Once first_input has run, call test_exit after every event and
    ;;; stop when it returns true.

    rc_mouse_setup(rc_window);

    dlocal
        rc_mousing,
        rc_button_procedures = #_< writeable [0] >_#,
        rc_move_procedures = #_< writeable [0] >_#
        ;

    define lconstant handle_event(widget, item, data);
        lvars widget, item, data, x, y;
        rc_transxyin(gfx_mouse()) -> (x, y);
        if data >= 0 then
            if first then
                if item = "button" then
                    first_input(x, y, data, item); false -> first;
                endif
            else
                other_input(x, y, data, item)
            endif;
        endif;
        if not(first) and test_exit(x, y, data, item) then
            true -> rc_mouse_done;
        endif
    enddefine;

    handle_event -> front(rc_button_procedures);
    handle_event -> front(rc_move_procedures);

    true -> rc_mousing;

    rc_mouse_poll(procedure(); rc_mouse_done endprocedure);
enddefine;

define rc_mouse_draw(listpoints, stop_button);
    ;;; Draw a picture with the mouse, rubber-banding the next line.
    ;;; If listpoints is true, return the list of confirmed points.
    lvars listpoints, list = [], stop_button,
          lastx, lasty,             ;;; last confirmed point
          band = false;             ;;; canvas mark while banding

    define lconstant first(x, y, data, item);
        lvars x, y, data, item;
        rc_jumpto(x, y);
        rc_drawpoint(x, y);
        x -> lastx; y -> lasty;
        gfx_mark() -> band;
        if listpoints then rc_conspoint(x, y) :: list -> list endif
    enddefine;

    define lconstant other(x, y, data, item);
        lvars x, y, data, item;
        returnif(item == "button" and data < 0);
        ;;; remove the previous rubber line, draw the current one
        gfx_rewind(band);
        rc_jumpto(lastx, lasty);
        rc_drawto(x, y);
        if item == "button" then
            ;;; confirmed: keep it and band from the new point
            x -> lastx; y -> lasty;
            gfx_mark() -> band;
            if listpoints then rc_conspoint(x, y) :: list -> list endif
        endif;
    enddefine;

    define lconstant exit(/*x, y,*/ data, item);
        lvars data, item;
        -> ->;
        item == "button" and data == stop_button
    enddefine;

    rc_mouse_do(first, other, exit);
    if band then gfx_rewind(band) endif;    ;;; drop the dangling band
    if listpoints then rev(list) endif
enddefine;

constant rc_mouse = true;       ;;; for "uses"

endsection;
