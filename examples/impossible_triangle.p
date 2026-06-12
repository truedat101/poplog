/* examples/impossible_triangle.p -- the Penrose "tribar" impossible triangle.
 *
 * Three identical beams, each rotated 120 deg about the centre, each drawn so
 * its far end overlaps the next beam -- a loop that cannot exist in 3D.
 *
 * Needs a graphics build (./configure --experimental-graphics, or
 * `nix build .#poplog-gfx`).  Run from the Poplog source tree with:
 *     ./poplog ./target/pop/basepop11 examples/impossible_triangle.p
 * or, with a graphics build's front-end on PATH:
 *     pop11 examples/impossible_triangle.p
 */

uses popgfx;
false -> popradians;            ;;; cos/sin in degrees

lconstant W = 620, H = 600, CX = 310, CY = 330;
gfx_init('Impossible Triangle -- Pop-11', W, H) -> ;
lconstant fg = gfx_rgb(255, 210, 90);

lconstant R = 165, BW = 34;     ;;; medial-triangle radius, beam width

;;; vertex k of the medial triangle (centreline corners), +y up, centred
define lconstant mv(k) -> y -> x;
    lvars k, a = 90 + 120*k;
    CX + R*cos(a) -> x;
    CY - R*sin(a) -> y;
enddefine;

;;; draw beam k: a parallelogram from corner k toward corner k+1, its far end
;;; extended by BW so it overlaps the next beam (the impossible joint).
define lconstant beam(k);
    lvars k, xa, ya, xb, yb, ux, uy, px, py, len, hw = BW/2;
    mv(k)   -> ya -> xa;
    mv(k+1) -> yb -> xb;
    xb - xa -> ux;  yb - ya -> uy;             ;;; A -> B direction
    sqrt(ux*ux + uy*uy) -> len;  ux/len -> ux;  uy/len -> uy;
    -uy -> px;  ux -> py;                       ;;; perpendicular
    ;;; make sure the perpendicular points OUTWARD (away from centre)
    lvars mx = (xa+xb)/2, my = (ya+yb)/2;
    if (mx+px-CX)**2 + (my+py-CY)**2 < (mx-CX)**2 + (my-CY)**2 then
        -px -> px;  -py -> py
    endif;
    ;;; Outer edge runs PAST the corner (by BW); inner edge stops at B.  The
    ;;; far cap is then a slanted end-face, and the next beam tucks under it --
    ;;; that asymmetry, repeated around the loop, is the impossible joint.
    lvars fx = xb + ux*BW, fy = yb + uy*BW;     ;;; extended outer-far
    lvars oxa = xa+px*hw, oya = ya+py*hw,  ixa = xa-px*hw, iya = ya-py*hw;
    lvars oxb = fx+px*hw, oyb = fy+py*hw,  ixb = xb-px*hw, iyb = yb-py*hw;
    gfx_line(oxa, oya, oxb, oyb, fg, 2);        ;;; outer long edge (extended)
    gfx_line(ixa, iya, ixb, iyb, fg, 2);        ;;; inner long edge (to B)
    gfx_line(oxa, oya, ixa, iya, fg, 2);        ;;; near cap
    gfx_line(oxb, oyb, ixb, iyb, fg, 2)         ;;; slanted far end-face
enddefine;

lvars k;
for k from 0 to 2 do beam(k) endfor;

gfx_text(120, H-40, gfx_rgb(180,180,190), 'Penrose tribar -- impossible in 3D');

gfx_run(3000);          ;;; ~60s, or until you close it
gfx_shutdown();
