/* Standalone smoke test for the Poplog Dear ImGui + Metal backend.
 *
 * Opens a native window, renders a fixed number of frames (a canvas line/rect +
 * a panel with a button), then exits 0.  It links ONLY against the backend glue
 * and ImGui -- no Poplog -- so it proves the --experimental-gfx toolchain
 * end-to-end on a Mac before any Poplog image exists.
 *
 *   make gfx-smoke && ./gfx-smoke [frames]
 *
 * Exit codes: 0 ok, 2 = could not init (no Metal device / no window server).
 */
#include <stdio.h>
#include <stdlib.h>
#include "imgui_backend.h"

int main(int argc, const char **argv)
{
    int frames = (argc > 1) ? atoi(argv[1]) : 120;     /* ~a couple seconds */

    if (!pop_gfx_init("Poplog -- gfx smoke", 800, 500)) {
        fprintf(stderr, "pop_gfx_init failed (no Metal device / no window server?)\n");
        return 2;
    }

    int drawn = 0, clicks = 0;
    for (int i = 0; i < frames && !pop_gfx_should_close(); ++i) {
        if (!pop_gfx_frame_begin()) { pop_gfx_poll(); continue; }

        /* canvas (rc_graphic-style) drawing */
        pop_gfx_draw_text(60, 24, pop_gfx_rgba(255, 255, 255, 255),
                          "Poplog -- Dear ImGui + Metal smoke test (no X)");
        pop_gfx_draw_rect(60, 60, 740, 440, pop_gfx_rgba(200, 200, 200, 120), 1.0f);
        pop_gfx_draw_line(60, 60, 740, 440, pop_gfx_rgba(80, 220, 120, 255), 3.0f);
        pop_gfx_draw_line(60, 440, 740, 60, pop_gfx_rgba(120, 160, 255, 255), 3.0f);

        /* a native panel with a widget */
        if (pop_gfx_begin("Hello from Pop-11")) {
            pop_gfx_label("Native macOS graphics, no X server.");
            if (pop_gfx_button("Click me")) clicks++;
        }
        pop_gfx_end();

        pop_gfx_frame_end();
        drawn++;
    }

    pop_gfx_shutdown();
    printf("smoke ok: %d frames rendered, %d clicks\n", drawn, clicks);
    return 0;
}
