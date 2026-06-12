/* examples/cube3d.p -- a spinning 3D wireframe cube, projected to 2D.
 *
 * Eight vertices, twelve edges; each frame rotates them about two axes,
 * applies a perspective projection, and redraws.  Demonstrates per-frame
 * animation on the retained canvas (gfx_clear / gfx_step).
 *
 * Run:  ./poplog ./target/pop/basepop11 examples/cube3d.p
 */

uses popgfx;

false -> popradians;            ;;; cos/sin in degrees

lconstant W = 600, H = 600, CX = 300, CY = 300, SCALE = 150, DIST = 4;
gfx_init('3D Cube -- Pop-11', W, H) -> ;
lconstant fg = gfx_rgb(120, 200, 255);

;;; unit cube centred at the origin: 8 vertices, 12 edges (1-based indices)
lconstant verts = {
    {-1 -1 -1} { 1 -1 -1} { 1  1 -1} {-1  1 -1}
    {-1 -1  1} { 1 -1  1} { 1  1  1} {-1  1  1} };
lconstant edges = [ [1 2][2 3][3 4][4 1]          ;;; back face
                    [5 6][6 7][7 8][8 5]          ;;; front face
                    [1 5][2 6][3 7][4 8] ];       ;;; connecting struts

;;; rotate vertex by (ay about Y, ax about X), perspective-project, and leave
;;; the screen point as two stack values: sx (lower), sy (top).
define lconstant project(v, ay, ax);
    lvars v, ay, ax, x = v(1), y = v(2), z = v(3), x1, z1, y2, z2, f;
    x * cos(ay) + z * sin(ay) -> x1;
    z * cos(ay) - x * sin(ay) -> z1;
    y * cos(ax) - z1 * sin(ax) -> y2;
    y * sin(ax) + z1 * cos(ax) -> z2;
    DIST / (DIST - z2) -> f;                        ;;; nearer = bigger
    CX + x1 * f * SCALE,                            ;;; sx
    CY - y2 * f * SCALE                             ;;; sy (screen +y is down)
enddefine;

lvars angle = 20, i, e, pts;
repeat
    gfx_clear();
    {% for i from 1 to 8 do project(verts(i), angle, 25) endfor %} -> pts;
    fast_for e in edges do
        lvars a = e(1), b = e(2);
        gfx_line(pts(a*2-1), pts(a*2), pts(b*2-1), pts(b*2), fg, 2)
    endfor;
    quitunless(gfx_step());
    angle + 2 -> angle;
    syssleep(3)
endrepeat;

gfx_shutdown();
