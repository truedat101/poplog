/* Standalone smoke test for the Poplog Dear ImGui + Metal backend.
 *
 * Builds a RETAINED canvas scene once, then renders a fixed number of frames
 * (the scene persists every frame) with an immediate panel on top, and exits 0.
 * Links ONLY against the backend glue + ImGui -- no Poplog -- so it proves the
 * --experimental-gfx toolchain end-to-end on a Mac before any Poplog image.
 *
 *   make gfx-smoke && ./gfx-smoke [frames]
 *
 * Exit codes: 0 ok, 2 = could not init (no Metal device / no window server).
 */
#include <stdio.h>
#include <stdlib.h>
#include "imgui_backend.h"

static void build_scene(void)
{
    const uint32_t white = pop_gfx_rgba(255, 255, 255, 255);
    const uint32_t grey  = pop_gfx_rgba(200, 200, 200, 120);
    const uint32_t green = pop_gfx_rgba( 80, 220, 120, 255);
    const uint32_t blue  = pop_gfx_rgba(120, 160, 255, 255);
    const uint32_t amber = pop_gfx_rgba(255, 190,  60, 255);

    pop_gfx_clear();                                   /* like XpwClearWindow */
    pop_gfx_draw_text(60, 24, white, "Poplog -- retained canvas (no X): line/rect/circle/arc/point");
    pop_gfx_draw_rect(60, 60, 740, 440, grey, 1.0f);
    pop_gfx_draw_line(60, 60, 740, 440, green, 3.0f);
    pop_gfx_draw_line(60, 440, 740, 60, blue, 3.0f);
    pop_gfx_draw_circle(400, 250, 120, amber, 2.0f);
    pop_gfx_fill_circle(400, 250, 6, amber);
    pop_gfx_draw_arc(400, 250, 160, 200.0f, 340.0f, white, 2.0f);
    for (int i = 0; i < 12; ++i)                        /* a ring of points  */
        pop_gfx_draw_point(400 + 90 * (i - 6) / 6.0f, 130, green);
}

int main(int argc, const char **argv)
{
    int frames = (argc > 1) ? atoi(argv[1]) : 120;

    if (!pop_gfx_init("Poplog -- gfx smoke", 800, 520)) {
        fprintf(stderr, "pop_gfx_init failed (no Metal device / no window server?)\n");
        return 2;
    }

    build_scene();                                     /* drawn ONCE, retained */

    int drawn = 0, clicks = 0, checked = 0;
    for (int i = 0; i < frames && !pop_gfx_should_close(); ++i) {
        if (!pop_gfx_frame_begin()) { pop_gfx_poll(); continue; }

        if (pop_gfx_begin("Hello from Pop-11")) {
            pop_gfx_label("Native graphics: SDL3+OpenGL (Linux), Metal (macOS).");
            pop_gfx_label("The canvas behind me was drawn once and persists.");
            if (pop_gfx_button("Click me")) clicks++;
            checked = pop_gfx_checkbox("A checkbox", checked);
        }
        pop_gfx_end();

        pop_gfx_frame_end();
        drawn++;
    }

    float mx = pop_gfx_mouse_x(), my = pop_gfx_mouse_y();
    if (mx < -1.0e6f)   /* ImGui's -FLT_MAX sentinel: no mouse over the window */
        printf("smoke ok: %d frames, %d clicks, checkbox=%d, mouse=(none)\n",
               drawn, clicks, checked);
    else
        printf("smoke ok: %d frames, %d clicks, checkbox=%d, mouse=(%.0f,%.0f)\n",
               drawn, clicks, checked, mx, my);
    pop_gfx_shutdown();
    return 0;
}
