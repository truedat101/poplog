/* Poplog <-> Dear ImGui glue (native Metal + Cocoa).  See imgui_backend.h.
 *
 * Compile as ObjC++ with ARC: clang++ -ObjC++ -fobjc-arc.  Links against
 * Metal, MetalKit, Cocoa, QuartzCore, GameController, Carbon.
 *
 * This drives Dear ImGui imperatively (the example in examples/example_apple_metal
 * is delegate-driven; here Poplog owns the loop) using an MTKView in manual
 * (paused) mode -- we fetch a render-pass descriptor + drawable per frame and
 * present it ourselves from pop_gfx_frame_end().
 */
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"
#include "imgui_backend.h"

/* --- window-close delegate -------------------------------------------- */
static bool g_closed = false;

@interface PopGfxWindowDelegate : NSObject <NSWindowDelegate>
@end
@implementation PopGfxWindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender { (void)sender; g_closed = true; return NO; }
@end

/* --- backend state ----------------------------------------------------- */
static id<MTLDevice>            g_device   = nil;
static id<MTLCommandQueue>      g_queue    = nil;
static NSWindow                *g_window   = nil;
static MTKView                 *g_view     = nil;
static PopGfxWindowDelegate    *g_delegate = nil;
static MTLRenderPassDescriptor *g_rpd      = nil;  /* current frame's pass desc */
static bool                     g_frame_active = false;

int pop_gfx_init(const char *title, int width, int height)
{
    @autoreleasepool {
        g_device = MTLCreateSystemDefaultDevice();
        if (g_device == nil)
            return 0;                                  /* no Metal-capable GPU  */
        g_queue = [g_device newCommandQueue];

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSRect frame = NSMakeRect(0, 0,
                                  width  > 0 ? width  : 1200,
                                  height > 0 ? height : 720);
        g_window = [[NSWindow alloc] initWithContentRect:frame
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
            backing:NSBackingStoreBuffered defer:NO];
        [g_window setTitle:[NSString stringWithUTF8String:(title ? title : "Poplog")]];

        g_view = [[MTKView alloc] initWithFrame:frame device:g_device];
        g_view.paused = YES;                           /* we draw on demand     */
        g_view.enableSetNeedsDisplay = NO;
        g_window.contentView = g_view;

        g_delegate = [[PopGfxWindowDelegate alloc] init];
        g_window.delegate = g_delegate;

        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        ImGui::GetIO().IniFilename = NULL;             /* no imgui.ini for host */
        ImGui::StyleColorsDark();
        ImGui_ImplMetal_Init(g_device);
        ImGui_ImplOSX_Init(g_view);

        [g_window center];
        [g_window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp finishLaunching];                       /* run loop w/o NSApp run */
        g_closed = false;
        return 1;
    }
}

void pop_gfx_poll(void)
{
    @autoreleasepool {
        NSEvent *ev;
        while ((ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                          untilDate:[NSDate distantPast]
                          inMode:NSDefaultRunLoopMode
                          dequeue:YES]) != nil) {
            [NSApp sendEvent:ev];
        }
    }
}

int pop_gfx_should_close(void) { return g_closed ? 1 : 0; }

int pop_gfx_frame_begin(void)
{
    pop_gfx_poll();
    MTLRenderPassDescriptor *rpd = g_view.currentRenderPassDescriptor;
    if (rpd == nil)
        return 0;                                      /* no drawable this tick */
    g_rpd = rpd;

    ImGuiIO &io = ImGui::GetIO();
    const CGSize sz = g_view.bounds.size;
    io.DisplaySize = ImVec2((float)sz.width, (float)sz.height);
    CGFloat scale = g_view.window.screen.backingScaleFactor;
    if (scale <= 0) scale = 1.0;
    io.DisplayFramebufferScale = ImVec2((float)scale, (float)scale);

    ImGui_ImplMetal_NewFrame(rpd);
    ImGui_ImplOSX_NewFrame(g_view);
    ImGui::NewFrame();
    g_frame_active = true;
    return 1;
}

void pop_gfx_frame_end(void)
{
    if (!g_frame_active)
        return;
    g_frame_active = false;

    @autoreleasepool {
        ImGui::Render();
        id<MTLCommandBuffer> cb = [g_queue commandBuffer];
        g_rpd.colorAttachments[0].clearColor = MTLClearColorMake(0.10, 0.10, 0.12, 1.0);
        id<MTLRenderCommandEncoder> enc =
            [cb renderCommandEncoderWithDescriptor:g_rpd];
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);
        [enc endEncoding];
        id<CAMetalDrawable> drawable = g_view.currentDrawable;
        if (drawable != nil)
            [cb presentDrawable:drawable];
        [cb commit];
        g_rpd = nil;
    }
}

void pop_gfx_shutdown(void)
{
    @autoreleasepool {
        ImGui_ImplMetal_Shutdown();
        ImGui_ImplOSX_Shutdown();
        ImGui::DestroyContext();
        [g_window orderOut:nil];
        g_window.delegate = nil;
        g_window = nil; g_view = nil; g_delegate = nil;
        g_queue = nil; g_device = nil;
    }
}

/* --- immediate canvas drawing ----------------------------------------- */
uint32_t pop_gfx_rgba(int r, int g, int b, int a) { return IM_COL32(r, g, b, a); }

void pop_gfx_draw_line(float x0, float y0, float x1, float y1, uint32_t c, float t)
{ ImGui::GetBackgroundDrawList()->AddLine(ImVec2(x0, y0), ImVec2(x1, y1), c, t); }

void pop_gfx_draw_rect(float x0, float y0, float x1, float y1, uint32_t c, float t)
{ ImGui::GetBackgroundDrawList()->AddRect(ImVec2(x0, y0), ImVec2(x1, y1), c, 0.0f, 0, t); }

void pop_gfx_fill_rect(float x0, float y0, float x1, float y1, uint32_t c)
{ ImGui::GetBackgroundDrawList()->AddRectFilled(ImVec2(x0, y0), ImVec2(x1, y1), c); }

void pop_gfx_draw_text(float x, float y, uint32_t c, const char *s)
{ if (s) ImGui::GetBackgroundDrawList()->AddText(ImVec2(x, y), c, s); }

/* --- immediate panels -------------------------------------------------- */
int  pop_gfx_begin(const char *title) { return ImGui::Begin(title ? title : "##win") ? 1 : 0; }
void pop_gfx_end(void)                { ImGui::End(); }
void pop_gfx_label(const char *s)     { if (s) ImGui::TextUnformatted(s); }
int  pop_gfx_button(const char *label){ return ImGui::Button(label ? label : "##btn") ? 1 : 0; }

int  pop_gfx_checkbox(const char *label, int v)
{ bool b = (v != 0); ImGui::Checkbox(label ? label : "##chk", &b); return b ? 1 : 0; }
