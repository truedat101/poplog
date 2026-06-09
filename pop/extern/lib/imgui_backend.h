/* Poplog <-> Dear ImGui glue: a small extern "C" surface (pop_gfx_*) over a
 * native Metal + Cocoa Dear ImGui backend, for the experimental macOS graphics
 * path (configure --experimental-gfx).  Poplog's FFI calls C; the implementation
 * (imgui_backend.mm) is ObjC++ and talks to ImGui's C++ API directly -- so no
 * cimgui, no GLFW/SDL.  See PORTING-ARM64-M-SILICON-OSX.md sec. 6.
 *
 * Model: IMMEDIATE.  Poplog drives the loop -- each tick call frame_begin, issue
 * draw/widget calls, then frame_end.  Widgets return their result inline (e.g.
 * pop_gfx_button -> 1 on click), so UI logic can run via forward Pop->C calls
 * without the reverse C->Pop callback trampoline.
 */
#ifndef POP_IMGUI_BACKEND_H
#define POP_IMGUI_BACKEND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --- lifecycle (call on the main thread) ------------------------------- */
int  pop_gfx_init(const char *title, int width, int height); /* 1 ok, 0 fail */
void pop_gfx_shutdown(void);
int  pop_gfx_should_close(void);   /* 1 once the window has been closed      */

/* --- frame ------------------------------------------------------------- */
/* frame_begin returns 1 if a frame is ready (then draw + call frame_end), or
 * 0 if no drawable is available this tick (skip drawing and frame_end). */
int  pop_gfx_frame_begin(void);
void pop_gfx_frame_end(void);
void pop_gfx_poll(void);           /* pump pending OS events (non-blocking)  */

/* --- immediate canvas drawing (background list; screen-space pixels) ---- */
uint32_t pop_gfx_rgba(int r, int g, int b, int a);
void pop_gfx_draw_line(float x0, float y0, float x1, float y1, uint32_t rgba, float thickness);
void pop_gfx_draw_rect(float x0, float y0, float x1, float y1, uint32_t rgba, float thickness);
void pop_gfx_fill_rect(float x0, float y0, float x1, float y1, uint32_t rgba);
void pop_gfx_draw_text(float x, float y, uint32_t rgba, const char *text);

/* --- immediate panels (ImGui windows + widgets) ------------------------ */
int  pop_gfx_begin(const char *title); /* 1 if visible; ALWAYS call end()    */
void pop_gfx_end(void);
void pop_gfx_label(const char *text);
int  pop_gfx_button(const char *label);          /* 1 on click               */
int  pop_gfx_checkbox(const char *label, int value); /* returns new value     */

#ifdef __cplusplus
}
#endif

#endif /* POP_IMGUI_BACKEND_H */
