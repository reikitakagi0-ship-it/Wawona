// Simple Wayland Test Client
// Draws a colored rectangle using SHM buffers

#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include "test_xdg-shell-client-protocol.h"
#include "src/logging.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

struct wl_display *display = NULL;
struct wl_compositor *compositor = NULL;
struct wl_surface *surface = NULL;
struct wl_shm *shm = NULL;
struct wl_buffer *buffer = NULL;
struct xdg_wm_base *wm_base = NULL;
struct xdg_surface *xdg_surface = NULL;
struct xdg_toplevel *toplevel = NULL;

int width = 400;
int height = 300;
int stride;
void *data = NULL;
int shm_fd = -1;

static void shm_format(void *data, struct wl_shm *shm, uint32_t format) {
    (void)data;
    (void)shm;
    (void)format;
    // Format supported
}

static const struct wl_shm_listener shm_listener = {
    shm_format,
};

static void registry_handle_global(void *data, struct wl_registry *registry,
                                   uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    log_printf("[CLIENT] ", "registry_handle_global() - name=%u, interface=%s, version=%u\n", 
               name, interface, version);
    if (strcmp(interface, "wl_compositor") == 0) {
        log_printf("[CLIENT] ", "Binding to wl_compositor\n");
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
        log_printf("[CLIENT] ", "wl_compositor bound: %p\n", (void *)compositor);
    } else if (strcmp(interface, "wl_shm") == 0) {
        log_printf("[CLIENT] ", "Binding to wl_shm\n");
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
        wl_shm_add_listener(shm, &shm_listener, NULL);
        log_printf("[CLIENT] ", "wl_shm bound: %p\n", (void *)shm);
    } else if (strcmp(interface, "xdg_wm_base") == 0) {
        log_printf("[CLIENT] ", "Binding to xdg_wm_base\n");
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 4);
        log_printf("[CLIENT] ", "xdg_wm_base bound: %p\n", (void *)wm_base);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry,
                                          uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
    // Global removed
}

static const struct wl_registry_listener registry_listener = {
    registry_handle_global,
    registry_handle_global_remove,
};

static void wm_base_ping(void *data, struct xdg_wm_base *wm, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(wm, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
    wm_base_ping,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
                                  uint32_t serial) {
    (void)data;
    log_printf("[CLIENT] ", "xdg_surface_configure() - serial=%u\n", serial);
    xdg_surface_ack_configure(xdg_surface, serial);
    log_printf("[CLIENT] ", "xdg_surface_configure() - ack sent\n");
}

static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_configure,
};

static void xdg_toplevel_configure(void *data, struct xdg_toplevel *toplevel,
                                   int32_t w, int32_t h, struct wl_array *states) {
    (void)data;
    (void)toplevel;
    (void)states;
    if (w > 0 && h > 0) {
        width = w;
        height = h;
    }
}

static void xdg_toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)data;
    (void)toplevel;
    // Close requested
}

static void xdg_toplevel_configure_bounds(void *data, struct xdg_toplevel *toplevel,
                                          int32_t width, int32_t height) {
    (void)data;
    (void)toplevel;
    (void)width;
    (void)height;
    // Configure bounds received
}

static void xdg_toplevel_wm_capabilities(void *data, struct xdg_toplevel *toplevel,
                                         struct wl_array *capabilities) {
    (void)data;
    (void)toplevel;
    (void)capabilities;
    // WM capabilities received
}

static const struct xdg_toplevel_listener toplevel_listener = {
    xdg_toplevel_configure,
    xdg_toplevel_close,
    xdg_toplevel_configure_bounds,
    xdg_toplevel_wm_capabilities,
};

static int create_shm_buffer(void) {
    int ret;
    size_t size = stride * height;
    
    // Create shared memory file
    char name[] = "/tmp/wayland-shm-XXXXXX";
    shm_fd = mkstemp(name);
    if (shm_fd < 0) {
        fprintf(stderr, "Failed to create shm file: %s\n", strerror(errno));
        return -1;
    }
    
    unlink(name);
    
    ret = ftruncate(shm_fd, size);
    if (ret < 0) {
        close(shm_fd);
        fprintf(stderr, "Failed to truncate shm file: %s\n", strerror(errno));
        return -1;
    }
    
    data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    if (data == MAP_FAILED) {
        close(shm_fd);
        fprintf(stderr, "Failed to mmap shm file: %s\n", strerror(errno));
        return -1;
    }
    
    // Fill with a pattern (red gradient)
    uint32_t *pixels = (uint32_t *)data;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            uint8_t r = (x * 255) / width;
            uint8_t g = (y * 255) / height;
            uint8_t b = 128;
            pixels[y * (stride / 4) + x] = (0xFF << 24) | (r << 16) | (g << 8) | b;
        }
    }
    
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, shm_fd, size);
    buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    
    return 0;
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    init_client_logging();
    
    // Set up XDG_RUNTIME_DIR if not set (required for Wayland)
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    if (!runtime_dir) {
        const char *tmpdir = getenv("TMPDIR");
        if (!tmpdir) tmpdir = "/tmp";
        
        char runtime_path[512];
        snprintf(runtime_path, sizeof(runtime_path), "%s/wayland-runtime", tmpdir);
        
        // Try to create directory (ignore errors - might already exist)
        mkdir(runtime_path, 0700);
        
        setenv("XDG_RUNTIME_DIR", runtime_path, 0);
        printf("Set XDG_RUNTIME_DIR to: %s\n", runtime_path);
    }
    
    log_printf("[CLIENT] ", "Connecting to Wayland display...\n");
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "[CLIENT] Failed to connect to Wayland display\n");
        fprintf(stderr, "[CLIENT] Make sure the compositor is running and WAYLAND_DISPLAY is set\n");
        return 1;
    }
    
    log_printf("[CLIENT] ", "Connected to Wayland display: %p\n", (void *)display);
    
    log_printf("[CLIENT] ", "Getting registry...\n");
    struct wl_registry *registry = wl_display_get_registry(display);
    log_printf("[CLIENT] ", "Registry: %p\n", (void *)registry);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_flush(display);
    
    log_printf("[CLIENT] ", "Waiting for registry globals (roundtrip)\n");
    if (wl_display_roundtrip(display) < 0) {
        int err = wl_display_get_error(display);
        const struct wl_interface *iface = NULL;
        uint32_t id = 0;
        uint32_t protocol_error = wl_display_get_protocol_error(display, &iface, &id);
        fprintf(stderr, "[CLIENT] roundtrip failed (display error=%d)\n", err);
        if (protocol_error != 0) {
            fprintf(stderr, "[CLIENT] Protocol error: interface=%s, id=%u, code=%u\n",
                    iface ? iface->name : "unknown", id, protocol_error);
        }
        return 1;
    }
    
    if (!compositor || !shm || !wm_base) {
        log_printf("[CLIENT] ", "Globals incomplete after roundtrip, dispatching once more\n");
        if (wl_display_dispatch(display) < 0) {
            int err = wl_display_get_error(display);
            fprintf(stderr, "[CLIENT] dispatch failed (display error=%d)\n", err);
            return 1;
        }
    }
    
    if (!compositor || !shm || !wm_base) {
        fprintf(stderr, "[CLIENT] Missing required globals - compositor=%p, shm=%p, wm_base=%p\n",
                (void *)compositor, (void *)shm, (void *)wm_base);
        return 1;
    }
    
    if (wm_base) {
        xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
    }
    log_printf("[CLIENT] ", "Got required globals\n");
    
    log_printf("[CLIENT] ", "Creating surface...\n");
    surface = wl_compositor_create_surface(compositor);
    if (!surface) {
        fprintf(stderr, "[CLIENT] Failed to create surface\n");
        cleanup_logging();
        return 1;
    }
    log_printf("[CLIENT] ", "Surface created: %p\n", (void *)surface);
    
    log_printf("[CLIENT] ", "Getting xdg_surface...\n");
    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    log_printf("[CLIENT] ", "xdg_surface: %p\n", (void *)xdg_surface);
    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    
    log_printf("[CLIENT] ", "Getting xdg_toplevel...\n");
    toplevel = xdg_surface_get_toplevel(xdg_surface);
    log_printf("[CLIENT] ", "xdg_toplevel: %p\n", (void *)toplevel);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_title(toplevel, "Wayland Test Client");
    
    log_printf("[CLIENT] ", "Committing surface...\n");
    wl_surface_commit(surface);
    wl_display_flush(display);
    log_printf("[CLIENT] ", "Dispatching events after commit...\n");
    wl_display_dispatch(display);
    log_printf("[CLIENT] ", "Events dispatched\n");
    
    stride = width * 4; // ARGB8888 = 4 bytes per pixel
    
    if (create_shm_buffer() < 0) {
        return 1;
    }
    
    printf("Created SHM buffer: %dx%d, stride=%d\n", width, height, stride);
    
    log_printf("[CLIENT] ", "Attaching buffer to surface...\n");
    wl_surface_attach(surface, buffer, 0, 0);
    log_printf("[CLIENT] ", "Committing surface with buffer...\n");
    wl_surface_commit(surface);
    wl_display_flush(display);
    log_printf("[CLIENT] ", "Dispatching events after buffer attach...\n");
    wl_display_dispatch(display);
    log_printf("[CLIENT] ", "Events dispatched\n");
    
    log_printf("[CLIENT] ", "Surface attached and committed\n");
    log_printf("[CLIENT] ", "Window should be visible now. Running event loop (Ctrl+C to exit)...\n");
    
    // Run event loop instead of blocking on getchar()
    while (wl_display_dispatch(display) != -1) {
        // Continue processing events
    }
    
    log_printf("[CLIENT] ", "Event loop exited\n");
    
    // Cleanup
    if (data != MAP_FAILED) {
        munmap(data, stride * height);
    }
    if (shm_fd >= 0) {
        close(shm_fd);
    }
    
    if (buffer) wl_buffer_destroy(buffer);
    if (toplevel) xdg_toplevel_destroy(toplevel);
    if (xdg_surface) xdg_surface_destroy(xdg_surface);
    if (surface) wl_surface_destroy(surface);
    if (shm) wl_shm_destroy(shm);
    if (compositor) wl_compositor_destroy(compositor);
    if (wm_base) xdg_wm_base_destroy(wm_base);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    
    cleanup_logging();
    return 0;
}

