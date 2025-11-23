#import "macos_backend.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <libproc.h>
#endif
#include <wayland-server-core.h>
#include <wayland-server.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include "logging.h"
#include "wayland_compositor.h"
#include "wayland_primary_selection.h"
#include "wayland_protocol_stubs.h"
#include "wayland_viewporter.h"
#include "wayland_shell.h"
#include "wayland_screencopy.h"
#include "wayland_idle_inhibit.h"
#include "wayland_pointer_gestures.h"
#include "wayland_gtk_shell.h"
#include "wayland_plasma_shell.h"
#include "wayland_qt_extensions.h"
#include "wayland_relative_pointer.h"
#include "wayland_pointer_constraints.h"
#include "wayland_tablet.h"
#include "wayland_idle_manager.h"
#include "wayland_keyboard_shortcuts.h"
#include "wayland_linux_dmabuf.h"
#include "wayland_drm.h"
#include "metal_waypipe.h"
#include "xdg-shell-protocol.h"

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// iOS: Use UIView instead of NSView
@interface CompositorView : UIView
@property (nonatomic, assign) InputHandler *inputHandler;
@property (nonatomic, assign) SurfaceRenderer *renderer;
@property (nonatomic, strong) MTKView *metalView;
@end

@implementation CompositorView
- (void)drawRect:(CGRect)rect {
    if (self.metalView && self.metalView.superview == self) {
        return;
    }
    if (self.renderer) {
        [self.renderer drawSurfacesInRect:rect];
    } else {
        [[UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0] setFill];
        UIRectFill(rect);
    }
}
@end
#else
// macOS: Use NSView
@interface CompositorView : NSView
@property (nonatomic, assign) InputHandler *inputHandler;  // assign for MRC compatibility
@property (nonatomic, assign) SurfaceRenderer *renderer;  // assign for MRC compatibility
@property (nonatomic, strong) MTKView *metalView;  // Metal view for full compositor rendering
@end

@implementation CompositorView
- (BOOL)isFlipped {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (BOOL)acceptsMouseMovedEvents {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    NSLog(@"[COMPOSITOR VIEW] Became first responder - ready for keyboard input");
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
    NSLog(@"[COMPOSITOR VIEW] Resigned first responder");
    return [super resignFirstResponder];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.metalView && self.metalView.superview == self) {
        return;
    }
    if (self.renderer) {
        [self.renderer drawSurfacesInRect:dirtyRect];
    } else {
        [[NSColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0] setFill];
        NSRectFill(dirtyRect);
    }
}

- (void)keyDown:(NSEvent *)event {
    if (self.inputHandler) {
        [self.inputHandler handleKeyboardEvent:event];
    } else {
        [super keyDown:event];
    }
}

- (void)keyUp:(NSEvent *)event {
    if (self.inputHandler) {
        [self.inputHandler handleKeyboardEvent:event];
    } else {
        [super keyUp:event];
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.inputHandler && self.inputHandler.seat && self.inputHandler.seat->focused_surface) {
        [self.inputHandler handleKeyboardEvent:event];
        return YES;
    }
    return [super performKeyEquivalent:event];
}
@end
#endif

// Static reference to compositor instance for C callback
static MacOSCompositor *g_compositor_instance = NULL;

// Forward declarations
static int send_frame_callbacks_timer(void *data);
static void send_frame_callbacks_timer_idle(void *data);
static BOOL ensure_frame_callback_timer_on_event_thread(MacOSCompositor *compositor, uint32_t delay_ms, const char *reason);
static void ensure_frame_callback_timer_idle(void *data);

// C function for frame callback requested callback
// Called from event thread when a client requests a frame callback
static void macos_compositor_frame_callback_requested(void) {
    if (!g_compositor_instance) return;
    
    // This runs on the event thread - safe to create timer directly
    if (g_compositor_instance.display) {
        struct wl_event_loop *eventLoop = wl_display_get_event_loop(g_compositor_instance.display);
        BOOL timer_was_missing = (g_compositor_instance.frame_callback_source == NULL);
        if (ensure_frame_callback_timer_on_event_thread(g_compositor_instance, 16, "frame request")) {
            // CRITICAL: Always trigger immediate frame callback send when requested
            // This ensures clients don't wait up to 16ms for the timer to fire
            // The idle callback will run immediately on the event loop
            if (eventLoop) {
                wl_event_loop_add_idle(eventLoop, send_frame_callbacks_timer_idle, (__bridge void *)g_compositor_instance);
            } else if (timer_was_missing) {
                log_printf("[COMPOSITOR] ", "macos_compositor_frame_callback_requested: Timer ensured but event loop missing\n");
            }
        } else {
            log_printf("[COMPOSITOR] ", "macos_compositor_frame_callback_requested: Failed to ensure timer\n");
        }
    }
}

// C function to update window title when focus changes
void macos_compositor_update_title(struct wl_client *client) {
    if (g_compositor_instance) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_compositor_instance updateWindowTitleForClient:client];
        });
    }
}

// C function to detect full compositors and switch to Metal backend
// OPTIMIZED: Only switch to Metal for actual nested compositors, not proxies like waypipe
void macos_compositor_detect_full_compositor(struct wl_client *client) {
    if (!g_compositor_instance) {
        NSLog(@"⚠️ g_compositor_instance is NULL, cannot detect compositor");
        return;
    }
    
    // Try to get PID for detection
    pid_t client_pid = 0;
    uid_t client_uid = 0;
    gid_t client_gid = 0;
    wl_client_get_credentials(client, &client_pid, &client_uid, &client_gid);
    
    BOOL shouldSwitchToMetal = NO;
    NSString *processName = nil;
    
    if (client_pid > 0) {
        // Check process name to determine if this is a nested compositor
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
        char proc_path[PROC_PIDPATHINFO_MAXSIZE] = {0};
        int ret = proc_pidpath(client_pid, proc_path, sizeof(proc_path));
        if (ret > 0) {
            NSString *processPath = [NSString stringWithUTF8String:proc_path];
#else
        // iOS: Process name detection not available
        NSString *processPath = nil;
        if (0) {
#endif
            processName = [processPath lastPathComponent];
            NSLog(@"🔍 Client binding to wl_compositor: %@ (PID: %d)", processName, client_pid);
            
            // Known nested compositors that should use Metal backend
            // Includes: Weston, wlroots-based (Sway, River, Hyprland), GNOME (Mutter), KDE (KWin)
            NSArray<NSString *> *nestedCompositors = @[
                @"weston", @"weston-desktop-shell",
                @"mutter", @"gnome-shell", @"gnome-session",
                @"kwin_wayland", @"kwin", @"plasmashell",
                @"sway", @"river", @"hyprland", @"niri", @"cage",
                @"wayfire", @"hikari", @"orbital"
            ];
            
            NSString *lowercaseName = [processName lowercaseString];
            for (NSString *compositor in nestedCompositors) {
                if ([lowercaseName containsString:compositor]) {
                    shouldSwitchToMetal = YES;
                    NSLog(@"✅ Detected nested compositor: %@ - switching to Metal backend", processName);
                    break;
                }
            }
            
            // waypipe is a proxy/tunnel, NOT a compositor - don't switch backend
            if ([lowercaseName containsString:@"waypipe"]) {
                shouldSwitchToMetal = NO;
                NSLog(@"ℹ️ Detected waypipe proxy - keeping Cocoa backend for regular clients");
            }
        }
    } else {
        // PID unavailable - likely forwarded through waypipe or similar proxy
        // Don't switch backend automatically - waypipe clients should use Cocoa
        NSLog(@"🔍 Client PID unavailable (likely forwarded through waypipe) - keeping Cocoa backend");
        shouldSwitchToMetal = NO;
    }
    
    // Only switch to Metal if we detected an actual nested compositor
    if (shouldSwitchToMetal) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_compositor_instance switchToMetalBackend];
        });
    } else {
        NSLog(@"ℹ️ Client binding to wl_compositor but not a nested compositor - using Cocoa backend");
    }
    
    // Update window title with client name (regardless of backend)
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_compositor_instance updateWindowTitleForClient:client];
    });
}

// Forward declaration
static void renderSurfaceImmediate(struct wl_surface_impl *surface);

// C wrapper function for render callback
static void render_surface_callback(struct wl_surface_impl *surface) {
    if (!surface) return;
    
    // CRITICAL: Validate surface is still valid before dispatching async render
    // The surface may be destroyed between commit and async render execution
    if (!surface->resource) return;
    
    // SAFETY: Check user_data FIRST before calling wl_resource_get_client
    // This is safer because user_data access doesn't dereference as many internal fields
    struct wl_surface_impl *surface_check = wl_resource_get_user_data(surface->resource);
    if (!surface_check || surface_check != surface) return;
    
    // Now verify resource is still valid by checking if we can get the client
    struct wl_client *client = wl_resource_get_client(surface->resource);
    if (!client) return;
    
    if (g_compositor_instance && g_compositor_instance.renderingBackend) {
        // CRITICAL: Render SYNCHRONOUSLY on main thread for immediate updates
        // Wayland compositors MUST repaint immediately when clients commit buffers
        // Async dispatch causes race conditions and delays that break nested compositors
        if ([NSThread isMainThread]) {
            renderSurfaceImmediate(surface);
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                renderSurfaceImmediate(surface);
            });
        }
    }
}

// Helper function to render surface immediately on main thread
static void renderSurfaceImmediate(struct wl_surface_impl *surface) {
    if (!g_compositor_instance || !surface) return;
    
    // Check if window needs to be shown and sized for first client
    if (!g_compositor_instance.windowShown && surface->buffer_resource) {
        // Get buffer size to size window appropriately
        struct buffer_data {
            void *data;
            int32_t offset;
            int32_t width;
            int32_t height;
            int32_t stride;
            uint32_t format;
        };
        struct buffer_data *buf_data = wl_resource_get_user_data(surface->buffer_resource);
        if (buf_data && buf_data->width > 0 && buf_data->height > 0) {
            [g_compositor_instance showAndSizeWindowForFirstClient:buf_data->width height:buf_data->height];
        }
    }
    
    // Render surface immediately
    if ([g_compositor_instance.renderingBackend respondsToSelector:@selector(renderSurface:)]) {
        [g_compositor_instance.renderingBackend renderSurface:surface];
    }
    
    // CRITICAL: Trigger IMMEDIATE redraw after rendering surface
    // This ensures nested compositors (like Weston) see updates immediately
    // Wayland spec requires compositors to repaint immediately on surface commit
    if ([g_compositor_instance.renderingBackend respondsToSelector:@selector(setNeedsDisplay)]) {
        [g_compositor_instance.renderingBackend setNeedsDisplay];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    } else if (g_compositor_instance.window && g_compositor_instance.window.rootViewController.view) {
        // iOS: Fallback for Cocoa backend
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_compositor_instance.window.rootViewController.view setNeedsDisplay];
        });
#else
    } else if (g_compositor_instance.window && g_compositor_instance.window.contentView) {
        // macOS: Fallback for Cocoa backend
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_compositor_instance.window.contentView setNeedsDisplay:YES];
        });
#endif
    }
}

// C wrapper function to remove surface (for cleanup)
void remove_surface_from_renderer(struct wl_surface_impl *surface) {
    if (!g_compositor_instance) {
        return;
    }
    
    // CRITICAL: Use dispatch_sync to ensure surface is removed from renderer
    // BEFORE the surface struct is freed by the caller (surface_destroy).
    // Using dispatch_async causes a race condition where the block runs after
    // the surface is freed, leading to Use-After-Free crashes.
    if ([NSThread isMainThread]) {
        // Remove from Cocoa renderer if active
        if (g_compositor_instance.renderer) {
            [g_compositor_instance.renderer removeSurface:surface];
        }
        
        // Remove from Metal renderer if active
        if (g_compositor_instance.renderingBackend && 
            g_compositor_instance.backendType == 1 &&
            [g_compositor_instance.renderingBackend respondsToSelector:@selector(removeSurface:)]) {
            [g_compositor_instance.renderingBackend removeSurface:surface];
        }
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            // Remove from Cocoa renderer if active
            if (g_compositor_instance.renderer) {
                [g_compositor_instance.renderer removeSurface:surface];
            }
            
            // Remove from Metal renderer if active
            if (g_compositor_instance.renderingBackend && 
                g_compositor_instance.backendType == 1 &&
                [g_compositor_instance.renderingBackend respondsToSelector:@selector(removeSurface:)]) {
                [g_compositor_instance.renderingBackend removeSurface:surface];
            }
        });
    }
}

// C function to check if window should be hidden after client disconnects
// Called from client_destroy_listener after removing all surfaces
void macos_compositor_check_and_hide_window_if_needed(void) {
    if (!g_compositor_instance) {
        return;
    }
    
    // Check if there are any remaining surfaces
    // We need to check the surfaces list from wayland_compositor.c
    // Since we can't directly access it, we'll use a callback mechanism
    // For now, we'll check if the window is shown and hide it
    // The actual surface count check will be done in client_destroy_listener
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_compositor_instance.windowShown && g_compositor_instance.window) {
            NSLog(@"[WINDOW] All clients disconnected - hiding window");
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            g_compositor_instance.window.hidden = YES;
#else
            [g_compositor_instance.window orderOut:nil];
#endif
            g_compositor_instance.windowShown = NO;
        }
    });
}

@implementation MacOSCompositor

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithDisplay:(struct wl_display *)display window:(UIWindow *)window {
#else
- (instancetype)initWithDisplay:(struct wl_display *)display window:(NSWindow *)window {
#endif
    self = [super init];
    if (self) {
        _display = display;
        _window = window;
        _eventLoop = wl_display_get_event_loop(display);
        _shouldStopEventThread = NO;
        _frame_callback_source = NULL;
        _pending_resize_width = 0;
        _pending_resize_height = 0;
        _needs_resize_configure = NO;
        _windowShown = NO; // Track if window has been shown (delayed until first client)
        _isFullscreen = NO; // Track if window is in fullscreen mode
        _fullscreenExitTimer = nil; // Timer to exit fullscreen after client disconnects
        _connectedClientCount = 0; // Track number of connected clients
        
        // Create custom view that accepts first responder and handles drawing
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        CGRect contentRect = CGRectMake(0, 0, 800, 600);
        CompositorView *compositorView = [[CompositorView alloc] initWithFrame:contentRect];
        window.rootViewController = [[UIViewController alloc] init];
        window.rootViewController.view = compositorView;
#else
        NSRect contentRect = NSMakeRect(0, 0, 800, 600);
        CompositorView *compositorView = [[CompositorView alloc] initWithFrame:contentRect];
        [window setContentView:compositorView];
        [window setDelegate:self];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidEnterFullScreen:)
                                                     name:NSWindowDidEnterFullScreenNotification
                                                   object:window];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidExitFullScreen:)
                                                     name:NSWindowDidExitFullScreenNotification
                                                   object:window];
        [window setAcceptsMouseMovedEvents:YES];
        [window setCollectionBehavior:NSWindowCollectionBehaviorDefault];
        [window setStyleMask:(NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskResizable |
                              NSWindowStyleMaskMiniaturizable)];
        [window makeFirstResponder:compositorView];
#endif
        
        // Create surface renderer with NSView (like OWL compositor)
        // Start with Cocoa renderer, will switch to Metal if full compositor detected
        _renderer = [[SurfaceRenderer alloc] initWithCompositorView:compositorView];
        _renderingBackend = _renderer;
        _backendType = 0; // RENDERING_BACKEND_COCOA
        
        // Set renderer reference in view for drawRect: calls
        compositorView.renderer = _renderer;
        
        // Store global reference for C callbacks (MUST be set before clients connect)
        g_compositor_instance = self;
        NSLog(@"   Global compositor instance set for client detection: %p", (__bridge void *)self);
        
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        NSLog(@"🚀 iOS Wayland Compositor initialized");
#else
        NSLog(@"🚀 macOS Wayland Compositor initialized");
        NSLog(@"   Window: %@", window.title);
#endif
        NSLog(@"   Display: %p", (void *)display);
        NSLog(@"   Initial backend: Cocoa (will auto-switch to Metal for full compositors)");
    }
    return self;
}

- (void)setupInputHandling {
    if (_seat && _window) {
        _inputHandler = [[InputHandler alloc] initWithSeat:_seat window:_window compositor:self];
        [_inputHandler setupInputHandling];
        
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        // iOS: Set input handler reference in compositor view
        UIView *contentView = _window.rootViewController.view;
        if ([contentView isKindOfClass:[CompositorView class]]) {
            ((CompositorView *)contentView).inputHandler = _inputHandler;
        }
        // iOS: Touch events are handled via UIKit gesture recognizers
        // Keyboard events are handled via UIResponder chain
#else
        // macOS: Set input handler reference in compositor view for keyboard event handling
        NSView *contentView = _window.contentView;
        if ([contentView isKindOfClass:[CompositorView class]]) {
            ((CompositorView *)contentView).inputHandler = _inputHandler;
        }
        
        // Set up event monitoring for mouse events only
        // Keyboard events are handled directly in CompositorView keyDown/keyUp methods
        NSEventMask eventMask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp |
                               NSEventMaskRightMouseDown | NSEventMaskRightMouseUp |
                               NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp |
                               NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged |
                               NSEventMaskRightMouseDragged | NSEventMaskOtherMouseDragged |
                               NSEventMaskScrollWheel;
        
        [NSEvent addLocalMonitorForEventsMatchingMask:eventMask handler:^NSEvent *(NSEvent *event) {
            // CRITICAL: Always return the event to allow normal window processing
            // We just observe events for Wayland clients, but don't consume them
            if ([event window] == self.window) {
                // Check if event is in content area (not title bar)
                NSPoint locationInWindow = [event locationInWindow];
                NSRect contentRect = [self.window.contentView frame];
                
                // Only process events in content area - let window handle title bar events
                if (locationInWindow.y <= contentRect.size.height && locationInWindow.y >= 0 &&
                    locationInWindow.x >= 0 && locationInWindow.x <= contentRect.size.width) {
                    NSEventType type = [event type];
                    if (type == NSEventTypeMouseMoved || type == NSEventTypeLeftMouseDragged ||
                        type == NSEventTypeRightMouseDragged || type == NSEventTypeOtherMouseDragged ||
                        type == NSEventTypeLeftMouseDown || type == NSEventTypeLeftMouseUp ||
                        type == NSEventTypeRightMouseDown || type == NSEventTypeRightMouseUp ||
                        type == NSEventTypeOtherMouseDown || type == NSEventTypeOtherMouseUp ||
                        type == NSEventTypeScrollWheel) {
                        // Forward to Wayland clients but don't consume the event
                        [self.inputHandler handleMouseEvent:event];
                    }
                }
            }
            // ALWAYS return event - never consume it, so window controls work normally
            return event;
        }];
        
        NSLog(@"   ✓ Input handling set up (macOS)");
#endif
    }
}

- (BOOL)start {
    init_compositor_logging();
    NSLog(@"✅ Starting compositor backend...");
    log_printf("[COMPOSITOR] ", "Starting compositor backend...\n");
    
    // Create Wayland protocol implementations
    // These globals are advertised to clients and enable EGL platform extension support
    // Clients querying the registry will see wl_compositor, which allows them to create
    // EGL surfaces using eglCreatePlatformWindowSurfaceEXT with Wayland surfaces
    _compositor = wl_compositor_create(_display);
    if (!_compositor) {
        NSLog(@"❌ Failed to create wl_compositor");
        return NO;
    }
    NSLog(@"   ✓ wl_compositor created (supports EGL platform extensions)");
    
    // Set up render callback for immediate rendering on commit
    g_compositor_instance = self;
    wl_compositor_set_render_callback(_compositor, render_surface_callback);
    
    // Set up title update callback to update window title when focus changes
    wl_compositor_set_title_update_callback(_compositor, macos_compositor_update_title);
    
    // Set up frame callback requested callback to ensure timer is running
    wl_compositor_set_frame_callback_requested(_compositor, macos_compositor_frame_callback_requested);
    
    // Get window size for output
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    CGRect frame = _window.bounds;
#else
    NSRect frame = [_window.contentView bounds];
#endif
    _output = wl_output_create(_display, (int32_t)frame.size.width, (int32_t)frame.size.height, "iOS");
    if (!_output) {
        NSLog(@"❌ Failed to create wl_output");
        return NO;
    }
    NSLog(@"   ✓ wl_output created (%dx%d)", (int)frame.size.width, (int)frame.size.height);
    
    _seat = wl_seat_create(_display);
    if (!_seat) {
        NSLog(@"❌ Failed to create wl_seat");
        return NO;
    }
    NSLog(@"   ✓ wl_seat created");
    
    // Set seat in compositor for focus management
    wl_compositor_set_seat(_seat);
    
    _shm = wl_shm_create(_display);
    if (!_shm) {
        NSLog(@"❌ Failed to create wl_shm");
        return NO;
    }
    NSLog(@"   ✓ wl_shm created");
    
    _subcompositor = wl_subcompositor_create(_display);
    if (!_subcompositor) {
        NSLog(@"❌ Failed to create wl_subcompositor");
        return NO;
    }
    NSLog(@"   ✓ wl_subcompositor created");
    
    _data_device_manager = wl_data_device_manager_create(_display);
    if (!_data_device_manager) {
        NSLog(@"❌ Failed to create wl_data_device_manager");
        return NO;
    }
    NSLog(@"   ✓ wl_data_device_manager created");
    
    _xdg_wm_base = xdg_wm_base_create(_display);
    if (!_xdg_wm_base) {
        NSLog(@"❌ Failed to create xdg_wm_base");
        return NO;
    }
    // Set initial output size
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    CGRect initialFrame = _window.bounds;
#else
    NSRect initialFrame = [_window.contentView bounds];
#endif
    xdg_wm_base_set_output_size(_xdg_wm_base, (int32_t)initialFrame.size.width, (int32_t)initialFrame.size.height);
    NSLog(@"   ✓ xdg_wm_base created");
    
    // Create optional protocol implementations to satisfy client requirements
    // These are minimal stubs - full implementations can be added later
    
    // Primary selection protocol
    struct wl_primary_selection_manager_impl *primary_selection = wl_primary_selection_create(_display);
    if (primary_selection) {
        NSLog(@"   ✓ Primary selection protocol created");
    }
    
    // Decoration manager protocol
    struct wl_decoration_manager_impl *decoration = wl_decoration_create(_display);
    if (decoration) {
        NSLog(@"   ✓ Decoration manager protocol created");
    }
    
    // Toplevel icon protocol
    struct wl_toplevel_icon_manager_impl *toplevel_icon = wl_toplevel_icon_create(_display);
    if (toplevel_icon) {
        NSLog(@"   ✓ Toplevel icon protocol created");
    }
    
    // XDG activation protocol
    struct wl_activation_manager_impl *activation = wl_activation_create(_display);
    if (activation) {
        NSLog(@"   ✓ XDG activation protocol created");
    }
    
    // Fractional scale protocol
    struct wl_fractional_scale_manager_impl *fractional_scale = wl_fractional_scale_create(_display);
    if (fractional_scale) {
        NSLog(@"   ✓ Fractional scale protocol created");
    }
    
    // Cursor shape protocol
    struct wl_cursor_shape_manager_impl *cursor_shape = wl_cursor_shape_create(_display);
    if (cursor_shape) {
        NSLog(@"   ✓ Cursor shape protocol created");
    }
    
    // Text input protocol v3
    struct wl_text_input_manager_impl *text_input = wl_text_input_create(_display);
    if (text_input && text_input->global) {
        self.text_input_manager = text_input; // Store to keep it alive
        NSLog(@"   ✓ Text input protocol v3 created (global=%p)", (void *)text_input->global);
    } else {
        NSLog(@"   ❌ Failed to create text input protocol v3");
        self.text_input_manager = NULL;
    }
    
    // Text input protocol v1 (for weston-editor compatibility)
    struct wl_text_input_manager_v1_impl *text_input_v1 = wl_text_input_v1_create(_display);
    if (text_input_v1 && text_input_v1->global) {
        NSLog(@"   ✓ Text input protocol v1 created (global=%p)", (void *)text_input_v1->global);
    } else {
        NSLog(@"   ❌ Failed to create text input protocol v1");
    }
    
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    // EGL buffer handler (for rendering EGL/OpenGL ES buffers using KosmicKrisp+Zink)
    struct egl_buffer_handler *egl_handler = calloc(1, sizeof(struct egl_buffer_handler));
    if (egl_handler) {
        if (egl_buffer_handler_init(egl_handler, _display) == 0) {
            self.egl_buffer_handler = egl_handler;
            NSLog(@"   ✓ EGL buffer handler initialized (KosmicKrisp+Zink)");
        } else {
            NSLog(@"   ⚠️ EGL buffer handler initialization failed (EGL may not be available)");
            free(egl_handler);
            self.egl_buffer_handler = NULL;
        }
    } else {
        NSLog(@"   ❌ Failed to allocate EGL buffer handler");
        self.egl_buffer_handler = NULL;
    }
#else
    // iOS: EGL is disabled in KosmicKrisp
    self.egl_buffer_handler = NULL;
#endif
    
    // Viewporter protocol (critical for Weston compatibility)
    struct wl_viewporter_impl *viewporter = wl_viewporter_create(_display);
    if (viewporter) {
        NSLog(@"   ✓ Viewporter protocol created");
    }
    
    // Shell protocol (legacy compatibility)
    struct wl_shell_impl *shell = wl_shell_create(_display);
    if (shell) {
        NSLog(@"   ✓ Shell protocol created");
    }
    
    // Screencopy protocol (screen capture)
    struct wl_screencopy_manager_impl *screencopy = wl_screencopy_manager_create(_display);
    if (screencopy) {
        NSLog(@"   ✓ Screencopy protocol created");
    }
    
    // Linux DMA-BUF protocol (critical for wlroots and hardware-accelerated clients)
    struct wl_linux_dmabuf_manager_impl *linux_dmabuf = wl_linux_dmabuf_create(_display);
    if (linux_dmabuf) {
        NSLog(@"   ✓ Linux DMA-BUF protocol created");
    }
    
    // wl_drm protocol (for EGL fallback when dmabuf feedback doesn't provide render node)
    struct wl_drm_impl *wl_drm = wl_drm_create(_display);
    if (wl_drm) {
        NSLog(@"   ✓ wl_drm protocol created (stub for macOS EGL compatibility)");
    }
    
    // Idle inhibit protocol (prevent screensaver)
    struct wl_idle_inhibit_manager_impl *idle_inhibit = wl_idle_inhibit_manager_create(_display);
    if (idle_inhibit) {
        NSLog(@"   ✓ Idle inhibit protocol created");
    }
    
    // Pointer gestures protocol (trackpad gestures)
    struct wl_pointer_gestures_impl *pointer_gestures = wl_pointer_gestures_create(_display);
    if (pointer_gestures) {
        NSLog(@"   ✓ Pointer gestures protocol created");
    }
    
    // Relative pointer protocol (relative motion for games)
    struct wl_relative_pointer_manager_impl *relative_pointer = wl_relative_pointer_manager_create(_display);
    if (relative_pointer) {
        NSLog(@"   ✓ Relative pointer protocol created");
    }
    
    // Pointer constraints protocol (pointer locking/confining for games)
    struct wl_pointer_constraints_impl *pointer_constraints = wl_pointer_constraints_create(_display);
    if (pointer_constraints) {
        NSLog(@"   ✓ Pointer constraints protocol created");
    }
    
    // Register additional protocols
    struct wl_tablet_manager_impl *tablet = wl_tablet_create(_display);
    if (tablet) {
        NSLog(@"   ✓ Tablet protocol created");
    }
    
    struct wl_idle_manager_impl *idle_manager = wl_idle_manager_create(_display);
    if (idle_manager) {
        NSLog(@"   ✓ Idle manager protocol created");
    }
    
    struct wl_keyboard_shortcuts_inhibit_manager_impl *keyboard_shortcuts = wl_keyboard_shortcuts_create(_display);
    if (keyboard_shortcuts) {
        NSLog(@"   ✓ Keyboard shortcuts inhibit protocol created");
    }
    
    // GTK Shell protocol (for GTK applications)
    struct wl_gtk_shell_manager_impl *gtk_shell = wl_gtk_shell_create(_display);
    if (gtk_shell) {
        NSLog(@"   ✓ GTK Shell protocol created");
    }
    
    // Plasma Shell protocol (for KDE applications)
    struct wl_plasma_shell_manager_impl *plasma_shell = wl_plasma_shell_create(_display);
    if (plasma_shell) {
        NSLog(@"   ✓ Plasma Shell protocol created");
    }
    
    // Presentation time protocol (for accurate presentation timing feedback)
    struct wp_presentation_impl *presentation = wp_presentation_create(_display, _output);
    if (presentation) {
        NSLog(@"   ✓ Presentation time protocol created");
    }
    
    // Color management protocol (for color operations and HDR support)
    _color_manager = wp_color_manager_create(_display, _output);
    if (_color_manager) {
        NSLog(@"   ✓ Color management protocol created (HDR: %s)", 
              _color_manager->hdr_supported ? "yes" : "no");
    } else {
        NSLog(@"   ✗ Color management protocol creation failed");
    }
    
    // Qt Wayland Extensions (for QtWayland applications)
    struct wl_qt_surface_extension_impl *qt_surface = wl_qt_surface_extension_create(_display);
    if (qt_surface) {
        NSLog(@"   ✓ Qt Surface Extension protocol created");
    }
    struct wl_qt_windowmanager_impl *qt_wm = wl_qt_windowmanager_create(_display);
    if (qt_wm) {
        NSLog(@"   ✓ Qt Window Manager protocol created");
    } else {
        NSLog(@"   ✗ Qt Window Manager protocol creation failed");
    }
    
    // Start dedicated Wayland event processing thread
    NSLog(@"   ✓ Starting Wayland event processing thread");
    _shouldStopEventThread = NO;
    __unsafe_unretained MacOSCompositor *unsafeSelf = self;
    _eventThread = [[NSThread alloc] initWithBlock:^{
        MacOSCompositor *compositor = unsafeSelf;
        if (!compositor) return;
        
        log_printf("[COMPOSITOR] ", "🚀 Wayland event thread started\n");
        
        // Set up proper error handling for client connections
        // wl_display_run() handles client connections internally
        // NOTE: You may see "failed to read client connection (pid 0)" errors from libwayland-server.
        // These are NORMAL and EXPECTED when:
        // - waypipe clients test/check the socket connection (happens during colima-client startup)
        // - Clients connect then immediately disconnect to verify connectivity
        // - "pid 0" means PID unavailable (normal for waypipe forwarded connections)
        // - These are transient connection attempts, not real errors
        // - libwayland-server handles them gracefully and continues accepting connections
        // - The actual connection will succeed on retry
        // This error is printed by libwayland-server to stderr and cannot be suppressed from our code.
        log_printf("[COMPOSITOR] ", "ℹ️  Note: Transient 'failed to read client connection' errors during client setup are normal and harmless\n");
        
        @try {
            // Use manual event loop instead of wl_display_run() to ensure timers fire
            // wl_display_run() blocks on file descriptors and may not process timers reliably
            struct wl_event_loop *eventLoop = wl_display_get_event_loop(compositor.display);
            while (!compositor.shouldStopEventThread) {
                // Dispatch events with a timeout to allow timers to fire
                // Use 16ms timeout (matches frame callback timer interval)
                int ret = wl_event_loop_dispatch(eventLoop, 16);
                if (ret < 0) {
                    log_printf("[COMPOSITOR] ", "⚠️ Event loop dispatch failed: %d\n", ret);
                    break;
                }
                // Flush clients after each dispatch
                wl_display_flush_clients(compositor.display);
            }
        } @catch (NSException *exception) {
            log_printf("[COMPOSITOR] ", "⚠️ Exception in Wayland event thread: %s\n", 
                       [exception.reason UTF8String]);
        }
        
        log_printf("[COMPOSITOR] ", "🛑 Wayland event thread stopped\n");
    }];
    _eventThread.name = @"WaylandEventThread";
    [_eventThread start];
    
    // Set up frame rendering using CVDisplayLink/CADisplayLink - syncs to display refresh rate
    // This automatically matches the display's refresh rate (e.g., 60Hz, 120Hz, etc.)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    _displayLink = displayLink;
    double refreshRate = displayLink.preferredFramesPerSecond > 0 ? (double)displayLink.preferredFramesPerSecond : 60.0;
    NSLog(@"   Frame rendering active (%.0fHz - synced to display)", refreshRate);
#else
    CVDisplayLinkRef displayLink = NULL;
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
    
    if (displayLink) {
        // Set callback to renderFrame
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, (__bridge void *)self);
        // Start display link - it will continue running even when window loses focus
        // This ensures Wayland clients continue to receive frame callbacks and can render
        CVDisplayLinkStart(displayLink);
        _displayLink = displayLink;
        
        // Get actual refresh rate for logging
        CVTime time = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink);
        double refreshRate = 60.0; // Default fallback
        if (!(time.flags & kCVTimeIsIndefinite) && time.timeValue != 0) {
            refreshRate = (double)time.timeScale / (double)time.timeValue;
        }
        NSLog(@"   Frame rendering active (%.0fHz - synced to display)", refreshRate);
    } else {
        // Fallback to 60Hz timer if CVDisplayLink fails
        NSTimer *fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                                  target:self
                                                                selector:@selector(renderFrame)
                                                                userInfo:nil
                                                                 repeats:YES];
        (void)fallbackTimer; // Timer is retained by the run loop, no need to store reference
        _displayLink = NULL;
        NSLog(@"   Frame rendering active (60Hz - fallback timer)");
    }
#endif
    
    // Add a heartbeat timer to show compositor is alive (every 5 seconds)
    static int heartbeat_count = 0;
    [NSTimer scheduledTimerWithTimeInterval:5.0
                                     repeats:YES
                                       block:^(NSTimer *timer) {
        heartbeat_count++;
        log_printf("[COMPOSITOR] ", "💓 Compositor heartbeat #%d - window visible, event thread running\n", heartbeat_count);
        // Stop after 12 heartbeats (1 minute) to reduce log spam
        if (heartbeat_count >= 12) {
            [timer invalidate];
            log_printf("[COMPOSITOR] ", "💓 Heartbeat logging stopped (compositor still running)\n");
        }
    }];
    
    // Set up input handling
    [self setupInputHandling];
    
    NSLog(@"✅ Compositor backend started");
    NSLog(@"   Wayland event processing thread active");
    NSLog(@"   Input handling active");
    
    return YES;
}


- (BOOL)processWaylandEvents {
    // DEPRECATED: Event processing is now handled by the dedicated event thread
    // This method is kept for compatibility but should not be used
    // The event thread handles all Wayland event processing with blocking dispatch
    return NO;
}

// DisplayLink callback - called at display refresh rate
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)displayLinkCallback:(CADisplayLink *)displayLink {
    (void)displayLink;
    [self renderFrame];
}
#else
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                   const CVTimeStamp *inNow,
                                   const CVTimeStamp *inOutputTime,
                                   CVOptionFlags flagsIn,
                                   CVOptionFlags *flagsOut,
                                   void *displayLinkContext) {
    (void)displayLink;
    (void)inNow;
    (void)inOutputTime;
    (void)flagsIn;
    (void)flagsOut;
    MacOSCompositor *compositor = (__bridge MacOSCompositor *)displayLinkContext;
    if (compositor) {
        // Render on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [compositor renderFrame];
        });
    }
    return kCVReturnSuccess;
}
#endif

// Show and size window when first client connects
- (void)showAndSizeWindowForFirstClient:(int32_t)width height:(int32_t)height {
    if (_windowShown) {
        return; // Already shown
    }
    
    NSLog(@"[WINDOW] First client connected - showing window with size %dx%d", width, height);
    
    // Resize window to match client surface size
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Set window frame directly
    CGRect windowFrame = CGRectMake(0, 0, width, height);
    _window.frame = windowFrame;
    (void)width; (void)height; // Used in NSLog below
#else
    // macOS: frameRectForContentRect automatically accounts for window frame (titlebar, borders)
    NSRect contentRect = NSMakeRect(0, 0, width, height);
    NSRect windowFrame = [_window frameRectForContentRect:contentRect];
    
    // Center window on screen
    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1920, 1080);
    CGFloat x = screenFrame.origin.x + (screenFrame.size.width - windowFrame.size.width) / 2;
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Set window frame directly
    _window.frame = windowFrame;
    UIView *contentView = _window.rootViewController.view;
    contentView.frame = windowFrame;
#else
    CGFloat y = screenFrame.origin.y + (screenFrame.size.height - windowFrame.size.height) / 2;
    windowFrame.origin = NSMakePoint(x, y);
    
    // Set window frame
    [_window setFrame:windowFrame display:YES];  // Use display:YES to ensure immediate update
    
    // CRITICAL: Ensure content view frame matches window content rect
    // The content view might have been initialized with a different size (800x600)
    NSView *contentView = _window.contentView;
    NSRect contentViewFrame = [_window contentRectForFrameRect:windowFrame];
    contentViewFrame.origin = NSMakePoint(0, 0);  // Content view origin is always (0,0)
    contentView.frame = contentViewFrame;
#endif
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    NSLog(@"[WINDOW] Content view resized to: %.0fx%.0f", 
          contentViewFrame.size.width, contentViewFrame.size.height);
#endif
    
    // Ensure Metal view (if exists) matches window size before showing
    if ([contentView isKindOfClass:[CompositorView class]]) {
        CompositorView *compositorView = (CompositorView *)contentView;
        
        // If Metal view exists, ensure it matches the window content size
        if (_backendType == 1 && compositorView.metalView) {
            // Metal view frame should match content view bounds (in points)
            // CRITICAL: Do NOT manually set bounds - MTKView handles this automatically
            // Setting bounds manually interferes with MTKView's Retina scaling logic
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            CGRect contentBounds = compositorView.bounds;
            compositorView.metalView.frame = contentBounds;
            [compositorView.metalView setNeedsDisplay];
#else
            NSRect contentBounds = compositorView.bounds;
            compositorView.metalView.frame = contentBounds;
            [compositorView.metalView setNeedsDisplay:YES];
#endif
            // MTKView automatically sets bounds to match frame - don't override!
            // The drawableSize will be automatically calculated based on frame size and Retina scale
            NSLog(@"[WINDOW] Metal view sized to match window content: frame=%.0fx%.0f (MTKView handles bounds/drawable automatically)", 
                  contentBounds.size.width, contentBounds.size.height);
        }
    }
    
    // Update output size to match client
    if (_output) {
        wl_output_update_size(_output, width, height);
    }
    if (_xdg_wm_base) {
        xdg_wm_base_set_output_size(_xdg_wm_base, width, height);
    }
    
    // Show window and make it key
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    _window.hidden = NO;
    [_window makeKeyWindow];
#else
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_window becomeKeyWindow];
#endif
    
    _windowShown = YES;
    
    NSLog(@"[WINDOW] Window shown and sized to %dx%d", width, height);
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// NSWindowDelegate method - called when window close button (X) is clicked
- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    
    NSLog(@"[WINDOW] Window close button clicked - sending close event to client");
    
    // Get the global seat to find the focused surface
    extern struct wl_seat_impl *global_seat;
    if (!global_seat || !global_seat->focused_surface) {
        NSLog(@"[WINDOW] No focused surface - closing window");
        return YES; // Allow window to close
    }
    
    // Get the focused surface
    struct wl_surface_impl *focused_surface = (struct wl_surface_impl *)global_seat->focused_surface;
    if (!focused_surface || !focused_surface->resource) {
        NSLog(@"[WINDOW] Focused surface is invalid - closing window");
        return YES; // Allow window to close
    }
    
    // Find the toplevel associated with this surface
    extern struct xdg_toplevel_impl *xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *wl_surface);
    struct xdg_toplevel_impl *toplevel = xdg_surface_get_toplevel_from_wl_surface(focused_surface);
    
    if (!toplevel || !toplevel->resource) {
        NSLog(@"[WINDOW] No toplevel found for focused surface - closing window");
        return YES; // Allow window to close
    }
    
    // Verify the toplevel resource is still valid
    struct wl_client *client = wl_resource_get_client(toplevel->resource);
    if (!client || wl_resource_get_user_data(toplevel->resource) == NULL) {
        NSLog(@"[WINDOW] Toplevel resource is invalid - closing window");
        return YES; // Allow window to close
    }
    
    // Send close event to the client
    NSLog(@"[WINDOW] Sending close event to client (toplevel=%p, client=%p)", (void *)toplevel, (void *)client);
    
    // Use the xdg_toplevel_send_close function from xdg-shell-protocol.h
    // This sends the XDG_TOPLEVEL_CLOSE event to the client
    wl_resource_post_event(toplevel->resource, XDG_TOPLEVEL_CLOSE);
    
    // Flush the client connection to ensure the close event is sent
    wl_display_flush_clients(_display);
    
    // Disconnect the client after a short delay to allow it to handle the close event
    // This gives well-behaved clients a chance to clean up gracefully
    // Store the client pointer in a local variable for the block
    struct wl_client *client_to_disconnect = client;
    struct wl_resource *toplevel_resource = toplevel->resource;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Check if client is still connected by verifying the toplevel resource still belongs to it
        if (client_to_disconnect && toplevel_resource) {
            struct wl_client *current_client = wl_resource_get_client(toplevel_resource);
            if (current_client == client_to_disconnect) {
                // Client is still connected - disconnect it
                NSLog(@"[WINDOW] Client did not close gracefully - disconnecting");
                wl_client_destroy(client_to_disconnect);
            }
        }
    });
    
    // Don't close the window immediately - let the client handle the close event
    // The window will be closed when the client disconnects
    return NO; // Prevent window from closing immediately
}
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// NSWindowDelegate method - called when window becomes key
- (void)windowDidBecomeKey:(NSNotification *)notification {
    (void)notification;
    NSLog(@"[WINDOW] Window became key - accepting keyboard input");
    
    // Ensure compositor view is first responder when window becomes key
    NSView *contentView = _window.contentView;
    if ([contentView isKindOfClass:[CompositorView class]] && _window.firstResponder != contentView) {
        [_window makeFirstResponder:contentView];
    }
}

// NSWindowDelegate method - called when window enters fullscreen
- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    (void)notification;
    _isFullscreen = YES;
    NSLog(@"[FULLSCREEN] Window entered fullscreen");
}

// NSWindowDelegate method - called when window exits fullscreen
- (void)windowDidExitFullScreen:(NSNotification *)notification {
    (void)notification;
    _isFullscreen = NO;
    
    // Cancel any pending exit timer
    if (_fullscreenExitTimer) {
        [_fullscreenExitTimer invalidate];
        _fullscreenExitTimer = nil;
    }
    
    // Ensure titlebar is visible after exiting fullscreen (especially if client disconnected)
    // This allows users to interact with the window even if no clients are connected
    if (_window && _connectedClientCount == 0) {
        NSWindowStyleMask titlebarStyle = (NSWindowStyleMaskTitled |
                                           NSWindowStyleMaskClosable |
                                           NSWindowStyleMaskResizable |
                                           NSWindowStyleMaskMiniaturizable);
        if (_window.styleMask != titlebarStyle) {
            _window.styleMask = titlebarStyle;
            NSLog(@"[FULLSCREEN] Restored titlebar after exiting fullscreen (no clients connected)");
        }
    }
    
    NSLog(@"[FULLSCREEN] Window exited fullscreen");
}
#endif

// NSWindowDelegate method - called when window is resized
- (void)windowDidResize:(NSNotification *)notification {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Handle resize differently
    (void)notification;
#else
    NSWindow *window = notification.object;
    NSRect frame = [window.contentView bounds];
    int32_t width = (int32_t)frame.size.width;
    int32_t height = (int32_t)frame.size.height;
    
    NSLog(@"[WINDOW] Window resized to %dx%d", width, height);
    
    // Update Metal view frame to match window size if Metal backend is active
    NSView *contentView = window.contentView;
    if ([contentView isKindOfClass:[CompositorView class]]) {
        CompositorView *compositorView = (CompositorView *)contentView;
        
        // If Metal view exists, ensure it matches the window size
        if (_backendType == 1 && compositorView.metalView) {
            NSRect metalFrame = compositorView.bounds;
            compositorView.metalView.frame = metalFrame;
            // CRITICAL: Do NOT manually set bounds - MTKView handles this automatically
            // MTKView automatically sets bounds to match frame and calculates drawableSize
            // Manually setting bounds interferes with Retina scaling
            NSLog(@"[WINDOW] Metal view resized to match window: frame=%.0fx%.0f (MTKView handles bounds/drawable automatically)", 
                  metalFrame.size.width, metalFrame.size.height);
            
            // Trigger Metal view to update its drawable size
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            [compositorView.metalView setNeedsDisplay];
        } else {
            // Cocoa backend - trigger redraw
            [contentView setNeedsDisplay];
#else
            [compositorView.metalView setNeedsDisplay:YES];
        } else {
            // Cocoa backend - trigger redraw
            [contentView setNeedsDisplay:YES];
#endif
        }
    }
#endif
    
    // Update output size (width and height are declared in platform-specific branches above)
    int32_t width, height;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    CGRect frame = _window.bounds;
    width = (int32_t)frame.size.width;
    height = (int32_t)frame.size.height;
#else
    NSWindow *window = notification.object;
    NSRect frame = [window.contentView bounds];
    width = (int32_t)frame.size.width;
    height = (int32_t)frame.size.height;
#endif
    
    if (_output) {
        wl_output_update_size(_output, width, height);
    }
    
    // Update xdg_wm_base output size immediately
    if (_xdg_wm_base) {
        xdg_wm_base_set_output_size(_xdg_wm_base, width, height);
    }
    
    // Schedule configure events to be sent from the Wayland event thread
    // Wayland server functions must be called from the event thread
    _pending_resize_width = width;
    _pending_resize_height = height;
    _needs_resize_configure = YES;
    
    // Trigger the idle callback immediately to send configure events
    if (_eventLoop) {
        // Kick the timer from the event loop thread to send configure + frame callbacks quickly
        wl_event_loop_add_idle(_eventLoop, ensure_frame_callback_timer_idle, (__bridge void *)self);
    }
}

// Idle callback to trigger first frame callback immediately
static void send_frame_callbacks_timer_idle(void *data) {
    MacOSCompositor *compositor = (__bridge MacOSCompositor *)data;
    if (compositor) {
        log_printf("[COMPOSITOR] ", "send_frame_callbacks_timer_idle: Triggering immediate frame callback\n");
        fflush(stdout);
        // Call the timer function directly to send frame callbacks immediately
        send_frame_callbacks_timer(data);
    }
}

// Ensure the frame callback timer exists and is scheduled (must run on event thread)
static BOOL ensure_frame_callback_timer_on_event_thread(MacOSCompositor *compositor, uint32_t delay_ms, const char *reason) {
    if (!compositor || !compositor.display) {
        return NO;
    }

    struct wl_event_loop *eventLoop = wl_display_get_event_loop(compositor.display);
    if (!eventLoop) {
        log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: event loop unavailable\n");
        return NO;
    }

    if (!compositor.frame_callback_source) {
        compositor.frame_callback_source = wl_event_loop_add_timer(eventLoop, send_frame_callbacks_timer, (__bridge void *)compositor);
        if (!compositor.frame_callback_source) {
            log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: Failed to create timer (%s)\n",
                       reason ? reason : "no reason");
            return NO;
        }
        log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: Created timer (%s, delay=%ums)\n",
                   reason ? reason : "no reason", delay_ms);
    }

    int ret = wl_event_source_timer_update(compositor.frame_callback_source, delay_ms);
    if (ret < 0) {
        int err = errno;
        log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: timer update failed (%s, delay=%ums) - recreating\n",
                   strerror(err), delay_ms);
        wl_event_source_remove(compositor.frame_callback_source);
        compositor.frame_callback_source = NULL;

        compositor.frame_callback_source = wl_event_loop_add_timer(eventLoop, send_frame_callbacks_timer, (__bridge void *)compositor);
        if (!compositor.frame_callback_source) {
            log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: Failed to recreate timer after error\n");
            return NO;
        }

        ret = wl_event_source_timer_update(compositor.frame_callback_source, delay_ms);
        if (ret < 0) {
            err = errno;
            log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: Second timer update failed (%s)\n",
                       strerror(err));
            wl_event_source_remove(compositor.frame_callback_source);
            compositor.frame_callback_source = NULL;
            return NO;
        }

        log_printf("[COMPOSITOR] ", "ensure_frame_callback_timer_on_event_thread: Timer recreated successfully\n");
    }
    return YES;
}

// Idle helper to (re)arm the timer from threads other than the event thread
static void ensure_frame_callback_timer_idle(void *data) {
    MacOSCompositor *compositor = (__bridge MacOSCompositor *)data;
    if (compositor) {
        ensure_frame_callback_timer_on_event_thread(compositor, 0, "idle kick");
    }
}

// Timer callback to send frame callbacks from Wayland event thread
// This fires every ~16ms (60Hz) to match display refresh rate
static int send_frame_callbacks_timer(void *data) {
    MacOSCompositor *compositor = (__bridge MacOSCompositor *)data;
    if (compositor) {
        // This runs on the Wayland event thread - safe to call Wayland server functions
        
        // Timer fires every 16ms - log first few calls and then every 60th call
        static int timer_call_count = 0;
        timer_call_count++;
        if (timer_call_count <= 5 || timer_call_count % 60 == 0) {
            log_printf("[COMPOSITOR] ", "send_frame_callbacks_timer() called (call #%d)\n", timer_call_count);
            fflush(stdout); // Force flush to ensure log is visible
        }
        
        // Handle pending resize configure events first
        if (compositor.needs_resize_configure) {
            if (compositor.xdg_wm_base) {
                xdg_wm_base_send_configure_to_all_toplevels(compositor.xdg_wm_base, 
                                                             compositor.pending_resize_width, 
                                                             compositor.pending_resize_height);
            }
            compositor.needs_resize_configure = NO;
        }
        
        // Send frame callbacks
        int sent_count = wl_send_frame_callbacks();
        if (sent_count > 0) {
            log_printf("[COMPOSITOR] ", "send_frame_callbacks_timer: Sent %d frame callback(s)\n", sent_count);
            fflush(stdout);
        }
        
        // CRITICAL: Flush clients to ensure frame callbacks are sent immediately
        // This wakes up clients waiting on wl_display_dispatch()
        wl_display_flush_clients(compositor.display);
        
        // CRITICAL: Always keep timer running - clients request new frame callbacks AFTER receiving them
        // If we stop the timer when there are no pending callbacks, we'll miss the next request
        // The timer will be removed when the compositor stops or all clients disconnect
        // Keep firing every 16ms (60Hz) continuously
        if (!ensure_frame_callback_timer_on_event_thread(compositor, 16, "re-arm")) {
            log_printf("[COMPOSITOR] ", "send_frame_callbacks_timer: Failed to re-arm timer\n");
        }
        return 0;
    }
    return 0;
}

- (void)sendFrameCallbacksImmediately {
    // Force immediate frame callback dispatch - used after input events
    // This allows clients to render updates immediately in response to input
    // NOTE: Must be called from main thread, but the timer callback will run on event thread
    if (_eventLoop && wl_has_pending_frame_callbacks()) {
        // Ensure timer is running - use idle callback so logic executes on event thread
        wl_event_loop_add_idle(_eventLoop, ensure_frame_callback_timer_idle, (__bridge void *)self);
    }
}

// Render context for thread-safe iteration
struct RenderContext {
    __unsafe_unretained MacOSCompositor *compositor;
    BOOL surfacesWereRendered;
};

// Iterator function for rendering surfaces
static void render_surface_iterator(struct wl_surface_impl *surface, void *data) {
    struct RenderContext *ctx = (struct RenderContext *)data;
    MacOSCompositor *self = ctx->compositor;
    
    // Only render if surface is still valid and has committed buffer
    if (surface->committed && surface->buffer_resource && surface->resource) {
        // Verify resource is still valid before rendering
        struct wl_client *client = wl_resource_get_client(surface->resource);
        if (client) {
            // Use active rendering backend (Cocoa or Metal)
            // Render regardless of window focus state - clients need updates
            if (self.renderingBackend) {
                if ([self.renderingBackend respondsToSelector:@selector(renderSurface:)]) {
                    [self.renderingBackend renderSurface:surface];
                    ctx->surfacesWereRendered = YES;
                } else if (self.renderer) {
                    // Fallback to Cocoa renderer
                    [self.renderer renderSurface:surface];
                    ctx->surfacesWereRendered = YES;
                }
            }
        }
        surface->committed = false;
    }
}

- (void)renderFrame {
    // Render callback - called at display refresh rate (via CVDisplayLink)
    // Event processing is handled by the dedicated Wayland event thread
    // This ensures smooth rendering updates synced to display refresh
    // NOTE: This continues to run even when the window loses focus, ensuring
    // Wayland clients continue to receive frame callbacks and can render updates

    // Note: Frame callback timer is now created automatically when clients request frame callbacks
    // via the macos_compositor_frame_callback_requested callback. This ensures the timer is
    // created on the event thread and starts firing immediately.
    // We don't need to check here anymore - the timer will be created when needed.
    
    // Check for any committed surfaces and render them
    // Note: The event thread also triggers rendering, but this ensures
    // we catch any surfaces that might have been committed between thread dispatches
    // Continue rendering even when window isn't focused - clients need frame callbacks
    
    struct RenderContext ctx;
    ctx.compositor = self;
    ctx.surfacesWereRendered = NO;
    
    // Use thread-safe iteration to render surfaces
    // This locks the surfaces mutex to prevent race conditions with the event thread
    wl_compositor_for_each_surface(render_surface_iterator, &ctx);
    
    BOOL surfacesWereRendered = ctx.surfacesWereRendered;
    
    // Trigger view redraw if surfaces were rendered
    // CRITICAL: Even with Metal backend continuous rendering, we must trigger redraw
    // when surfaces are updated to ensure immediate display of nested compositor updates
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    UIView *contentView = _window.rootViewController.view;
    if (surfacesWereRendered && _window && contentView) {
        if (_backendType == 1) {
            // Metal backend - trigger redraw using renderer's setNeedsDisplay method
            // This ensures nested compositors (like Weston) see updates immediately
            if ([self->_renderingBackend respondsToSelector:@selector(setNeedsDisplay)]) {
                [self->_renderingBackend setNeedsDisplay];
            }
        } else {
            // Cocoa backend - needs explicit redraw
            [contentView setNeedsDisplay];
        }
    } else if (_window && contentView && _backendType != 1) {
        // Cocoa backend always needs redraw for frame callbacks
        [contentView setNeedsDisplay];
    }
#else
    if (surfacesWereRendered && _window && _window.contentView) {
        if (_backendType == 1) {
            // Metal backend - trigger redraw using renderer's setNeedsDisplay method
            // This ensures nested compositors (like Weston) see updates immediately
            if ([self->_renderingBackend respondsToSelector:@selector(setNeedsDisplay)]) {
                [self->_renderingBackend setNeedsDisplay];
            }
        } else {
            // Cocoa backend - needs explicit redraw
            [_window.contentView setNeedsDisplay:YES];
        }
    } else if (_window && _window.contentView && _backendType != 1) {
        // Cocoa backend always needs redraw for frame callbacks
        [_window.contentView setNeedsDisplay:YES];
    }
#endif
}


// Helper function to disconnect all clients gracefully
static void disconnect_all_clients(struct wl_display *display) {
    if (!display) return;
    
    log_printf("[COMPOSITOR] ", "🔌 Disconnecting all clients...\n");
    
    // Terminate display to stop accepting new connections first
    wl_display_terminate(display);
    
    // Flush once to send termination signal
    wl_display_flush_clients(display);
    
    // Process a few events to let termination propagate
    struct wl_event_loop *eventLoop = wl_display_get_event_loop(display);
    for (int i = 0; i < 5; i++) {
        int ret = wl_event_loop_dispatch(eventLoop, 10);
        if (ret < 0) break;
        wl_display_flush_clients(display);
    }
    
    // Use the official Wayland server API to destroy all clients
    // This is the proper protocol-compliant way to disconnect all clients
    wl_display_destroy_clients(display);
    
    // Process events multiple times AFTER destroying clients
    // This gives clients (like waypipe) time to detect the disconnect and exit gracefully
    for (int i = 0; i < 30; i++) {
        // Dispatch events with a short timeout
        int ret = wl_event_loop_dispatch(eventLoop, 50);
        if (ret < 0) {
            // Error or no more events - continue a bit more to ensure cleanup
            if (i < 15) {
                // Still process a few more times even on error to let waypipe detect disconnect
                continue;
            } else {
                break;
            }
        }
        // Flush all client connections to send pending messages
        wl_display_flush_clients(display);
    }
    
    // Small delay to allow waypipe and other clients to fully detect disconnect and exit
    // This helps prevent "Broken pipe" errors from appearing after shutdown
    usleep(100000); // 100ms delay
    
    // Final flush to ensure all messages are sent
    wl_display_flush_clients(display);
    
    log_printf("[COMPOSITOR] ", "✅ Client disconnection complete\n");
}

- (void)stop {
    NSLog(@"🛑 Stopping compositor backend...");
    
    // Clear global reference
    if (g_compositor_instance == self) {
        g_compositor_instance = NULL;
    }
    
    // CRITICAL: Disconnect clients FIRST while event thread is still running
    // This ensures the event loop can properly process disconnection events
    // and send them to clients (like waypipe) so they can detect the disconnect
    if (_display) {
        disconnect_all_clients(_display);
    }
    
    // Now signal event thread to stop (after clients are disconnected)
    _shouldStopEventThread = YES;
    
    // Wait for event thread to finish (with timeout)
    if (_eventThread && [_eventThread isExecuting]) {
        // Give thread up to 1 second to finish
        NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while ([_eventThread isExecuting] && [timeout timeIntervalSinceNow] > 0) {
            [NSThread sleepForTimeInterval:0.01];
        }
        
        if ([_eventThread isExecuting]) {
            NSLog(@"⚠️ Event thread did not stop gracefully, forcing termination");
        }
    }
    _eventThread = nil;
    
    // Stop display link
    if (_displayLink) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
        [_displayLink invalidate];
#else
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
#endif
        _displayLink = NULL;
    }
    
    // Stop frame callback timer
    if (_frame_callback_source) {
        wl_event_source_remove(_frame_callback_source);
        _frame_callback_source = NULL;
    }
    
    // Clean up Wayland resources
    if (_xdg_wm_base) {
        xdg_wm_base_destroy(_xdg_wm_base);
        _xdg_wm_base = NULL;
    }
    
    if (_shm) {
        wl_shm_destroy(_shm);
        _shm = NULL;
    }
    
    if (_seat) {
        wl_seat_destroy(_seat);
        _seat = NULL;
    }
    
    if (_output) {
        wl_output_destroy(_output);
        _output = NULL;
    }
    
    if (_compositor) {
        wl_compositor_destroy(_compositor);
        _compositor = NULL;
    }
    
    cleanup_logging();
    NSLog(@"🛑 Compositor backend stopped");
}

- (void)switchToMetalBackend {
    // Switch from Cocoa to Metal rendering backend for full compositors
    if (_backendType == 1) { // Already using Metal
        return;
    }
    
    NSLog(@"🔄 Switching to Metal rendering backend for full compositor support");
    
    // Get the compositor view
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    UIView *contentView = _window.rootViewController.view;
    CGRect windowBounds;
#else
    NSView *contentView = _window.contentView;
    NSRect windowBounds;
#endif
    if (![contentView isKindOfClass:[CompositorView class]]) {
        NSLog(@"⚠️ Content view is not CompositorView, cannot switch to Metal");
        return;
    }
    
    CompositorView *compositorView = (CompositorView *)contentView;
    
    // Get current window size for Metal view
    windowBounds = compositorView.bounds;
    
    // Create Metal view with exact window size
    // Use a custom class that allows window dragging for proper window controls
    Class CompositorMTKViewClass = NSClassFromString(@"CompositorMTKView");
    MTKView *metalView = nil;
    if (CompositorMTKViewClass) {
        metalView = [[CompositorMTKViewClass alloc] initWithFrame:windowBounds];
    } else {
        // Fallback to regular MTKView if custom class not available
        metalView = [[MTKView alloc] initWithFrame:windowBounds];
    }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    metalView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
#else
    metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    // Ensure Metal view is opaque and properly configured
    metalView.wantsLayer = YES;
    metalView.layer.opaque = YES;
    metalView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
#endif
    metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    metalView.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
    
    // CRITICAL: Don't block mouse events - allow window controls to work
    // The Metal view should not intercept mouse events meant for window controls
    // Note: mouseDownCanMoveWindow is a method, not a property - handled in CompositorView
    // Don't set ignoresMouseEvents - we need to receive events for Wayland clients
    // But ensure the view doesn't block window controls
    
    // Ensure Metal view matches window size exactly
    metalView.frame = windowBounds;
    
    NSLog(@"   Creating Metal view with frame: %.0fx%.0f at (%.0f, %.0f)",
          windowBounds.size.width, windowBounds.size.height,
          windowBounds.origin.x, windowBounds.origin.y);
    
    // Create Metal renderer
    MetalRenderer *metalRenderer = [[MetalRenderer alloc] initWithMetalView:metalView];
    if (!metalRenderer) {
        NSLog(@"❌ Failed to create Metal renderer");
        return;
    }
    
    // Add Metal view as subview (on top of Cocoa view for rendering)
    // The Metal view renders content but allows events to pass through to CompositorView
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [compositorView addSubview:metalView];
    compositorView.metalView = metalView;
    // iOS: Touch events are handled via UIKit gesture recognizers
    // Re-setup input handling if needed
    if (_inputHandler) {
        [_inputHandler setupInputHandling];
    }
#else
    [compositorView addSubview:metalView positioned:NSWindowAbove relativeTo:nil];
    compositorView.metalView = metalView;
    
    // Ensure CompositorView remains the responder chain - Metal view just renders
    // This allows CompositorView to handle events while Metal view displays content
    [metalView setNextResponder:compositorView];
    
    // CRITICAL: Ensure mouse events pass through to CompositorView for tracking areas
    // The Metal view should not block mouse events - they need to reach the tracking area
    // Don't set ignoresMouseEvents - we need events for Wayland clients
    // But ensure the view hierarchy allows events to reach CompositorView's tracking area
    
    // Update input handler's tracking area to cover the full view including Metal view
    if (_inputHandler) {
        // Remove old tracking area and create new one covering full bounds
        NSView *inputContentView = _window.contentView;
        for (NSTrackingArea *area in [inputContentView trackingAreas]) {
            [inputContentView removeTrackingArea:area];
        }
        // Re-setup input handling with updated tracking area
        [_inputHandler setupInputHandling];
    }
#endif
    
    // Switch rendering backend
    _renderingBackend = metalRenderer;
    _backendType = 1; // RENDERING_BACKEND_METAL
    
    // Update render callback to use Metal backend
    // The render_surface_callback will now use the Metal backend
    
    NSLog(@"✅ Switched to Metal rendering backend");
    NSLog(@"   Metal view frame: %.0fx%.0f", metalView.frame.size.width, metalView.frame.size.height);
    NSLog(@"   Window bounds: %.0fx%.0f", windowBounds.size.width, windowBounds.size.height);
    NSLog(@"   Metal renderer: %@", metalRenderer);
}

- (void)updateWindowTitleForClient:(struct wl_client *)client {
    if (!_window || !client) return;
    
    NSString *windowTitle = @"Wawona"; // Default title when no clients
    
    // Try to get the focused surface's toplevel title/app_id
    if (_seat && _seat->focused_surface) {
        struct wl_surface_impl *surface = (struct wl_surface_impl *)_seat->focused_surface;
        if (surface && surface->resource) {
            struct wl_client *surface_client = wl_resource_get_client(surface->resource);
            if (surface_client == client) {
                // Get the toplevel for this surface
                extern struct xdg_toplevel_impl *xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *wl_surface);
                struct xdg_toplevel_impl *toplevel = xdg_surface_get_toplevel_from_wl_surface(surface);
                
                if (toplevel) {
                    // Prefer title over app_id, fallback to app_id if title is not set
                    if (toplevel->title && strlen(toplevel->title) > 0) {
                        windowTitle = [NSString stringWithUTF8String:toplevel->title];
                    } else if (toplevel->app_id && strlen(toplevel->app_id) > 0) {
                        // Use app_id, but make it more readable
                        NSString *appId = [NSString stringWithUTF8String:toplevel->app_id];
                        // Remove common prefixes like "org.freedesktop." or "com."
                        appId = [appId stringByReplacingOccurrencesOfString:@"org.freedesktop." withString:@""];
                        appId = [appId stringByReplacingOccurrencesOfString:@"com." withString:@""];
                        // Capitalize first letter
                        if (appId.length > 0) {
                            appId = [[appId substringToIndex:1].uppercaseString stringByAppendingString:[appId substringFromIndex:1]];
                        }
                        windowTitle = appId;
                    }
                }
                
                // If we still don't have a title, try process name as fallback
                if ([windowTitle isEqualToString:@"Wawona"]) {
                    pid_t client_pid = 0;
                    uid_t client_uid = 0;
                    gid_t client_gid = 0;
                    wl_client_get_credentials(client, &client_pid, &client_uid, &client_gid);
                    
                    if (client_pid > 0) {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
                        char proc_path[PROC_PIDPATHINFO_MAXSIZE] = {0};
                        int ret = proc_pidpath(client_pid, proc_path, sizeof(proc_path));
                        if (ret > 0) {
                            NSString *processPath = [NSString stringWithUTF8String:proc_path];
#else
                        // iOS: Process name detection not available
                        NSString *processPath = nil;
                        if (0) {
#endif
                            NSString *processName = [processPath lastPathComponent];
                            // Remove common suffixes and make it look nice
                            processName = [processName stringByReplacingOccurrencesOfString:@".exe" withString:@""];
                            windowTitle = processName;
                        }
                    }
                }
            }
        }
    }
    
    // Update window title
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Window titles are not displayed in the same way
    (void)windowTitle;
    NSLog(@"[WINDOW] Updated title to: %@", windowTitle);
#else
    // macOS: Update titlebar title
    [_window setTitle:windowTitle];
    NSLog(@"[WINDOW] Updated titlebar title to: %@", windowTitle);
#endif
}

// C function to set CSD mode for a toplevel (hide/show macOS window decorations)
void macos_compositor_set_csd_mode_for_toplevel(struct xdg_toplevel_impl *toplevel, bool csd) {
    if (!g_compositor_instance || !toplevel) {
        return;
    }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    (void)csd; // iOS: CSD mode not applicable
#else
    // Dispatch to main thread to update UI
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = g_compositor_instance.window;
        if (!window) {
            return;
        }
        
        // Get current style mask
        NSWindowStyleMask currentStyle = window.styleMask;
        
        // CRITICAL: Cannot change styleMask while window is in fullscreen - macOS throws exception
        // We'll handle fullscreen titlebar visibility by exiting fullscreen after client disconnect
        // (see macos_compositor_handle_client_disconnect)
        BOOL isFullscreen = g_compositor_instance.isFullscreen;
        
        // Don't change style mask while in fullscreen - wait for fullscreen to exit first
        if (isFullscreen) {
            NSLog(@"[CSD] Skipping styleMask change - window is in fullscreen (will be handled after exit)");
            return;
        }
        
        if (csd) {
            // CLIENT_SIDE decorations - hide macOS window decorations
            // Remove titlebar, close button, etc. - client will draw its own decorations
            NSWindowStyleMask csdStyle = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable;
            if (currentStyle != csdStyle) {
                window.styleMask = csdStyle;
                NSLog(@"[CSD] Window decorations hidden for CLIENT_SIDE decoration mode");
            }
        } else {
            // SERVER_SIDE decorations - show macOS window decorations
            // Show titlebar, close button, resize controls, etc.
            NSWindowStyleMask gsdStyle = (NSWindowStyleMaskTitled |
                                         NSWindowStyleMaskClosable |
                                         NSWindowStyleMaskResizable |
                                         NSWindowStyleMaskMiniaturizable);
            if (currentStyle != gsdStyle) {
                window.styleMask = gsdStyle;
                NSLog(@"[CSD] Window decorations shown for SERVER_SIDE decoration mode");
            }
        }
    });
#endif
}

// C function to activate/raise the window (called from activation protocol)
void macos_compositor_activate_window(void) {
    if (!g_compositor_instance) {
        return;
    }
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    // Dispatch to main thread to raise window
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = g_compositor_instance.window;
        if (!window) {
            return;
        }
        
        // Raise window to front and make it key
        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [window becomeKeyWindow];
        
        NSLog(@"[ACTIVATION] Window activated and raised to front");
    });
#endif
}

// C function to handle client disconnection (may exit fullscreen if needed)
void macos_compositor_handle_client_disconnect(void) {
    if (!g_compositor_instance) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        MacOSCompositor *compositor = g_compositor_instance;
        
        // Decrement client count
        if (compositor.connectedClientCount > 0) {
            compositor.connectedClientCount--;
        }
        
        NSLog(@"[FULLSCREEN] Client disconnected. Connected clients: %lu", (unsigned long)compositor.connectedClientCount);
        
        // If we're in fullscreen and have no clients, start exit timer
        // NOTE: We cannot change styleMask while in fullscreen - macOS throws an exception
        // Instead, we'll exit fullscreen after 10 seconds, which will restore the titlebar
        if (compositor.isFullscreen && compositor.connectedClientCount == 0) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            // iOS: Fullscreen handling not applicable
            (void)compositor;
#else
            NSWindow *window = compositor.window;
            if (window) {
                // Cancel any existing timer
                if (compositor.fullscreenExitTimer) {
                    [compositor.fullscreenExitTimer invalidate];
                    compositor.fullscreenExitTimer = nil;
                }
                
                // Start 10-second timer to close window if no new client connects
                // If no clients are connected, there's no reason to keep the window open
                compositor.fullscreenExitTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                                                   repeats:NO
                                                                                     block:^(NSTimer *timer) {
                    (void)timer; // Unused parameter
                    // Check if we still have no clients
                    if (compositor.connectedClientCount == 0 && compositor.isFullscreen) {
                        NSLog(@"[FULLSCREEN] No clients connected after 10 seconds - closing window");
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
                        // iOS: Hide window instead of closing
                        window.hidden = YES;
#else
                        if (@available(macOS 10.12, *)) {
                            [window performClose:nil];
                        }
#endif
                    }
                    compositor.fullscreenExitTimer = nil;
                }];
                NSLog(@"[FULLSCREEN] Started 10-second timer to close window if no client connects");
            }
#endif
        }
    });
}

// C function to handle new client connection (cancel fullscreen exit timer)
void macos_compositor_handle_client_connect(void) {
    if (!g_compositor_instance) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        MacOSCompositor *compositor = g_compositor_instance;
        
        // Increment client count
        compositor.connectedClientCount++;
        
        NSLog(@"[FULLSCREEN] Client connected. Connected clients: %lu", (unsigned long)compositor.connectedClientCount);
        
        // Cancel fullscreen exit timer if a client connected
        if (compositor.fullscreenExitTimer) {
            [compositor.fullscreenExitTimer invalidate];
            compositor.fullscreenExitTimer = nil;
            NSLog(@"[FULLSCREEN] Cancelled fullscreen exit timer (client connected)");
        }
    });
}

// C function to update window title when no clients are connected
void macos_compositor_update_title_no_clients(void) {
    if (!g_compositor_instance) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        MacOSCompositor *compositor = g_compositor_instance;
        if (compositor.window) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            // iOS: Window titles not displayed
            (void)compositor;
#else
            [compositor.window setTitle:@"Wawona"];
#endif
            NSLog(@"[WINDOW] Updated titlebar title to: Wawona (no clients connected)");
        }
    });
}

// C function to get EGL buffer handler (for rendering EGL buffers)
struct egl_buffer_handler *macos_compositor_get_egl_buffer_handler(void) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: EGL is disabled
    return NULL;
#else
    if (!g_compositor_instance) {
        return NULL;
    }
    return g_compositor_instance.egl_buffer_handler;
#endif
}

- (void)dealloc {
    // Remove notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Clean up timer
    if (_fullscreenExitTimer) {
        [_fullscreenExitTimer invalidate];
        _fullscreenExitTimer = nil;
    }
    
    // Clean up text input manager
    if (_text_input_manager) {
        wl_text_input_destroy(_text_input_manager);
        _text_input_manager = NULL;
    }
    
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    // Clean up EGL buffer handler
    if (_egl_buffer_handler) {
        egl_buffer_handler_cleanup(_egl_buffer_handler);
        free(_egl_buffer_handler);
        _egl_buffer_handler = NULL;
    }
#endif
    
    [self stop];
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    [super dealloc];
#endif
}

@end

