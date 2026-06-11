/* examples/rc_square.p -- minimal rc_graphic demo.
   Run:  ./poplog ./target/pop/pop11 examples/rc_square.p          */

uses rc_graphic;
rc_start();
repeat 4 times rc_draw(150); rc_turn(90) endrepeat;
rc_print_at(-60, -200, 'a square, from Pop-11');
rc_pump(500);           ;;; window stays live ~5 seconds
rc_finish();
