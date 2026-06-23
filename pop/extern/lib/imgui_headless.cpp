/* Headless graphics regression harness (Linux/SDL3 backend).
 *
 * Renders the retained-canvas scene to a PPM image with NO window, display,
 * compositor, or GPU -- it forces SDL's "offscreen" video driver (EGL
 * surfaceless) and relies on Mesa llvmpipe for software rendering.  This is
 * the CI / `validate-gfx` primitive: deterministic, reproducible, and free of
 * the X11/Wayland/driver plumbing that a live window needs.
 *
 *   make gfx-headless && ./gfx-headless out.ppm
 *
 * Exit 0 + a non-trivial PPM on success; exit 2 if the GL stack is
 * unavailable (so a regression script can SKIP rather than fail).  The caller
 * checks the image is non-blank (the scene draws bright primitives on a dark
 * background).
 */
#include <stdio.h>
#include <stdlib.h>
#include "imgui_backend.h"

/* implemented in imgui_backend_sdl.cpp (SDL/OpenGL backend only) */
extern "C" int pop_gfx_render_to_ppm(const char *path);

static void build_scene(void)
{
    const uint32_t white = pop_gfx_rgba(255, 255, 255, 255);
    const uint32_t green = pop_gfx_rgba( 80, 220, 120, 255);
    const uint32_t blue  = pop_gfx_rgba(120, 160, 255, 255);
    const uint32_t amber = pop_gfx_rgba(255, 190,  60, 255);

    pop_gfx_clear();
    pop_gfx_draw_text(60, 24, white, "Poplog headless render (SDL3 offscreen + llvmpipe)");
    pop_gfx_draw_rect(60, 60, 740, 440, white, 1.0f);
    pop_gfx_draw_line(60, 60, 740, 440, green, 3.0f);
    pop_gfx_draw_line(60, 440, 740, 60, blue, 3.0f);
    pop_gfx_draw_circle(400, 250, 120, amber, 2.0f);
    pop_gfx_fill_circle(400, 250, 6, amber);
    pop_gfx_draw_arc(400, 250, 160, 200.0f, 340.0f, white, 2.0f);
}

int main(int argc, char **argv)
{
    const char *out = (argc > 1) ? argv[1] : "gfx-headless.ppm";

    /* Pick the offscreen driver unless the caller asked for something else. */
    if (!getenv("SDL_VIDEODRIVER"))
        setenv("SDL_VIDEODRIVER", "offscreen", 1);

    if (!pop_gfx_init("Poplog headless", 800, 520)) {
        fprintf(stderr, "gfx-headless: pop_gfx_init failed (no usable GL stack)\n");
        return 2;
    }
    build_scene();
    int ok = pop_gfx_render_to_ppm(out);
    pop_gfx_shutdown();

    if (!ok) { fprintf(stderr, "gfx-headless: render/readback failed\n"); return 2; }
    printf("gfx-headless: wrote %s\n", out);
    return 0;
}
