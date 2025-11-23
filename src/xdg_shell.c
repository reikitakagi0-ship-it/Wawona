#include "xdg_shell.h"
#include "wayland_compositor.h"
#include "logging.h"
#include "xdg-shell-protocol.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Event opcodes for xdg_popup (from xdg-shell.xml)
#define XDG_POPUP_CONFIGURE 0
#define XDG_POPUP_POPUP_DONE 1
#define XDG_POPUP_REPOSITIONED 2

static void xdg_wm_base_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
static void xdg_wm_base_destroy_handler(struct wl_client *client, struct wl_resource *resource);
static void xdg_wm_base_create_positioner(struct wl_client *client, struct wl_resource *resource, uint32_t id);
static void xdg_wm_base_get_xdg_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface);
static void xdg_wm_base_pong(struct wl_client *client, struct wl_resource *resource, uint32_t serial);

static const struct xdg_wm_base_interface xdg_wm_base_impl_interface = {
    .destroy = xdg_wm_base_destroy_handler,
    .create_positioner = xdg_wm_base_create_positioner,
    .get_xdg_surface = xdg_wm_base_get_xdg_surface,
    .pong = xdg_wm_base_pong,
};

static void xdg_surface_destroy_handler(struct wl_client *client, struct wl_resource *resource);
static void xdg_surface_get_toplevel(struct wl_client *client, struct wl_resource *resource, uint32_t id);
static void xdg_surface_get_popup(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *parent, struct wl_resource *positioner);
static void xdg_surface_set_window_geometry(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height);
static void xdg_surface_ack_configure(struct wl_client *client, struct wl_resource *resource, uint32_t serial);

static void xdg_popup_destroy_handler(struct wl_client *client, struct wl_resource *resource);
static void xdg_popup_grab(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial);
static void xdg_popup_reposition(struct wl_client *client, struct wl_resource *resource, struct wl_resource *positioner, uint32_t token);

static const struct xdg_surface_interface xdg_surface_impl_interface = {
    .destroy = xdg_surface_destroy_handler,
    .get_toplevel = xdg_surface_get_toplevel,
    .get_popup = xdg_surface_get_popup,
    .set_window_geometry = xdg_surface_set_window_geometry,
    .ack_configure = xdg_surface_ack_configure,
};

static const struct xdg_popup_interface xdg_popup_impl_interface = {
    .destroy = xdg_popup_destroy_handler,
    .grab = xdg_popup_grab,
    .reposition = xdg_popup_reposition,
};

static void xdg_toplevel_destroy_handler(struct wl_client *client, struct wl_resource *resource);
static void xdg_toplevel_set_parent(struct wl_client *client, struct wl_resource *resource, struct wl_resource *parent);
static void xdg_toplevel_set_title(struct wl_client *client, struct wl_resource *resource, const char *title);
static void xdg_toplevel_set_app_id(struct wl_client *client, struct wl_resource *resource, const char *app_id);
static void xdg_toplevel_show_window_menu(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial, int32_t x, int32_t y);
static void xdg_toplevel_move(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial);
static void xdg_toplevel_resize(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial, uint32_t edges);
static void xdg_toplevel_set_max_size(struct wl_client *client, struct wl_resource *resource, int32_t width, int32_t height);
static void xdg_toplevel_set_min_size(struct wl_client *client, struct wl_resource *resource, int32_t width, int32_t height);
static void xdg_toplevel_set_maximized(struct wl_client *client, struct wl_resource *resource);
static void xdg_toplevel_unset_maximized(struct wl_client *client, struct wl_resource *resource);
static void xdg_toplevel_set_fullscreen(struct wl_client *client, struct wl_resource *resource, struct wl_resource *output);
static void xdg_toplevel_unset_fullscreen(struct wl_client *client, struct wl_resource *resource);
static void xdg_toplevel_set_minimized(struct wl_client *client, struct wl_resource *resource);

static const struct xdg_toplevel_interface xdg_toplevel_impl_interface = {
    .destroy = xdg_toplevel_destroy_handler,
    .set_parent = xdg_toplevel_set_parent,
    .set_title = xdg_toplevel_set_title,
    .set_app_id = xdg_toplevel_set_app_id,
    .show_window_menu = xdg_toplevel_show_window_menu,
    .move = xdg_toplevel_move,
    .resize = xdg_toplevel_resize,
    .set_max_size = xdg_toplevel_set_max_size,
    .set_min_size = xdg_toplevel_set_min_size,
    .set_maximized = xdg_toplevel_set_maximized,
    .unset_maximized = xdg_toplevel_unset_maximized,
    .set_fullscreen = xdg_toplevel_set_fullscreen,
    .unset_fullscreen = xdg_toplevel_unset_fullscreen,
    .set_minimized = xdg_toplevel_set_minimized,
};

// Global list of xdg surfaces
struct xdg_surface_impl *xdg_surfaces = NULL;

// Track nested compositor clients (like Weston) that should be fullscreen
// This is set when a client binds to wl_compositor (detected in compositor_bind)
static struct wl_client *nested_compositor_client = NULL;

// Function to mark a client as a nested compositor (called from compositor_bind)
void xdg_shell_mark_nested_compositor(struct wl_client *client) {
    nested_compositor_client = client;
    log_printf("[XDG_SHELL] ", "Marked client %p as nested compositor (will auto-fullscreen toplevels, no decorations)\n", (void *)client);
}

// Function to get nested compositor client (for use by other modules like decoration manager)
struct wl_client *nested_compositor_client_from_xdg_shell(void) {
    return nested_compositor_client;
}

struct xdg_wm_base_impl *xdg_wm_base_create(struct wl_display *display) {
    struct xdg_wm_base_impl *wm_base = calloc(1, sizeof(*wm_base));
    if (!wm_base) return NULL;
    
    wm_base->display = display;
    wm_base->version = 7; // xdg-shell version 7 (latest, supports all modern features)
    wm_base->output_width = 800;  // Default size
    wm_base->output_height = 600;
    
    wm_base->global = wl_global_create(display, &xdg_wm_base_interface, (int)wm_base->version, wm_base, xdg_wm_base_bind);
    
    if (!wm_base->global) {
        free(wm_base);
        return NULL;
    }
    
    return wm_base;
}

void xdg_wm_base_set_output_size(struct xdg_wm_base_impl *wm_base, int32_t width, int32_t height) {
    if (!wm_base) return;
    wm_base->output_width = width;
    wm_base->output_height = height;
}

void xdg_wm_base_destroy(struct xdg_wm_base_impl *wm_base) {
    if (!wm_base) return;
    
    wl_global_destroy(wm_base->global);
    free(wm_base);
}

static void xdg_wm_base_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    log_printf("[COMPOSITOR] ", "xdg_wm_base_bind() - client=%p, version=%u, id=%u\n", 
               (void *)client, version, id);
    struct xdg_wm_base_impl *wm_base = data;
    struct wl_resource *resource = wl_resource_create(client, &xdg_wm_base_interface, (int)version, id);
    
    if (!resource) {
        log_printf("[COMPOSITOR] ", "xdg_wm_base_bind() - failed to create resource\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(resource, &xdg_wm_base_impl_interface, wm_base, NULL);
    log_printf("[COMPOSITOR] ", "xdg_wm_base_bind() - resource created successfully\n");
}

static void xdg_wm_base_destroy_handler(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

// Positioner implementation
struct xdg_positioner_impl {
    struct wl_resource *resource;
    int32_t x, y;
    int32_t width, height;
    int32_t anchor_rect_x, anchor_rect_y, anchor_rect_width, anchor_rect_height;
    uint32_t anchor;
    uint32_t gravity;
    uint32_t constraint_adjustment;
    int32_t offset_x, offset_y;
    bool reactive;
    int32_t parent_size_width, parent_size_height;
    int32_t parent_configure_serial;
};

static struct xdg_positioner_impl *positioner_from_resource(struct wl_resource *resource) {
    return wl_resource_get_user_data(resource);
}

static void positioner_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    free(positioner);
    wl_resource_destroy(resource);
}

static void positioner_set_size(struct wl_client *client, struct wl_resource *resource,
                                int32_t width, int32_t height) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->width = width;
        positioner->height = height;
    }
}

static void positioner_set_anchor_rect(struct wl_client *client, struct wl_resource *resource,
                                       int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->anchor_rect_x = x;
        positioner->anchor_rect_y = y;
        positioner->anchor_rect_width = width;
        positioner->anchor_rect_height = height;
    }
}

static void positioner_set_anchor(struct wl_client *client, struct wl_resource *resource,
                                  uint32_t anchor) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->anchor = anchor;
    }
}

static void positioner_set_gravity(struct wl_client *client, struct wl_resource *resource,
                                   uint32_t gravity) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->gravity = gravity;
    }
}

static void positioner_set_constraint_adjustment(struct wl_client *client, struct wl_resource *resource,
                                                 uint32_t constraint_adjustment) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->constraint_adjustment = constraint_adjustment;
    }
}

static void positioner_set_offset(struct wl_client *client, struct wl_resource *resource,
                                  int32_t x, int32_t y) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->offset_x = x;
        positioner->offset_y = y;
    }
}

static void positioner_set_reactive(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->reactive = true;
    }
}

static void positioner_set_parent_size(struct wl_client *client, struct wl_resource *resource,
                                       int32_t parent_size_width, int32_t parent_size_height) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->parent_size_width = parent_size_width;
        positioner->parent_size_height = parent_size_height;
    }
}

static void positioner_set_parent_configure(struct wl_client *client, struct wl_resource *resource,
                                            uint32_t serial) {
    (void)client;
    struct xdg_positioner_impl *positioner = positioner_from_resource(resource);
    if (positioner) {
        positioner->parent_configure_serial = (int32_t)serial;
    }
}

static const struct xdg_positioner_interface positioner_interface = {
    .destroy = positioner_destroy,
    .set_size = positioner_set_size,
    .set_anchor_rect = positioner_set_anchor_rect,
    .set_anchor = positioner_set_anchor,
    .set_gravity = positioner_set_gravity,
    .set_constraint_adjustment = positioner_set_constraint_adjustment,
    .set_offset = positioner_set_offset,
    .set_reactive = positioner_set_reactive,
    .set_parent_size = positioner_set_parent_size,
    .set_parent_configure = positioner_set_parent_configure,
};

static void xdg_wm_base_create_positioner(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    (void)resource;  // wm_base not used in positioner creation
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    
    struct xdg_positioner_impl *positioner = calloc(1, sizeof(*positioner));
    if (!positioner) {
        wl_client_post_no_memory(client);
        return;
    }
    
    struct wl_resource *positioner_resource = wl_resource_create(client, &xdg_positioner_interface, (int)version, id);
    if (!positioner_resource) {
        free(positioner);
        wl_client_post_no_memory(client);
        return;
    }
    
    positioner->resource = positioner_resource;
    wl_resource_set_implementation(positioner_resource, &positioner_interface, positioner, NULL);
    
    log_printf("[XDG_SHELL] ", "create_positioner() - client=%p, id=%u\n", (void *)client, id);
}

static void xdg_wm_base_get_xdg_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface) {
    log_printf("[COMPOSITOR] ", "xdg_wm_base_get_xdg_surface() - client=%p, id=%u, surface=%p\n", 
               (void *)client, id, (void *)surface);
    struct xdg_wm_base_impl *wm_base = wl_resource_get_user_data(resource);
    struct wl_surface_impl *wl_surface = wl_surface_from_resource(surface);
    
    if (!wl_surface) {
        log_printf("[COMPOSITOR] ", "xdg_wm_base_get_xdg_surface() - invalid wl_surface, posting error\n");
        wl_resource_post_error(resource, XDG_WM_BASE_ERROR_ROLE, "invalid wl_surface");
        return;
    }
    
    log_printf("[COMPOSITOR] ", "xdg_wm_base_get_xdg_surface() - wl_surface=%p\n", (void *)wl_surface);
    struct xdg_surface_impl *xdg_surface = calloc(1, sizeof(*xdg_surface));
    if (!xdg_surface) {
        log_printf("[COMPOSITOR] ", "xdg_wm_base_get_xdg_surface() - failed to allocate xdg_surface\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    xdg_surface->resource = wl_resource_create(client, &xdg_surface_interface, (int)wl_resource_get_version(resource), id);
    if (!xdg_surface->resource) {
        log_printf("[COMPOSITOR] ", "xdg_wm_base_get_xdg_surface() - failed to create resource\n");
        free(xdg_surface);
        wl_client_post_no_memory(client);
        return;
    }
    
    xdg_surface->wl_surface = wl_surface;
    xdg_surface->wm_base = wm_base;  // Store reference to wm_base
    wl_resource_set_implementation(xdg_surface->resource, &xdg_surface_impl_interface, xdg_surface, NULL);
    
    // Add to list
    xdg_surface->next = xdg_surfaces;
    xdg_surfaces = xdg_surface;
    
    // Send configure event
    uint32_t serial = wl_display_next_serial(wm_base->display);
    log_printf("[COMPOSITOR] ", "xdg_wm_base_get_xdg_surface() - sending configure event, serial=%u\n", serial);
    xdg_surface_send_configure(xdg_surface->resource, serial);
    xdg_surface->configure_serial = serial;
    xdg_surface->last_acked_serial = 0; // Initialize
    log_printf("[COMPOSITOR] ", "xdg_wm_base_get_xdg_surface() - completed\n");
}

static void xdg_wm_base_pong(struct wl_client *client, struct wl_resource *resource, uint32_t serial) {
    // Pong handling
    (void)client; (void)resource; (void)serial;
}

static void xdg_surface_destroy_handler(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct xdg_surface_impl *xdg_surface = wl_resource_get_user_data(resource);
    
    // Remove from list
    if (xdg_surfaces == xdg_surface) {
        xdg_surfaces = xdg_surface->next;
    } else {
        struct xdg_surface_impl *s = xdg_surfaces;
        while (s && s->next != xdg_surface) s = s->next;
        if (s) s->next = xdg_surface->next;
    }
    
    free(xdg_surface);
}

// Helper function to get xdg_toplevel from a wl_surface_impl
struct xdg_toplevel_impl *xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *wl_surface) {
    if (!wl_surface) return NULL;
    
    // Check if this surface has an associated xdg_surface with a toplevel role
    struct xdg_surface_impl *xdg_surface = xdg_surfaces;
    while (xdg_surface) {
        if (xdg_surface->wl_surface == wl_surface && xdg_surface->role) {
            // Check if role is a toplevel (not a popup)
            struct xdg_toplevel_impl *toplevel = (struct xdg_toplevel_impl *)xdg_surface->role;
            if (toplevel && toplevel->resource) {
                return toplevel;
            }
        }
        xdg_surface = xdg_surface->next;
    }
    return NULL;
}

// Helper function to check if a wl_surface is a toplevel
bool xdg_surface_is_toplevel(struct wl_surface_impl *wl_surface) {
    return xdg_surface_get_toplevel_from_wl_surface(wl_surface) != NULL;
}

static void xdg_surface_get_toplevel(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    log_printf("[COMPOSITOR] ", "xdg_surface_get_toplevel() - client=%p, id=%u\n", (void *)client, id);
    struct xdg_surface_impl *xdg_surface = wl_resource_get_user_data(resource);
    
    struct xdg_toplevel_impl *toplevel = calloc(1, sizeof(*toplevel));
    if (!toplevel) {
        log_printf("[COMPOSITOR] ", "xdg_surface_get_toplevel() - failed to allocate toplevel\n");
        wl_client_post_no_memory(client);
        return;
    }
    
    toplevel->resource = wl_resource_create(client, &xdg_toplevel_interface, (int)wl_resource_get_version(resource), id);
    if (!toplevel->resource) {
        log_printf("[COMPOSITOR] ", "xdg_surface_get_toplevel() - failed to create resource\n");
        free(toplevel);
        wl_client_post_no_memory(client);
        return;
    }
    
    toplevel->xdg_surface = xdg_surface;
    toplevel->decoration_mode = 0; // Initialize to unset (will be set by decoration protocol)
    xdg_surface->role = toplevel;
    
    wl_resource_set_implementation(toplevel->resource, &xdg_toplevel_impl_interface, toplevel, NULL);
    
    // Send configure with actual output size
    int32_t width = xdg_surface->wm_base ? xdg_surface->wm_base->output_width : 800;
    int32_t height = xdg_surface->wm_base ? xdg_surface->wm_base->output_height : 600;
    
    // Check if this is a nested compositor (like Weston) - if so, automatically set fullscreen
    bool is_nested_compositor = (nested_compositor_client == client);
    if (is_nested_compositor) {
        log_printf("[COMPOSITOR] ", "xdg_surface_get_toplevel() - nested compositor detected, setting fullscreen\n");
        // Set fullscreen state immediately
        toplevel->states |= XDG_TOPLEVEL_STATE_FULLSCREEN;
    }
    
    log_printf("[COMPOSITOR] ", "xdg_surface_get_toplevel() - sending configure events with size %dx%d%s\n", 
               width, height, is_nested_compositor ? " (FULLSCREEN)" : "");
    struct wl_array states;
    wl_array_init(&states);
    
    // Add fullscreen state if this is a nested compositor
    if (is_nested_compositor) {
        uint32_t *state = wl_array_add(&states, sizeof(uint32_t));
        if (state) {
            *state = XDG_TOPLEVEL_STATE_FULLSCREEN;
        }
    }
    
    uint32_t serial = wl_display_next_serial(wl_client_get_display(client));
    xdg_toplevel_send_configure(toplevel->resource, width, height, &states);
    xdg_surface_send_configure(xdg_surface->resource, serial);
    xdg_surface->configure_serial = serial; // Update most recent serial sent
    toplevel->width = width;
    toplevel->height = height;
    wl_array_release(&states);
    log_printf("[COMPOSITOR] ", "xdg_surface_get_toplevel() - completed, serial=%u%s\n", 
               serial, is_nested_compositor ? " (FULLSCREEN)" : "");
}

static void xdg_popup_destroy_handler(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct xdg_popup_impl *popup = wl_resource_get_user_data(resource);
    if (popup) {
        if (popup->xdg_surface) {
            popup->xdg_surface->role = NULL;  // Clear role
        }
        free(popup);
    }
    wl_resource_destroy(resource);
}

static void xdg_popup_grab(struct wl_client *client, struct wl_resource *resource,
                           struct wl_resource *seat_resource, uint32_t serial) {
    (void)client;
    (void)seat_resource;
    (void)serial;
    struct xdg_popup_impl *popup = wl_resource_get_user_data(resource);
    if (popup) {
        log_printf("[XDG_SHELL] ", "popup_grab() - popup=%p, serial=%u\n",
                   (void *)popup, serial);
        // TODO: Implement popup grab (keyboard/pointer focus)
    }
}

static void xdg_popup_reposition(struct wl_client *client, struct wl_resource *resource,
                                 struct wl_resource *positioner_resource, uint32_t token) {
    (void)client;
    (void)token;
    struct xdg_popup_impl *popup = wl_resource_get_user_data(resource);
    struct xdg_positioner_impl *positioner = wl_resource_get_user_data(positioner_resource);
    
    if (popup && positioner) {
        popup->positioner = positioner;
        // Calculate new position based on positioner
        popup->x = positioner->anchor_rect_x + positioner->offset_x;
        popup->y = positioner->anchor_rect_y + positioner->offset_y;
        
        // Send configure event
        if (popup->xdg_surface) {
            popup->configure_serial = wl_display_get_serial(wl_client_get_display(client));
            // Use wl_resource_post_event directly (opcodes from xdg-shell-protocol.h)
            wl_resource_post_event(resource, XDG_POPUP_CONFIGURE, popup->x, popup->y,
                                  popup->positioner->width, popup->positioner->height);
            wl_resource_post_event(resource, XDG_POPUP_REPOSITIONED, token);
        }
        
        log_printf("[XDG_SHELL] ", "popup_reposition() - popup=%p, x=%d, y=%d\n",
                   (void *)popup, popup->x, popup->y);
    }
}

static void xdg_surface_get_popup(struct wl_client *client, struct wl_resource *resource, uint32_t id,
                                  struct wl_resource *parent_resource, struct wl_resource *positioner_resource) {
    struct xdg_surface_impl *xdg_surface = wl_resource_get_user_data(resource);
    struct xdg_surface_impl *parent = wl_resource_get_user_data(parent_resource);
    struct xdg_positioner_impl *positioner = wl_resource_get_user_data(positioner_resource);
    
    if (!xdg_surface || !parent || !positioner) {
        wl_resource_post_error(resource, XDG_WM_BASE_ERROR_INVALID_POPUP_PARENT,
                              "invalid parent or positioner");
        return;
    }
    
    // Check if surface already has a role
    if (xdg_surface->role) {
        wl_resource_post_error(resource, XDG_WM_BASE_ERROR_NOT_THE_TOPMOST_POPUP,
                              "surface already has a role");
        return;
    }
    
    struct xdg_popup_impl *popup = calloc(1, sizeof(*popup));
    if (!popup) {
        wl_client_post_no_memory(client);
        return;
    }
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *popup_resource = wl_resource_create(client, &xdg_popup_interface, (int)version, id);
    if (!popup_resource) {
        free(popup);
        wl_client_post_no_memory(client);
        return;
    }
    
    popup->resource = popup_resource;
    popup->xdg_surface = xdg_surface;
    popup->parent = parent;
    popup->positioner = positioner;
    popup->x = positioner->anchor_rect_x + positioner->offset_x;
    popup->y = positioner->anchor_rect_y + positioner->offset_y;
    
    xdg_surface->role = popup;  // Set popup as role
    
    wl_resource_set_implementation(popup_resource, &xdg_popup_impl_interface, popup, NULL);
    
    // Send configure event
    popup->configure_serial = wl_display_get_serial(wl_client_get_display(client));
    // xdg_popup.configure event: x, y, width, height
    wl_resource_post_event(popup_resource, XDG_POPUP_CONFIGURE, popup->x, popup->y,
                          positioner->width, positioner->height);
    
    log_printf("[XDG_SHELL] ", "get_popup() - surface=%p, parent=%p, x=%d, y=%d, w=%d, h=%d\n",
               (void *)xdg_surface->wl_surface, (void *)parent->wl_surface,
               popup->x, popup->y, positioner->width, positioner->height);
}

static void xdg_surface_set_window_geometry(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height) {
    // Geometry handling
    (void)client; (void)resource; (void)x; (void)y; (void)width; (void)height;
}

static void xdg_surface_ack_configure(struct wl_client *client, struct wl_resource *resource, uint32_t serial) {
    (void)client;
    struct xdg_surface_impl *xdg_surface = wl_resource_get_user_data(resource);
    log_printf("[COMPOSITOR] ", "xdg_surface_ack_configure() - serial=%u, last_acked=%u, most_recent=%u\n", 
               serial, xdg_surface->last_acked_serial, xdg_surface->configure_serial);
    
    // Accept any serial that is <= the most recent configure serial sent (valid configure event)
    // Clients may acknowledge configure events in order, so we accept any valid serial
    if (serial > 0 && serial <= xdg_surface->configure_serial) {
        // Update last_acked_serial to the maximum of current and new
        if (serial > xdg_surface->last_acked_serial) {
            xdg_surface->last_acked_serial = serial;
        }
        xdg_surface->configured = true;
        log_printf("[COMPOSITOR] ", "xdg_surface_ack_configure() - surface configured\n");
    } else {
        log_printf("[COMPOSITOR] ", "xdg_surface_ack_configure() - invalid serial (ignored)\n");
    }
}

static void xdg_toplevel_destroy_handler(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
    if (toplevel) {
        if (toplevel->title) free(toplevel->title);
        if (toplevel->app_id) free(toplevel->app_id);
        free(toplevel);
    }
    wl_resource_destroy(resource);
}

static void xdg_toplevel_set_parent(struct wl_client *client, struct wl_resource *resource, struct wl_resource *parent) {
    // Parent handling
    (void)client; (void)resource; (void)parent;
}

static void xdg_toplevel_set_title(struct wl_client *client, struct wl_resource *resource, const char *title) {
    (void)client;
    struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
    if (toplevel->title) free(toplevel->title);
    toplevel->title = title ? strdup(title) : NULL;
    
    // Update macOS window title when client sets title
    if (toplevel && toplevel->xdg_surface && toplevel->xdg_surface->wl_surface) {
        extern void macos_compositor_update_title(struct wl_client *client);
        macos_compositor_update_title(client);
    }
}

static void xdg_toplevel_set_app_id(struct wl_client *client, struct wl_resource *resource, const char *app_id) {
    (void)client;
    struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
    if (toplevel->app_id) free(toplevel->app_id);
    toplevel->app_id = app_id ? strdup(app_id) : NULL;
    
    // Update macOS window title when client sets app_id (if title not set)
    if (toplevel && toplevel->xdg_surface && toplevel->xdg_surface->wl_surface) {
        extern void macos_compositor_update_title(struct wl_client *client);
        macos_compositor_update_title(client);
    }
}

static void xdg_toplevel_show_window_menu(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial, int32_t x, int32_t y) {
    // Window menu
    (void)client; (void)resource; (void)seat; (void)serial; (void)x; (void)y;
}

static void xdg_toplevel_move(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial) {
    // Move handling
    (void)client; (void)resource; (void)seat; (void)serial;
}

static void xdg_toplevel_resize(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial, uint32_t edges) {
    // Resize handling
    (void)client; (void)resource; (void)seat; (void)serial; (void)edges;
}

static void xdg_toplevel_set_max_size(struct wl_client *client, struct wl_resource *resource, int32_t width, int32_t height) {
    // Max size
    (void)client; (void)resource; (void)width; (void)height;
}

static void xdg_toplevel_set_min_size(struct wl_client *client, struct wl_resource *resource, int32_t width, int32_t height) {
    // Min size
    (void)client; (void)resource; (void)width; (void)height;
}

static void xdg_toplevel_set_maximized(struct wl_client *client, struct wl_resource *resource) {
    // Maximized
    (void)client; (void)resource;
}

static void xdg_toplevel_unset_maximized(struct wl_client *client, struct wl_resource *resource) {
    // Unmaximized
    (void)client; (void)resource;
}

static void xdg_toplevel_set_fullscreen(struct wl_client *client, struct wl_resource *resource, struct wl_resource *output) {
    struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
    if (!toplevel || !toplevel->xdg_surface) {
        return;
    }
    
    // Set fullscreen state
    toplevel->states |= XDG_TOPLEVEL_STATE_FULLSCREEN;
    
    // Get output size for fullscreen configure
    int32_t width = toplevel->xdg_surface->wm_base ? toplevel->xdg_surface->wm_base->output_width : 800;
    int32_t height = toplevel->xdg_surface->wm_base ? toplevel->xdg_surface->wm_base->output_height : 600;
    
    log_printf("[XDG_SHELL] ", "xdg_toplevel_set_fullscreen() - toplevel=%p, output=%p, size=%dx%d\n",
               (void *)toplevel, (void *)output, width, height);
    
    // Send configure event with fullscreen state
    struct wl_array states;
    wl_array_init(&states);
    uint32_t *state = wl_array_add(&states, sizeof(uint32_t));
    if (state) {
        *state = XDG_TOPLEVEL_STATE_FULLSCREEN;
    }
    
    uint32_t serial = wl_display_next_serial(wl_client_get_display(client));
    xdg_toplevel_send_configure(toplevel->resource, width, height, &states);
    xdg_surface_send_configure(toplevel->xdg_surface->resource, serial);
    toplevel->xdg_surface->configure_serial = serial;
    toplevel->width = width;
    toplevel->height = height;
    wl_array_release(&states);
    
    log_printf("[XDG_SHELL] ", "xdg_toplevel_set_fullscreen() - sent configure: %dx%d (FULLSCREEN), serial=%u\n",
               width, height, serial);
}

static void xdg_toplevel_unset_fullscreen(struct wl_client *client, struct wl_resource *resource) {
    struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
    if (!toplevel || !toplevel->xdg_surface) {
        return;
    }
    
    // Clear fullscreen state
    toplevel->states &= ~(uint32_t)XDG_TOPLEVEL_STATE_FULLSCREEN;
    
    // Get output size for windowed configure
    int32_t width = toplevel->xdg_surface->wm_base ? toplevel->xdg_surface->wm_base->output_width : 800;
    int32_t height = toplevel->xdg_surface->wm_base ? toplevel->xdg_surface->wm_base->output_height : 600;
    
    log_printf("[XDG_SHELL] ", "xdg_toplevel_unset_fullscreen() - toplevel=%p, size=%dx%d\n",
               (void *)toplevel, width, height);
    
    // Send configure event without fullscreen state
    struct wl_array states;
    wl_array_init(&states);
    uint32_t serial = wl_display_next_serial(wl_client_get_display(client));
    xdg_toplevel_send_configure(toplevel->resource, width, height, &states);
    xdg_surface_send_configure(toplevel->xdg_surface->resource, serial);
    toplevel->xdg_surface->configure_serial = serial;
    toplevel->width = width;
    toplevel->height = height;
    wl_array_release(&states);
}

static void xdg_toplevel_set_minimized(struct wl_client *client, struct wl_resource *resource) {
    // Minimized
    (void)client; (void)resource;
}

// Send configure events to all toplevel surfaces (called on window resize)
void xdg_wm_base_send_configure_to_all_toplevels(struct xdg_wm_base_impl *wm_base, int32_t width, int32_t height) {
    if (!wm_base) return;
    
    struct xdg_surface_impl *surface = xdg_surfaces;
    while (surface) {
        // Store next pointer before potentially modifying the list
        struct xdg_surface_impl *next = surface->next;
        
        if (surface->role) {
            struct xdg_toplevel_impl *toplevel = (struct xdg_toplevel_impl *)surface->role;
            if (toplevel && toplevel->resource) {
                // Verify toplevel resource is still valid before sending event
                struct wl_client *client = wl_resource_get_client(toplevel->resource);
                if (!client) {
                    // Client disconnected, resource is invalid - skip
                    surface = next;
                    continue;
                }
                // Verify resource user_data is still valid
                if (wl_resource_get_user_data(toplevel->resource) == NULL) {
                    // Resource was destroyed - skip
                    surface = next;
                    continue;
                }
                // Verify surface resource is still valid
                if (!surface->resource || wl_resource_get_user_data(surface->resource) == NULL) {
                    // Surface resource was destroyed - skip
                    surface = next;
                    continue;
                }
                
                // Double-check resources are still valid right before sending (race condition protection)
                struct wl_client *client_check = wl_resource_get_client(toplevel->resource);
                if (!client_check || wl_resource_get_user_data(toplevel->resource) == NULL ||
                    !surface->resource || wl_resource_get_user_data(surface->resource) == NULL) {
                    // Resource was destroyed between check and send - skip
                    surface = next;
                    continue;
                }
                
                // Update toplevel size
                toplevel->width = width;
                toplevel->height = height;
                
                // Send configure event
                struct wl_array states;
                wl_array_init(&states);
                uint32_t serial = wl_display_next_serial(wm_base->display);
                
                // Final check right before sending
                if (wl_resource_get_user_data(toplevel->resource) != NULL &&
                    wl_resource_get_user_data(surface->resource) != NULL) {
                    xdg_toplevel_send_configure(toplevel->resource, width, height, &states);
                    xdg_surface_send_configure(surface->resource, serial);
                    surface->configure_serial = serial;
                    log_printf("[COMPOSITOR] ", "Sent configure event to toplevel: %dx%d, serial=%u\n", width, height, serial);
                }
                
                wl_array_release(&states);
            }
        }
        surface = next;
    }
}

