#pragma once
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#include <wayland-server-core.h>
#include "wayland_compositor.h"
#include "wayland_output.h"
#include "wayland_seat.h"
#include "wayland_shm.h"
#include "wayland_subcompositor.h"
#include "wayland_data_device_manager.h"
#include "wayland_presentation.h"
#include "wayland_color_management.h"
#include "surface_renderer.h"
#include "input_handler.h"
#include "metal_renderer.h"
#include "xdg_shell.h"
#include "egl_buffer_handler.h"

// macOS Wayland Compositor Backend
// This is a from-scratch implementation - no WLRoots

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@interface MacOSCompositor : NSObject
@property (nonatomic, strong) UIWindow *window;
#else
@interface MacOSCompositor : NSObject <NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
#endif
@property (nonatomic, assign) struct wl_display *display;
@property (nonatomic, assign) struct wl_event_loop *eventLoop;
@property (nonatomic, strong) SurfaceRenderer *renderer;  // Cocoa renderer (single window)
@property (nonatomic, strong) id renderingBackend;  // Can be SurfaceRenderer or MetalRenderer
@property (nonatomic, assign) int backendType;  // RENDERING_BACKEND_COCOA or RENDERING_BACKEND_METAL
@property (nonatomic, strong) InputHandler *inputHandler;

// Wayland protocol implementations
@property (nonatomic, assign) struct wl_compositor_impl *compositor;
@property (nonatomic, assign) struct wl_output_impl *output;
@property (nonatomic, assign) struct wl_seat_impl *seat;
@property (nonatomic, assign) struct wl_shm_impl *shm;
@property (nonatomic, assign) struct wl_subcompositor_impl *subcompositor;
@property (nonatomic, assign) struct wl_data_device_manager_impl *data_device_manager;
@property (nonatomic, assign) struct xdg_wm_base_impl *xdg_wm_base;
@property (nonatomic, assign) struct wp_color_manager_impl *color_manager;
@property (nonatomic, assign) struct wl_text_input_manager_impl *text_input_manager;
@property (nonatomic, assign) struct egl_buffer_handler *egl_buffer_handler;

// Event loop integration
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property (nonatomic, strong) CADisplayLink *displayLink;
#else
@property (nonatomic, assign) CVDisplayLinkRef displayLink;
#endif
@property (nonatomic, strong) NSThread *eventThread;
@property (nonatomic, assign) BOOL shouldStopEventThread;
@property (nonatomic, assign) struct wl_event_source *frame_callback_source;
@property (nonatomic, assign) int32_t pending_resize_width;
@property (nonatomic, assign) int32_t pending_resize_height;
@property (nonatomic, assign) volatile BOOL needs_resize_configure;
@property (nonatomic, assign) BOOL windowShown; // Track if window has been shown (delayed until first client)
@property (nonatomic, assign) BOOL isFullscreen; // Track if window is in fullscreen mode
@property (nonatomic, strong) NSTimer *fullscreenExitTimer; // Timer to exit fullscreen after client disconnects
@property (nonatomic, assign) NSUInteger connectedClientCount; // Track number of connected clients

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithDisplay:(struct wl_display *)display window:(UIWindow *)window;
#else
- (instancetype)initWithDisplay:(struct wl_display *)display window:(NSWindow *)window;
#endif
- (BOOL)start;
- (void)stop;
- (BOOL)processWaylandEvents; // Returns YES if events were processed
- (void)renderFrame;
- (void)sendFrameCallbacksImmediately; // Force immediate frame callback dispatch (for input events)
- (void)switchToMetalBackend; // Switch to Metal rendering for full compositors
- (void)updateWindowTitleForClient:(struct wl_client *)client; // Update window title with client name
- (void)showAndSizeWindowForFirstClient:(int32_t)width height:(int32_t)height; // Show and size window when first client connects

@end

// C function to remove surface from renderer (for cleanup)
void remove_surface_from_renderer(struct wl_surface_impl *surface);

// C function to check if window should be hidden (called when client disconnects)
void macos_compositor_check_and_hide_window_if_needed(void);

// C function to set CSD mode for a toplevel (hide/show macOS window decorations)
void macos_compositor_set_csd_mode_for_toplevel(struct xdg_toplevel_impl *toplevel, bool csd);

// C function to activate/raise the window (called from activation protocol)
void macos_compositor_activate_window(void);

// C function to handle client disconnection (may exit fullscreen if needed)
void macos_compositor_handle_client_disconnect(void);

// C function to handle new client connection (cancel fullscreen exit timer)
void macos_compositor_handle_client_connect(void);

// C function to update window title when no clients are connected
void macos_compositor_update_title_no_clients(void);

// C function to get EGL buffer handler (for rendering EGL buffers)
struct egl_buffer_handler *macos_compositor_get_egl_buffer_handler(void);

