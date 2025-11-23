#include "wayland_protocol_stubs.h"
#include "xdg-activation-protocol.h"
#include "fractional-scale-protocol.h"
#include "cursor-shape-protocol.h"
#include "xdg-decoration-protocol.h"
#include "xdg-toplevel-icon-protocol.h"
#include "text-input-v3-protocol.h"
#include "text-input-v1-protocol.h.server"
#include "xdg_shell.h"
#include "wayland_seat.h"
#include "wayland_compositor.h"
#include "logging.h"
#include <wayland-server.h>
#include <stdlib.h>
#include <stdio.h>
#include <CoreGraphics/CoreGraphics.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>

// Some protocol definitions (like cursor-shape) reference tablet tool interfaces
// that we don't implement. Provide a minimal placeholder to satisfy the linker.
const struct wl_interface zwp_tablet_tool_v2_interface = {
    "zwp_tablet_tool_v2",
    1,
    0, NULL,
    0, NULL
};

// ============================================================================
// XDG Activation Protocol (xdg_activation_v1)
// ============================================================================

struct activation_token_data {
    char token[64];
};

static uint64_t activation_token_counter = 1;

static void activation_token_set_serial(struct wl_client *client, struct wl_resource *resource, uint32_t serial, struct wl_resource *seat) {
    (void)client;
    (void)resource;
    (void)serial;
    (void)seat;
    log_printf("[XDG_ACTIVATION] ", "token_set_serial() - serial=%u (stub)\n", serial);
}

static void activation_token_set_app_id(struct wl_client *client, struct wl_resource *resource, const char *app_id) {
    (void)client;
    (void)resource;
    (void)app_id;
    log_printf("[XDG_ACTIVATION] ", "token_set_app_id() - app_id=%s (stub)\n", app_id ? app_id : "NULL");
}

static void activation_token_set_surface(struct wl_client *client, struct wl_resource *resource, struct wl_resource *surface) {
    (void)client;
    (void)resource;
    (void)surface;
    log_printf("[XDG_ACTIVATION] ", "token_set_surface() (stub)\n");
}

static void activation_token_commit(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct activation_token_data *data = wl_resource_get_user_data(resource);
    if (!data) return;
    if (data->token[0] == '\0') {
        uint64_t value = activation_token_counter++;
        snprintf(data->token, sizeof(data->token), "stub-token-%llu", (unsigned long long)value);
    }
    log_printf("[XDG_ACTIVATION] ", "token_commit() - issuing token %s\n", data->token);
    xdg_activation_token_v1_send_done(resource, data->token);
}

static void activation_token_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void activation_token_resource_destroy(struct wl_resource *resource) {
    struct activation_token_data *data = wl_resource_get_user_data(resource);
    if (data) {
        free(data);
    }
}

static const struct xdg_activation_token_v1_interface activation_token_interface = {
    .set_serial = activation_token_set_serial,
    .set_app_id = activation_token_set_app_id,
    .set_surface = activation_token_set_surface,
    .commit = activation_token_commit,
    .destroy = activation_token_destroy,
};

static void activation_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void activation_get_activation_token(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct activation_token_data *data = calloc(1, sizeof(*data));
    if (!data) {
        wl_client_post_no_memory(client);
        return;
    }

    struct wl_resource *token = wl_resource_create(client, &xdg_activation_token_v1_interface, wl_resource_get_version(resource), id);
    if (!token) {
        free(data);
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(token, &activation_token_interface, data, activation_token_resource_destroy);
    log_printf("[XDG_ACTIVATION] ", "Created activation token resource %p\n", (void *)token);
}

// Forward declarations
extern struct wl_seat_impl *global_seat;
extern struct wl_compositor_impl *global_compositor;
bool xdg_surface_is_toplevel(struct wl_surface_impl *wl_surface);
extern void macos_compositor_activate_window(void);
extern struct xdg_surface_impl *xdg_surfaces;

static void activation_activate(struct wl_client *client, struct wl_resource *resource, const char *token, struct wl_resource *surface) {
    (void)client;
    (void)resource;
    (void)token; // Token validation could be added later
    
    if (!surface) {
        log_printf("[XDG_ACTIVATION] ", "activate() called with NULL surface\n");
        return;
    }
    
    // Get the wl_surface_impl from the surface resource
    struct wl_surface_impl *wl_surface = wl_resource_get_user_data(surface);
    if (!wl_surface) {
        log_printf("[XDG_ACTIVATION] ", "activate() - surface resource has no user_data\n");
        return;
    }
    
    // Verify this is a toplevel surface
    if (!xdg_surface_is_toplevel(wl_surface)) {
        log_printf("[XDG_ACTIVATION] ", "activate() - surface is not a toplevel, ignoring\n");
        return;
    }
    
    log_printf("[XDG_ACTIVATION] ", "activate() - activating toplevel surface %p with token=%s\n", 
               (void *)wl_surface, token ? token : "NULL");
    
    // Set focus to this surface
    if (global_seat) {
        // Send leave events to previously focused surface
        struct wl_surface_impl *prev_focused = (struct wl_surface_impl *)global_seat->focused_surface;
        if (prev_focused && prev_focused != wl_surface && prev_focused->resource) {
            uint32_t serial = wl_seat_get_serial(global_seat);
            if (global_seat->keyboard_resource) {
                wl_seat_send_keyboard_leave(global_seat, prev_focused->resource, serial);
            }
            if (global_seat->pointer_resource) {
                wl_seat_send_pointer_leave(global_seat, prev_focused->resource, serial);
            }
        }
        
        // Set focus to the activated surface
        wl_seat_set_focused_surface(global_seat, wl_surface);
        
        // Send enter events to the activated surface
        if (global_seat->keyboard_resource && wl_surface->resource) {
            uint32_t serial = wl_seat_get_serial(global_seat);
            struct wl_array keys;
            wl_array_init(&keys);
            wl_seat_send_keyboard_enter(global_seat, wl_surface->resource, serial, &keys);
            wl_array_release(&keys);
        }
        
        if (global_seat->pointer_resource && wl_surface->resource) {
            uint32_t serial = wl_seat_get_serial(global_seat);
            double x = wl_surface->buffer_width > 0 ? wl_surface->buffer_width / 2.0 : 200.0;
            double y = wl_surface->buffer_height > 0 ? wl_surface->buffer_height / 2.0 : 150.0;
            wl_seat_send_pointer_enter(global_seat, wl_surface->resource, serial, x, y);
        }
    }
    
    // Raise window on macOS (make it key and frontmost)
    macos_compositor_activate_window();
    
    // Send configure event with ACTIVATED state to the toplevel
    // Find the xdg_toplevel associated with this surface
    struct xdg_surface_impl *xdg_surface = xdg_surfaces;
    while (xdg_surface) {
        if (xdg_surface->wl_surface == wl_surface && xdg_surface->role) {
            struct xdg_toplevel_impl *toplevel = (struct xdg_toplevel_impl *)xdg_surface->role;
            if (toplevel && toplevel->resource) {
                // Add ACTIVATED state
                toplevel->states |= XDG_TOPLEVEL_STATE_ACTIVATED;
                
                // Send configure event with ACTIVATED state
                int32_t width = toplevel->width > 0 ? toplevel->width : 800;
                int32_t height = toplevel->height > 0 ? toplevel->height : 600;
                
                struct wl_array states;
                wl_array_init(&states);
                uint32_t *state = wl_array_add(&states, sizeof(uint32_t));
                if (state) {
                    *state = XDG_TOPLEVEL_STATE_ACTIVATED;
                }
                
                uint32_t serial = ++xdg_surface->configure_serial;
                // Send configure events (using same pattern as xdg_shell.c)
                xdg_toplevel_send_configure(toplevel->resource, width, height, &states);
                xdg_surface_send_configure(xdg_surface->resource, serial);
                xdg_surface->configure_serial = serial;
                toplevel->width = width;
                toplevel->height = height;
                wl_array_release(&states);
                
                log_printf("[XDG_ACTIVATION] ", "activate() - sent configure with ACTIVATED state to toplevel %p\n", (void *)toplevel);
                break;
            }
        }
        xdg_surface = xdg_surface->next;
    }
}

static const struct xdg_activation_v1_interface activation_interface = {
    .destroy = activation_destroy,
    .get_activation_token = activation_get_activation_token,
    .activate = activation_activate,
};

static void activation_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &xdg_activation_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &activation_interface, data, NULL);
    log_printf("[XDG_ACTIVATION] ", "activation_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
}

struct wl_activation_manager_impl *wl_activation_create(struct wl_display *display) {
    struct wl_activation_manager_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) return NULL;

    manager->display = display;
    manager->global = wl_global_create(display, &xdg_activation_v1_interface, 1, manager, activation_bind);
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    return manager;
}

void wl_activation_destroy(struct wl_activation_manager_impl *manager) {
    if (!manager) return;
    wl_global_destroy(manager->global);
    free(manager);
}

// ============================================================================
// Fractional Scale Protocol (wp_fractional_scale_manager_v1)
// ============================================================================

static void fractional_scale_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static const struct wp_fractional_scale_v1_interface fractional_scale_interface = {
    .destroy = fractional_scale_destroy,
};

static void fractional_scale_manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void fractional_scale_manager_get_fractional_scale(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface) {
    (void)surface;
    struct wl_resource *scale = wl_resource_create(client, &wp_fractional_scale_v1_interface, wl_resource_get_version(resource), id);
    if (!scale) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(scale, &fractional_scale_interface, NULL, NULL);
    
    // Detect macOS Retina display scale factor
    // Fractional scale is in 1/120ths: 120 = 1.0x, 240 = 2.0x, 180 = 1.5x, etc.
    uint32_t preferred_scale = 120; // Default to 1.0x
    
    // Detect macOS Retina display scale factor using CoreGraphics
    // This avoids needing Objective-C runtime in C file
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Use default scale (typically 2.0x for Retina)
    CGFloat backingScale = 2.0; // iOS devices typically have Retina displays
    // Convert CGFloat scale to 120ths (e.g., 2.0 -> 240, 1.5 -> 180)
    preferred_scale = (uint32_t)(backingScale * 120.0);
    // Clamp to reasonable values (between 120 and 480 = 1.0x to 4.0x)
    if (preferred_scale < 120) preferred_scale = 120;
    if (preferred_scale > 480) preferred_scale = 480;
#else
    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    if (mainDisplay != kCGNullDirectDisplay) {
        CGSize physicalSize = CGDisplayScreenSize(mainDisplay);
        CGSize pixelSize;
        pixelSize.width = CGDisplayPixelsWide(mainDisplay);
        pixelSize.height = CGDisplayPixelsHigh(mainDisplay);
        
        if (physicalSize.width > 0 && pixelSize.width > 0) {
            // Calculate DPI and determine if Retina (typically > 200 DPI)
            CGFloat dpi = (pixelSize.width / physicalSize.width) * 25.4; // Convert to DPI
            // Retina displays typically have 2.0x scale factor
            CGFloat backingScale = (dpi > 200) ? 2.0 : 1.0;
            // Convert CGFloat scale to 120ths (e.g., 2.0 -> 240, 1.5 -> 180)
            preferred_scale = (uint32_t)(backingScale * 120.0);
            // Clamp to reasonable values (between 120 and 480 = 1.0x to 4.0x)
            if (preferred_scale < 120) preferred_scale = 120;
            if (preferred_scale > 480) preferred_scale = 480;
        }
    }
#endif
    
    wp_fractional_scale_v1_send_preferred_scale(scale, preferred_scale);
    log_printf("[FRACTIONAL_SCALE] ", "get_fractional_scale() - created resource %u with scale=%u (%.2fx)\n", id, preferred_scale, preferred_scale / 120.0);
}

static const struct wp_fractional_scale_manager_v1_interface fractional_scale_manager_interface = {
    .destroy = fractional_scale_manager_destroy,
    .get_fractional_scale = fractional_scale_manager_get_fractional_scale,
};

static void fractional_scale_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wp_fractional_scale_manager_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &fractional_scale_manager_interface, data, NULL);
    log_printf("[FRACTIONAL_SCALE] ", "fractional_scale_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
}

struct wl_fractional_scale_manager_impl *wl_fractional_scale_create(struct wl_display *display) {
    struct wl_fractional_scale_manager_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) return NULL;

    manager->display = display;
    manager->global = wl_global_create(display, &wp_fractional_scale_manager_v1_interface, 1, manager, fractional_scale_bind);
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    return manager;
}

void wl_fractional_scale_destroy(struct wl_fractional_scale_manager_impl *manager) {
    if (!manager) return;
    wl_global_destroy(manager->global);
    free(manager);
}

// ============================================================================
// Cursor Shape Protocol (wp_cursor_shape_manager_v1)
// ============================================================================

static void cursor_shape_device_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

// Forward declaration for cursor setting function (implemented in cursor_shape_bridge.m)
extern void set_macos_cursor_shape(uint32_t shape);

static void cursor_shape_device_set_shape(struct wl_client *client, struct wl_resource *resource, uint32_t serial, uint32_t shape) {
    (void)client;
    (void)resource;
    
    // Call Objective-C bridge function to set macOS cursor
    set_macos_cursor_shape(shape);
    log_printf("[CURSOR_SHAPE] ", "set_shape() - serial=%u, shape=%u\n", serial, shape);
}

static const struct wp_cursor_shape_device_v1_interface cursor_shape_device_interface = {
    .destroy = cursor_shape_device_destroy,
    .set_shape = cursor_shape_device_set_shape,
};

static void cursor_shape_manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void cursor_shape_manager_get_pointer(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *pointer) {
    (void)pointer;
    struct wl_resource *device = wl_resource_create(client, &wp_cursor_shape_device_v1_interface, wl_resource_get_version(resource), id);
    if (!device) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(device, &cursor_shape_device_interface, NULL, NULL);
    log_printf("[CURSOR_SHAPE] ", "get_pointer() - created device id=%u\n", id);
}

static void cursor_shape_manager_get_tablet_tool(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *tablet_tool) {
    (void)tablet_tool;
    struct wl_resource *device = wl_resource_create(client, &wp_cursor_shape_device_v1_interface, wl_resource_get_version(resource), id);
    if (!device) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(device, &cursor_shape_device_interface, NULL, NULL);
    log_printf("[CURSOR_SHAPE] ", "get_tablet_tool_v2() - created device id=%u\n", id);
}

static const struct wp_cursor_shape_manager_v1_interface cursor_shape_manager_interface = {
    .destroy = cursor_shape_manager_destroy,
    .get_pointer = cursor_shape_manager_get_pointer,
    .get_tablet_tool_v2 = cursor_shape_manager_get_tablet_tool,
};

static void cursor_shape_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wp_cursor_shape_manager_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &cursor_shape_manager_interface, data, NULL);
    log_printf("[CURSOR_SHAPE] ", "cursor_shape_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
}

struct wl_cursor_shape_manager_impl *wl_cursor_shape_create(struct wl_display *display) {
    struct wl_cursor_shape_manager_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) return NULL;

    manager->display = display;
    manager->global = wl_global_create(display, &wp_cursor_shape_manager_v1_interface, 1, manager, cursor_shape_bind);
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    return manager;
}

void wl_cursor_shape_destroy(struct wl_cursor_shape_manager_impl *manager) {
    if (!manager) return;
    wl_global_destroy(manager->global);
    free(manager);
}

// ============================================================================
// XDG Decoration Protocol (zxdg_decoration_manager_v1)
// ============================================================================

static void decoration_manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void toplevel_decoration_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

// Forward declaration
struct xdg_toplevel_impl;
extern struct xdg_surface_impl *xdg_surfaces;
struct xdg_toplevel_impl *find_toplevel_from_decoration_resource(struct wl_resource *decoration_resource);

// Helper to find toplevel from decoration resource
struct xdg_toplevel_impl *find_toplevel_from_decoration_resource(struct wl_resource *decoration_resource) {
    // Decoration resource user_data stores the toplevel pointer directly
    return (struct xdg_toplevel_impl *)wl_resource_get_user_data(decoration_resource);
}

static void toplevel_decoration_set_mode(struct wl_client *client, struct wl_resource *resource, uint32_t mode) {
    (void)client;
    
    // Find the toplevel associated with this decoration
    struct xdg_toplevel_impl *toplevel = find_toplevel_from_decoration_resource(resource);
    
    if (mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE) {
        log_printf("[DECORATION] ", "toplevel_decoration_set_mode() - CLIENT_SIDE requested for toplevel %p\n", (void *)toplevel);
        
        // SUPPORT CSD: Allow CLIENT_SIDE decorations
        // When CSD is requested, hide macOS window decorations (titlebar, etc.)
        if (toplevel) {
            toplevel->decoration_mode = ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
            
            // Notify macOS backend to hide window decorations for this toplevel
            // We'll need a callback to macos_backend to hide decorations
            extern void macos_compositor_set_csd_mode_for_toplevel(struct xdg_toplevel_impl *toplevel, bool csd);
            macos_compositor_set_csd_mode_for_toplevel(toplevel, true);
        }
        
        // Send configure event to accept CLIENT_SIDE mode
        zxdg_toplevel_decoration_v1_send_configure(resource, mode);
        log_printf("[DECORATION] ", "toplevel_decoration_set_mode() - CLIENT_SIDE mode accepted (macOS decorations will be hidden)\n");
        return;
    }
    
    // SERVER_SIDE mode - show macOS window decorations (unless fullscreen)
    if (toplevel) {
        toplevel->decoration_mode = ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
        
        // Check if this is a nested compositor or fullscreen
        struct wl_client *nested_client = nested_compositor_client_from_xdg_shell();
        bool is_nested_compositor = (nested_client == wl_resource_get_client(resource));
        bool is_fullscreen = (toplevel->states & XDG_TOPLEVEL_STATE_FULLSCREEN) != 0;
        
        // Hide macOS decorations for nested compositors or fullscreen toplevels
        extern void macos_compositor_set_csd_mode_for_toplevel(struct xdg_toplevel_impl *toplevel, bool csd);
        if (is_nested_compositor || is_fullscreen) {
            macos_compositor_set_csd_mode_for_toplevel(toplevel, true); // Hide decorations
            log_printf("[DECORATION] ", "toplevel_decoration_set_mode() - SERVER_SIDE mode (macOS decorations hidden for nested/fullscreen)\n");
        } else {
            macos_compositor_set_csd_mode_for_toplevel(toplevel, false); // Show decorations
            log_printf("[DECORATION] ", "toplevel_decoration_set_mode() - SERVER_SIDE mode accepted (macOS decorations will be shown)\n");
        }
    }
    
    zxdg_toplevel_decoration_v1_send_configure(resource, mode);
}

static void toplevel_decoration_unset_mode(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    (void)resource;
    // Stub: accept but don't implement
    log_printf("[DECORATION] ", "toplevel_decoration_unset_mode() (stub)\n");
}

static const struct zxdg_toplevel_decoration_v1_interface toplevel_decoration_interface = {
    .destroy = toplevel_decoration_destroy,
    .set_mode = toplevel_decoration_set_mode,
    .unset_mode = toplevel_decoration_unset_mode,
};

static void decoration_manager_get_toplevel_decoration(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *toplevel) {
    // Find the xdg_toplevel_impl from the toplevel resource
    struct xdg_toplevel_impl *toplevel_impl = NULL;
    if (toplevel) {
        toplevel_impl = wl_resource_get_user_data(toplevel);
    }
    
    struct wl_resource *decoration = wl_resource_create(client, &zxdg_toplevel_decoration_v1_interface, wl_resource_get_version(resource), id);
    if (!decoration) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // Store toplevel pointer in decoration resource user_data for easy lookup
    wl_resource_set_implementation(decoration, &toplevel_decoration_interface, toplevel_impl, NULL);
    
    // Check if this is a nested compositor
    struct wl_client *nested_client = nested_compositor_client_from_xdg_shell();
    bool is_nested_compositor = (nested_client == client);
    
    // Check if toplevel is fullscreen (nested compositors are always fullscreen)
    bool is_fullscreen = false;
    if (toplevel_impl) {
        // XDG_TOPLEVEL_STATE_FULLSCREEN = 2 (from xdg-shell-protocol.h)
        is_fullscreen = (toplevel_impl->states & XDG_TOPLEVEL_STATE_FULLSCREEN) != 0;
    }
    
    // For nested compositors or fullscreen toplevels, hide macOS decorations
    // We still use SERVER_SIDE mode (for protocol compliance), but hide macOS decorations
    uint32_t decoration_mode = ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
    
    if (toplevel_impl) {
        toplevel_impl->decoration_mode = decoration_mode;
        
        // If nested compositor or fullscreen, hide macOS window decorations
        if (is_nested_compositor || is_fullscreen) {
            extern void macos_compositor_set_csd_mode_for_toplevel(struct xdg_toplevel_impl *toplevel, bool csd);
            macos_compositor_set_csd_mode_for_toplevel(toplevel_impl, true); // true = hide decorations
            log_printf("[DECORATION] ", "get_toplevel_decoration() - nested compositor/fullscreen detected, hiding macOS decorations\n");
        }
    }
    
    if (is_nested_compositor) {
        log_printf("[DECORATION] ", "get_toplevel_decoration() - nested compositor detected, SERVER_SIDE mode (macOS decorations hidden)\n");
    } else {
        log_printf("[DECORATION] ", "get_toplevel_decoration() - regular client, defaulting to SERVER_SIDE mode (client can request CLIENT_SIDE)\n");
    }
    
    zxdg_toplevel_decoration_v1_send_configure(decoration, decoration_mode);
    log_printf("[DECORATION] ", "get_toplevel_decoration() - created decoration id=%u (SERVER_SIDE mode)\n", id);
}

static const struct zxdg_decoration_manager_v1_interface decoration_manager_interface = {
    .destroy = decoration_manager_destroy,
    .get_toplevel_decoration = decoration_manager_get_toplevel_decoration,
};

static void decoration_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    (void)data;
    struct wl_resource *resource = wl_resource_create(client, &zxdg_decoration_manager_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &decoration_manager_interface, NULL, NULL);
    log_printf("[DECORATION] ", "decoration_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
}

struct wl_decoration_manager_impl *wl_decoration_create(struct wl_display *display) {
    struct wl_decoration_manager_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) return NULL;
    
    manager->display = display;
    manager->global = wl_global_create(display, &zxdg_decoration_manager_v1_interface, 1, manager, decoration_bind);
    
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    
    return manager;
}

void wl_decoration_destroy(struct wl_decoration_manager_impl *manager) {
    if (!manager) return;
    
    wl_global_destroy(manager->global);
    free(manager);
}

// ============================================================================
// XDG Toplevel Icon Protocol (xdg_toplevel_icon_manager_v1)
// ============================================================================

static void toplevel_icon_manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void toplevel_icon_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void toplevel_icon_set_name(struct wl_client *client, struct wl_resource *resource, const char *name) {
    (void)client;
    (void)resource;
    (void)name;
    // Stub: accept but don't implement icon names
    log_printf("[TOPLEVEL_ICON] ", "icon_set_name() - name=%s (stub)\n", name ? name : "NULL");
}

static void toplevel_icon_add_buffer(struct wl_client *client, struct wl_resource *resource, struct wl_resource *buffer, int32_t scale) {
    (void)client;
    (void)resource;
    (void)buffer;
    (void)scale;
    // Stub: accept but don't implement icon buffers
    log_printf("[TOPLEVEL_ICON] ", "icon_add_buffer() - scale=%d (stub)\n", scale);
}

static const struct xdg_toplevel_icon_v1_interface toplevel_icon_interface = {
    .destroy = toplevel_icon_destroy,
    .set_name = toplevel_icon_set_name,
    .add_buffer = toplevel_icon_add_buffer,
};

static void toplevel_icon_manager_create_icon(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct wl_resource *icon = wl_resource_create(client, &xdg_toplevel_icon_v1_interface, wl_resource_get_version(resource), id);
    if (!icon) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(icon, &toplevel_icon_interface, NULL, NULL);
    log_printf("[TOPLEVEL_ICON] ", "create_icon() - created icon id=%u\n", id);
}

static void toplevel_icon_manager_set_icon(struct wl_client *client, struct wl_resource *resource, struct wl_resource *toplevel, struct wl_resource *icon) {
    (void)client;
    (void)resource;
    (void)toplevel;
    (void)icon;
    // Stub: accept but don't implement setting icon on toplevel
    log_printf("[TOPLEVEL_ICON] ", "manager_set_icon() (stub)\n");
}

static const struct xdg_toplevel_icon_manager_v1_interface toplevel_icon_manager_interface = {
    .destroy = toplevel_icon_manager_destroy,
    .create_icon = toplevel_icon_manager_create_icon,
    .set_icon = toplevel_icon_manager_set_icon,
};

static void toplevel_icon_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    (void)data;
    struct wl_resource *resource = wl_resource_create(client, &xdg_toplevel_icon_manager_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &toplevel_icon_manager_interface, NULL, NULL);
    log_printf("[TOPLEVEL_ICON] ", "toplevel_icon_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
}

struct wl_toplevel_icon_manager_impl *wl_toplevel_icon_create(struct wl_display *display) {
    struct wl_toplevel_icon_manager_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) return NULL;
    
    manager->display = display;
    manager->global = wl_global_create(display, &xdg_toplevel_icon_manager_v1_interface, 1, manager, toplevel_icon_bind);
    
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    
    return manager;
}

void wl_toplevel_icon_destroy(struct wl_toplevel_icon_manager_impl *manager) {
    if (!manager) return;
    
    wl_global_destroy(manager->global);
    free(manager);
}

// ============================================================================
// Text Input Protocol (zwp_text_input_manager_v3)
// ============================================================================

struct text_input_data {
    uint32_t serial;
    bool enabled;
    struct wl_resource *surface_resource;  // Surface this text input is for
    char *surrounding_text;
    int32_t cursor;
    int32_t anchor;
    uint32_t content_hint;
    uint32_t content_purpose;
    int32_t cursor_rect_x, cursor_rect_y, cursor_rect_width, cursor_rect_height;
};

// Global text input state
static struct wl_resource *current_text_input = NULL;
static struct wl_resource *current_text_input_surface = NULL;

static void text_input_resource_destroy(struct wl_resource *resource) {
    struct text_input_data *data = wl_resource_get_user_data(resource);
    if (data) {
        if (data->surrounding_text) {
            free(data->surrounding_text);
        }
        if (current_text_input == resource) {
            current_text_input = NULL;
            current_text_input_surface = NULL;
        }
        free(data);
    }
}

static void text_input_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void text_input_enable(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct text_input_data *data = wl_resource_get_user_data(resource);
    if (!data) return;
    
    // If another text input is already enabled, ignore this request
    // (protocol requires only one enabled text input per seat)
    if (current_text_input && current_text_input != resource) {
        struct text_input_data *current_data = wl_resource_get_user_data(current_text_input);
        if (current_data && current_data->enabled) {
            log_printf("[TEXT_INPUT] ", "enable() - ignoring, another text input already enabled\n");
            return;
        }
    }
    
    data->enabled = true;
    current_text_input = resource;
    
    // If we have a focused surface, send enter event immediately
    extern struct wl_seat_impl *global_seat;
    if (global_seat && global_seat->focused_surface) {
        struct wl_surface_impl *focused = (struct wl_surface_impl *)global_seat->focused_surface;
        if (focused && focused->resource) {
            wl_text_input_send_enter(focused->resource);
        }
    }
    
    log_printf("[TEXT_INPUT] ", "enable() - text input enabled (resource=%p)\n", (void *)resource);
}

static void text_input_disable(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct text_input_data *data = wl_resource_get_user_data(resource);
    if (!data) return;
    
    data->enabled = false;
    // Send leave event if this text input is currently active
    if (current_text_input == resource && current_text_input_surface) {
        zwp_text_input_v3_send_leave(resource, current_text_input_surface);
        current_text_input = NULL;
        current_text_input_surface = NULL;
    }
    log_printf("[TEXT_INPUT] ", "disable() - text input disabled\n");
}

static void text_input_set_surrounding_text(struct wl_client *client, struct wl_resource *resource, const char *text, int32_t cursor, int32_t anchor) {
    (void)client;
    struct text_input_data *data = wl_resource_get_user_data(resource);
    if (!data) return;
    
    // Store surrounding text
    if (data->surrounding_text) {
        free(data->surrounding_text);
    }
    data->surrounding_text = text ? strdup(text) : NULL;
    data->cursor = cursor;
    data->anchor = anchor;
    
    log_printf("[TEXT_INPUT] ", "set_surrounding_text() - cursor=%d, anchor=%d\n", cursor, anchor);
}

static void text_input_set_text_change_cause(struct wl_client *client, struct wl_resource *resource, uint32_t cause) {
    (void)client;
    (void)resource;
    (void)cause;
    // Store cause for IME context
    log_printf("[TEXT_INPUT] ", "set_text_change_cause() - cause=%u\n", cause);
}

static void text_input_set_content_type(struct wl_client *client, struct wl_resource *resource, uint32_t hint, uint32_t purpose) {
    (void)client;
    struct text_input_data *data = wl_resource_get_user_data(resource);
    if (!data) return;
    
    data->content_hint = hint;
    data->content_purpose = purpose;
    
    log_printf("[TEXT_INPUT] ", "set_content_type() - hint=%u, purpose=%u\n", hint, purpose);
}

static void text_input_set_cursor_rectangle(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)client;
    struct text_input_data *data = wl_resource_get_user_data(resource);
    if (!data) return;
    
    data->cursor_rect_x = x;
    data->cursor_rect_y = y;
    data->cursor_rect_width = width;
    data->cursor_rect_height = height;
    
    log_printf("[TEXT_INPUT] ", "set_cursor_rectangle() - x=%d, y=%d, w=%d, h=%d\n", x, y, width, height);
}

static void text_input_commit(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct text_input_data *data = wl_resource_get_user_data(resource);
    if (!data) return;
    data->serial++;
    zwp_text_input_v3_send_done(resource, data->serial);
    log_printf("[TEXT_INPUT] ", "commit() - serial=%u\n", data->serial);
}

static const struct zwp_text_input_v3_interface text_input_interface = {
    .destroy = text_input_destroy,
    .enable = text_input_enable,
    .disable = text_input_disable,
    .set_surrounding_text = text_input_set_surrounding_text,
    .set_text_change_cause = text_input_set_text_change_cause,
    .set_content_type = text_input_set_content_type,
    .set_cursor_rectangle = text_input_set_cursor_rectangle,
    .commit = text_input_commit,
};

static void text_input_manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void text_input_manager_get_text_input(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *seat) {
    (void)seat;
    struct text_input_data *data = calloc(1, sizeof(*data));
    if (!data) {
        wl_client_post_no_memory(client);
        return;
    }
    
    data->enabled = false;
    data->surrounding_text = NULL;
    data->cursor = 0;
    data->anchor = 0;
    data->content_hint = 0;
    data->content_purpose = 0;
    data->cursor_rect_x = data->cursor_rect_y = data->cursor_rect_width = data->cursor_rect_height = 0;
    data->surface_resource = NULL;

    struct wl_resource *text_input = wl_resource_create(client, &zwp_text_input_v3_interface, wl_resource_get_version(resource), id);
    if (!text_input) {
        free(data);
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(text_input, &text_input_interface, data, text_input_resource_destroy);
    
    // Set as current text input if none exists
    // In a full implementation, we'd track text inputs per seat
    if (!current_text_input) {
        current_text_input = text_input;
    }
    
    log_printf("[TEXT_INPUT] ", "get_text_input() - created text input id=%u\n", id);
}

// Helper functions to send text input events
void wl_text_input_send_enter(struct wl_resource *surface) {
    if (!surface) return;
    
    // Find the enabled text input for this surface's client
    struct wl_client *surface_client = wl_resource_get_client(surface);
    if (!surface_client) return;
    
    // If we have a current text input, check if it belongs to the same client
    if (current_text_input) {
        struct wl_client *text_input_client = wl_resource_get_client(current_text_input);
        if (text_input_client == surface_client) {
            struct text_input_data *data = wl_resource_get_user_data(current_text_input);
            if (data && data->enabled) {
                // Send enter event
                zwp_text_input_v3_send_enter(current_text_input, surface);
                current_text_input_surface = surface;
                data->surface_resource = surface;
                log_printf("[TEXT_INPUT] ", "send_enter() - surface=%p, text_input=%p\n", (void *)surface, (void *)current_text_input);
                return;
            }
        }
    }
    
    // No enabled text input for this client, silently ignore
    log_printf("[TEXT_INPUT] ", "send_enter() - no enabled text input for surface %p\n", (void *)surface);
}

void wl_text_input_send_leave(struct wl_resource *surface) {
    if (!surface) return;
    
    // Only send leave if this surface currently has text input focus
    if (current_text_input && current_text_input_surface == surface) {
        struct text_input_data *data = wl_resource_get_user_data(current_text_input);
        if (data && data->enabled) {
            // Send leave event
            zwp_text_input_v3_send_leave(current_text_input, surface);
            current_text_input_surface = NULL;
            data->surface_resource = NULL;
            log_printf("[TEXT_INPUT] ", "send_leave() - surface=%p, text_input=%p\n", (void *)surface, (void *)current_text_input);
        }
    }
}

void wl_text_input_send_commit_string(const char *text) {
    if (!current_text_input || !current_text_input_surface || !text) return;
    
    struct text_input_data *data = wl_resource_get_user_data(current_text_input);
    if (!data || !data->enabled) return;
    
    // Send commit string event
    zwp_text_input_v3_send_commit_string(current_text_input, text);
    log_printf("[TEXT_INPUT] ", "send_commit_string() - text=%s\n", text);
}

void wl_text_input_send_preedit_string(const char *text, int32_t cursor_begin, int32_t cursor_end) {
    if (!current_text_input || !current_text_input_surface) return;
    
    struct text_input_data *data = wl_resource_get_user_data(current_text_input);
    if (!data || !data->enabled) return;
    
    // Send preedit string event
    zwp_text_input_v3_send_preedit_string(current_text_input, text ? text : "", cursor_begin, cursor_end);
    log_printf("[TEXT_INPUT] ", "send_preedit_string() - text=%s, cursor_begin=%d, cursor_end=%d\n", 
               text ? text : "", cursor_begin, cursor_end);
}

static const struct zwp_text_input_manager_v3_interface text_input_manager_interface = {
    .destroy = text_input_manager_destroy,
    .get_text_input = text_input_manager_get_text_input,
};

static void text_input_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &zwp_text_input_manager_v3_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &text_input_manager_interface, data, NULL);
    log_printf("[TEXT_INPUT] ", "text_input_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
}

struct wl_text_input_manager_impl *wl_text_input_create(struct wl_display *display) {
    struct wl_text_input_manager_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) {
        log_printf("[TEXT_INPUT] ", "wl_text_input_create: failed to allocate manager\n");
        return NULL;
    }

    manager->display = display;
    manager->global = wl_global_create(display, &zwp_text_input_manager_v3_interface, 1, manager, text_input_bind);
    if (!manager->global) {
        log_printf("[TEXT_INPUT] ", "wl_text_input_create: failed to create global\n");
        free(manager);
        return NULL;
    }
    
    log_printf("[TEXT_INPUT] ", "wl_text_input_create: created text input manager (global=%p, interface=%s)\n", 
              (void *)manager->global, zwp_text_input_manager_v3_interface.name);
    return manager;
}

void wl_text_input_destroy(struct wl_text_input_manager_impl *manager) {
    if (!manager) return;
    wl_global_destroy(manager->global);
    free(manager);
}

// ============================================================================
// Text Input Protocol v1 (zwp_text_input_manager_v1) - for weston-editor compatibility
// ============================================================================

struct text_input_v1_data {
    uint32_t serial;
    bool enabled;
    struct wl_resource *surface_resource;
    struct wl_resource *seat_resource;
};

static void text_input_v1_resource_destroy(struct wl_resource *resource) {
    struct text_input_v1_data *data = wl_resource_get_user_data(resource);
    if (data) {
        free(data);
    }
}

// Minimal v1 text input implementation - just stubs for compatibility
static void text_input_v1_activate(struct wl_client *client, struct wl_resource *resource,
                                    struct wl_resource *seat, struct wl_resource *surface) {
    (void)client;
    struct text_input_v1_data *data = wl_resource_get_user_data(resource);
    if (data) {
        data->seat_resource = seat;
        data->surface_resource = surface;
        data->enabled = true;
        log_printf("[TEXT_INPUT_V1] ", "text_input_v1_activate() - seat=%p, surface=%p\n",
                   (void *)seat, (void *)surface);
    }
}

static void text_input_v1_deactivate(struct wl_client *client, struct wl_resource *resource,
                                      struct wl_resource *seat) {
    (void)client;
    (void)seat;
    struct text_input_v1_data *data = wl_resource_get_user_data(resource);
    if (data) {
        data->enabled = false;
        log_printf("[TEXT_INPUT_V1] ", "text_input_v1_deactivate()\n");
    }
}

static void text_input_v1_show_input_panel(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    (void)resource;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_show_input_panel()\n");
}

static void text_input_v1_hide_input_panel(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    (void)resource;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_hide_input_panel()\n");
}

static void text_input_v1_reset(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    (void)resource;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_reset()\n");
}

static void text_input_v1_set_surrounding_text(struct wl_client *client, struct wl_resource *resource,
                                                const char *text, uint32_t cursor, uint32_t anchor) {
    (void)client;
    (void)resource;
    (void)text;
    (void)cursor;
    (void)anchor;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_set_surrounding_text()\n");
}

static void text_input_v1_set_content_type(struct wl_client *client, struct wl_resource *resource,
                                            uint32_t hint, uint32_t purpose) {
    (void)client;
    (void)resource;
    (void)hint;
    (void)purpose;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_set_content_type()\n");
}

static void text_input_v1_set_cursor_rectangle(struct wl_client *client, struct wl_resource *resource,
                                                int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)client;
    (void)resource;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_set_cursor_rectangle()\n");
}

static void text_input_v1_set_preferred_language(struct wl_client *client, struct wl_resource *resource,
                                                  const char *language) {
    (void)client;
    (void)resource;
    (void)language;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_set_preferred_language()\n");
}

static void text_input_v1_commit_state(struct wl_client *client, struct wl_resource *resource,
                                        uint32_t serial) {
    (void)client;
    struct text_input_v1_data *data = wl_resource_get_user_data(resource);
    if (data) {
        data->serial = serial;
        log_printf("[TEXT_INPUT_V1] ", "text_input_v1_commit_state() - serial=%u\n", serial);
    }
}

static void text_input_v1_invoke_action(struct wl_client *client, struct wl_resource *resource,
                                         uint32_t button, uint32_t index) {
    (void)client;
    (void)resource;
    (void)button;
    (void)index;
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_invoke_action()\n");
}

static const struct zwp_text_input_v1_interface text_input_v1_interface = {
    .activate = text_input_v1_activate,
    .deactivate = text_input_v1_deactivate,
    .show_input_panel = text_input_v1_show_input_panel,
    .hide_input_panel = text_input_v1_hide_input_panel,
    .reset = text_input_v1_reset,
    .set_surrounding_text = text_input_v1_set_surrounding_text,
    .set_content_type = text_input_v1_set_content_type,
    .set_cursor_rectangle = text_input_v1_set_cursor_rectangle,
    .set_preferred_language = text_input_v1_set_preferred_language,
    .commit_state = text_input_v1_commit_state,
    .invoke_action = text_input_v1_invoke_action,
};

static void text_input_manager_v1_get_text_input(struct wl_client *client, struct wl_resource *resource,
                                                   uint32_t id) {
    log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - START: client=%p, resource=%p, id=%u\n",
              (void *)client, (void *)resource, id);
    
    if (!client) {
        log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - ERROR: client is NULL\n");
        return;
    }
    
    (void)resource;
    log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - allocating data\n");
    struct text_input_v1_data *data = calloc(1, sizeof(*data));
    if (!data) {
        log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - ERROR: failed to allocate data\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - initializing data\n");
    data->enabled = false;
    data->serial = 0;
    data->surface_resource = NULL;
    data->seat_resource = NULL;
    
    log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - creating text input resource\n");
    struct wl_resource *text_input = wl_resource_create(client, &zwp_text_input_v1_interface, 1, id);
    if (!text_input) {
        log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - ERROR: failed to create resource\n");
        free(data);
        wl_client_post_no_memory(client);
        return;
    }
    
    log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - setting implementation\n");
    wl_resource_set_implementation(text_input, &text_input_v1_interface, data, text_input_v1_resource_destroy);
    log_printf("[TEXT_INPUT_V1] ", "text_input_manager_v1_get_text_input() - SUCCESS: text_input=%p, id=%u\n", 
              (void *)text_input, id);
}

static const struct zwp_text_input_manager_v1_interface text_input_manager_v1_interface = {
    .create_text_input = text_input_manager_v1_get_text_input,
};

static void text_input_v1_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_bind() - START: client=%p, version=%u, id=%u, data=%p\n", 
              (void *)client, version, id, (void *)data);
    
    if (!client) {
        log_printf("[TEXT_INPUT_V1] ", "text_input_v1_bind() - ERROR: client is NULL\n");
        return;
    }
    
    if (!data) {
        log_printf("[TEXT_INPUT_V1] ", "text_input_v1_bind() - ERROR: data is NULL\n");
        return;
    }
    
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_bind() - creating resource with interface=%s\n", 
              zwp_text_input_manager_v1_interface.name);
    
    struct wl_resource *resource = wl_resource_create(client, &zwp_text_input_manager_v1_interface, (int)version, id);
    if (!resource) {
        log_printf("[TEXT_INPUT_V1] ", "text_input_v1_bind() - ERROR: failed to create resource\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_bind() - setting implementation\n");
    wl_resource_set_implementation(resource, &text_input_manager_v1_interface, data, NULL);
    log_printf("[TEXT_INPUT_V1] ", "text_input_v1_bind() - SUCCESS: resource=%p\n", (void *)resource);
}

struct wl_text_input_manager_v1_impl *wl_text_input_v1_create(struct wl_display *display) {
    struct wl_text_input_manager_v1_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) {
        log_printf("[TEXT_INPUT_V1] ", "wl_text_input_v1_create: failed to allocate manager\n");
        return NULL;
    }
    
    manager->display = display;
    manager->global = wl_global_create(display, &zwp_text_input_manager_v1_interface, 1, manager, text_input_v1_bind);
    if (!manager->global) {
        log_printf("[TEXT_INPUT_V1] ", "wl_text_input_v1_create: failed to create global\n");
        free(manager);
        return NULL;
    }
    
    log_printf("[TEXT_INPUT_V1] ", "wl_text_input_v1_create: created text input manager v1 (global=%p, interface=%s)\n",
              (void *)manager->global, zwp_text_input_manager_v1_interface.name);
    return manager;
}

void wl_text_input_v1_destroy(struct wl_text_input_manager_v1_impl *manager) {
    if (!manager) return;
    wl_global_destroy(manager->global);
    free(manager);
}
