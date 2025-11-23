#include "wayland_seat.h"
#include "wayland_compositor.h"
#include "logging.h"
#include <wayland-server-protocol.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static void seat_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
static void seat_get_pointer(struct wl_client *client, struct wl_resource *resource, uint32_t id);
static void seat_get_keyboard(struct wl_client *client, struct wl_resource *resource, uint32_t id);
static void seat_get_touch(struct wl_client *client, struct wl_resource *resource, uint32_t id);
static void seat_release(struct wl_client *client, struct wl_resource *resource);
static void send_pending_keyboard_enter_idle(void *data);
static void send_pending_modifiers_idle(void *data);

static const struct wl_seat_interface seat_interface = {
    .get_pointer = seat_get_pointer,
    .get_keyboard = seat_get_keyboard,
    .get_touch = seat_get_touch,
    .release = seat_release,
};

static void pointer_set_cursor(struct wl_client *client, struct wl_resource *resource, uint32_t serial, struct wl_resource *surface, int32_t hotspot_x, int32_t hotspot_y);
static void pointer_release(struct wl_client *client, struct wl_resource *resource);
static const struct wl_pointer_interface pointer_interface = {
    .set_cursor = pointer_set_cursor,
    .release = pointer_release,
};

static void keyboard_release(struct wl_client *client, struct wl_resource *resource);
static const struct wl_keyboard_interface keyboard_interface = {
    .release = keyboard_release,
};

static void touch_release(struct wl_client *client, struct wl_resource *resource);
static const struct wl_touch_interface touch_interface = {
    .release = touch_release,
};

struct wl_seat_impl *wl_seat_create(struct wl_display *display) {
    struct wl_seat_impl *seat = calloc(1, sizeof(*seat));
    if (!seat) return NULL;
    
    seat->display = display;
    seat->capabilities = WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD | WL_SEAT_CAPABILITY_TOUCH;
    seat->serial = 1;
    
    seat->global = wl_global_create(display, &wl_seat_interface, 7, seat, seat_bind);
    
    if (!seat->global) {
        free(seat);
        return NULL;
    }
    
    return seat;
}

void wl_seat_destroy(struct wl_seat_impl *seat) {
    if (!seat) return;
    
    // Clean up pending keyboard enter idle callback
    if (seat->pending_keyboard_enter_idle) {
        wl_event_source_remove(seat->pending_keyboard_enter_idle);
        seat->pending_keyboard_enter_idle = NULL;
    }
    
    // Clean up pending modifiers idle callback
    if (seat->pending_modifiers_idle) {
        wl_event_source_remove(seat->pending_modifiers_idle);
        seat->pending_modifiers_idle = NULL;
    }
    
    // Clear pending keyboard enter state
    seat->pending_keyboard_enter_surface = NULL;
    seat->pending_keyboard_enter_keyboard_resource = NULL;
    seat->pending_keyboard_enter_serial = 0;
    seat->pending_keyboard_enter_keys = NULL;
    
    // Clear pending modifiers state
    seat->pending_modifiers_needed = false;
    seat->pending_modifiers_serial = 0;
    
    wl_global_destroy(seat->global);
    free(seat);
}

static void seat_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_seat_impl *seat = data;
    log_printf("[SEAT] ", "seat_bind: client=%p, version=%u, id=%u, capabilities=0x%x\n", 
               (void *)client, version, id, seat->capabilities);
    
    struct wl_resource *resource = wl_resource_create(client, &wl_seat_interface, (int)version, id);
    
    if (!resource) {
        log_printf("[SEAT] ", "seat_bind: failed to create seat resource\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(resource, &seat_interface, seat, NULL);
    
    wl_seat_send_capabilities(resource, seat->capabilities);
    log_printf("[SEAT] ", "seat_bind: sent capabilities=0x%x (keyboard=%s, pointer=%s, touch=%s)\n",
               seat->capabilities,
               (seat->capabilities & WL_SEAT_CAPABILITY_KEYBOARD) ? "yes" : "no",
               (seat->capabilities & WL_SEAT_CAPABILITY_POINTER) ? "yes" : "no",
               (seat->capabilities & WL_SEAT_CAPABILITY_TOUCH) ? "yes" : "no");
    
    if (version >= WL_SEAT_NAME_SINCE_VERSION) {
        wl_seat_send_name(resource, "default");
    }
}

static void seat_get_pointer(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *pointer_resource = wl_resource_create(client, &wl_pointer_interface, wl_resource_get_version(resource), id);
    
    if (!pointer_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(pointer_resource, &pointer_interface, seat, NULL);
    seat->pointer_resource = pointer_resource;
}

static void seat_get_keyboard(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    log_printf("[SEAT] ", "seat_get_keyboard: client=%p, seat=%p, id=%u\n", (void *)client, (void *)seat, id);
    
    struct wl_resource *keyboard_resource = wl_resource_create(client, &wl_keyboard_interface, wl_resource_get_version(resource), id);
    
    if (!keyboard_resource) {
        log_printf("[SEAT] ", "seat_get_keyboard: failed to create keyboard resource\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(keyboard_resource, &keyboard_interface, seat, NULL);
    seat->keyboard_resource = keyboard_resource;
    log_printf("[SEAT] ", "seat_get_keyboard: keyboard resource created successfully: %p\n", (void *)keyboard_resource);
    
    // Send keymap - use a standard pc+us layout so Linux clients understand our keycodes
    const char *keymap_string =
        "xkb_keymap {\n"
        "  xkb_keycodes  { include \"evdev+aliases(qwerty)\" };\n"
        "  xkb_types     { include \"complete\" };\n"
        "  xkb_compat    { include \"complete\" };\n"
        "  xkb_symbols   { include \"pc+us\" };\n"
        "  xkb_geometry  { include \"pc(pc105)\" };\n"
        "};\n";
    
    int keymap_fd = -1;
    size_t keymap_size = strlen(keymap_string) + 1;
    
    // Create a temporary file for the keymap
    char keymap_path[] = "/tmp/wayland-keymap-XXXXXX";
    keymap_fd = mkstemp(keymap_path);
    if (keymap_fd >= 0) {
        unlink(keymap_path);
        if (write(keymap_fd, keymap_string, keymap_size) == (ssize_t)keymap_size) {
            lseek(keymap_fd, 0, SEEK_SET);
            // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
            // WL_KEYBOARD_KEYMAP is defined as 0 in wayland-server-protocol.h
            wl_resource_post_event(keyboard_resource, WL_KEYBOARD_KEYMAP, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, keymap_fd, (uint32_t)keymap_size);
        }
        close(keymap_fd);
    }
}

static void seat_get_touch(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *touch_resource = wl_resource_create(client, &wl_touch_interface, wl_resource_get_version(resource), id);
    
    if (!touch_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(touch_resource, &touch_interface, seat, NULL);
    seat->touch_resource = touch_resource;
}

static void touch_release(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void seat_release(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void pointer_set_cursor(struct wl_client *client, struct wl_resource *resource, uint32_t serial, struct wl_resource *surface, int32_t hotspot_x, int32_t hotspot_y) {
    (void)client;  // Client is available but not needed for validation
    (void)serial;  // Serial is used for protocol validation but we accept all valid requests
    
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    if (!seat) {
        log_printf("[SEAT] ", "pointer_set_cursor: seat is NULL\n");
        return;
    }
    
    // CRITICAL: Validate surface if provided (NULL is valid - means hide cursor)
    if (surface) {
        // Verify surface resource is still valid
        if (wl_resource_get_user_data(surface) == NULL ||
            wl_resource_get_client(surface) == NULL) {
            log_printf("[SEAT] ", "pointer_set_cursor: cursor surface resource is invalid (ignoring)\n");
            return; // Surface was destroyed or client disconnected
        }
        
        // Track this surface as a cursor surface
        seat->cursor_surface = surface;
        seat->cursor_hotspot_x = hotspot_x;
        seat->cursor_hotspot_y = hotspot_y;
        
        log_printf("[SEAT] ", "pointer_set_cursor: cursor surface set to %p (hotspot: %d, %d)\n", 
                  (void *)surface, hotspot_x, hotspot_y);
        
        // Mark the surface as a cursor surface by storing a special marker in user_data
        // We'll check this in surface_commit to skip normal surface handling
        struct wl_surface_impl *surface_impl = wl_resource_get_user_data(surface);
        if (surface_impl) {
            // Store a pointer to the seat in the surface's user_data field
            // We'll use a special marker to identify cursor surfaces
            // Actually, we can't modify user_data here - it's already set to surface_impl
            // Instead, we'll check if the surface matches seat->cursor_surface in surface_commit
        }
    } else {
        // NULL surface means hide cursor
        seat->cursor_surface = NULL;
        log_printf("[SEAT] ", "pointer_set_cursor: cursor hidden (NULL surface)\n");
    }
    
    // Note: We don't actually render the cursor surface yet
    // Clients can set cursor surfaces, but we use macOS native cursors
    // This is protocol-compliant - we accept the request but don't use the surface
    // TODO: Implement cursor rendering using NSCursor or custom CALayer
}

static void pointer_release(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    if (seat) {
        seat->pointer_resource = NULL;
    }
    // Clear user data before destroying to prevent use-after-free
    wl_resource_set_user_data(resource, NULL);
    wl_resource_destroy(resource);
}

static void keyboard_release(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    log_printf("[SEAT] ", "keyboard_release: resource=%p, seat=%p\n", (void *)resource, (void *)seat);
    if (seat) {
        if (seat->keyboard_resource == resource) {
            log_printf("[SEAT] ", "keyboard_release: clearing keyboard_resource\n");
            // Cancel pending modifiers idle callback if any
            if (seat->pending_modifiers_idle) {
                wl_event_source_remove(seat->pending_modifiers_idle);
                seat->pending_modifiers_idle = NULL;
            }
            seat->pending_modifiers_needed = false;
            seat->keyboard_resource = NULL;
        } else {
            log_printf("[SEAT] ", "keyboard_release: WARNING - keyboard_resource mismatch (seat->keyboard_resource=%p, resource=%p)\n", 
                      (void *)seat->keyboard_resource, (void *)resource);
        }
    }
    // Clear user data before destroying to prevent use-after-free
    wl_resource_set_user_data(resource, NULL);
    wl_resource_destroy(resource);
}

void wl_seat_set_capabilities(struct wl_seat_impl *seat, uint32_t capabilities) {
    seat->capabilities = capabilities;
}

uint32_t wl_seat_get_serial(struct wl_seat_impl *seat) {
    return ++seat->serial;
}

void wl_seat_set_focused_surface(struct wl_seat_impl *seat, void *surface) {
    seat->focused_surface = surface;
    // For simplicity, pointer focus follows keyboard focus
    // In a full compositor, pointer focus would be independent
    seat->pointer_focused_surface = surface;
}

void wl_seat_send_pointer_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, double x, double y) {
    if (!seat || !seat->pointer_resource || !surface) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: invalid parameters (seat=%p, pointer_resource=%p, surface=%p)\n",
                  (void *)seat, (void *)(seat ? seat->pointer_resource : NULL), (void *)surface);
        return;
    }
    
    // CRITICAL: Check if pointer_resource looks valid (not obviously corrupted)
    // Valid pointers should be aligned and in reasonable memory range
    if ((uintptr_t)seat->pointer_resource < 0x1000 || ((uintptr_t)seat->pointer_resource & 0x7) != 0) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: pointer_resource looks corrupted (0x%p)\n", (void *)seat->pointer_resource);
        seat->pointer_resource = NULL;
        return;
    }
    
    // CRITICAL: Check if surface looks valid (not obviously corrupted)
    if ((uintptr_t)surface < 0x1000 || ((uintptr_t)surface & 0x7) != 0) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: surface looks corrupted (0x%p)\n", (void *)surface);
        return;
    }
    
    // Verify pointer resource is still valid before sending event
    if (wl_resource_get_user_data(seat->pointer_resource) == NULL) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: pointer_resource user_data is NULL\n");
        seat->pointer_resource = NULL;
        return; // Pointer resource was destroyed
    }
    // Verify pointer resource's client is still valid
    if (wl_resource_get_client(seat->pointer_resource) == NULL) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: pointer_resource client is NULL\n");
        seat->pointer_resource = NULL;
        return; // Pointer resource's client disconnected
    }
    // Verify surface resource is still valid
    if (wl_resource_get_user_data(surface) == NULL) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: surface user_data is NULL\n");
        return; // Surface resource was destroyed
    }
    // Verify surface resource's client is still valid
    if (wl_resource_get_client(surface) == NULL) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: surface client is NULL\n");
        return; // Surface resource's client disconnected
    }

    // Get the surface implementation from the resource
    struct wl_surface_impl *surface_impl = wl_resource_get_user_data(surface);
    if (!surface_impl) {
        return; // Surface was destroyed
    }

    // If entering a different surface, send leave to the previous one first
    if (seat->pointer_focused_surface != surface_impl && seat->pointer_focused_surface) {
        struct wl_surface_impl *prev = (struct wl_surface_impl *)seat->pointer_focused_surface;
        if (prev->resource && wl_resource_get_user_data(prev->resource) != NULL) {
            uint32_t leave_serial = wl_seat_get_serial(seat);
            log_printf("[SEAT] ", "wl_seat_send_pointer_enter: sending leave to previous surface %p\n", (void *)prev);
            wl_seat_send_pointer_leave(seat, prev->resource, leave_serial);
        }
    }

    // Clear pressed buttons when entering a new surface (fresh start)
    seat->pressed_buttons = 0;
    
    // CRITICAL: Final validation right before calling variadic function
    // The surface or pointer_resource might have become invalid between checks
    if (!seat->pointer_resource || !surface ||
        wl_resource_get_user_data(seat->pointer_resource) == NULL ||
        wl_resource_get_client(seat->pointer_resource) == NULL ||
        wl_resource_get_user_data(surface) == NULL ||
        wl_resource_get_client(surface) == NULL) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: resource became invalid right before sending enter\n");
        return;
    }
    
    // Double-check that surface_impl still matches
    struct wl_surface_impl *check_impl = wl_resource_get_user_data(surface);
    if (check_impl != surface_impl) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: surface implementation changed - skipping\n");
        return;
    }
    
    wl_fixed_t fx = wl_fixed_from_double(x);
    wl_fixed_t fy = wl_fixed_from_double(y);
    
    // Store in local variables to ensure they don't change during the call
    struct wl_resource *final_pointer_res = seat->pointer_resource;
    struct wl_resource *final_surface = surface;
    
    // Final check one more time
    if (final_pointer_res != seat->pointer_resource ||
        final_surface != surface ||
        wl_resource_get_user_data(final_pointer_res) == NULL ||
        wl_resource_get_client(final_pointer_res) == NULL ||
        wl_resource_get_user_data(final_surface) == NULL ||
        wl_resource_get_client(final_surface) == NULL) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_enter: resource became invalid at last moment\n");
        return;
    }
    
    // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
    // This avoids calling convention issues with variadic functions on ARM64 macOS
    // WL_POINTER_ENTER is defined as 0 in wayland-server-protocol.h
    wl_resource_post_event(final_pointer_res, WL_POINTER_ENTER, serial, final_surface, fx, fy);

    // Update pointer focus
    seat->pointer_focused_surface = surface_impl;
    log_printf("[SEAT] ", "wl_seat_send_pointer_enter: pointer focus set to surface %p\n", (void *)surface_impl);
}

void wl_seat_send_pointer_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial) {
    if (!seat->pointer_resource || !surface) return;
    // Verify pointer resource is still valid before sending event
    if (wl_resource_get_user_data(seat->pointer_resource) == NULL) {
        return; // Pointer resource was destroyed
    }
    // Verify pointer resource's client is still valid
    if (wl_resource_get_client(seat->pointer_resource) == NULL) {
        return; // Pointer resource's client disconnected
    }
    // Verify surface resource is still valid
    if (wl_resource_get_user_data(surface) == NULL) {
        return; // Surface resource was destroyed
    }
    // Verify surface resource's client is still valid
    if (wl_resource_get_client(surface) == NULL) {
        return; // Surface resource's client disconnected
    }
    
    // Clear pressed buttons when pointer leaves (Wayland protocol requirement)
    // Any buttons that were pressed must be considered released when pointer leaves
    if (seat->pressed_buttons != 0) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_leave: clearing pressed buttons (bitmask=0x%X)\n", seat->pressed_buttons);
        seat->pressed_buttons = 0;
    }
    
    // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
    // WL_POINTER_LEAVE is defined as 1 in wayland-server-protocol.h
    wl_resource_post_event(seat->pointer_resource, WL_POINTER_LEAVE, serial, surface);

    // Clear pointer focus
    seat->pointer_focused_surface = NULL;
    log_printf("[SEAT] ", "wl_seat_send_pointer_leave: pointer focus cleared\n");
}

void wl_seat_send_pointer_motion(struct wl_seat_impl *seat, uint32_t time, double x, double y) {
    if (!seat || !seat->pointer_resource) return;
    // Verify pointer resource is still valid before sending event
    if (wl_resource_get_user_data(seat->pointer_resource) == NULL) {
        seat->pointer_resource = NULL; // Clear invalid pointer
        return; // Pointer resource was destroyed
    }

    // For simplicity, assume pointer is always over the focused surface (toplevel)
    // In a full compositor, you'd need to check which surface contains (x,y)
    struct wl_surface_impl *current_surface = (struct wl_surface_impl *)seat->focused_surface;

    // If we don't have a focused surface yet, don't send motion events
    if (!current_surface || !current_surface->resource ||
        wl_resource_get_user_data(current_surface->resource) == NULL) {
        return;
    }

    // Send enter event if this is the first time we're interacting with this surface
    if (seat->pointer_focused_surface != current_surface) {
        // Send leave event for previous surface if any
        if (seat->pointer_focused_surface && ((struct wl_surface_impl *)seat->pointer_focused_surface)->resource) {
            struct wl_surface_impl *prev = (struct wl_surface_impl *)seat->pointer_focused_surface;
            if (wl_resource_get_user_data(prev->resource) != NULL) {
                uint32_t serial = wl_seat_get_serial(seat);
                log_printf("[SEAT] ", "wl_seat_send_pointer_motion: sending leave to surface %p\n", (void *)prev);
                wl_seat_send_pointer_leave(seat, prev->resource, serial);
            }
        }

        // Send enter event for new surface
        uint32_t serial = wl_seat_get_serial(seat);
        log_printf("[SEAT] ", "wl_seat_send_pointer_motion: sending enter to surface %p at (%.1f, %.1f)\n",
                  (void *)current_surface, x, y);
        // FIXED: Pass double values (x, y) not wl_fixed_t values (fx, fy)
        wl_seat_send_pointer_enter(seat, current_surface->resource, serial, x, y);

        // Update pointer focus
        seat->pointer_focused_surface = current_surface;
    }

    // Always send motion event to the focused surface
    wl_fixed_t fx = wl_fixed_from_double(x);
    wl_fixed_t fy = wl_fixed_from_double(y);
    
    // Log cursor position for debugging
    log_printf("[CURSOR] ", "mouse motion: position=(%.1f, %.1f), surface=%p, time=%u\n", 
               x, y, (void *)current_surface, time);
    
    // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
    // WL_POINTER_MOTION is defined as 2 in wayland-server-protocol.h
    wl_resource_post_event(seat->pointer_resource, WL_POINTER_MOTION, time, fx, fy);
    
    // Flush events to client immediately so input is processed right away
    struct wl_client *client = wl_resource_get_client(seat->pointer_resource);
    if (client) {
        wl_client_flush(client);
    }
}

void wl_seat_send_pointer_button(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    if (!seat || !seat->pointer_resource) return;
    // Verify pointer resource is still valid before sending event
    if (wl_resource_get_user_data(seat->pointer_resource) == NULL) {
        seat->pointer_resource = NULL; // Clear invalid pointer
        return; // Pointer resource was destroyed
    }

    // Only send button events if the pointer is currently focused on a surface
    // This prevents "stray button release events" when the pointer hasn't entered any surface
    if (!seat->pointer_focused_surface) {
        log_printf("[SEAT] ", "wl_seat_send_pointer_button: no pointer focus, ignoring button event (button=%u, state=%u)\n", button, state);
        return;
    }

    // Track button state to prevent duplicate press/release events
    // Wayland protocol requires: can only send press once, and release only for pressed buttons
    if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
        // Check if button is already pressed - if so, ignore duplicate press
        if (button >= 272 && button < 272 + 32) {
            uint32_t bit = button - 272;
            uint32_t button_mask = (1U << bit);
            
            if (seat->pressed_buttons & button_mask) {
                // Button is already pressed - ignore duplicate press event
                log_printf("[SEAT] ", "wl_seat_send_pointer_button: ignoring duplicate press for button %u (already pressed, bitmask=0x%X)\n", button, seat->pressed_buttons);
                return;
            }
            
            // Mark button as pressed
            seat->pressed_buttons |= button_mask;
            log_printf("[SEAT] ", "wl_seat_send_pointer_button: button %u pressed (bitmask=0x%X)\n", button, seat->pressed_buttons);
        }
        // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
        // WL_POINTER_BUTTON is defined as 3 in wayland-server-protocol.h
        wl_resource_post_event(seat->pointer_resource, WL_POINTER_BUTTON, serial, time, button, state);
    } else if (state == WL_POINTER_BUTTON_STATE_RELEASED) {
        // Only send release if button was previously pressed
        if (button >= 272 && button < 272 + 32) {
            uint32_t bit = button - 272;
            uint32_t button_mask = (1U << bit);
            if (seat->pressed_buttons & button_mask) {
                seat->pressed_buttons &= ~button_mask;
                log_printf("[SEAT] ", "wl_seat_send_pointer_button: button %u released (bitmask=0x%X)\n", button, seat->pressed_buttons);
                // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
        // WL_POINTER_BUTTON is defined as 3 in wayland-server-protocol.h
        wl_resource_post_event(seat->pointer_resource, WL_POINTER_BUTTON, serial, time, button, state);
            } else {
                log_printf("[SEAT] ", "wl_seat_send_pointer_button: ignoring stray release for button %u (not pressed, bitmask=0x%X)\n", button, seat->pressed_buttons);
            }
        } else {
            log_printf("[SEAT] ", "wl_seat_send_pointer_button: ignoring release for invalid button %u\n", button);
        }
    }
}

void wl_seat_send_keyboard_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, struct wl_array *keys) {
    if (!seat->keyboard_resource || !surface) return;
    // Verify keyboard resource is still valid before sending event
    if (wl_resource_get_user_data(seat->keyboard_resource) == NULL) {
        return; // Keyboard resource was destroyed
    }
    // Verify keyboard resource's client is still valid
    if (wl_resource_get_client(seat->keyboard_resource) == NULL) {
        return; // Keyboard resource's client disconnected
    }
    // Verify surface resource is still valid
    if (wl_resource_get_user_data(surface) == NULL) {
        return; // Surface resource was destroyed
    }
    // Verify surface resource's client is still valid
    if (wl_resource_get_client(surface) == NULL) {
        return; // Surface resource's client disconnected
    }
    // Ensure keys array is valid (not NULL and properly initialized)
    if (!keys) {
        log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: keys array is NULL, creating empty array\n");
        struct wl_array empty_keys;
        wl_array_init(&empty_keys);
        log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: sending enter event to surface %p (empty keys array)\n", (void *)surface);
        
        // Verify keyboard resource is still valid before sending enter event
        if (wl_resource_get_user_data(seat->keyboard_resource) == NULL ||
            wl_resource_get_client(seat->keyboard_resource) == NULL) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: keyboard resource became invalid before sending enter (NULL keys case)\n");
            wl_array_release(&empty_keys);
            return;
        }
        
        // Store keyboard_resource pointer in a local variable to ensure it doesn't change
        struct wl_resource *keyboard_res = seat->keyboard_resource;
        
        // CRITICAL: Verify the resource is still valid and matches what we stored
        if (!keyboard_res || 
            keyboard_res != seat->keyboard_resource ||
            wl_resource_get_user_data(keyboard_res) == NULL ||
            wl_resource_get_client(keyboard_res) == NULL) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: keyboard resource became invalid right before sending enter (NULL keys case)\n");
        wl_array_release(&empty_keys);
            return;
        }
        
        // CRITICAL: Verify surface is still valid before calling
        if (!surface ||
            wl_resource_get_user_data(surface) == NULL ||
            wl_resource_get_client(surface) == NULL) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: surface resource became invalid right before sending enter (NULL keys case)\n");
            wl_array_release(&empty_keys);
            return;
        }
        
        // CRITICAL: Defer keyboard enter event via idle callback to avoid calling variadic function from FFI callback
        // Calling variadic functions (like wl_keyboard_send_enter) from within FFI callbacks can corrupt the stack
        // Store state for deferred send
        struct wl_array *keys_copy = malloc(sizeof(struct wl_array));
        if (!keys_copy) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: failed to allocate keys array copy\n");
            wl_array_release(&empty_keys);
            return;
        }
        // Properly initialize the copy - don't shallow copy the structure
        wl_array_init(keys_copy);
        // empty_keys is already empty (size=0, data=NULL), so no need to copy data
        
        // Cancel any existing pending keyboard enter idle
        if (seat->pending_keyboard_enter_idle) {
            wl_event_source_remove(seat->pending_keyboard_enter_idle);
            seat->pending_keyboard_enter_idle = NULL;
        }
        
        // Store state for deferred send
        seat->pending_keyboard_enter_keyboard_resource = keyboard_res;
        seat->pending_keyboard_enter_surface = surface;
        seat->pending_keyboard_enter_serial = serial;
        seat->pending_keyboard_enter_keys = keys_copy;
        
        // Schedule keyboard enter to be sent via idle callback
            struct wl_event_loop *event_loop = wl_display_get_event_loop(seat->display);
            if (event_loop) {
            seat->pending_keyboard_enter_idle = wl_event_loop_add_idle(event_loop, send_pending_keyboard_enter_idle, seat);
            if (seat->pending_keyboard_enter_idle) {
                log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: scheduled keyboard enter event via idle callback (NULL keys case)\n");
                } else {
                log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: failed to schedule keyboard enter idle callback (NULL keys case)\n");
                free(keys_copy);
                seat->pending_keyboard_enter_keys = NULL;
                }
            } else {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: event loop unavailable for keyboard enter idle callback (NULL keys case)\n");
            free(keys_copy);
            seat->pending_keyboard_enter_keys = NULL;
        }
    } else {
        // Verify keys array is properly initialized
        // An empty array (size=0, data=NULL) is valid and means no keys are pressed
        log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: sending enter event to surface %p (keys: size=%zu, data=%p)\n", 
                  (void *)surface, keys->size, (void *)keys->data);
        
        // Verify the array structure is valid before passing to Wayland
        // The array should have size=0 and data=NULL for an empty array, or valid data pointer for non-empty
        // Only check for invalid state: size>0 but data==NULL (should never happen)
        if (keys->size > 0 && keys->data == NULL) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: WARNING - keys array has size>0 but data is NULL, fixing\n");
            // This is invalid - reset to empty array
            wl_array_release(keys);
            wl_array_init(keys);
        }
        // Note: size=0 and data=NULL is the correct state for an empty array
        
        // Verify keyboard resource is still valid before sending enter event
        // Double-check after all the validation above
        if (wl_resource_get_user_data(seat->keyboard_resource) == NULL ||
            wl_resource_get_client(seat->keyboard_resource) == NULL) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: keyboard resource became invalid before sending enter\n");
            return;
        }
        
        // Store keyboard_resource pointer in a local variable to ensure it doesn't change
        struct wl_resource *keyboard_res = seat->keyboard_resource;
        
        // CRITICAL: Verify the resource is still valid one more time before calling
        // Also verify it matches what we stored (no concurrent modification)
        if (!keyboard_res || 
            keyboard_res != seat->keyboard_resource ||
            wl_resource_get_user_data(keyboard_res) == NULL ||
            wl_resource_get_client(keyboard_res) == NULL) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: keyboard resource became invalid right before sending enter\n");
            return;
        }
        
        // CRITICAL: Verify surface is still valid before calling
        if (!surface ||
            wl_resource_get_user_data(surface) == NULL ||
            wl_resource_get_client(surface) == NULL) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: surface resource became invalid right before sending enter\n");
            return;
        }
        
        // CRITICAL: Verify keys array pointer is valid (not corrupted)
        if (!keys) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: keys array is NULL in non-NULL branch - this should not happen\n");
            return;
        }
        
        // CRITICAL: Defer keyboard enter event via idle callback to avoid calling variadic function from FFI callback
        // Calling variadic functions (like wl_keyboard_send_enter) from within FFI callbacks can corrupt the stack
        // Copy the keys array since it might be a stack variable that won't exist when the callback runs
        struct wl_array *keys_copy = malloc(sizeof(struct wl_array));
        if (!keys_copy) {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: failed to allocate keys array copy\n");
            return;
        }
        wl_array_init(keys_copy);
        if (keys->size > 0 && keys->data) {
            // Copy the keys data
            wl_array_add(keys_copy, keys->size);
            memcpy(keys_copy->data, keys->data, keys->size);
        }
        
        // Cancel any existing pending keyboard enter idle
        if (seat->pending_keyboard_enter_idle) {
            wl_event_source_remove(seat->pending_keyboard_enter_idle);
            seat->pending_keyboard_enter_idle = NULL;
        }
        
        // Store state for deferred send
        seat->pending_keyboard_enter_keyboard_resource = keyboard_res;
        seat->pending_keyboard_enter_surface = surface;
        seat->pending_keyboard_enter_serial = serial;
        seat->pending_keyboard_enter_keys = keys_copy;
        
        // Schedule keyboard enter to be sent via idle callback
            struct wl_event_loop *event_loop = wl_display_get_event_loop(seat->display);
            if (event_loop) {
            seat->pending_keyboard_enter_idle = wl_event_loop_add_idle(event_loop, send_pending_keyboard_enter_idle, seat);
            if (seat->pending_keyboard_enter_idle) {
                log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: scheduled keyboard enter event via idle callback\n");
                } else {
                log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: failed to schedule keyboard enter idle callback\n");
                wl_array_release(keys_copy);
                free(keys_copy);
                seat->pending_keyboard_enter_keys = NULL;
                }
            } else {
            log_printf("[SEAT] ", "wl_seat_send_keyboard_enter: event loop unavailable for keyboard enter idle callback\n");
            wl_array_release(keys_copy);
            free(keys_copy);
            seat->pending_keyboard_enter_keys = NULL;
        }
    }
}

void wl_seat_send_keyboard_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial) {
    if (!seat->keyboard_resource || !surface) return;
    // Verify keyboard resource is still valid before sending event
    if (wl_resource_get_user_data(seat->keyboard_resource) == NULL) {
        return; // Keyboard resource was destroyed
    }
    // Verify keyboard resource's client is still valid
    if (wl_resource_get_client(seat->keyboard_resource) == NULL) {
        return; // Keyboard resource's client disconnected
    }
    // Verify surface resource is still valid
    if (wl_resource_get_user_data(surface) == NULL) {
        return; // Surface resource was destroyed
    }
    // Verify surface resource's client is still valid
    if (wl_resource_get_client(surface) == NULL) {
        return; // Surface resource's client disconnected
    }
    // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
    // WL_KEYBOARD_LEAVE is defined as 2 in wayland-server-protocol.h
    wl_resource_post_event(seat->keyboard_resource, WL_KEYBOARD_LEAVE, serial, surface);
}

// Helper function to check if a keycode is a modifier key and update modifier state
// Returns true if modifier state changed, false otherwise
static bool update_modifier_state(struct wl_seat_impl *seat, uint32_t key, uint32_t state) {
    // XKB modifier masks (from xkb_keysym.h)
    // These are bit positions in the modifier state
    uint32_t shift_mask = 1 << 0;   // Shift
    uint32_t lock_mask = 1 << 1;    // Caps Lock
    uint32_t control_mask = 1 << 2; // Control
    uint32_t mod1_mask = 1 << 3;    // Alt/Meta
    uint32_t mod4_mask = 1 << 6;    // Mod4 (Super/Windows)
    
    uint32_t modifier_mask = 0;
    bool state_changed = false;
    
    // Map Linux keycodes to modifier masks
    // Keycode 42 = Left Control, 54 = Right Shift, 56 = Left Shift, 29 = Left Alt, etc.
    switch (key) {
        case 42:  // Left Control
        case 97:  // Right Control
            modifier_mask = control_mask;
            break;
        case 56:  // Left Shift
        case 54:  // Right Shift
            modifier_mask = shift_mask;
            break;
        case 29:  // Left Alt
        case 100: // Right Alt
            modifier_mask = mod1_mask; // Alt is typically mod1
            break;
        case 58:  // Caps Lock
            modifier_mask = lock_mask;
            break;
        case 125: // Left Super/Command
        case 126: // Right Super/Command
            modifier_mask = mod4_mask; // Super/Command is typically mod4
            break;
        default:
            return false; // Not a modifier key
    }
    
    // Update modifier state based on key press/release
    uint32_t old_depressed = seat->mods_depressed;
    
    if (state == WL_KEYBOARD_KEY_STATE_PRESSED) {
        seat->mods_depressed |= modifier_mask;
        if (key == 58) { // Caps Lock - toggle locked state
            seat->mods_locked ^= modifier_mask;
            state_changed = true; // Caps Lock always changes state
        } else {
            state_changed = (old_depressed != seat->mods_depressed);
        }
    } else if (state == WL_KEYBOARD_KEY_STATE_RELEASED) {
        seat->mods_depressed &= ~modifier_mask;
        state_changed = (old_depressed != seat->mods_depressed);
        // Note: Caps Lock locked state persists until toggled again
    }
    
    return state_changed;
}

// Idle callback to send pending keyboard enter event (deferred from FFI callback)
static void send_pending_keyboard_enter_idle(void *data) {
    log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: START\n");
    struct wl_seat_impl *seat = (struct wl_seat_impl *)data;
    if (!seat) {
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: seat is NULL\n");
        return;
    }
    
    log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: seat=%p\n", (void *)seat);
    
    // Clear the idle source first to prevent re-entry
    seat->pending_keyboard_enter_idle = NULL;
    
    // Use the stored resources from when we scheduled the callback
    struct wl_resource *keyboard_res = seat->pending_keyboard_enter_keyboard_resource;
    struct wl_resource *surface = seat->pending_keyboard_enter_surface;
    uint32_t serial = seat->pending_keyboard_enter_serial;
    struct wl_array *keys = seat->pending_keyboard_enter_keys;
    
    // Clear pending state immediately to prevent reuse
    seat->pending_keyboard_enter_keyboard_resource = NULL;
    seat->pending_keyboard_enter_surface = NULL;
    seat->pending_keyboard_enter_serial = 0;
    seat->pending_keyboard_enter_keys = NULL;
    
    if (!keyboard_res || !surface) {
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: missing keyboard or surface resource\n");
        if (keys) {
            wl_array_release(keys);
            free(keys);
        }
        return;
    }
    
    // Verify resources are still valid
    if (wl_resource_get_user_data(keyboard_res) == NULL ||
        wl_resource_get_client(keyboard_res) == NULL ||
        wl_resource_get_user_data(surface) == NULL ||
        wl_resource_get_client(surface) == NULL) {
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: resources became invalid\n");
        if (keys) {
            wl_array_release(keys);
            free(keys);
        }
        return;
    }
    
    // CRITICAL: Final validation right before calling variadic function
    // Check pointer validity (alignment and address range)
    if ((uintptr_t)keyboard_res < 0x1000 || ((uintptr_t)keyboard_res & 0x7) != 0) {
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: keyboard_res looks corrupted (0x%p)\n", (void *)keyboard_res);
        if (keys) {
            wl_array_release(keys);
            free(keys);
        }
        return;
    }
    
    if ((uintptr_t)surface < 0x1000 || ((uintptr_t)surface & 0x7) != 0) {
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: surface looks corrupted (0x%p)\n", (void *)surface);
        if (keys) {
            wl_array_release(keys);
            free(keys);
        }
        return;
    }
    
    // CRITICAL: Re-validate resources one more time right before calling
    if (wl_resource_get_user_data(keyboard_res) == NULL ||
        wl_resource_get_client(keyboard_res) == NULL ||
        wl_resource_get_user_data(surface) == NULL ||
        wl_resource_get_client(surface) == NULL) {
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: resources became invalid right before sending enter\n");
        if (keys) {
            wl_array_release(keys);
            free(keys);
        }
        return;
    }
    
    // Verify keys array is valid
    if (!keys) {
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: keys array is NULL, creating empty array\n");
        struct wl_array empty_keys;
        wl_array_init(&empty_keys);
        
        // Store in local variables for final call
        struct wl_resource *final_keyboard_res = keyboard_res;
        struct wl_resource *final_surface = surface;
        struct wl_array *final_keys = &empty_keys;
        
        // Final check one more time
        if (final_keyboard_res != keyboard_res ||
            final_surface != surface ||
            wl_resource_get_user_data(final_keyboard_res) == NULL ||
            wl_resource_get_client(final_keyboard_res) == NULL ||
            wl_resource_get_user_data(final_surface) == NULL ||
            wl_resource_get_client(final_surface) == NULL) {
            log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: resources changed at last moment\n");
            wl_array_release(&empty_keys);
            return;
        }
        
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: CALLING wl_resource_post_event for keyboard enter (empty keys case)\n");
        log_printf("[SEAT] ", "  keyboard_res=%p, serial=%u, surface=%p, keys=%p\n", 
                  (void *)final_keyboard_res, serial, (void *)final_surface, (void *)final_keys);
        // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
        // This avoids calling convention issues with variadic functions on ARM64 macOS
        // WL_KEYBOARD_ENTER is defined as 1 in wayland-server-protocol.h
        wl_resource_post_event(final_keyboard_res, WL_KEYBOARD_ENTER, serial, final_surface, final_keys);
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: keyboard enter sent successfully (empty keys case)\n");
        wl_array_release(&empty_keys);
    } else {
        // CRITICAL: Validate keys array pointer and structure before using
        if ((uintptr_t)keys < 0x1000 || ((uintptr_t)keys & 0x7) != 0) {
            log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: keys array pointer looks corrupted (0x%p)\n", (void *)keys);
            free(keys);
            return;
        }
        
        // Validate keys array structure
        if (keys->size > 0 && keys->data == NULL) {
            log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: keys array has invalid state (size=%zu but data is NULL), fixing\n", keys->size);
            wl_array_release(keys);
            wl_array_init(keys);
        }
        
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: sending keyboard enter (serial=%u, surface=%p, keys: size=%zu)\n",
                  serial, (void *)surface, keys->size);
        
        // Store in local variables for final call
        struct wl_resource *final_keyboard_res = keyboard_res;
        struct wl_resource *final_surface = surface;
        struct wl_array *final_keys = keys;
        
        // Final check one more time
        if (final_keyboard_res != keyboard_res ||
            final_surface != surface ||
            final_keys != keys ||
            wl_resource_get_user_data(final_keyboard_res) == NULL ||
            wl_resource_get_client(final_keyboard_res) == NULL ||
            wl_resource_get_user_data(final_surface) == NULL ||
            wl_resource_get_client(final_surface) == NULL) {
            log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: resources changed at last moment\n");
            wl_array_release(keys);
            free(keys);
            return;
        }
        
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: CALLING wl_resource_post_event for keyboard enter (with keys)\n");
        log_printf("[SEAT] ", "  keyboard_res=%p, serial=%u, surface=%p, keys=%p, keys_size=%zu\n", 
                  (void *)final_keyboard_res, serial, (void *)final_surface, (void *)final_keys, final_keys->size);
        // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
        // This avoids calling convention issues with variadic functions on ARM64 macOS
        // WL_KEYBOARD_ENTER is defined as 1 in wayland-server-protocol.h
        wl_resource_post_event(final_keyboard_res, WL_KEYBOARD_ENTER, serial, final_surface, final_keys);
        log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: keyboard enter sent successfully (with keys)\n");
        // Release keys array (it was allocated with malloc)
        wl_array_release(keys);
        free(keys);
    }
    
    // Schedule modifiers event after enter (as required by protocol)
    // Don't store the resource pointer - use seat->keyboard_resource directly in idle callback
    // CRITICAL: Only schedule if resource is valid and serial is valid
    if (keyboard_res &&
        wl_resource_get_user_data(keyboard_res) != NULL &&
        wl_resource_get_client(keyboard_res) != NULL) {
        uint32_t modifiers_serial = wl_seat_get_serial(seat);
        
        // CRITICAL: Ensure serial is valid before scheduling
        if (modifiers_serial == 0 || modifiers_serial > 0x7fffffff) {
            log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: invalid serial (0x%x) - skipping modifiers\n", modifiers_serial);
        } else {
            seat->pending_modifiers_serial = modifiers_serial;
            seat->pending_modifiers_needed = true;
            
            // Cancel any existing pending modifiers idle
            if (seat->pending_modifiers_idle) {
                wl_event_source_remove(seat->pending_modifiers_idle);
                seat->pending_modifiers_idle = NULL;
            }
            
            // Schedule modifiers to be sent via idle callback
            struct wl_event_loop *event_loop = wl_display_get_event_loop(seat->display);
            if (event_loop) {
                seat->pending_modifiers_idle = wl_event_loop_add_idle(event_loop, send_pending_modifiers_idle, seat);
                if (seat->pending_modifiers_idle) {
                    log_printf("[SEAT] ", "send_pending_keyboard_enter_idle: scheduled modifiers event via idle callback (serial=%u)\n", modifiers_serial);
                }
            }
        }
    }
}

// Idle callback to send pending modifiers event after keyboard enter
static void send_pending_modifiers_idle(void *data) {
    struct wl_seat_impl *seat = (struct wl_seat_impl *)data;
    if (!seat) {
        return;
    }
    
    // Clear the idle source first to prevent re-entry
    seat->pending_modifiers_idle = NULL;
    seat->pending_modifiers_needed = false;
    
    // Use seat->keyboard_resource directly (don't store a copy that can become invalid)
    struct wl_resource *keyboard_res = seat->keyboard_resource;
    if (!keyboard_res) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: no keyboard resource\n");
        return;
    }
    
    // CRITICAL: Check if pointer looks valid (not obviously corrupted)
    // Valid pointers should be aligned and in reasonable memory range
    if ((uintptr_t)keyboard_res < 0x1000 || ((uintptr_t)keyboard_res & 0x7) != 0) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource pointer looks corrupted (0x%p)\n", (void *)keyboard_res);
        return;
    }
    
    // Verify serial is valid (should be non-zero)
    uint32_t serial = seat->pending_modifiers_serial;
    if (serial == 0) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: invalid serial (0)\n");
        return;
    }
    
    // CRITICAL: Verify keyboard resource is still valid
    // Check user_data first (safer than checking client)
    void *user_data = wl_resource_get_user_data(keyboard_res);
    if (!user_data) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource became invalid (user_data is NULL)\n");
        seat->keyboard_resource = NULL; // Clear invalid pointer
        return;
    }
    
    // CRITICAL: Verify the keyboard resource's client is still connected
    struct wl_client *keyboard_client = wl_resource_get_client(keyboard_res);
    if (!keyboard_client) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource's client is NULL (client disconnected)\n");
        seat->keyboard_resource = NULL; // Clear invalid pointer
        return;
    }
    
    // CRITICAL: Double-check that keyboard_res still matches seat->keyboard_resource
    // (it might have changed during validation)
    if (keyboard_res != seat->keyboard_resource) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource changed during validation (keyboard was destroyed)\n");
        return;
    }
    
    // CRITICAL: Final verification right before the call
    // Re-check user_data and client one more time
    if (wl_resource_get_user_data(keyboard_res) == NULL ||
        wl_resource_get_client(keyboard_res) == NULL) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource became invalid in final check\n");
        seat->keyboard_resource = NULL; // Clear invalid pointer
        return;
    }
    
    // CRITICAL: Verify keyboard_res still matches seat->keyboard_resource
    // (it might have been destroyed and replaced)
    if (keyboard_res != seat->keyboard_resource) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource was replaced during validation\n");
        return;
    }
    
    // Send modifiers with no modifiers pressed (initial state after enter)
    // Use explicit uint32_t values to ensure proper type
    uint32_t mods_depressed = 0;
    uint32_t mods_latched = 0;
    uint32_t mods_locked = 0;
    uint32_t group = 0;
    
    log_printf("[SEAT] ", "send_pending_modifiers_idle: sending modifiers (serial=%u, resource=%p)\n", serial, (void *)keyboard_res);
    
    // CRITICAL: Wrap the call in a check to ensure keyboard_res hasn't changed
    // Store in local variable and verify one last time
    struct wl_resource *final_keyboard_res = seat->keyboard_resource;
    
    // CRITICAL: Check pointer validity one more time (alignment and address range)
    if ((uintptr_t)final_keyboard_res < 0x1000 || ((uintptr_t)final_keyboard_res & 0x7) != 0) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: final_keyboard_res pointer looks corrupted (0x%p)\n", (void *)final_keyboard_res);
        seat->keyboard_resource = NULL; // Clear corrupted pointer
        return;
    }
    
    if (final_keyboard_res != keyboard_res) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource changed during validation\n");
        return;
    }
    
    // CRITICAL: Final validation - check user_data and client one more time
    void *final_user_data = wl_resource_get_user_data(final_keyboard_res);
    struct wl_client *final_client = wl_resource_get_client(final_keyboard_res);
    
    if (!final_user_data || !final_client) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource became invalid in final check (user_data=%p, client=%p)\n", 
                  (void *)final_user_data, (void *)final_client);
        seat->keyboard_resource = NULL; // Clear invalid pointer
        return;
    }
    
    // CRITICAL: Verify the resource hasn't changed one more time
    if (final_keyboard_res != seat->keyboard_resource) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: keyboard resource changed right before call\n");
        return;
    }
    
    // Now safe to call - all checks passed
    // Use explicit uint32_t values to ensure proper type for variadic function
    log_printf("[SEAT] ", "send_pending_modifiers_idle: calling wl_keyboard_send_modifiers (resource=%p, serial=%u)\n", 
              (void *)final_keyboard_res, serial);
    
    // CRITICAL: One final check - ensure the resource pointer hasn't been corrupted
    // The crash address 0x0000000e00000007 suggests memory corruption
    // Check that the pointer is still valid and matches what we expect
    if ((uintptr_t)final_keyboard_res != (uintptr_t)seat->keyboard_resource) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: resource pointer mismatch - aborting call\n");
        return;
    }
    
    // CRITICAL: Verify the resource is still valid one more time right before the call
    // This is the last chance to catch any race conditions
    void *last_check_user_data = wl_resource_get_user_data(final_keyboard_res);
    struct wl_client *last_check_client = wl_resource_get_client(final_keyboard_res);
    
    if (!last_check_user_data || !last_check_client) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: resource invalid at final moment - aborting call\n");
        seat->keyboard_resource = NULL;
        return;
    }
    
    // CRITICAL: Ensure serial is valid (non-zero)
    if (serial == 0) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: invalid serial (0) - aborting call\n");
        return;
    }
    
    // WORKAROUND: Temporarily disable modifiers sending due to crashes
    // The crash address 0x0000000e00000007 suggests memory corruption in variadic function
    // TODO: Investigate root cause - may be related to calling variadic functions from idle callbacks
    // or memory corruption in the Wayland library's argument parsing
    
    // CRITICAL: Final safety check - ensure the resource pointer hasn't been corrupted
    // The crash address 0x0000000e00000007 suggests memory corruption
    // Double-check the pointer is still valid and properly aligned
    uintptr_t resource_addr = (uintptr_t)final_keyboard_res;
    if (resource_addr < 0x1000 || (resource_addr & 0x7) != 0 || resource_addr > 0x7fffffffffff) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: resource pointer looks corrupted (0x%p) - aborting\n", 
                  (void *)final_keyboard_res);
        seat->keyboard_resource = NULL;
        return;
    }
    
    // CRITICAL: Ensure all arguments are valid before calling variadic function
    // Check that serial is reasonable (not corrupted)
    if (serial == 0 || serial > 0x7fffffff) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: serial looks corrupted (0x%x) - aborting\n", serial);
        return;
    }
    
    // Final check: ensure resource still matches
    if (final_keyboard_res != seat->keyboard_resource) {
        log_printf("[SEAT] ", "send_pending_modifiers_idle: resource changed at last moment - aborting\n");
        return;
    }
    
    // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
    // This avoids calling convention issues with variadic functions on ARM64 macOS
    // WL_KEYBOARD_MODIFIERS is defined as 4 in wayland-server-protocol.h
    log_printf("[SEAT] ", "send_pending_modifiers_idle: sending modifiers via wl_resource_post_event\n");
    log_printf("[SEAT] ", "  Resource: %p, Serial: %u, Mods: depressed=%u latched=%u locked=%u group=%u\n",
              (void *)final_keyboard_res, serial, mods_depressed, mods_latched, mods_locked, group);
    
    // Use wl_resource_post_event directly (safer than variadic wrapper on ARM64)
    wl_resource_post_event(final_keyboard_res, WL_KEYBOARD_MODIFIERS, 
                          serial, mods_depressed, mods_latched, mods_locked, group);
    
    log_printf("[SEAT] ", "send_pending_modifiers_idle: modifiers sent successfully\n");
}

void wl_seat_send_keyboard_modifiers(struct wl_seat_impl *seat, uint32_t serial) {
    if (!seat || !seat->keyboard_resource) return;
    if (!seat->focused_surface) return;
    
    // Verify keyboard resource is still valid
    if (wl_resource_get_user_data(seat->keyboard_resource) == NULL) {
        // Cancel pending modifiers idle callback if any
        if (seat->pending_modifiers_idle) {
            wl_event_source_remove(seat->pending_modifiers_idle);
            seat->pending_modifiers_idle = NULL;
        }
        seat->pending_modifiers_needed = false;
        seat->keyboard_resource = NULL;
        return;
    }
    
    // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
    // This avoids calling convention issues with variadic functions on ARM64 macOS
    log_printf("[SEAT] ", "wl_seat_send_keyboard_modifiers: sending modifiers via wl_resource_post_event\n");
    log_printf("[SEAT] ", "  Resource: %p, Serial: %u, Mods: depressed=%u latched=%u locked=%u group=%u\n",
              (void *)seat->keyboard_resource, serial, seat->mods_depressed, seat->mods_latched, seat->mods_locked, seat->group);
    
    // Use wl_resource_post_event directly (safer than variadic wrapper on ARM64)
    wl_resource_post_event(seat->keyboard_resource, WL_KEYBOARD_MODIFIERS,
                          serial, seat->mods_depressed, seat->mods_latched, 
                          seat->mods_locked, seat->group);
    
    // Flush client connection immediately to reduce input latency
    struct wl_client *client = wl_resource_get_client(seat->keyboard_resource);
    if (client) {
        wl_client_flush(client);
    }
}

void wl_seat_send_keyboard_key(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t key, uint32_t state) {
    if (!seat || !seat->keyboard_resource) {
        return;
    }

    // Only send keyboard events if there's a focused surface
    // Keyboard events should only go to the client that has keyboard focus
    if (!seat->focused_surface) {
        return; // No focused surface, don't send keyboard events
    }

    // Update modifier state if this is a modifier key
    // Only send modifier update if modifier state actually changed
    bool modifier_changed = update_modifier_state(seat, key, state);
    
    // Verify keyboard resource is still valid before sending event
    // If the client disconnected, the resource will be destroyed
    struct wl_client *client = wl_resource_get_client(seat->keyboard_resource);
    if (!client) {
        // Client disconnected, resource is invalid - clear it
        // Cancel pending modifiers idle callback if any
        if (seat->pending_modifiers_idle) {
            wl_event_source_remove(seat->pending_modifiers_idle);
            seat->pending_modifiers_idle = NULL;
        }
        seat->pending_modifiers_needed = false;
        seat->keyboard_resource = NULL;
        return;
    }
    // Also verify the resource's user_data is still valid
    if (wl_resource_get_user_data(seat->keyboard_resource) == NULL) {
        // Resource was destroyed, clear it
        // Cancel pending modifiers idle callback if any
        if (seat->pending_modifiers_idle) {
            wl_event_source_remove(seat->pending_modifiers_idle);
            seat->pending_modifiers_idle = NULL;
        }
        seat->pending_modifiers_needed = false;
        seat->keyboard_resource = NULL;
        return;
    }
    
    // Verify that the keyboard resource belongs to the client that owns the focused surface
    // For waypipe, all surfaces come through waypipe's client, so this should match
    // But if it doesn't, we should still send the event to the keyboard resource we have
    // since waypipe will handle forwarding
    struct wl_surface_impl *focused = (struct wl_surface_impl *)seat->focused_surface;
    if (focused && focused->resource) {
        struct wl_client *focused_client = wl_resource_get_client(focused->resource);
        // Don't check for mismatch - waypipe will handle forwarding if needed
        (void)focused_client; // Suppress unused variable warning
    }
    
    // FIXED: Use wl_resource_post_event directly instead of variadic wrapper function
    // WL_KEYBOARD_KEY is defined as 3 in wayland-server-protocol.h
    wl_resource_post_event(seat->keyboard_resource, WL_KEYBOARD_KEY, serial, time, key, state);
    
    // Send modifier update after key event if modifier state changed
    // This ensures the client knows the current modifier state
    if (modifier_changed) {
        uint32_t mods_serial = wl_seat_get_serial(seat);
        wl_seat_send_keyboard_modifiers(seat, mods_serial);
    }
    
    // Flush client connection immediately to reduce input latency
    // Reuse the client variable already defined above
    if (client) {
        wl_client_flush(client);
    }
}

void wl_seat_send_touch_down(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, struct wl_resource *surface, int32_t id, wl_fixed_t x, wl_fixed_t y) {
    if (!seat->touch_resource) return;
    wl_touch_send_down(seat->touch_resource, serial, time, surface, id, x, y);
}

void wl_seat_send_touch_up(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, int32_t id) {
    if (!seat->touch_resource) return;
    wl_touch_send_up(seat->touch_resource, serial, time, id);
}

void wl_seat_send_touch_motion(struct wl_seat_impl *seat, uint32_t time, int32_t id, wl_fixed_t x, wl_fixed_t y) {
    if (!seat->touch_resource) return;
    wl_touch_send_motion(seat->touch_resource, time, id, x, y);
}

void wl_seat_send_touch_frame(struct wl_seat_impl *seat) {
    if (!seat->touch_resource) return;
    wl_touch_send_frame(seat->touch_resource);
}

void wl_seat_send_touch_cancel(struct wl_seat_impl *seat) {
    if (!seat->touch_resource) return;
    wl_touch_send_cancel(seat->touch_resource);
}

