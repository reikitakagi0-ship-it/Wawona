#include "xdg_shell.h"
#include <wayland-server-protocol.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "logging.h" // Include logging header

struct xdg_surface_impl *xdg_surfaces = NULL;
static struct wl_client *nested_compositor_client = NULL;

// --- Forward Declarations ---
static void xdg_surface_destroy_resource(struct wl_resource *resource);
static void xdg_toplevel_destroy_resource(struct wl_resource *resource);

// --- XDG Toplevel ---

static void
xdg_toplevel_destroy(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static void
xdg_toplevel_set_parent(struct wl_client *client, struct wl_resource *resource, struct wl_resource *parent)
{
}

static void
xdg_toplevel_set_title(struct wl_client *client, struct wl_resource *resource, const char *title)
{
}

static void
xdg_toplevel_set_app_id(struct wl_client *client, struct wl_resource *resource, const char *app_id)
{
}

static void
xdg_toplevel_show_window_menu(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial, int32_t x, int32_t y)
{
}

static void
xdg_toplevel_move(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial)
{
}

static void
xdg_toplevel_resize(struct wl_client *client, struct wl_resource *resource, struct wl_resource *seat, uint32_t serial, uint32_t edges)
{
}

static void
xdg_toplevel_set_max_size(struct wl_client *client, struct wl_resource *resource, int32_t width, int32_t height)
{
}

static void
xdg_toplevel_set_min_size(struct wl_client *client, struct wl_resource *resource, int32_t width, int32_t height)
{
}

static void
xdg_toplevel_set_maximized(struct wl_client *client, struct wl_resource *resource)
{
}

static void
xdg_toplevel_unset_maximized(struct wl_client *client, struct wl_resource *resource)
{
}

static void
xdg_toplevel_set_fullscreen(struct wl_client *client, struct wl_resource *resource, struct wl_resource *output)
{
}

static void
xdg_toplevel_unset_fullscreen(struct wl_client *client, struct wl_resource *resource)
{
}

static void
xdg_toplevel_set_minimized(struct wl_client *client, struct wl_resource *resource)
{
}

static const struct xdg_toplevel_interface xdg_toplevel_implementation = {
    .destroy = xdg_toplevel_destroy,
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

// --- XDG Surface ---

static void
xdg_surface_destroy(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static void
xdg_surface_get_toplevel(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    log_printf("[XDG-SHELL] ", "xdg_surface_get_toplevel called for resource %p\n", resource);
    struct xdg_surface_impl *xdg_surface = wl_resource_get_user_data(resource);
    struct wl_resource *toplevel_resource = wl_resource_create(client, &xdg_toplevel_interface, wl_resource_get_version(resource), id);
    if (!toplevel_resource) {
        wl_resource_post_no_memory(resource);
        return;
    }
    
    wl_resource_set_implementation(toplevel_resource, &xdg_toplevel_implementation, xdg_surface, NULL);
    xdg_surface->role = toplevel_resource;
    
    // Send initial configure event to unblock client
    struct wl_array states;
    wl_array_init(&states);
    // Add activated state
    uint32_t *activated = wl_array_add(&states, sizeof(uint32_t));
    if (activated) *activated = XDG_TOPLEVEL_STATE_ACTIVATED;
    
    // Use output size from wm_base if available
    int32_t width = xdg_surface->wm_base->output_width;
    int32_t height = xdg_surface->wm_base->output_height;
    
    log_printf("[XDG-SHELL] ", "Sending initial configure to toplevel %p (size: %dx%d)\n", toplevel_resource, width, height);
    xdg_toplevel_send_configure(toplevel_resource, width, height, &states);
    wl_array_release(&states);
    
    xdg_surface_send_configure(resource, 1); // Serial 1
}

static void
xdg_surface_get_popup(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *parent, struct wl_resource *positioner)
{
    // Stub
}

static void
xdg_surface_set_window_geometry(struct wl_client *client, struct wl_resource *resource, int32_t x, int32_t y, int32_t width, int32_t height)
{
}

static void
xdg_surface_ack_configure(struct wl_client *client, struct wl_resource *resource, uint32_t serial)
{
    struct xdg_surface_impl *xdg_surface = wl_resource_get_user_data(resource);
    xdg_surface->configured = true;
}

static const struct xdg_surface_interface xdg_surface_implementation = {
    .destroy = xdg_surface_destroy,
    .get_toplevel = xdg_surface_get_toplevel,
    .get_popup = xdg_surface_get_popup,
    .set_window_geometry = xdg_surface_set_window_geometry,
    .ack_configure = xdg_surface_ack_configure,
};

static void
wm_base_destroy_resource(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static void
wm_base_create_positioner(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    // Stub
}

static void
wm_base_get_xdg_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface)
{
    log_printf("[XDG-SHELL] ", "wm_base_get_xdg_surface called\n");
    struct xdg_wm_base_impl *wm_base = wl_resource_get_user_data(resource);
    struct wl_resource *xdg_resource = wl_resource_create(client, &xdg_surface_interface, wl_resource_get_version(resource), id);
    if (!xdg_resource) {
        wl_resource_post_no_memory(resource);
        return;
    }
    
    struct xdg_surface_impl *xdg_surface = calloc(1, sizeof(struct xdg_surface_impl));
    if (!xdg_surface) {
        wl_resource_post_no_memory(resource);
        return;
    }
    xdg_surface->resource = xdg_resource;
    xdg_surface->wm_base = wm_base;
    xdg_surface->wl_surface = wl_resource_get_user_data(surface);
    xdg_surface->next = xdg_surfaces;
    xdg_surfaces = xdg_surface;
    
    wl_resource_set_implementation(xdg_resource, &xdg_surface_implementation, xdg_surface, NULL);
}

static void
wm_base_pong(struct wl_client *client, struct wl_resource *resource, uint32_t serial)
{
    // Handle pong
}

static const struct xdg_wm_base_interface wm_base_interface = {
    .destroy = wm_base_destroy_resource,
    .create_positioner = wm_base_create_positioner,
    .get_xdg_surface = wm_base_get_xdg_surface,
    .pong = wm_base_pong,
};

static void
bind_wm_base(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct xdg_wm_base_impl *wm_base = data;
    struct wl_resource *resource;

    resource = wl_resource_create(client, &xdg_wm_base_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &wm_base_interface, wm_base, NULL);
}

struct xdg_wm_base_impl *
xdg_wm_base_create(struct wl_display *display)
{
    struct xdg_wm_base_impl *wm_base = calloc(1, sizeof(struct xdg_wm_base_impl));
    if (!wm_base) return NULL;

    wm_base->display = display;
    wm_base->version = 1;
    
    wm_base->global = wl_global_create(display, &xdg_wm_base_interface, 1, wm_base, bind_wm_base);
    if (!wm_base->global) {
        free(wm_base);
        return NULL;
    }

    return wm_base;
}

void
xdg_wm_base_destroy(struct xdg_wm_base_impl *wm_base)
{
    if (!wm_base) return;
    if (wm_base->global) wl_global_destroy(wm_base->global);
    free(wm_base);
}

void
xdg_wm_base_send_configure_to_all_toplevels(struct xdg_wm_base_impl *wm_base, int32_t width, int32_t height)
{
    if (!wm_base) return;
    
    // Update stored size
    wm_base->output_width = width;
    wm_base->output_height = height;
    
    // Iterate all surfaces
    struct xdg_surface_impl *surface = xdg_surfaces;
    while (surface) {
        if (surface->wm_base == wm_base && surface->role) { // Check it has a role (toplevel)
            struct wl_resource *toplevel_resource = surface->role;
            
            // Only send if it's a toplevel (check interface or implementation)
            // For simplicity, assume role is toplevel if set (we only support toplevel now)
            
            struct wl_array states;
            wl_array_init(&states);
            uint32_t *activated = wl_array_add(&states, sizeof(uint32_t));
            if (activated) *activated = XDG_TOPLEVEL_STATE_ACTIVATED;
            // Add maximized/fullscreen if needed...
            
            log_printf("[XDG-SHELL] ", "Sending resize configure to toplevel %p (size: %dx%d)\n", toplevel_resource, width, height);
            xdg_toplevel_send_configure(toplevel_resource, width, height, &states);
            wl_array_release(&states);
            
            xdg_surface_send_configure(surface->resource, ++surface->configure_serial);
        }
        surface = surface->next;
    }
}

void
xdg_wm_base_set_output_size(struct xdg_wm_base_impl *wm_base, int32_t width, int32_t height)
{
    if (wm_base) {
        wm_base->output_width = width;
        wm_base->output_height = height;
    }
}

bool
xdg_surface_is_toplevel(struct wl_surface_impl *wl_surface)
{
    return false; // Stub
}

struct xdg_toplevel_impl *
xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *wl_surface)
{
    return NULL; // Stub
}

void
xdg_shell_mark_nested_compositor(struct wl_client *client)
{
    nested_compositor_client = client;
}

struct wl_client *
nested_compositor_client_from_xdg_shell(void)
{
    return nested_compositor_client;
}
