/* examples/tenprint.p -- the classic 10 PRINT maze.
 *
 *   10 PRINT CHR$(205.5+RND(1)); : GOTO 10
 *
 * The one-liner that fills a Commodore 64 screen with a random diagonal
 * maze (see https://10print.org/).  Here each grid cell gets a random
 * "/" or "\", drawn as a line.
 *
 * Needs a graphics build (./configure --experimental-graphics, or
 * `nix build .#poplog-gfx`).  Run from the Poplog source tree with:
 *     ./poplog ./target/pop/basepop11 examples/tenprint.p
 * or, with a graphics build's front-end on PATH:
 *     pop11 examples/tenprint.p
 */

uses popgfx;

lconstant
    CELL = 24,                  ;;; cell size in pixels
    COLS = 30, ROWS = 24,
    W = COLS * CELL, H = ROWS * CELL;

gfx_init('10 PRINT -- Pop-11', W, H) -> ;

lconstant fg = gfx_rgb(120, 255, 140);   ;;; C64-ish green on black

lvars row, col;
for row from 0 to ROWS - 1 do
    for col from 0 to COLS - 1 do
        lvars x = col * CELL, y = row * CELL;
        if random(1.0) < 0.5 then
            gfx_line(x, y, x + CELL, y + CELL, fg, 2)        ;;; "\"
        else
            gfx_line(x, y + CELL, x + CELL, y, fg, 2)        ;;; "/"
        endif
    endfor
endfor;

gfx_run(3000);          ;;; window stays ~60s, or until you close it
gfx_shutdown();
