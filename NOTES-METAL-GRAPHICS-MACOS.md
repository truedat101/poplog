# macOS native graphics: the Metal backend presentation freeze

Status: **diagnosed, fix pending.** This note records why the experimental
Metal graphics backend (`pop/extern/lib/imgui_backend.mm`) stutters/freezes
during continuous animation, what proved the cause, and how to fix it.

## Symptom

A continuously animating demo (e.g. `examples/cube3d.p` with no per-frame
`syssleep`) runs **smooth for ~3 seconds, then freezes ~1 s, advances a few
frames, freezes again**, repeating. A low-frame-rate loop (the original
`syssleep(3)`, ~30 fps) merely *judders* and limps along without an obvious
freeze, which masked the bug for a while.

## What we proved

1. **The render loop is healthy.** Per-frame tracing in the backend
   (`POP_GFX_DEBUG=1`, time between `frame_begin` calls, drawable-acquire time)
   showed **no >100 ms loop stalls and no nil drawables** in our own runs, at a
   steady ~57–59 fps. The Pop-11 loop, the gfx surface, and the frame pacing
   are not the problem.

2. **The SDL3 + OpenGL backend is perfectly smooth on macOS.** Building
   `basepop11` with the *other* backend (`imgui_backend_sdl.cpp`, normally the
   Linux one) on macOS — SDL3 window + an OpenGL core-profile context — runs
   the exact smooth no-sleep loop with **no freeze**. So the freeze is specific
   to the **Metal** integration, not the Pop loop or the `pop_gfx_*` surface.

3. **A known-good Metal+ImGui reference does the present *exactly* as we do.**
   `metal-imgui-example` (SDL window + `metal-cpp` rendering) presents with
   `commandBuffer->presentDrawable(drawable); commandBuffer->commit();` — **no
   semaphore, no `waitUntilCompleted`**, identical to our `pop_gfx_frame_end()`.
   So present/commit ordering and frame-in-flight pacing are **not** the
   differentiator. (Every earlier fix attempt — an in-flight semaphore, a
   `usleep` frame limiter, an `NSRunLoop` + `CATransaction flush` limiter — was
   aimed at this non-problem and either deadlocked, raced, or still froze.)

## Root cause

**We drive an `MTKView` outside the draw cycle it is designed for.**

`imgui_backend.mm` creates an `MTKView` with `paused = YES` and
`enableSetNeedsDisplay = NO`, then never calls `[view draw]`. Instead it reaches
into the view every frame and pulls `currentRenderPassDescriptor` (in
`frame_begin`) and `currentDrawable` (in `frame_end`), renders a command buffer,
and presents.

`MTKView` owns its `CAMetalLayer`'s drawable pool (≈3 drawables) and only
**advances and recycles** that pool as part of its own `draw()` / display-link
cycle. With the view paused and `draw()` never called, the drawables we grab by
hand are never returned to the pool. After the pool drains — a few seconds at
~60 fps — `currentDrawable` blocks on its internal ~1 second timeout, then
returns nil. That is precisely the observed "freeze ~1 s, a few frames, freeze"
cadence.

The two configurations that *work* both obtain the drawable from a **plain
`CAMetalLayer` via `nextDrawable`**, which recycles correctly under fully manual
control (the window server presents and releases drawables out-of-process — no
`MTKView` draw cycle and no running Cocoa run loop required):

* the reference: `SDL_RenderGetMetalLayer(...)` → `layer->nextDrawable()`;
* our SDL backend: SDL's GL swapchain + `SDL_GL_SwapWindow`.

Note the run loop is a red herring: SDL also pumps events with a bare
`nextEventMatchingMask` loop (like our `pop_gfx_poll`) and does **not** run
`[NSApp run]`. The difference is the **layer/drawable management**, not the
event pump — which is why servicing the run loop did not help while the
`MTKView` path remained.

## Code-level comparison

| | `imgui_backend.mm` (freezes) | `metal-imgui-example` (works) | `imgui_backend_sdl.cpp` (works) |
|---|---|---|---|
| Surface | hand-rolled `NSWindow` + **`MTKView` (paused)** | SDL window + **plain `CA::MetalLayer`** | SDL window |
| Drawable / frame | `g_view.currentDrawable` (outside `draw()`) | `layer->nextDrawable()` | GL back buffer |
| Present | `presentDrawable` + `commit` | `presentDrawable` + `commit` *(identical)* | `SDL_GL_SwapWindow` (vsync-blocking) |
| In-flight pacing | none | none | implicit (blocking swap) |
| Run loop | `[NSApp finishLaunching]` + manual pump | SDL pump | SDL pump |

## Fix

Replace the `MTKView` in `imgui_backend.mm` with a **plain `CAMetalLayer`** we
manage directly, mirroring the reference. Concretely:

* Create an `NSView` with `wantsLayer = YES` whose `layer` is a `CAMetalLayer`
  (or a custom `NSView` subclass returning one), set `device`, `pixelFormat`
  (`BGRA8Unorm`), and `framebufferOnly = YES`; make it the window's content view.
* `frame_begin`: set `layer.drawableSize` from the view's backing size,
  `id<CAMetalDrawable> d = [layer nextDrawable]` (early-out if nil), build a
  `MTLRenderPassDescriptor` whose color attachment texture is `d.texture`.
* `frame_end`: encode, `[cb presentDrawable:d]; [cb commit];` — unchanged.

Everything else stays: the retained-canvas display list, `ImGui_ImplMetal_*`,
the `pop_gfx_*` C surface, and the Pop-side loop. Because a plain layer recycles
drawables correctly, the smooth no-sleep loop will then pace naturally on the
present and stay smooth.

### Alternative

Adopt **SDL3 as the macOS platform layer too** (already proven here) and retire
the bespoke Cocoa/Metal backend, unifying on one cross-platform backend. The SDL
backend needed only a macOS GL-context branch (3.2 core, forward-compatible,
GLSL 150) to build and run on macOS — see the `#ifdef __APPLE__` in
`imgui_backend_sdl.cpp`. Trade-off: adds an SDL3 runtime dependency on macOS
(vs. system frameworks only), but removes a hand-rolled Cocoa integration.

## Reproducing / instrumentation

* Smooth no-sleep loop that triggers it: a `repeat ... gfx_step() ...` with no
  `syssleep` (the Metal backend never blocks, so without a sleep the loop runs
  free and drains the pool fastest).
* `POP_GFX_DEBUG=1` arms per-frame stall tracing in `pop_gfx_frame_begin`
  (frame-period gaps and drawable-acquire time to stderr). Note: the freeze is
  only reliably visible with the window **foreground/active**; an occluded or
  backgrounded window composites differently and may not reproduce it.
