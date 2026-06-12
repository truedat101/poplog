/* examples/poplog_letters.p -- the word POPLOG in giant block letters,
 * where each big letter is itself drawn out of small copies of that letter.
 * (Big "P" made of little "P"s, big "O" of little "O"s, ...)
 *
 * Run:  ./poplog ./target/pop/basepop11 examples/poplog_letters.p
 */

uses popgfx;

;;; 5x7 bitmaps -- one row per string, '1' = draw a small glyph there
lconstant
    bmP = ['11110' '10001' '10001' '11110' '10000' '10000' '10000'],
    bmO = ['01110' '10001' '10001' '10001' '10001' '10001' '01110'],
    bmL = ['10000' '10000' '10000' '10000' '10000' '10000' '11111'],
    bmG = ['01110' '10001' '10000' '10111' '10001' '10001' '01110'];

;;; the word, as (character, bitmap) pairs
lconstant word = [ [`P` ^bmP] [`O` ^bmO] [`P` ^bmP]
                   [`L` ^bmL] [`O` ^bmO] [`G` ^bmG] ];

lconstant CW = 11, CH = 13;             ;;; small-glyph cell size (px)
lconstant GW = 5*CW + 14;               ;;; per big-letter advance
lconstant MARGIN = 22;
lconstant W = length(word) * GW + 2*MARGIN + 50, H = 7*CH + 70;

gfx_init('POPLOG -- letters made of letters', W, H) -> ;

;;; a colour per big letter
lconstant cols = {%
    gfx_rgb(255,110,110), gfx_rgb(255,180, 80), gfx_rgb(245,235, 90),
    gfx_rgb(120,230,130), gfx_rgb(120,180,255), gfx_rgb(200,140,255) %};

define lconstant draw_glyph(ch, bitmap, ox, oy, col);
    lvars ch, bitmap, ox, oy, col, r, c, glyph = consstring(ch, 1);
    for r from 1 to 7 do
        lvars row = bitmap(r);
        for c from 1 to 5 do
            if row(c) == `1` then
                gfx_text(ox + (c-1)*CW, oy + (r-1)*CH, col, glyph)
            endif
        endfor
    endfor
enddefine;

lvars i, oy = 34;
for i from 1 to length(word) do
    lvars pair = word(i);
    draw_glyph(pair(1), pair(2), MARGIN + (i-1)*GW, oy, cols(i))
endfor;
gfx_text(MARGIN, oy + 7*CH + 18, gfx_rgb(180,180,190),
         'each giant letter is drawn out of small copies of itself -- Pop-11');

gfx_run(3000);          ;;; ~60s, or until you close it
gfx_shutdown();
