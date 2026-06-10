;;; TEACH RC_GRAPHIC walkthrough: every example from the teach file, in order.
uses rc_graphic;
rc_start();

;;; -- Drawing lines --
rc_drawline(-200, 0, 200, 0);
rc_drawline(0, -200, 0, 200);
rc_jumpto(-150, -150);
rc_drawto(-150, 150);
rc_drawto(150, 150);
rc_drawpoint(100, -50);
rc_print_at(-90, -180, 'hello from the turtle');
rc_pump(40);

;;; -- Turtling: square --
rc_start();
repeat 4 times
    rc_draw(150);
    rc_turn(90);
endrepeat;

;;; -- polygon procedure --
define polygon(side, n);
    repeat n times
        rc_draw(side);
        rc_turn(360 / n);
    endrepeat;
enddefine;

rc_start();
polygon(100, 3);
polygon(100, 5);
polygon(100, 8);
rc_pump(40);

;;; -- square spiral --
rc_start();
lvars side;
for side from 4 by 4 to 240 do
    rc_draw(side);
    rc_turn(91);
endfor;
rc_pump(40);

;;; -- jumping and relative moves --
rc_start();
rc_jump(100);
rc_turn(90);
rc_draw(50);
rc_jumpby(-200, -50);
rc_drawby(50, 100);

;;; -- circles and arcs --
rc_start();
rc_jumpto(0, -100);
rc_arc_around(100, 360);
rc_jumpto(-220, 220);
rc_draw_rectangle(120, 80);
rc_jumpto(100, 220);
rc_draw_oblong(120, 80, 20);
rc_draw_arc(-60, -120, 120, 80, 0, 180 * 64);
rc_pump(40);

;;; -- coordinate frames --
rc_start();
rc_set_coordinates(0, rc_window_ysize, 0.5, -0.5);
rc_drawline(0, 0, 400, 400);
rc_drawline(0, 400, 400, 0);
rc_pump(40);

rc_start();
lvars i;
for i from 1 to 5 do
    polygon(100, 4);
    rc_stretch_frame_by(0.7);
endfor;
rc_pump(40);

;;; -- turtle state checks (non-visual invariants) --
rc_start();
rc_jumpto(10, 20);
unless rc_xposition = 10 and rc_yposition = 20 then
    mishap(0, 'TEACH WALKTHROUGH: jumpto state wrong')
endunless;
rc_turn(45);
unless rc_heading = 45 then mishap(0, 'TEACH WALKTHROUGH: heading wrong') endunless;
lvars st = rc_save_state();
rc_jumpto(0, 0); rc_turn(100);
rc_restore_state(st);
unless rc_xposition = 10 and rc_heading = 45 then
    mishap(0, 'TEACH WALKTHROUGH: restore_state wrong')
endunless;

;;; -- rc_mouse machinery (non-interactive parts) --
uses rc_mouse;
lvars m = gfx_mark();
rc_drawline(-50, -50, 50, 50);
gfx_rewind(m);

rc_finish();
'teach-walkthrough-PASSED' =>
