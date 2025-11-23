#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>

// Forward declaration
struct wl_seat_impl;

// Wayland Compositor Protocol Implementation
// Implements wl_compositor, wl_surface, wl_output, wl_seat

struct wl_compositor_impl;
struct wl_surface_impl;
struct wl_output_impl;

// Render callback type - called when a surface is committed
typedef void (*wl_surface_render_callback_t)(struct wl_surface_impl *surface);

// Title update callback type - called when focus changes to update window title
typedef void (*wl_title_update_callback_t)(struct wl_client *client);

// Frame callback requested callback type - called when a client requests a frame callback
typedef void (*wl_frame_callback_requested_t)(void);

// Compositor global
struct wl_compositor_impl {
    struct wl_global *global;
    struct wl_display *display;
    wl_surface_render_callback_t render_callback; // Callback for immediate rendering
    wl_title_update_callback_t update_title_callback; // Callback for updating window title
    wl_frame_callback_requested_t frame_callback_requested; // Callback when frame callback is requested
};

// Surface implementation
struct wl_surface_impl {
    struct wl_resource *resource;
    struct wl_surface_impl *next;
    
    // Buffer management
    struct wl_resource *buffer_resource;
    int32_t width, height;
    int32_t buffer_width, buffer_height;
    bool buffer_release_sent;
    
    // Position and state
    int32_t x, y;
    bool committed;
    
    // Callbacks
    struct wl_resource *frame_callback;
    
    // Viewport (for viewporter protocol)
    void *viewport;  // struct wl_viewport_impl *
    
    // User data (for linking to CALayer)
    void *user_data;
    
    // Color management
    void *color_management; // struct wp_color_management_surface_impl *
};

// Output implementation - defined in wayland_output.h

// Seat implementation - defined in wayland_seat.h

// Function declarations
struct wl_compositor_impl *wl_compositor_create(struct wl_display *display);
void wl_compositor_destroy(struct wl_compositor_impl *compositor);
void wl_compositor_set_render_callback(struct wl_compositor_impl *compositor, wl_surface_render_callback_t callback);
void wl_compositor_set_title_update_callback(struct wl_compositor_impl *compositor, wl_title_update_callback_t callback);
void wl_compositor_set_frame_callback_requested(struct wl_compositor_impl *compositor, wl_frame_callback_requested_t callback);
void wl_compositor_set_seat(struct wl_seat_impl *seat);

// Thread-safe surface iteration
typedef void (*wl_surface_iterator_func_t)(struct wl_surface_impl *surface, void *data);
void wl_compositor_for_each_surface(wl_surface_iterator_func_t iterator, void *data);

// Lock/Unlock surfaces mutex (for external safe access)
void wl_compositor_lock_surfaces(void);
void wl_compositor_unlock_surfaces(void);

// Forward declarations - implementations in separate files
struct wl_output_impl *wl_output_create(struct wl_display *display, int32_t width, int32_t height, const char *name);
void wl_output_destroy(struct wl_output_impl *output);

struct wl_seat_impl *wl_seat_create(struct wl_display *display);
void wl_seat_destroy(struct wl_seat_impl *seat);

// Surface management
struct wl_surface_impl *wl_surface_from_resource(struct wl_resource *resource);
void wl_surface_damage(struct wl_surface_impl *surface, int32_t x, int32_t y, int32_t width, int32_t height);
void wl_surface_commit(struct wl_surface_impl *surface);

// Buffer handling
void wl_surface_attach_buffer(struct wl_surface_impl *surface, struct wl_resource *buffer);
void *wl_buffer_get_shm_data(struct wl_resource *buffer, int32_t *width, int32_t *height, int32_t *stride);
void wl_buffer_end_shm_access(struct wl_resource *buffer);

// Surface iteration
struct wl_surface_impl *wl_get_all_surfaces(void);

// Send frame callbacks to all surfaces with pending callbacks
// Called at display refresh rate to synchronize with display
// Returns the number of callbacks sent
int wl_send_frame_callbacks(void);
bool wl_has_pending_frame_callbacks(void);

// Clear buffer reference from surfaces (called when buffer is destroyed)
void wl_compositor_clear_buffer_reference(struct wl_resource *buffer_resource);

// Destroy all tracked clients (for shutdown) - explicitly disconnects all clients including waypipe
void wl_compositor_destroy_all_clients(void);

