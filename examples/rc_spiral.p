/* examples/rc_spiral.p -- the classic square spiral.
   Run:  ./poplog ./target/pop/pop11 examples/rc_spiral.p          */

uses rc_graphic;
rc_start();
lvars side;
for side from 4 by 4 to 240 do
    rc_draw(side); rc_turn(91);
endfor;
rc_pump(500);
rc_finish();
