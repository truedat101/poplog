/* examples/vectrex.p -- a concept "screenshot" for a Vectrex-style game.
 *
 * The Vectrex (1982) was a vector-display console: bright phosphor lines on
 * black, portrait screen, no pixels.  This is a mock Minestorm/Asteroids
 * scene -- HUD, player ship, drifting rocks, and shots -- all in line art.
 *
 * Run:  ./poplog ./target/pop/basepop11 examples/vectrex.p
 */

uses popgfx;
false -> popradians;            ;;; cos/sin in degrees

lconstant W = 480, H = 620;
gfx_init('VECTREX -- concept', W, H) -> ;
lconstant glow = gfx_rgb(170, 255, 235);   ;;; phosphor white-cyan

;;; draw a closed polygon from a flat list [x1 y1 x2 y2 ...]
define lconstant poly(pts, col, t);
    lvars pts, col, t, n = length(pts) div 2, i;
    for i from 1 to n do
        lvars j = (i mod n) + 1;
        gfx_line(pts(i*2-1), pts(i*2), pts(j*2-1), pts(j*2), col, t)
    endfor
enddefine;

;;; a jagged asteroid centred at (cx,cy)
define lconstant asteroid(cx, cy, r, col);
    lvars cx, cy, r, col, n = 9, i;
    poly([% for i from 0 to n-1 do
        lvars a = i * 360 / n, rr = r * (0.72 + random(0.5));
        cx + rr*cos(a), cy + rr*sin(a)
    endfor %], col, 1)
enddefine;

;;; --- HUD ------------------------------------------------------------------
gfx_rect(16, 16, W-16, H-16, gfx_rgb(60,90,85), 1);          ;;; screen border
gfx_text(30, 26, glow, 'SCORE  04250');
gfx_text(W-150, 26, glow, 'HI  19880');
;;; remaining lives, as little ships, top area
lvars k;
for k from 0 to 2 do
    lvars bx = 34 + k*22;
    poly([% bx, 58, bx-8, 74, bx, 68, bx+8, 74 %], glow, 1)
endfor;

;;; --- field ----------------------------------------------------------------
asteroid(130, 200, 46, glow);
asteroid(340, 150, 34, glow);
asteroid(250, 300, 60, glow);
asteroid(380, 340, 26, glow);

;;; a UFO
poly([% 70, 420, 110, 420, 124, 434, 56, 434 %], glow, 1);
gfx_line(82, 420, 96, 408, glow, 1);
gfx_line(96, 408, 112, 420, glow, 1);

;;; player ship -- a dart at the bottom, pointing up
lconstant px = 240, py = 540;
poly([% px, py-26,  px+18, py+18,  px, py+8,  px-18, py+18 %], glow, 2);
gfx_line(px, py+8, px, py+24, gfx_rgb(255,160,90), 2);       ;;; thruster flame

;;; shots streaking up from the ship
for k from 0 to 2 do
    lvars sx = px + (k-1)*40, sy = py - 70 - k*30;
    gfx_line(sx, sy, sx, sy-14, glow, 1)
endfor;

gfx_text(150, H-40, gfx_rgb(150,180,175), 'MINE  STORM');

gfx_run(3000);          ;;; ~60s, or until you close it
gfx_shutdown();
