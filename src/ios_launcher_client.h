// iOS Launcher Client - Header
// Forward declarations to avoid including wayland-client.h in main.m

#import <Foundation/Foundation.h>
#include <pthread.h>

@class WawonaAppDelegate;

// Forward declare wayland-client types (avoid including wayland-client.h in main.m)
struct wl_display;

// Start the launcher client thread with a pre-connected socket file descriptor
pthread_t startLauncherClientThread(WawonaAppDelegate *delegate, int client_fd);

// Get the client display (returns wayland-client wl_display*, not wayland-server)
struct wl_display *getLauncherClientDisplay(WawonaAppDelegate *delegate);

// Disconnect and cleanup the launcher client
void disconnectLauncherClient(WawonaAppDelegate *delegate);

