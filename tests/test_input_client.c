// Interactive Wayland Test Client
// Displays keyboard input and mouse events on screen

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
#include <ctype.h>

struct wl_display *display = NULL;
struct wl_compositor *compositor = NULL;
struct wl_surface *surface = NULL;
struct wl_shm *shm = NULL;
struct wl_buffer *buffer = NULL;
struct xdg_wm_base *wm_base = NULL;
struct xdg_surface *xdg_surface = NULL;
struct xdg_toplevel *toplevel = NULL;
struct wl_seat *seat = NULL;
struct wl_pointer *pointer = NULL;
struct wl_keyboard *keyboard = NULL;
struct wl_callback *frame_callback = NULL;

int width = 0;
int height = 0;
int stride;
void *data = NULL;
int shm_fd = -1;
int configured_width = 0;
int configured_height = 0;
int needs_resize = 0;

// Input state
double pointer_x = 0, pointer_y = 0;
int pointer_buttons = 0;
char input_buffer[256] = {0};
int input_pos = 0;
int needs_redraw = 1;
int pending_frame = 0;

// Simple font rendering (8x8 pixel font)
static void draw_char(uint32_t *pixels, int x, int y, char c, uint32_t color) {
    // Very simple 8x8 font - just draw a box for now
    // In a real implementation, you'd use a bitmap font
    for (int py = 0; py < 8; py++) {
        for (int px = 0; px < 8; px++) {
            int px_pos = x + px;
            int py_pos = y + py;
            if (px_pos >= 0 && px_pos < width && py_pos >= 0 && py_pos < height) {
                pixels[py_pos * (stride / 4) + px_pos] = color;
            }
        }
    }
}

static void draw_text(uint32_t *pixels, int x, int y, const char *text, uint32_t color) {
    int pos = 0;
    while (text[pos] && x + pos * 8 < width) {
        draw_char(pixels, x + pos * 8, y, text[pos], color);
        pos++;
    }
}

static void redraw_buffer(void) {
    if (!data) return;
    
    uint32_t *pixels = (uint32_t *)data;
    
    // Clear to dark gray
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            pixels[y * (stride / 4) + x] = 0xFF202020; // Dark gray
        }
    }
    
    // Draw title
    draw_text(pixels, 10, 10, "Wayland Input Test Client", 0xFFFFFFFF);
    
    // Draw pointer position
    char pos_text[64];
    snprintf(pos_text, sizeof(pos_text), "Pointer: %.0f, %.0f", pointer_x, pointer_y);
    draw_text(pixels, 10, 30, pos_text, 0xFFFFFF00);
    
    // Draw button state
    char button_text[64];
    snprintf(button_text, sizeof(button_text), "Buttons: %d", pointer_buttons);
    draw_text(pixels, 10, 50, button_text, 0xFFFFFF00);
    
    // Draw input buffer
    char input_label[64];
    snprintf(input_label, sizeof(input_label), "Input: %s", input_buffer);
    draw_text(pixels, 10, 70, input_label, 0xFF00FF00);
    
    // Draw cursor
    int cursor_x = (int)pointer_x;
    int cursor_y = (int)pointer_y;
    if (cursor_x >= 0 && cursor_x < width && cursor_y >= 0 && cursor_y < height) {
        // Draw a small crosshair
        for (int i = -5; i <= 5; i++) {
            if (cursor_x + i >= 0 && cursor_x + i < width) {
                pixels[cursor_y * (stride / 4) + cursor_x + i] = 0xFFFF0000; // Red horizontal
            }
            if (cursor_y + i >= 0 && cursor_y + i < height) {
                pixels[(cursor_y + i) * (stride / 4) + cursor_x] = 0xFFFF0000; // Red vertical
            }
        }
    }
    
    needs_redraw = 0;
}

// Forward declaration
static void frame_callback_done(void *data, struct wl_callback *callback, uint32_t time);
static void redraw_buffer(void);
static int create_shm_buffer(void);
static void destroy_shm_buffer(void);

static const struct wl_callback_listener frame_listener = {
    frame_callback_done,
};

// Frame callback - called when compositor is ready for next frame
// Always redraw and request next frame callback for smooth rendering
static void frame_callback_done(void *data, struct wl_callback *callback, uint32_t time) {
    (void)data;
    (void)time;
    wl_callback_destroy(callback);
    frame_callback = NULL;
    pending_frame = 0;
    
    // Always redraw (even if no changes, to ensure smooth frame rate)
    // This ensures we're rendering at display refresh rate
    if (needs_redraw || buffer != NULL) {
        redraw_buffer();
        wl_surface_attach(surface, buffer, 0, 0);
        
        // Always request next frame callback for continuous rendering
        frame_callback = wl_surface_frame(surface);
        wl_callback_add_listener(frame_callback, &frame_listener, NULL);
        wl_surface_commit(surface);
        wl_display_flush(display);
        needs_redraw = 0;
        pending_frame = 1;
    }
}

static void shm_format(void *data, struct wl_shm *shm, uint32_t format) {
    (void)data;
    (void)shm;
    (void)format;
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
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, "wl_shm") == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
        wl_shm_add_listener(shm, &shm_listener, NULL);
    } else if (strcmp(interface, "xdg_wm_base") == 0) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 4);
    } else if (strcmp(interface, "wl_seat") == 0) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 7);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    registry_handle_global,
    registry_handle_global_remove,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    (void)data;
    log_printf("[CLIENT] ", "xdg_surface_configure() - serial=%u\n", serial);
    xdg_surface_ack_configure(xdg_surface, serial);
    // Note: Actual size comes from xdg_toplevel_configure
}

static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_configure,
};

static void xdg_toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t new_width, int32_t new_height, struct wl_array *states) {
    (void)data;
    (void)toplevel;
    (void)states;
    
    if (new_width > 0 && new_height > 0) {
        // If size changed, mark for resize
        if (new_width != width || new_height != height) {
            configured_width = new_width;
            configured_height = new_height;
            needs_resize = 1;
            log_printf("[CLIENT] ", "xdg_toplevel_configure() - %dx%d (will resize from %dx%d)\n", 
                      new_width, new_height, width, height);
            
            // Immediately handle resize if buffer exists (not initial configure)
            if (buffer != NULL && width > 0 && height > 0) {
                log_printf("[CLIENT] ", "Immediately resizing buffer...\n");
                
                // Update size
                width = configured_width;
                height = configured_height;
                needs_resize = 0;
                
                // Recreate buffer with new size
                if (create_shm_buffer() >= 0) {
                    // Redraw and attach new buffer immediately
                    redraw_buffer();
                    wl_surface_attach(surface, buffer, 0, 0);
                    
                    // Request new frame callback
                    if (frame_callback) {
                        wl_callback_destroy(frame_callback);
                        frame_callback = NULL;
                    }
                    frame_callback = wl_surface_frame(surface);
                    wl_callback_add_listener(frame_callback, &frame_listener, NULL);
                    wl_surface_commit(surface);
                    wl_display_flush(display);
                    pending_frame = 1;
                } else {
                    fprintf(stderr, "[CLIENT] Failed to recreate buffer after resize\n");
                }
            }
        } else {
            log_printf("[CLIENT] ", "xdg_toplevel_configure() - %dx%d (no size change)\n", new_width, new_height);
        }
    } else {
        log_printf("[CLIENT] ", "xdg_toplevel_configure() - %dx%d (no size)\n", new_width, new_height);
    }
}

static void xdg_toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)data;
    (void)toplevel;
    log_printf("[CLIENT] ", "xdg_toplevel_close()\n");
}

static void xdg_toplevel_configure_bounds(void *data, struct xdg_toplevel *toplevel,
                                          int32_t width, int32_t height) {
    (void)data;
    (void)toplevel;
    (void)width;
    (void)height;
}

static void xdg_toplevel_wm_capabilities(void *data, struct xdg_toplevel *toplevel,
                                         struct wl_array *capabilities) {
    (void)data;
    (void)toplevel;
    (void)capabilities;
}

static const struct xdg_toplevel_listener toplevel_listener = {
    xdg_toplevel_configure,
    xdg_toplevel_close,
    xdg_toplevel_configure_bounds,
    xdg_toplevel_wm_capabilities,
};

// Pointer event handlers
static void pointer_enter(void *data, struct wl_pointer *pointer, uint32_t serial, struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y) {
    (void)data;
    (void)pointer;
    (void)serial;
    (void)surface;
    pointer_x = wl_fixed_to_double(x);
    pointer_y = wl_fixed_to_double(y);
    needs_redraw = 1;
    log_printf("[CLIENT] ", "pointer_enter() - x=%.2f, y=%.2f\n", pointer_x, pointer_y);
}

static void pointer_leave(void *data, struct wl_pointer *pointer, uint32_t serial, struct wl_surface *surface) {
    (void)data;
    (void)pointer;
    (void)serial;
    (void)surface;
    log_printf("[CLIENT] ", "pointer_leave()\n");
}

static void pointer_motion(void *data, struct wl_pointer *pointer, uint32_t time, wl_fixed_t x, wl_fixed_t y) {
    (void)data;
    (void)pointer;
    (void)time;
    pointer_x = wl_fixed_to_double(x);
    pointer_y = wl_fixed_to_double(y);
    needs_redraw = 1;
    // Frame callback is already pending from previous frame, so we don't need to request another
    // The frame callback will handle the redraw
}

static void pointer_button(void *data, struct wl_pointer *pointer, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    (void)data;
    (void)pointer;
    (void)serial;
    (void)time;
    if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
        pointer_buttons |= (1 << (button - 272));
        log_printf("[CLIENT] ", "pointer_button() - button %u PRESSED\n", button);
    } else {
        pointer_buttons &= ~(1 << (button - 272));
        log_printf("[CLIENT] ", "pointer_button() - button %u RELEASED\n", button);
    }
    needs_redraw = 1;
    // Frame callback is already pending from previous frame, so we don't need to request another
    // The frame callback will handle the redraw
}

static void pointer_axis(void *data, struct wl_pointer *pointer, uint32_t time, uint32_t axis, wl_fixed_t value) {
    (void)data;
    (void)pointer;
    (void)time;
    (void)axis;
    (void)value;
}

static const struct wl_pointer_listener pointer_listener = {
    pointer_enter,
    pointer_leave,
    pointer_motion,
    pointer_button,
    pointer_axis,
};

// Keyboard event handlers
static void keyboard_keymap(void *data, struct wl_keyboard *keyboard, uint32_t format, int32_t fd, uint32_t size) {
    (void)data;
    (void)keyboard;
    (void)format;
    (void)fd;
    (void)size;
    log_printf("[CLIENT] ", "keyboard_keymap() - format=%u, size=%u\n", format, size);
    close(fd);
}

static void keyboard_enter(void *data, struct wl_keyboard *keyboard, uint32_t serial, struct wl_surface *surface, struct wl_array *keys) {
    (void)data;
    (void)keyboard;
    (void)serial;
    (void)surface;
    (void)keys;
    log_printf("[CLIENT] ", "keyboard_enter()\n");
}

static void keyboard_leave(void *data, struct wl_keyboard *keyboard, uint32_t serial, struct wl_surface *surface) {
    (void)data;
    (void)keyboard;
    (void)serial;
    (void)surface;
    log_printf("[CLIENT] ", "keyboard_leave()\n");
}

static void keyboard_key(void *data, struct wl_keyboard *keyboard, uint32_t serial, uint32_t time, uint32_t key, uint32_t state) {
    (void)data;
    (void)keyboard;
    (void)serial;
    (void)time;
    
    if (state == WL_KEYBOARD_KEY_STATE_PRESSED) {
        log_printf("[CLIENT] ", "keyboard_key() - key %u PRESSED\n", key);
        
        // Simple key mapping (Linux keycodes to ASCII)
        // This is a very basic mapping - real implementation would use XKB
        char c = 0;
        if (key >= 2 && key <= 11) {
            // Numbers 1-0
            c = '0' + ((key - 1) % 10);
        } else if (key >= 16 && key <= 25) {
            // Q-P
            c = 'q' + (key - 16);
        } else if (key >= 30 && key <= 38) {
            // A-L
            c = 'a' + (key - 30);
        } else if (key >= 39 && key <= 46) {
            // Z-M
            c = 'z' + (key - 39);
        } else if (key == 13 || key == 28) {
            // Enter
            c = '\n';
        } else if (key == 15) {
            // Backspace
            if (input_pos > 0) {
                input_pos--;
                input_buffer[input_pos] = 0;
            }
            needs_redraw = 1;
            // Frame callback is already pending from previous frame, so we don't need to request another
            // The frame callback will handle the redraw
            return;
        } else if (key == 57) {
            // Space
            c = ' ';
        }
        
        if (c != 0 && input_pos < (int)(sizeof(input_buffer) - 1)) {
            input_buffer[input_pos++] = c;
            input_buffer[input_pos] = 0;
            needs_redraw = 1;
            // Frame callback is already pending from previous frame, so we don't need to request another
            // The frame callback will handle the redraw
        }
    } else {
        log_printf("[CLIENT] ", "keyboard_key() - key %u RELEASED\n", key);
    }
}

static void keyboard_modifiers(void *data, struct wl_keyboard *keyboard, uint32_t serial, uint32_t mods_depressed, uint32_t mods_latched, uint32_t mods_locked, uint32_t group) {
    (void)data;
    (void)keyboard;
    (void)serial;
    (void)mods_depressed;
    (void)mods_latched;
    (void)mods_locked;
    (void)group;
}

static const struct wl_keyboard_listener keyboard_listener = {
    keyboard_keymap,
    keyboard_enter,
    keyboard_leave,
    keyboard_key,
    keyboard_modifiers,
    NULL, // repeat_info (not used)
};

static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t capabilities) {
    (void)data;
    log_printf("[CLIENT] ", "seat_capabilities() - capabilities=0x%x\n", capabilities);
    
    if (capabilities & WL_SEAT_CAPABILITY_POINTER && !pointer) {
        log_printf("[CLIENT] ", "Getting pointer...\n");
        pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer, &pointer_listener, NULL);
    }
    
    if (capabilities & WL_SEAT_CAPABILITY_KEYBOARD && !keyboard) {
        log_printf("[CLIENT] ", "Getting keyboard...\n");
        keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL);
    }
}

static void seat_name(void *data, struct wl_seat *seat, const char *name) {
    (void)data;
    (void)seat;
    log_printf("[CLIENT] ", "seat_name() - %s\n", name);
}

static const struct wl_seat_listener seat_listener = {
    seat_capabilities,
    seat_name,
};

static void destroy_shm_buffer(void) {
    if (buffer) {
        wl_buffer_destroy(buffer);
        buffer = NULL;
    }
    if (data != NULL && data != MAP_FAILED && width > 0 && height > 0) {
        size_t size = (width * 4) * height;
        munmap(data, size);
        data = NULL;
    }
    if (shm_fd >= 0) {
        close(shm_fd);
        shm_fd = -1;
    }
}

static int create_shm_buffer(void) {
    // Clean up old buffer if it exists
    destroy_shm_buffer();
    
    if (width <= 0 || height <= 0) {
        fprintf(stderr, "Invalid buffer size: %dx%d\n", width, height);
        return -1;
    }
    
    stride = width * 4;
    size_t size = stride * height;
    
    char name[] = "/tmp/wayland-shm-XXXXXX";
    shm_fd = mkstemp(name);
    if (shm_fd < 0) {
        fprintf(stderr, "Failed to create shm file: %s\n", strerror(errno));
        return -1;
    }
    
    unlink(name);
    
    int ret = ftruncate(shm_fd, size);
    if (ret < 0) {
        close(shm_fd);
        shm_fd = -1;
        fprintf(stderr, "Failed to truncate shm file: %s\n", strerror(errno));
        return -1;
    }
    
    data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    if (data == MAP_FAILED) {
        close(shm_fd);
        shm_fd = -1;
        fprintf(stderr, "Failed to mmap shm file: %s\n", strerror(errno));
        return -1;
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
    
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    if (!runtime_dir) {
        const char *tmpdir = getenv("TMPDIR");
        if (!tmpdir) tmpdir = "/tmp";
        char runtime_path[512];
        snprintf(runtime_path, sizeof(runtime_path), "%s/wayland-runtime", tmpdir);
        mkdir(runtime_path, 0700);
        setenv("XDG_RUNTIME_DIR", runtime_path, 0);
    }
    
    log_printf("[CLIENT] ", "Connecting to Wayland display...\n");
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "[CLIENT] Failed to connect to Wayland display\n");
        return 1;
    }
    
    log_printf("[CLIENT] ", "Connected to Wayland display: %p\n", (void *)display);
    
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_flush(display);
    
    log_printf("[CLIENT] ", "Waiting for registry globals (roundtrip)\n");
    if (wl_display_roundtrip(display) < 0) {
        fprintf(stderr, "[CLIENT] Failed to get registry globals\n");
        return 1;
    }
    
    if (!compositor || !shm || !wm_base || !seat) {
        fprintf(stderr, "[CLIENT] Missing required globals\n");
        return 1;
    }
    
    log_printf("[CLIENT] ", "Got required globals\n");
    
    // Set up seat listener
    wl_seat_add_listener(seat, &seat_listener, NULL);
    
    surface = wl_compositor_create_surface(compositor);
    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    
    toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_title(toplevel, "Wayland Input Test");
    
    // Request fullscreen
    xdg_toplevel_set_fullscreen(toplevel, NULL);
    
    wl_surface_commit(surface);
    wl_display_flush(display);
    
    // Wait for initial configure event to get window size
    log_printf("[CLIENT] ", "Waiting for configure event...\n");
    while (configured_width == 0 || configured_height == 0) {
        if (wl_display_dispatch(display) < 0) {
            fprintf(stderr, "[CLIENT] Failed to dispatch events\n");
            return 1;
        }
    }
    
    // Set initial size from configure event
    width = configured_width;
    height = configured_height;
    
    if (create_shm_buffer() < 0) {
        return 1;
    }
    
    printf("Created SHM buffer: %dx%d, stride=%d\n", width, height, stride);
    
    // Initial draw
    redraw_buffer();
    wl_surface_attach(surface, buffer, 0, 0);
    frame_callback = wl_surface_frame(surface);
    wl_callback_add_listener(frame_callback, &frame_listener, NULL);
    wl_surface_commit(surface);
    wl_display_flush(display);
    wl_display_dispatch(display);
    
    log_printf("[CLIENT] ", "Window should be visible. Type and move mouse to test input!\n");
    log_printf("[CLIENT] ", "Press Ctrl+C to exit\n");
    
    // Event loop - use non-blocking dispatch for responsive event handling
    // Frame callbacks handle redraws at display refresh rate
    while (1) {
        // Prepare to read events (non-blocking)
        while (wl_display_prepare_read(display) != 0) {
            // If prepare_read returns non-zero, there are events already buffered
            // Dispatch them first
            int ret = wl_display_dispatch_pending(display);
            if (ret < 0) {
                fprintf(stderr, "[CLIENT] Display error, exiting\n");
                goto cleanup;
            }
        }
        
        // Flush any pending requests before reading
        wl_display_flush(display);
        
        // Read events (non-blocking - returns immediately if no data)
        wl_display_read_events(display);
        
        // Dispatch any events that were read
        int ret = wl_display_dispatch_pending(display);
        if (ret < 0) {
            fprintf(stderr, "[CLIENT] Display error, exiting\n");
            break;
        }
        
        // Handle resize if needed (fallback - should be handled in configure callback)
        // This is a safety net in case resize wasn't handled immediately
        if (needs_resize && configured_width > 0 && configured_height > 0) {
            log_printf("[CLIENT] ", "Resizing buffer from %dx%d to %dx%d (fallback handler)\n", 
                       width, height, configured_width, configured_height);
            
            // Update size
            width = configured_width;
            height = configured_height;
            needs_resize = 0;
            
            // Recreate buffer with new size
            if (create_shm_buffer() < 0) {
                fprintf(stderr, "[CLIENT] Failed to recreate buffer after resize\n");
                break;
            }
            
            // Redraw and attach new buffer
            redraw_buffer();
            wl_surface_attach(surface, buffer, 0, 0);
            
            // Request new frame callback
            if (frame_callback) {
                wl_callback_destroy(frame_callback);
                frame_callback = NULL;
            }
            frame_callback = wl_surface_frame(surface);
            wl_callback_add_listener(frame_callback, &frame_listener, NULL);
            wl_surface_commit(surface);
            wl_display_flush(display);
            pending_frame = 1;
        }
        
        // Small sleep to prevent CPU spinning when no events
        // Frame callbacks will wake us up when rendering is needed
        usleep(1000); // 1ms sleep
    }
    
cleanup:
    
    // Cleanup
    if (frame_callback) {
        wl_callback_destroy(frame_callback);
    }
    destroy_shm_buffer();
    
    if (pointer) wl_pointer_destroy(pointer);
    if (keyboard) wl_keyboard_destroy(keyboard);
    if (seat) wl_seat_destroy(seat);
    // buffer is destroyed in destroy_shm_buffer()
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

