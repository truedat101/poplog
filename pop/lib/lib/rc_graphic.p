/* --- Apple M-silicon Poplog. Distributed under the Free Poplog licence. ---
 > File:            pop/lib/lib/rc_graphic.p
 > Purpose:         Relative-coordinate graphics on the native backend
 > Documentation:   HELP * RC_GRAPHIC, TEACH * RC_GRAPHIC
 >
 > A port of C.x/x/pop/lib/rc_graphic.p (Aaron Sloman et al) from the
 > Xpw/XVed window layer onto the native graphics backend (Dear ImGui +
 > Metal -- LIB * POPGFX), for Poplog builds without X (macOS).  The
 > public interface, the turtle/coordinate-frame model, the defaults and
 > the clipping behaviour follow the original; only the window layer
 > differs:
 >  - rc_window is true while the native window is open (not a widget);
 >  - rc_window_x/y (screen position) are accepted but ignored;
 >  - rc_linestyle/rc_linefunction are accepted but ignored (no GC
 >    rasterops on Metal); rc_linewidth works;
 >  - arcs, oblongs and (when scales differ in magnitude) ellipses are
 >    drawn as exact polylines rather than X arcs;
 >  - rc_gfx_foreground (an extension) holds the pop_gfx rgba colour
 >    used for drawing, default white.
 */

compile_mode :pop11 +strict;

uses popgfx;

section;

/* WINDOW-LAYER STATE */

global vars rc_wm_input = false;            ;;; compatibility only

lvars gfx_live = false;                     ;;; window open?

define lconstant rc_islive() /* -> bool */;
    gfx_live and gfx_step()
enddefine;

;;; default macro (verbatim from the original): assign the expression
;;; (read up to the semicolon) unless test(name) == result
define lconstant macro RC_DEFAULT name test result /* default */;
    lvars name, test, result, item;
    dl([if ^test(^name) == ^result then]);
    repeat
        readitem() -> item;
    quitif(item == ";");
        item
    endrepeat;
    dl([-> ^name endif;])
enddefine;

/* POINTS (as in the original) */

global vars procedure(rc_conspoint, rc_destpoint);
RC_DEFAULT rc_conspoint isundef true conspair;
RC_DEFAULT rc_destpoint isundef true destpair;

define rc_getxy(/* <point> or x, y */) /* -> y -> x */;
    unless isnumber(dup()) then rc_destpoint() endunless
enddefine;

/* TURTLE STATE */

global vars rc_xposition, rc_yposition, rc_heading;
RC_DEFAULT rc_xposition isnumber false 0;
RC_DEFAULT rc_yposition isnumber false 0;
RC_DEFAULT rc_heading   isnumber 0;

/* WINDOW ATTRIBUTES */

global vars
    rc_window,
    rc_window_x, rc_window_y,
    rc_window_xsize, rc_window_ysize,
    rc_clipping,
    rc_xmin, rc_ymin, rc_xmax, rc_ymax,
;

RC_DEFAULT rc_window_xsize isinteger false 500;
RC_DEFAULT rc_window_ysize isinteger false 500;
RC_DEFAULT rc_window_x isinteger false 520;
RC_DEFAULT rc_window_y isinteger false 300;
RC_DEFAULT rc_clipping isboolean false true;
RC_DEFAULT rc_xmin isinteger false 0;
RC_DEFAULT rc_ymin isinteger false 0;
RC_DEFAULT rc_xmax isinteger false rc_window_xsize;
RC_DEFAULT rc_ymax isinteger false rc_window_ysize;

/* DRAWING ATTRIBUTES */

lvars linewidth = 1, linestyle = 0, linefunction = 3;

global vars rc_gfx_foreground;
unless isinteger(rc_gfx_foreground) then
    gfx_rgb(255, 255, 255) -> rc_gfx_foreground
endunless;

define active rc_linewidth(); linewidth enddefine;
define updaterof active rc_linewidth(w);
    lvars w; if w == 0 then 1 else w endif -> linewidth
enddefine;

define active rc_linestyle(); linestyle enddefine;
define updaterof active rc_linestyle(s); lvars s; s -> linestyle enddefine;

define active rc_linefunction(); linefunction enddefine;
define updaterof active rc_linefunction(f);
    lvars f; f -> linefunction
enddefine;

/* COORDINATE FRAME */

global vars rc_xscale, rc_yscale, rc_xorigin, rc_yorigin;
RC_DEFAULT rc_xorigin isnumber false rc_window_xsize >> 1;
RC_DEFAULT rc_yorigin isnumber false rc_window_ysize >> 1;
RC_DEFAULT rc_xscale isnumber false 1;
RC_DEFAULT rc_yscale isnumber false -1;

define vars rc_transxyout(x, y) /* -> y -> x */;
    lvars x, y;
    round(if rc_xscale == 1 then x else x * rc_xscale endif + rc_xorigin),
    round(if rc_yscale == 1 then y else y * rc_yscale endif + rc_yorigin),
enddefine;

define vars rc_transxyin(x, y) /* -> y -> x */;
    ;;; window -> user coordinates (the LIB RC_MOUSE definition)
    lvars x, y;
    (x - rc_xorigin) / rc_xscale,
    (y - rc_yorigin) / rc_yscale,
enddefine;

define rc_set_coordinates(xorigin, yorigin, xscale, yscale);
    lvars xorigin, yorigin, xscale, yscale;
    xorigin -> rc_xorigin;
    yorigin -> rc_yorigin;
    xscale -> rc_xscale;
    yscale -> rc_yscale;
enddefine;

define rc_shift_frame_by(/*x, y*/);
    lvars x, y;
    rc_getxy() -> y -> x;
    rc_xorigin + x * rc_xscale -> rc_xorigin;
    rc_yorigin + y * rc_yscale -> rc_yorigin;
enddefine;

define rc_stretch_frame_by(scale);
    lvars scale;
    scale * rc_xscale -> rc_xscale;
    scale * rc_yscale -> rc_yscale;
enddefine;

define rc_setsize();
    ;;; the native window does not resize the canvas; sizes are as created
enddefine;

/* CREATING AND CLEARING THE WINDOW */

define rc_new_window(width, height, xloc, yloc, setframe);
    lvars width, height, xloc, yloc, setframe;
    unless width >= 0 and height >= 0 then
        mishap(width, height, 2, 'WIDTH AND HEIGHT OF WINDOW MUST BE POSITIVE')
    endunless;

    width -> rc_window_xsize;
    height -> rc_window_ysize;
    xloc -> rc_window_x;            ;;; accepted, not used
    yloc -> rc_window_y;

    if setframe then
        0 ->> rc_xmin -> rc_ymin;
        width -> rc_xmax; height -> rc_ymax;
        rc_set_coordinates(width >> 1, height >> 1, 1, -1);
        0 ->> rc_xposition ->> rc_yposition -> rc_heading;
    endif;

    if gfx_live then gfx_shutdown(); false -> gfx_live endif;
    unless gfx_init('Xgraphic', width, height) then
        mishap(0, 'rc_graphic: CANNOT OPEN GRAPHICS WINDOW')
    endunless;
    true ->> gfx_live -> rc_window;
    ;;; settle the freshly created window: the Metal layer needs a few
    ;;; pumped frames before presented content reliably appears
    ;;; (matters interactively, where only one frame per drawing call
    ;;; follows)
    gfx_run(15);
enddefine;

define rc_clear_window();
    gfx_clear();
    gfx_step() -> ;
enddefine;

define rc_start();
    if rc_islive() then
        rc_clear_window();
    else
        rc_new_window(rc_window_xsize, rc_window_ysize,
                      rc_window_x, rc_window_y, true)
    endif;
    0 ->> rc_xposition ->> rc_yposition -> rc_heading;
enddefine;

define rc_finish();
    if gfx_live then gfx_shutdown() endif;
    false ->> gfx_live -> rc_window;
enddefine;

/* STATE SAVE/RESTORE (as original) */

define rc_thispoint() /* -> point */;
    rc_conspoint(rc_xposition, rc_yposition)
enddefine;

define rc_save_state() /* -> state */;
    consvector(rc_xposition, rc_yposition, rc_heading,
               rc_xorigin, rc_yorigin, rc_xscale, rc_yscale, 7)
enddefine;

define rc_restore_state(state);
    lvars state;
    explode(state)
        -> rc_yscale -> rc_xscale -> rc_yorigin -> rc_xorigin
        -> rc_heading -> rc_yposition -> rc_xposition;
enddefine;

/* TURTLE UTILITIES */

define rc_turn(angle);
    lvars angle;
    rc_heading + angle -> rc_heading;
    while rc_heading >= 360 do rc_heading - 360 -> rc_heading endwhile;
    while rc_heading < 0 do rc_heading + 360 -> rc_heading endwhile;
enddefine;

define rc_turnto(/*x, y*/);
    lvars dx, dy;
    (rc_getxy(/*x, y*/) - rc_yposition -> dy) - rc_xposition -> dx;
    if dx = 0.0 and dy = 0.0 then
        mishap(dx + rc_xposition, dy + rc_yposition, 2,
               'POSITION TOO CLOSE TO CURRENT LOCATION')
    endif;
    arctan2(dx, dy) -> rc_heading
enddefine;

define rc_newposition(amount) -> newy -> newx;
    lvars amount, newx, newy;
    dlocal popradians = false;
    (rc_xposition + amount * cos(rc_heading)) -> newx;
    (rc_yposition + amount * sin(rc_heading)) -> newy;
enddefine;

define rc_jump(amount);
    lvars amount;
    rc_newposition(amount) -> rc_yposition -> rc_xposition;
enddefine;

define rc_jumpby(dx, dy);
    lvars dx, dy;
    rc_xposition + dx -> rc_xposition;
    rc_yposition + dy -> rc_yposition;
enddefine;

define rc_jumpto(/* x, y */);
    rc_getxy() -> rc_yposition -> rc_xposition
enddefine;

/* LOW-LEVEL DRAWING (window coordinates, after transform + clip) */

define lconstant gfx_seg(x1, y1, x2, y2);
    lvars x1, y1, x2, y2;
    returnunless(gfx_live);
    gfx_line(x1, y1, x2, y2, rc_gfx_foreground, linewidth);
    gfx_step() -> ;
enddefine;

define rc_drawpoint(/*x,y*/);
    lvars x, y;
    rc_transxyout(rc_getxy()) -> y -> x;
    returnunless(gfx_live);
    gfx_point(x, y, rc_gfx_foreground);
    gfx_step() -> ;
enddefine;

define rc_point_here();
    rc_drawpoint(rc_xposition, rc_yposition)
enddefine;

/* CLIPPING (verbatim from the original) */

define lconstant rc_clip(x1, y1, x2, y2, xlim, pred) -> bothout;
    lvars p1out, p2out, x1, x2, y1, y2, xlim, procedure pred, bothout = false;
    pred(x1, xlim) -> p1out;
    pred(x2, xlim) -> p2out;
    if p1out and p2out then
        true -> bothout;
    else
        if p1out or p2out then
            xlim,
            round(y2
                - (y2 - y1)*(number_coerce((x2 - xlim),0.0s+1))/(x2 - x1));
            if p1out then -> y1 -> x1 else -> y2 -> x2 endif;
        endif;
        x1, y1, x2, y2
    endif
enddefine;

define rc_drawline(/*x1, y1, x2, y2*/);
    lvars x1, y1, x2, y2;
    rc_getxy() -> y2 -> x2;
    rc_getxy() -> y1 -> x1;

    rc_transxyout(x1, y1) -> y1 -> x1;
    rc_transxyout(x2, y2) -> y2 -> x2;

    if rc_clipping then
        returnif(rc_clip(x1, y1, x2, y2, rc_xmin, nonop <));
           -> (x1, y1, x2, y2);
        returnif(rc_clip(x1, y1, x2, y2, rc_xmax, nonop >));
           -> (x1, y1, x2, y2);
        returnif(rc_clip(y1, x1, y2, x2, rc_ymin, nonop <));
           -> (y1, x1, y2, x2);
        returnif(rc_clip(y1, x1, y2, x2, rc_ymax, nonop >));
           -> (y1, x1, y2, x2)
    endif;

    gfx_seg(x1, y1, x2, y2);
enddefine;

define rc_drawto(/* x, y */);
    lvars x, y;
    rc_getxy() -> y -> x;
    rc_drawline(rc_xposition, rc_yposition, x, y);
    x -> rc_xposition; y -> rc_yposition;
enddefine;

define rc_drawby(dx, dy);
    lvars dx, dy;
    rc_drawto(rc_xposition + dx, rc_yposition + dy)
enddefine;

define rc_draw(amount);
    lvars amount;
    rc_drawto(rc_newposition(amount));
enddefine;

/* RECTANGLES, OBLONGS AND ARCS
   X drew these directly; here arcs/oblongs are exact polylines
   (which also sidesteps the XDrawArc angle bug noted in the original). */

define rc_draw_rectangle(width, height);
    lvars width, height, x, y, w, h;
    rc_transxyout(rc_xposition, rc_yposition) -> y -> x;
    round(abs(width * rc_xscale)) -> w;
    round(abs(height * rc_yscale)) -> h;
    returnunless(gfx_live);
    gfx_rect(x, y, x + w, y + h, rc_gfx_foreground, linewidth);
    gfx_step() -> ;
enddefine;

    /*  elliptical arc as a polyline: centre (window coords), x/y radii,
        from angle1 for angleinc degrees (X convention: degrees ccw from
        three o'clock in WINDOW coords -- y flips handled by caller's
        transform having happened already) */
define lconstant gfx_ellarc(cx, cy, rx, ry, angle1, angleinc);
    lvars cx, cy, rx, ry, angle1, angleinc, n, i, a, px, py, qx, qy;
    dlocal popradians = false;
    returnunless(gfx_live);
    max(8, round(abs(angleinc) / 4)) -> n;       ;;; <= 4 deg per segment
    cx + rx * cos(angle1) -> px;
    cy - ry * sin(angle1) -> py;                 ;;; window y runs down
    for i from 1 to n do
        angle1 + angleinc * i / n -> a;
        cx + rx * cos(a) -> qx;
        cy - ry * sin(a) -> qy;
        gfx_line(px, py, qx, qy, rc_gfx_foreground, linewidth);
        qx -> px; qy -> py;
    endfor;
    gfx_step() -> ;
enddefine;

define rc_draw_oblong(width, height, radius);
    lvars width, height, radius, x, y, w, h, r;
    rc_transxyout(rc_xposition, rc_yposition) -> y -> x;
    round(abs(width * rc_xscale)) -> w;
    round(abs(height * rc_yscale)) -> h;
    round(abs(radius * rc_xscale)) -> r;
    min(r, min(w >> 1, h >> 1)) -> r;
    returnunless(gfx_live);
    ;;; straight edges
    gfx_line(x + r, y,     x + w - r, y,     rc_gfx_foreground, linewidth);
    gfx_line(x + r, y + h, x + w - r, y + h, rc_gfx_foreground, linewidth);
    gfx_line(x,     y + r, x,     y + h - r, rc_gfx_foreground, linewidth);
    gfx_line(x + w, y + r, x + w, y + h - r, rc_gfx_foreground, linewidth);
    ;;; corner quadrants
    gfx_ellarc(x + r,     y + r,     r, r,  90,  90);
    gfx_ellarc(x + w - r, y + r,     r, r,   0,  90);
    gfx_ellarc(x + r,     y + h - r, r, r, 180,  90);
    gfx_ellarc(x + w - r, y + h - r, r, r, 270,  90);
enddefine;

define rc_draw_arc(/*x, y*/ width, height, angle1, angleinc);
    ;;; X convention: bounding box top-left (user coords), angles in
    ;;; 64ths of a degree ccw from three o'clock
    lvars x, y, width, height, angle1, angleinc, w, h;
    rc_getxy() -> y -> x;
    rc_transxyout(x, y) -> y -> x;
    round(abs(width * rc_xscale)) -> w;
    round(abs(height * rc_yscale)) -> h;
    gfx_ellarc(x + w / 2, y + h / 2, w / 2, h / 2,
               angle1 / 64, angleinc / 64);
enddefine;

define rc_arc_around(radius, degrees);
    ;;; verbatim logic from the original
    lvars xcentre, ycentre, radius, degrees, dx1, dy1, dx2, dy2, alpha;
    dlocal popradians = false;

    radius * sin(rc_heading) -> dx1;
    radius * cos(rc_heading) -> dy1;
    rc_heading + degrees -> alpha;
    radius * sin(alpha) -> dx2;
    radius * cos(alpha) -> dy2;
    if degrees >= 0 then
        (rc_xposition - dx1 ->> xcentre) + dx2 -> rc_xposition;
        (rc_yposition + dy1 ->> ycentre) - dy2 -> rc_yposition;
    else
        (rc_xposition + dx1 ->> xcentre) - dx2 -> rc_xposition;
        (rc_yposition - dy1 ->> ycentre) + dy2 -> rc_yposition;
    endif;

    rc_draw_arc(
        xcentre - sign(rc_xscale) * radius,
        ycentre - sign(rc_yscale) * radius,
        dup(radius + radius),
        if degrees >= 0 then
            (rc_heading - 90) * 64
        else
            (90 + rc_heading) * 64
        endif,
        round(degrees * 64));
    rc_turn(degrees)
enddefine;

/* PRINTING STRINGS */

define rc_print_at(/*x, y*/ string);
    lvars x, y, string;
    unless isstring(string) then
        mishap(string, 1, 'STRING NEEDED')
    endunless;
    rc_transxyout(rc_getxy(/*x, y*/)) -> y -> x;
    returnunless(gfx_live);
    ;;; XpwDrawString anchors at the baseline; the backend anchors at the
    ;;; top-left of the text box (~13px font ascent)
    gfx_text(x, y - 13, rc_gfx_foreground, string);
    gfx_step() -> ;
enddefine;

define rc_print_here(string);
    lvars string;
    rc_print_at(rc_xposition, rc_yposition, string)
enddefine;

/* KEEPING THE WINDOW ALIVE: pump events for n hundredths of a second */

define rc_pump(hsecs);
    lvars hsecs, i;
    for i from 1 to hsecs div 2 do
        quitunless(gfx_step());
        syssleep(2)
    endfor
enddefine;

global constant rc_graphic = true;      ;;; for uses

endsection;
