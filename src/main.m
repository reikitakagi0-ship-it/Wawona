#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "macos_backend.h"
#import "WawonaPreferences.h"
#import "WawonaAboutPanel.h"
#include <wayland-server-core.h>
#include <signal.h>
#include <stdlib.h>

static struct wl_display *g_display = NULL;
static MacOSCompositor *g_compositor = NULL;

// Signal handler for graceful shutdown
static void signal_handler(int sig) {
    (void)sig;
    NSLog(@"\n🛑 Received signal, shutting down gracefully...");
    if (g_compositor) {
        [g_compositor stop];
        g_compositor = nil;
    }
    if (g_display) {
        wl_display_destroy(g_display);
        g_display = NULL;
    }
    [NSApp terminate:nil];
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSLog(@"🎯 Wawona - Wayland Compositor for macOS");
        NSLog(@"   Using libwayland-server (no WLRoots)");
        NSLog(@"   Rendering with CALayer");
        NSLog(@"");
        
        // Set up NSApplication
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        
        // Set up menu bar
        NSMenu *menubar = [[NSMenu alloc] init];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        [menubar addItem:appMenuItem];
        [NSApp setMainMenu:menubar];
        
        NSMenu *appMenu = [[NSMenu alloc] init];
        NSString *appName = [[NSProcessInfo processInfo] processName];
        
        // About - use custom About panel
        NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"About %@", appName]
                                                            action:@selector(showAboutPanel:)
                                                     keyEquivalent:@""];
        [aboutItem setTarget:[WawonaAboutPanel sharedAboutPanel]];
        [appMenu addItem:aboutItem];
        
        [appMenu addItem:[NSMenuItem separatorItem]];
        
        // Preferences
        NSMenuItem *prefsItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..."
                                                            action:@selector(showPreferences:)
                                                     keyEquivalent:@","];
        [prefsItem setTarget:[WawonaPreferences sharedPreferences]];
        [appMenu addItem:prefsItem];
        
        [appMenu addItem:[NSMenuItem separatorItem]];
        
        // Quit
        NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
                                                           action:@selector(terminate:)
                                                    keyEquivalent:@"q"];
        [appMenu addItem:quitItem];
        
        [appMenuItem setSubmenu:appMenu];

        // Create compositor window
        NSRect frame = NSMakeRect(100, 100, 1024, 768);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
            styleMask:(NSWindowStyleMaskTitled |
                       NSWindowStyleMaskClosable |
                       NSWindowStyleMaskResizable |
                       NSWindowStyleMaskMiniaturizable)
            backing:NSBackingStoreBuffered
            defer:NO];

        [window setTitle:@"Wawona"];
        // Don't show window initially - wait for first client to connect
        // Window will be shown and sized automatically when first client surface is committed
        // [window makeKeyAndOrderFront:nil]; // DELAYED - shown when first client connects
        // [NSApp activateIgnoringOtherApps:YES]; // DELAYED - done when window is shown

        // Set up XDG_RUNTIME_DIR if not set (required for Wayland socket)
        const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
        NSString *runtimePath = nil;
        if (!runtime_dir) {
            NSString *tmpDir = NSTemporaryDirectory();
            if (tmpDir) {
                runtimePath = [tmpDir stringByAppendingPathComponent:@"wayland-runtime"];
                [[NSFileManager defaultManager] createDirectoryAtPath:runtimePath
                                           withIntermediateDirectories:YES
                                                            attributes:@{NSFilePosixPermissions: @0700}
                                                                 error:nil];
                setenv("XDG_RUNTIME_DIR", [runtimePath UTF8String], 1);
                runtime_dir = [runtimePath UTF8String];
                NSLog(@"   Set XDG_RUNTIME_DIR to: %@", runtimePath);
            }
        } else {
            // If XDG_RUNTIME_DIR is set (e.g., for VM sharing), ensure it's accessible
            runtimePath = [NSString stringWithUTF8String:runtime_dir];
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:runtimePath]) {
                // Set correct permissions (0700) for Wayland compatibility
                // Note: For VM sharing, the directory should be created with correct permissions
                // before being shared, or use a different approach like waypipe
                [fm setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:runtimePath error:nil];
            }
        }
        
        // Create Wayland display
        // This display is fully compatible with EGL_EXT_platform_base and EGL_EXT_platform_wayland
        // Clients can use eglGetPlatformDisplayEXT(EGL_PLATFORM_WAYLAND_EXT, display, NULL)
        // The warning about EGL_EXT_platform_base comes from the client's EGL library,
        // not from Wawona's display implementation
        struct wl_display *display = wl_display_create();
        if (!display) {
            NSLog(@"❌ Failed to create wl_display");
            return -1;
        }
        
        // Add Wayland socket (Unix domain socket)
        // This socket is compatible with all standard Wayland clients including EGL-based ones
        const char *socket = wl_display_add_socket_auto(display);
        if (!socket) {
            NSLog(@"❌ Failed to create WAYLAND_DISPLAY socket");
            NSLog(@"   Make sure XDG_RUNTIME_DIR is set and writable");
            wl_display_destroy(display);
            return -1;
        }

        NSLog(@"✅ Wayland socket created: %s", socket);
        NSLog(@"   Display supports EGL_EXT_platform_base (clients can use eglGetPlatformDisplayEXT)");
        
        // Set permissive socket permissions for VM access (if XDG_RUNTIME_DIR is shared)
        if (runtime_dir) {
            NSString *socketPath = [NSString stringWithUTF8String:runtime_dir];
            socketPath = [socketPath stringByAppendingPathComponent:[NSString stringWithUTF8String:socket]];
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:socketPath]) {
                [fm setAttributes:@{NSFilePosixPermissions: @0666} ofItemAtPath:socketPath error:nil];
                NSLog(@"   Socket permissions set to 666 for VM access");
            }
        }
        
        NSLog(@"   Clients can connect with: export WAYLAND_DISPLAY=%s", socket);
        NSLog(@"");

        // Store globals for signal handler
        g_display = display;
        
        // Create compositor backend
        MacOSCompositor *compositor = [[MacOSCompositor alloc] initWithDisplay:display window:window];
        g_compositor = compositor;
        
        // Set up signal handlers for graceful shutdown (after compositor is created)
        signal(SIGTERM, signal_handler);
        signal(SIGINT, signal_handler);
        
        if (![compositor start]) {
            NSLog(@"❌ Failed to start compositor backend");
            wl_display_destroy(display);
            return -1;
        }

        NSLog(@"🚀 Compositor running!");
        NSLog(@"   Ready for Wayland clients to connect");
        NSLog(@"");

        // Run macOS event loop
        // TODO: Integrate Wayland event loop with NSRunLoop
        [NSApp run];

        // Cleanup
        [compositor stop];
        g_compositor = nil;
        wl_display_destroy(display);
        g_display = NULL;
        
        NSLog(@"👋 Compositor shutdown complete");
    }
    return 0;
}

