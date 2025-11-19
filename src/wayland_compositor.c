#include "wayland_compositor.h"
#include "wayland_seat.h"
#include "xdg_shell.h"
#include "wayland_protocol_stubs.h"
#include "logging.h"
#include <wayland-server-protocol.h>
#include <wayland-server.h>
#include <wayland-util.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <pthread.h>

// Forward declarations
static void compositor_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
static void compositor_create_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id);
static void compositor_create_region(struct wl_client *client, struct wl_resource *resource, uint32_t id);

static const struct wl_compositor_interface compositor_interface = {
    .create_surface = compositor_create_surface,
    .create_region = compositor_create_region,
};

static void surface_destroy(struct wl_client *client, struct wl_resource *resource);
static void surface_attach(struct wl_client *client, struct wl_resource *resource, struct wl_resource *buffer, int32_t x, int32_t y);
static void surface_damage(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height);
static void surface_frame(struct wl_client *client, struct wl_resource *resource, uint32_t callback);
static void surface_set_opaque_region(struct wl_client *client, struct wl_resource *resource, struct wl_resource *region);
static void surface_set_input_region(struct wl_client *client, struct wl_resource *resource, struct wl_resource *region);
static void surface_commit(struct wl_client *client, struct wl_resource *resource);
static void surface_set_buffer_transform(struct wl_client *client, struct wl_resource *resource, int32_t transform);
static void surface_set_buffer_scale(struct wl_client *client, struct wl_resource *resource, int32_t scale);
static void surface_damage_buffer(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height);
static void surface_offset(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y);

static const struct wl_surface_interface surface_interface = {
    .destroy = surface_destroy,
    .attach = surface_attach,
    .damage = surface_damage,
    .frame = surface_frame,
    .set_opaque_region = surface_set_opaque_region,
    .set_input_region = surface_set_input_region,
    .commit = surface_commit,
    .set_buffer_transform = surface_set_buffer_transform,
    .set_buffer_scale = surface_set_buffer_scale,
    .damage_buffer = surface_damage_buffer,
    .offset = surface_offset,
};

static void region_destroy(struct wl_client *client, struct wl_resource *resource);
static void region_add(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height);
static void region_subtract(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height);

static const struct wl_region_interface region_interface = {
    .destroy = region_destroy,
    .add = region_add,
    .subtract = region_subtract,
};

// Global surface list
static struct wl_surface_impl *surfaces = NULL;
static pthread_mutex_t surfaces_mutex = PTHREAD_MUTEX_INITIALIZER;

// Thread-safe surface iteration
void wl_compositor_for_each_surface(wl_surface_iterator_func_t iterator, void *data) {
    pthread_mutex_lock(&surfaces_mutex);
    struct wl_surface_impl *surface = surfaces;
    while (surface) {
        // Store next pointer in case current surface is removed (though iterator shouldn't remove)
        struct wl_surface_impl *next = surface->next;
        iterator(surface, data);
        surface = next;
    }
    pthread_mutex_unlock(&surfaces_mutex);
}

// Lock/Unlock surfaces mutex (for external safe access)
void wl_compositor_lock_surfaces(void) {
    pthread_mutex_lock(&surfaces_mutex);
}

void wl_compositor_unlock_surfaces(void) {
    pthread_mutex_unlock(&surfaces_mutex);
}

// Clear buffer reference from surfaces (called when buffer is destroyed)
void wl_compositor_clear_buffer_reference(struct wl_resource *buffer_resource) {
    pthread_mutex_lock(&surfaces_mutex);
    struct wl_surface_impl *surface = surfaces;
    while (surface) {
        if (surface->buffer_resource == buffer_resource) {
            // Buffer is attached to this surface - clear the reference
            // The surface will handle NULL buffer on next commit
            surface->buffer_resource = NULL;
            surface->buffer_release_sent = true;
        }
        surface = surface->next;
    }
    pthread_mutex_unlock(&surfaces_mutex);
}

// Global compositor reference for render callbacks
static struct wl_compositor_impl *global_compositor = NULL;
struct wl_seat_impl *global_seat = NULL; // Exported for use by protocol stubs

// Forward declaration - function to remove surface from renderer
void remove_surface_from_renderer(struct wl_surface_impl *surface);

// Forward declaration - function to check if window should be hidden
extern void macos_compositor_check_and_hide_window_if_needed(void);

// Client destroy listener - called when a client disconnects
static void client_destroy_listener(struct wl_listener *listener, void *data) {
    (void)listener; // Unused, but required by wl_listener interface
    struct wl_client *client = (struct wl_client *)data;

    // Get client PID if available (for debugging)
    pid_t client_pid = 0;
    uid_t client_uid = 0;
    gid_t client_gid = 0;
    wl_client_get_credentials(client, &client_pid, &client_uid, &client_gid);

    log_printf("[COMPOSITOR] ", "🔌 CLIENT DISCONNECTED! client=%p, pid=%d, uid=%d, gid=%d\n",
               (void *)client, (int)client_pid, (int)client_uid, (int)client_gid);

    pthread_mutex_lock(&surfaces_mutex);
    // Clear all surfaces belonging to this client
    struct wl_surface_impl *surface = surfaces;
    struct wl_surface_impl *prev = NULL;

    while (surface) {
        struct wl_surface_impl *next = surface->next;
        bool belongs_to_client = false;

        // Check if this surface belongs to the disconnected client
        // CRITICAL: wl_resource_get_client() may crash if resource is already destroyed
        // So we check if resource exists first, then carefully check the client
        if (surface->resource) {
            // Try to get the client - this might fail if resource is destroyed
            // Use a safer approach: check if resource is still valid by trying to get its client
            struct wl_client *resource_client = NULL;
            // wl_resource_get_client() is safe even if resource is destroyed, but let's be extra careful
            // Actually, wl_resource_get_client() should be safe - it just returns NULL if destroyed
            resource_client = wl_resource_get_client(surface->resource);
            if (resource_client == client) {
                belongs_to_client = true;
            }
        }

        if (belongs_to_client) {
            log_printf("[COMPOSITOR] ", "  Clearing surface %p belonging to disconnected client\n", (void *)surface);

            // CRITICAL: Clear frame callback IMMEDIATELY to prevent race condition
            // wl_send_frame_callbacks() might be running concurrently and try to send
            // a callback to a destroyed resource, causing a crash in wl_closure_invoke
            if (surface->frame_callback) {
                log_printf("[COMPOSITOR] ", "  Clearing frame callback for disconnected client's surface\n");
                // Don't try to destroy the resource - it's already being destroyed by Wayland
                // Just clear the pointer to prevent wl_send_frame_callbacks() from accessing it
                surface->frame_callback = NULL;
            }

            // Clear color management if it exists
            if (surface->color_management) {
                // Color management surface will be destroyed by Wayland automatically
                // Just clear the pointer to avoid use-after-free
                surface->color_management = NULL;
            }

            // Clear focus if this surface was focused
            if (global_seat && global_seat->focused_surface == surface) {
                log_printf("[COMPOSITOR] ", "  Clearing focus for disconnected client's surface\n");
                wl_seat_set_focused_surface(global_seat, NULL);
            }
            // Clear pointer focus if this surface was pointer-focused
            if (global_seat && global_seat->pointer_focused_surface == surface) {
                log_printf("[COMPOSITOR] ", "  Clearing pointer focus for disconnected client's surface\n");
                global_seat->pointer_focused_surface = NULL;
            }

            // Clear the surface from renderer (removes CALayer and clears buffer)
            // This ensures the visual buffer is cleared even if surface_destroy hasn't been called yet
            remove_surface_from_renderer(surface);

            // Mark the surface as being cleaned up by clearing the resource
            // This prevents surface_destroy from trying to free it again
            // Note: surface_destroy will still be called by Wayland, but it will check
            // if the surface is already removed from the list
            surface->resource = NULL;

            // Remove from list
            if (prev) {
                prev->next = next;
            } else {
                surfaces = next;
            }

            // Free the surface
            free(surface);
            surface = next;
        } else {
            prev = surface;
            surface = next;
        }
    }
    pthread_mutex_unlock(&surfaces_mutex);

    // Also clean up xdg_surfaces belonging to this client
    struct xdg_surface_impl *xdg_surface = xdg_surfaces;
    struct xdg_surface_impl *xdg_prev = NULL;

    while (xdg_surface) {
        struct xdg_surface_impl *xdg_next = xdg_surface->next;

        // Check if this xdg_surface belongs to the disconnected client
        if (xdg_surface->resource && wl_resource_get_client(xdg_surface->resource) == client) {
            log_printf("[COMPOSITOR] ", "  Clearing xdg_surface %p belonging to disconnected client\n", (void *)xdg_surface);

            // If this xdg_surface has a toplevel role, clean it up
            if (xdg_surface->role) {
                struct xdg_toplevel_impl *toplevel = (struct xdg_toplevel_impl *)xdg_surface->role;
                if (toplevel) {
                    if (toplevel->title) free(toplevel->title);
                    if (toplevel->app_id) free(toplevel->app_id);
                    free(toplevel);
                }
            }

            // Remove from xdg_surfaces list
            if (xdg_prev) {
                xdg_prev->next = xdg_next;
            } else {
                xdg_surfaces = xdg_next;
            }

            // Free the xdg_surface
            free(xdg_surface);
            xdg_surface = xdg_next;
        } else {
            xdg_prev = xdg_surface;
            xdg_surface = xdg_next;
        }
    }

    log_printf("[COMPOSITOR] ", "  Finished cleaning up surfaces for disconnected client\n");
    
    // Check if there are any remaining surfaces
    // If no surfaces remain, hide the window
    if (surfaces == NULL) {
        log_printf("[COMPOSITOR] ", "  No remaining surfaces - hiding window\n");
        macos_compositor_check_and_hide_window_if_needed();
    } else {
        // Count remaining surfaces for logging
        int remaining_count = 0;
        struct wl_surface_impl *s = surfaces;
        while (s) {
            remaining_count++;
            s = s->next;
        }
        log_printf("[COMPOSITOR] ", "  %d surface(s) remaining - keeping window visible\n", remaining_count);
    }
}

static struct wl_listener client_destroy_listener_data = {.notify = client_destroy_listener};

// Compositor implementation
struct wl_compositor_impl *wl_compositor_create(struct wl_display *display) {
    struct wl_compositor_impl *compositor = calloc(1, sizeof(*compositor));
    if (!compositor) return NULL;
    
    compositor->display = display;
    compositor->global = wl_global_create(display, &wl_compositor_interface, 4, compositor, compositor_bind);
    
    if (!compositor->global) {
        free(compositor);
        return NULL;
    }
    
    // Initialize callbacks
    compositor->render_callback = NULL;
    compositor->update_title_callback = NULL;
    compositor->frame_callback_requested = NULL;
    
    // Client destroy listener will be added in compositor_bind() when clients connect
    // Store global reference for render callbacks
    global_compositor = compositor;
    
    return compositor;
}

void wl_compositor_destroy(struct wl_compositor_impl *compositor) {
    if (!compositor) return;
    
    wl_global_destroy(compositor->global);
    if (global_compositor == compositor) {
        global_compositor = NULL;
    }
    free(compositor);
}

void wl_compositor_set_render_callback(struct wl_compositor_impl *compositor, wl_surface_render_callback_t callback) {
    if (!compositor) return;
    compositor->render_callback = callback;
}

void wl_compositor_set_title_update_callback(struct wl_compositor_impl *compositor, wl_title_update_callback_t callback) {
    if (!compositor) return;
    compositor->update_title_callback = callback;
}

void wl_compositor_set_frame_callback_requested(struct wl_compositor_impl *compositor, wl_frame_callback_requested_t callback) {
    if (!compositor) return;
    compositor->frame_callback_requested = callback;
}

void wl_compositor_set_seat(struct wl_seat_impl *seat) {
    global_seat = seat;
}

// Forward declaration for client detection callback
extern void macos_compositor_detect_full_compositor(struct wl_client *client);
extern void xdg_shell_mark_nested_compositor(struct wl_client *client);

static void compositor_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    log_printf("[COMPOSITOR] ", "🔌 NEW CLIENT CONNECTED! compositor_bind() - client=%p, version=%u, id=%u\n", 
               (void *)client, version, id);
    struct wl_compositor_impl *compositor = data;
    
    // Get client credentials for better error reporting
    pid_t client_pid = 0;
    uid_t client_uid = 0;
    gid_t client_gid = 0;
    wl_client_get_credentials(client, &client_pid, &client_uid, &client_gid);
    
    // Note: client_pid may be 0 when connection is forwarded through waypipe
    // This is normal and not an error condition. During connection setup, waypipe
    // may make multiple connection attempts, and some may fail with "failed to read
    // client connection (pid 0)" - this is expected behavior and libwayland-server
    // handles it gracefully. The actual connection will succeed on retry.
    if (client_pid > 0) {
        log_printf("[COMPOSITOR] ", "  Client PID: %d, UID: %d, GID: %d\n", 
                   (int)client_pid, (int)client_uid, (int)client_gid);
    } else {
        log_printf("[COMPOSITOR] ", "  Client PID unavailable (likely forwarded through waypipe - this is normal)\n");
    }
    
    // Detect if this client is a full compositor (like Weston)
    // Full compositors bind to wl_compositor as a client when running nested
    log_printf("[COMPOSITOR] ", "  Calling macos_compositor_detect_full_compositor()\n");
    macos_compositor_detect_full_compositor(client);
    
    // Mark this client as a nested compositor in xdg_shell
    // This will cause any toplevels it creates to be automatically set to fullscreen
    log_printf("[COMPOSITOR] ", "  Marking client as nested compositor for auto-fullscreen\n");
    xdg_shell_mark_nested_compositor(client);
    
    // Add client destroy listener to clean up surfaces when client disconnects
    // This will be called automatically when the client disconnects
    // Note: During connection setup, you may see "failed to read client connection (pid 0)"
    // errors from libwayland-server. These are NORMAL and EXPECTED when:
    // - waypipe clients are connecting (multiple connection attempts during setup)
    // - Clients disconnect before completing handshake (transient connection attempts)
    // - PID is unavailable (pid 0) which is normal for waypipe forwarded connections
    // libwayland-server handles these gracefully and continues accepting connections.
    // The actual connection will succeed on retry - this is not a bug.
    wl_client_add_destroy_listener(client, &client_destroy_listener_data);
    log_printf("[COMPOSITOR] ", "  Added client destroy listener for client %p\n", (void *)client);
    
    struct wl_resource *resource = wl_resource_create(client, &wl_compositor_interface, (int)version, id);
    
    if (!resource) {
        log_printf("[COMPOSITOR] ", "compositor_bind() - failed to create resource, posting no memory\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(resource, &compositor_interface, compositor, NULL);
    log_printf("[COMPOSITOR] ", "compositor_bind() - resource created successfully\n");
}

static void compositor_create_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    log_printf("[COMPOSITOR] ", "compositor_create_surface() - client=%p, id=%u\n", (void *)client, id);
    struct wl_surface_impl *surface = calloc(1, sizeof(*surface));
    if (!surface) {
        log_printf("[COMPOSITOR] ", "compositor_create_surface() - failed to allocate surface\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    surface->resource = wl_resource_create(client, &wl_surface_interface, wl_resource_get_version(resource), id);
    if (!surface->resource) {
        log_printf("[COMPOSITOR] ", "compositor_create_surface() - failed to create resource\n");
        free(surface);
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(surface->resource, &surface_interface, surface, NULL);
    surface->buffer_release_sent = true;
    
    // Add to global list
    pthread_mutex_lock(&surfaces_mutex);
    surface->next = surfaces;
    surfaces = surface;
    pthread_mutex_unlock(&surfaces_mutex);
    log_printf("[COMPOSITOR] ", "compositor_create_surface() - surface %p created successfully\n", (void *)surface);
}

static void compositor_create_region(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    (void)resource;
    struct wl_resource *region_resource = wl_resource_create(client, &wl_region_interface, wl_resource_get_version(resource), id);
    if (!region_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(region_resource, &region_interface, NULL, NULL);
}

// Surface implementation
static void surface_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    
    // Check if surface was already cleaned up by client destroy listener
    if (!surface || surface->resource == NULL) {
        // Already cleaned up, nothing to do
        return;
    }
    
    // Clear focus if this surface was focused
    if (global_seat && global_seat->focused_surface == surface) {
        log_printf("[COMPOSITOR] ", "surface_destroy() - clearing focus for destroyed surface\n");
        wl_seat_set_focused_surface(global_seat, NULL);
    }
    
    // Remove CALayer for this surface (cleanup memory leak)
    remove_surface_from_renderer(surface);
    
    // Mark as destroyed to prevent double-free
    surface->resource = NULL;
    
    // Remove from list
    pthread_mutex_lock(&surfaces_mutex);
    if (surfaces == surface) {
        surfaces = surface->next;
    } else {
        struct wl_surface_impl *s = surfaces;
        while (s && s->next != surface) s = s->next;
        if (s) s->next = surface->next;
    }
    pthread_mutex_unlock(&surfaces_mutex);
    
    free(surface);
}

static void surface_attach(struct wl_client *client, struct wl_resource *resource, struct wl_resource *buffer, int32_t x, int32_t y) {
    (void)client;
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    
    log_printf("[COMPOSITOR] ", "surface_attach() - surface=%p, buffer=%p, x=%d, y=%d\n",
               (void *)surface, (void *)buffer, x, y);
    
    // Release old buffer if attached and different from new buffer
    if (surface->buffer_resource && surface->buffer_resource != buffer) {
        if (!surface->buffer_release_sent) {
            // CRITICAL: Verify the buffer resource is still valid before sending release
            // If the client disconnected or buffer was destroyed, this could crash
            struct wl_client *buffer_client = wl_resource_get_client(surface->buffer_resource);
            if (buffer_client) {
                // Buffer resource is still valid - safe to send release
                struct buffer_data *buf_data = wl_resource_get_user_data(surface->buffer_resource);
                if (buf_data) {
                    wl_buffer_send_release(surface->buffer_resource);
                }
            } else {
                // Buffer resource was destroyed (client disconnected) - just mark as released
                log_printf("[COMPOSITOR] ", "surface_attach: Old buffer already destroyed (client disconnected)\n");
            }
        }
        surface->buffer_release_sent = true;
    }
    
    // Set new buffer (NULL is valid - means no buffer attached)
    // According to Wayland spec: "If wl_surface.attach is sent with a NULL wl_buffer,
    // the following wl_surface.commit will remove the surface content."
    // So we don't clear here - we clear on commit if buffer is NULL
    surface->buffer_resource = buffer;
    surface->x = x;
    surface->y = y;
    surface->buffer_release_sent = buffer ? false : true;
}

static void surface_damage(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)client; // Unused but required by interface
    
    // Silently ignore degenerate damage rectangles (zero or negative width/height)
    // Some clients send these intentionally (e.g., to mark edges), and rejecting them
    // causes protocol errors that disconnect the client. Be tolerant and just ignore them.
    if (width <= 0 || height <= 0) {
        // Log for debugging but don't post error - be tolerant of client behavior
        log_printf("[COMPOSITOR] ", "surface_damage: ignoring degenerate damage rectangle: x=%d y=%d w=%d h=%d\n", x, y, width, height);
        return;
    }
    
    // Damage tracking - we'll handle this in commit
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    if (surface) {
        // Store damage region for later use (if needed)
        // For now, we just validate and accept valid damage rectangles
        (void)x; (void)y; // Coordinates stored for potential future use
    }
}

static void surface_frame(struct wl_client *client, struct wl_resource *resource, uint32_t callback) {
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    
    log_printf("[COMPOSITOR] ", "surface_frame() - surface=%p, callback=%u\n", 
               (void *)surface, callback);
    
    // Destroy any existing frame callback first
    if (surface->frame_callback) {
        log_printf("[COMPOSITOR] ", "surface_frame: Destroying existing frame callback\n");
        // Verify the callback resource is still valid before destroying
        // If the client disconnected, the resource might already be destroyed
        struct wl_client *callback_client = wl_resource_get_client(surface->frame_callback);
        if (callback_client) {
            // Resource is still valid - safe to destroy
            wl_resource_destroy(surface->frame_callback);
        } else {
            // Resource was already destroyed (client disconnected) - just clear pointer
            log_printf("[COMPOSITOR] ", "surface_frame: Existing callback already destroyed (client disconnected)\n");
        }
        surface->frame_callback = NULL;
    }
    
    struct wl_resource *callback_resource = wl_resource_create(client, &wl_callback_interface, 1, callback);
    if (!callback_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    surface->frame_callback = callback_resource;
    wl_resource_set_implementation(callback_resource, NULL, NULL, NULL);
    log_printf("[COMPOSITOR] ", "surface_frame: Created new frame callback resource (surface=%p, callback=%p)\n", 
              (void *)surface, (void *)callback_resource);
    fflush(stdout); // Force flush to ensure log is visible
    
    // Notify compositor that a frame callback was requested
    // This ensures the frame callback timer is running
    if (global_compositor && global_compositor->frame_callback_requested) {
        log_printf("[COMPOSITOR] ", "surface_frame: Calling frame_callback_requested callback\n");
        fflush(stdout);
        global_compositor->frame_callback_requested();
    } else {
        log_printf("[COMPOSITOR] ", "surface_frame: WARNING - frame_callback_requested callback is NULL!\n");
        fflush(stdout);
    }
}

static void surface_set_opaque_region(struct wl_client *client, struct wl_resource *resource, struct wl_resource *region) {
    // Opaque region handling
    (void)client;
    (void)resource;
    (void)region;
}

static void surface_set_input_region(struct wl_client *client, struct wl_resource *resource, struct wl_resource *region) {
    // Input region handling
    (void)client;
    (void)resource;
    (void)region;
}

static void surface_commit(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    surface->committed = true;
    log_printf("[COMPOSITOR] ", "surface_commit() - surface=%p, buffer=%p, committed=true\n", 
               (void *)surface, (void *)surface->buffer_resource);
    
    // According to Wayland spec: "If wl_surface.attach is sent with a NULL wl_buffer,
    // the following wl_surface.commit will remove the surface content."
    // Clear the layer contents when committing a NULL buffer
    if (!surface->buffer_resource) {
        // Clear layer contents but keep the layer (surface may reattach buffer later)
        remove_surface_from_renderer(surface);
        
        // Don't send enter events for surfaces without buffers
        // The surface content is being removed, so focus should remain unchanged
        // Just mark that we've committed (for frame callbacks)
        goto send_frame_callback;
    }
    
    // Frame callbacks are now sent during renderFrame at display refresh rate
    // This ensures clients receive callbacks synchronized with the display refresh
    
    // Send keyboard/pointer enter events ONLY for toplevel surfaces
    // Subsurfaces (decorations, titlebars) should NEVER get or change focus
    // Only send enter events if there's a buffer attached (visible surface)
    if (global_seat && xdg_surface_is_toplevel(surface)) {
        struct wl_surface_impl *focused = (struct wl_surface_impl *)global_seat->focused_surface;
        
        // Only send enter events if focus is changing
        if (focused != surface) {
            // Send leave events for the previously focused surface
            // IMPORTANT: Only send leave to toplevel surfaces that actually received enter events
            // IMPORTANT: Verify resource is still valid before sending events
            if (focused && focused->resource) {
                // Check if resource is still valid (not destroyed)
                // If resource was destroyed, wl_resource_get_user_data will return NULL
                struct wl_surface_impl *check = wl_resource_get_user_data(focused->resource);
                if (check == focused) {
                    // Resource is still valid, safe to send leave events
                    // Only send keyboard leave if the focused surface is a toplevel (received enter)
                    if (global_seat->keyboard_resource && xdg_surface_is_toplevel(focused)) {
                        uint32_t serial = wl_seat_get_serial(global_seat);
                        log_printf("[COMPOSITOR] ", "surface_commit: sending keyboard leave to toplevel surface %p\n", (void *)focused);
                        wl_seat_send_keyboard_leave(global_seat, focused->resource, serial);
                    }
                    // Only send pointer leave to toplevel surfaces (that received pointer enter)
                    if (global_seat->pointer_resource && xdg_surface_is_toplevel(focused)) {
                        uint32_t serial = wl_seat_get_serial(global_seat);
                        log_printf("[COMPOSITOR] ", "surface_commit: sending pointer leave to toplevel surface %p\n", (void *)focused);
                        wl_seat_send_pointer_leave(global_seat, focused->resource, serial);
                    }
                } else {
                    // Resource was destroyed, clear focus
                    wl_seat_set_focused_surface(global_seat, NULL);
                    // Don't send text input leave - resource is already destroyed
                }
            }
            
            // Send keyboard enter for the toplevel surface
            // NOTE: Client must request keyboard via seat.get_keyboard() first
            if (global_seat->keyboard_resource) {
                uint32_t serial = wl_seat_get_serial(global_seat);
                struct wl_array keys;
                wl_array_init(&keys);
                log_printf("[COMPOSITOR] ", "surface_commit: sending keyboard enter to toplevel surface %p\n", (void *)surface);
                wl_seat_send_keyboard_enter(global_seat, surface->resource, serial, &keys);
                wl_array_release(&keys);
            } else {
                log_printf("[COMPOSITOR] ", "surface_commit: keyboard_resource is NULL - client hasn't requested keyboard yet\n");
            }
            
            // Send pointer enter when surface gets focus (required before button events)
            // This ensures button events can be sent immediately without waiting for mouse motion
            if (global_seat->pointer_resource) {
                uint32_t serial = wl_seat_get_serial(global_seat);
                // Use center of surface for initial pointer position
                // Note: Wayland uses top-left origin, so Y increases downward
                double x = surface->buffer_width > 0 ? surface->buffer_width / 2.0 : 200.0;
                double y = surface->buffer_height > 0 ? surface->buffer_height / 2.0 : 150.0;
                log_printf("[COMPOSITOR] ", "surface_commit: sending pointer enter to toplevel surface %p at (%.1f, %.1f)\n",
                          (void *)surface, x, y);
                wl_seat_send_pointer_enter(global_seat, surface->resource, serial, x, y);
            }
            
            // Update focused surface
            wl_seat_set_focused_surface(global_seat, surface);
            
            // Update window title with client name when focus changes
            if (surface->resource) {
                struct wl_client *surface_client = wl_resource_get_client(surface->resource);
                if (surface_client && global_compositor && global_compositor->update_title_callback) {
                    global_compositor->update_title_callback(surface_client);
                }
            }
            
            // Send text input enter event if text input is enabled
            // This is called when a surface gains focus
            // CRITICAL: Verify surface resource is still valid before sending
            if (surface->resource) {
                struct wl_client *surface_client_check = wl_resource_get_client(surface->resource);
                if (surface_client_check) {
                    struct wl_surface_impl *surface_check = wl_resource_get_user_data(surface->resource);
                    if (surface_check == surface) {
                        wl_text_input_send_enter(surface->resource);
                    }
                }
            }
        }
    }
    
send_frame_callback:
    // Send frame callback if requested (even for NULL buffer commits)
    // Frame callbacks must be sent for every commit, regardless of buffer state
    // This allows clients to synchronize their rendering loop
    // Note: We defer frame callbacks to renderFrame for proper timing synchronization
    // The frame callback will be sent at the next display refresh
    // This is the standard Wayland pattern - frame callbacks are sent synchronized with display refresh
    
    // Trigger immediate rendering if callback is set and buffer is available
    if (surface->buffer_resource && global_compositor && global_compositor->render_callback) {
        global_compositor->render_callback(surface);
    }
}

static void surface_set_buffer_transform(struct wl_client *client, struct wl_resource *resource, int32_t transform) {
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    // Store transform for rendering
    // TODO: Apply transform when rendering
    (void)client;
    (void)surface;
    (void)transform;
}

static void surface_set_buffer_scale(struct wl_client *client, struct wl_resource *resource, int32_t scale) {
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    // Store scale for rendering
    // TODO: Apply scale when rendering
    (void)client;
    (void)surface;
    (void)scale;
}

static void surface_damage_buffer(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)client; // Unused but required by interface
    
    // Silently ignore degenerate damage rectangles (zero or negative width/height)
    // Some clients send these intentionally (e.g., to mark edges), and rejecting them
    // causes protocol errors that disconnect the client. Be tolerant and just ignore them.
    if (width <= 0 || height <= 0) {
        // Log for debugging but don't post error - be tolerant of client behavior
        log_printf("[COMPOSITOR] ", "surface_damage_buffer: ignoring degenerate damage rectangle: x=%d y=%d w=%d h=%d\n", x, y, width, height);
        return;
    }
    
    // Buffer damage tracking
    struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
    if (surface) {
        // Store buffer damage region for later use (if needed)
        // For now, we just validate and accept valid damage rectangles
        (void)x; (void)y; // Coordinates stored for potential future use
    }
}

static void surface_offset(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y) {
    // Surface offset
    (void)client;
    (void)resource;
    (void)x;
    (void)y;
}

// Region implementation
struct wl_region_impl {
    struct wl_resource *resource;
    // Store region rectangles (simplified - just track if region exists)
    bool has_region;
};

static void region_destroy(struct wl_client *client, struct wl_resource *resource) {
    // Region cleanup - regions don't need special cleanup
    (void)client;
    (void)resource;
}

static void region_add(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height) {
    // Add rectangle to region
    // For now, just mark that region exists
    // TODO: Implement proper region tracking with pixman_region32
    (void)client;
    (void)resource;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

static void region_subtract(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height) {
    // Subtract rectangle from region
    // TODO: Implement proper region tracking with pixman_region32
    (void)client;
    (void)resource;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

// Helper functions
struct wl_surface_impl *wl_surface_from_resource(struct wl_resource *resource) {
    return wl_resource_get_user_data(resource);
}

void wl_surface_damage(struct wl_surface_impl *surface, int32_t x, int32_t y, int32_t width, int32_t height) {
    // Mark surface as damaged
    (void)surface;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

void wl_surface_commit(struct wl_surface_impl *surface) {
    surface->committed = true;
    if (surface->buffer_resource) {
        surface->buffer_release_sent = false;
    }
}

void wl_surface_attach_buffer(struct wl_surface_impl *surface, struct wl_resource *buffer) {
    surface->buffer_resource = buffer;
    surface->buffer_release_sent = buffer ? false : true;
}

// Get all surfaces (for rendering)
struct wl_surface_impl *wl_get_all_surfaces(void) {
    return surfaces;
}

// Send frame callbacks to all surfaces with pending callbacks
// This is called at display refresh rate (via CVDisplayLink) to ensure
// frame callbacks are synchronized with the display refresh
// Returns the number of callbacks sent
int wl_send_frame_callbacks(void) {
    // Get current time in milliseconds since boot (monotonic clock)
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint32_t time = (uint32_t)((ts.tv_sec * 1000) + (ts.tv_nsec / 1000000));

    int callback_count = 0;
    pthread_mutex_lock(&surfaces_mutex);
    struct wl_surface_impl *surface = surfaces;
    while (surface) {
        // Store next pointer before potentially modifying the list
        struct wl_surface_impl *next = surface->next;

        // Check if frame_callback is still valid (not NULL and not destroyed)
        // The destroy listener will set it to NULL if the resource was destroyed
        if (surface->frame_callback) {
            // CRITICAL: Verify the surface's resource is still valid first
            // If the surface was destroyed, we shouldn't send callbacks
            if (!surface->resource) {
                // Surface was destroyed - clear frame callback
                log_printf("[COMPOSITOR] ", "Frame callback for destroyed surface %p - clearing\n", 
                          (void *)surface);
                surface->frame_callback = NULL;
            } else {
                // CRITICAL: Verify the callback resource is still valid before sending
                // Check both the callback resource's client AND verify it matches the surface's client
                struct wl_client *callback_client = wl_resource_get_client(surface->frame_callback);
                if (!callback_client) {
                    // Callback resource was destroyed (client disconnected) - clear it
                    log_printf("[COMPOSITOR] ", "Frame callback for surface %p invalid (callback resource destroyed)\n", 
                              (void *)surface);
                    surface->frame_callback = NULL;
                } else {
                    // Verify the surface resource is still valid
                    struct wl_client *surface_client = wl_resource_get_client(surface->resource);
                    if (!surface_client || surface_client != callback_client) {
                        // Surface resource destroyed or clients don't match - clear callback
                        log_printf("[COMPOSITOR] ", "Frame callback for surface %p invalid (surface resource destroyed or client mismatch)\n", 
                                  (void *)surface);
                        surface->frame_callback = NULL;
                    } else {
                        // Additional safety check: verify the surface resource's user_data matches
                        struct wl_surface_impl *surface_check = wl_resource_get_user_data(surface->resource);
                        if (surface_check != surface) {
                            // Surface resource was destroyed or reused - clear callback
                            log_printf("[COMPOSITOR] ", "Frame callback for surface %p invalid (surface resource user_data mismatch)\n", 
                                      (void *)surface);
                            surface->frame_callback = NULL;
                        } else {
                            // All checks passed - safe to send frame callback
                            log_printf("[COMPOSITOR] ", "Sending frame callback to surface %p (time=%u, callback=%p)\n", 
                                      (void *)surface, time, (void *)surface->frame_callback);
                            fflush(stdout); // Force flush to ensure log is visible
                            
                            // CRITICAL: Wrap send in additional safety - verify callback resource one more time
                            // This prevents crashes if resource is destroyed between checks
                            struct wl_client *final_check = wl_resource_get_client(surface->frame_callback);
                            if (final_check == callback_client) {
                                wl_callback_send_done(surface->frame_callback, time);
                                // Destroy the callback resource after sending
                                // Verify it's still valid before destroying
                                if (wl_resource_get_client(surface->frame_callback) == callback_client) {
                                    wl_resource_destroy(surface->frame_callback);
                                }
                                surface->frame_callback = NULL;
                                callback_count++;
                            } else {
                                // Resource was destroyed between checks - clear pointer
                                log_printf("[COMPOSITOR] ", "Frame callback destroyed between validation checks - clearing\n");
                                surface->frame_callback = NULL;
                            }
                        }
                    }
                }
            }
        }
        surface = next;
    }
    pthread_mutex_unlock(&surfaces_mutex);
    
    if (callback_count > 0) {
        log_printf("[COMPOSITOR] ", "Sent %d frame callback(s)\n", callback_count);
    }
    
    return callback_count;
}

// Check if any surfaces have pending frame callbacks
bool wl_has_pending_frame_callbacks(void) {
    pthread_mutex_lock(&surfaces_mutex);
    struct wl_surface_impl *surface = surfaces;
    while (surface) {
        if (surface->frame_callback) {
            pthread_mutex_unlock(&surfaces_mutex);
            return true;
        }
        surface = surface->next;
    }
    pthread_mutex_unlock(&surfaces_mutex);
    return false;
}

// Buffer handling helper
void *wl_buffer_get_shm_data(struct wl_resource *buffer, int32_t *width, int32_t *height, int32_t *stride) {
    struct wl_shm_buffer *shm_buffer = wl_shm_buffer_get(buffer);
    if (!shm_buffer) return NULL;
    
    if (width) *width = wl_shm_buffer_get_width(shm_buffer);
    if (height) *height = wl_shm_buffer_get_height(shm_buffer);
    if (stride) *stride = wl_shm_buffer_get_stride(shm_buffer);
    
    wl_shm_buffer_begin_access(shm_buffer);
    void *data = wl_shm_buffer_get_data(shm_buffer);
    return data;
}

void wl_buffer_end_shm_access(struct wl_resource *buffer) {
    struct wl_shm_buffer *shm_buffer = wl_shm_buffer_get(buffer);
    if (shm_buffer) {
        wl_shm_buffer_end_access(shm_buffer);
    }
}

