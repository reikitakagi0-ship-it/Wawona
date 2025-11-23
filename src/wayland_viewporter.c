#include "wayland_viewporter.h"
#include "wayland_compositor.h"
#include "logging.h"
#include <wayland-server.h>
#include <wayland-server-protocol.h>
#include <stdlib.h>
#include <string.h>

// Forward declaration - wl_surface_interface is defined in wayland-server-protocol.h
extern const struct wl_interface wl_surface_interface;

// Type arrays for interface messages
static const struct wl_interface *wp_viewporter_types[] = {
    NULL,  // wp_viewport (new_id)
    &wl_surface_interface,  // wl_surface (object)
};

// Message definitions for wp_viewporter interface
static const struct wl_message wp_viewporter_requests[] = {
    { "destroy", "", NULL },
    { "get_viewport", "no", wp_viewporter_types },
};

// Message definitions for wp_viewport interface
static const struct wl_message wp_viewport_requests[] = {
    { "destroy", "", NULL },
    { "set_source", "ffff", NULL },
    { "set_destination", "ii", NULL },
};

// Define interface structures (properly with method/event counts)
const struct wl_interface wp_viewporter_interface = {
    "wp_viewporter", 1,
    2, wp_viewporter_requests,
    0, NULL,  // No events
};

const struct wl_interface wp_viewport_interface = {
    "wp_viewport", 1,
    3, wp_viewport_requests,
    0, NULL,  // No events
};

// Viewporter protocol implementation
// Allows clients to crop and scale surfaces

struct wl_viewport_impl {
    struct wl_resource *resource;
    struct wl_surface_impl *surface;
    double src_x, src_y, src_width, src_height;
    double dst_width, dst_height;
    bool has_src;
    bool has_dst;
};

static struct wl_viewport_impl *viewport_from_resource(struct wl_resource *resource) {
    return wl_resource_get_user_data(resource);
}

static void viewport_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wl_viewport_impl *viewport = viewport_from_resource(resource);
    if (viewport && viewport->surface) {
        // Clear viewport from surface
        viewport->surface->viewport = NULL;
    }
    free(viewport);
    wl_resource_destroy(resource);
}

static void viewport_set_source(struct wl_client *client, struct wl_resource *resource,
                                wl_fixed_t x, wl_fixed_t y, wl_fixed_t width, wl_fixed_t height) {
    (void)client;
    struct wl_viewport_impl *viewport = viewport_from_resource(resource);
    if (!viewport || !viewport->surface) {
        return;
    }
    
    // Protocol requires: "If all of x, y, width and height are -1.0, the source rectangle is
    // unset instead. Any other set of values where width or height are zero
    // or negative, or x or y are negative, raise the bad_value protocol error."
    if (x == -1 && y == -1 && width == -1 && height == -1) {
        // Unset source (per protocol spec)
        viewport->has_src = false;
        log_printf("[VIEWPORTER] ", "viewport_set_source() - surface=%p, unset source\n",
                   (void *)viewport->surface);
        return;
    }
    
    if (x < 0 || y < 0 || width <= 0 || height <= 0) {
        wl_resource_post_error(resource, WP_VIEWPORT_ERROR_BAD_VALUE,
                              "negative x/y or zero/negative width/height");
        return;
    }
    
    viewport->src_x = wl_fixed_to_double(x);
    viewport->src_y = wl_fixed_to_double(y);
    viewport->src_width = wl_fixed_to_double(width);
    viewport->src_height = wl_fixed_to_double(height);
    viewport->has_src = true;
    
    log_printf("[VIEWPORTER] ", "viewport_set_source() - surface=%p, src=(%.2f, %.2f, %.2f, %.2f)\n",
               (void *)viewport->surface, viewport->src_x, viewport->src_y,
               viewport->src_width, viewport->src_height);
}

static void viewport_set_destination(struct wl_client *client, struct wl_resource *resource,
                                     wl_fixed_t width, wl_fixed_t height) {
    (void)client;
    struct wl_viewport_impl *viewport = viewport_from_resource(resource);
    if (!viewport || !viewport->surface) {
        return;
    }
    
    // Protocol requires: "Any other pair of values for width and height that
    // contains zero or negative values raises the bad_value protocol error."
    // Also handle -1, -1 as "unset" per protocol spec
    if (width == -1 && height == -1) {
        // Unset destination (per protocol spec)
        viewport->has_dst = false;
        log_printf("[VIEWPORTER] ", "viewport_set_destination() - surface=%p, unset destination\n",
                   (void *)viewport->surface);
        return;
    }
    
    if (width <= 0 || height <= 0) {
        wl_resource_post_error(resource, WP_VIEWPORT_ERROR_BAD_VALUE,
                              "zero or negative width or height");
        return;
    }
    
    viewport->dst_width = wl_fixed_to_double(width);
    viewport->dst_height = wl_fixed_to_double(height);
    viewport->has_dst = true;
    
    // Warn if viewport destination is suspiciously small compared to buffer size
    // This can indicate a client bug (e.g., foot setting 4x3 instead of actual surface size)
    if (viewport->surface && viewport->surface->buffer_width > 0 && viewport->surface->buffer_height > 0) {
        double buffer_w = (double)viewport->surface->buffer_width;
        double buffer_h = (double)viewport->surface->buffer_height;
        double ratio_w = viewport->dst_width / buffer_w;
        double ratio_h = viewport->dst_height / buffer_h;
        
        // If viewport is less than 1% of buffer size, it's likely a bug
        if (ratio_w < 0.01 || ratio_h < 0.01) {
            log_printf("[VIEWPORTER] ", "⚠️  WARNING: viewport_set_destination() - surface=%p, dst=(%.2f, %.2f) is suspiciously small compared to buffer=(%d, %d) (ratios: %.4fx, %.4fx)\n",
                       (void *)viewport->surface, viewport->dst_width, viewport->dst_height,
                       viewport->surface->buffer_width, viewport->surface->buffer_height, ratio_w, ratio_h);
        } else {
            log_printf("[VIEWPORTER] ", "viewport_set_destination() - surface=%p, dst=(%.2f, %.2f)\n",
                       (void *)viewport->surface, viewport->dst_width, viewport->dst_height);
        }
    } else {
        log_printf("[VIEWPORTER] ", "viewport_set_destination() - surface=%p, dst=(%.2f, %.2f)\n",
                   (void *)viewport->surface, viewport->dst_width, viewport->dst_height);
    }
}

static const struct wp_viewport_interface viewport_interface = {
    .destroy = viewport_destroy,
    .set_source = viewport_set_source,
    .set_destination = viewport_set_destination,
};

struct wl_viewporter_impl {
    struct wl_global *global;
    struct wl_display *display;
};

static void viewporter_get_viewport(struct wl_client *client, struct wl_resource *resource,
                                    uint32_t id, struct wl_resource *surface_resource) {
    struct wl_surface_impl *surface = wl_resource_get_user_data(surface_resource);
    if (!surface) {
        wl_resource_post_error(resource, WL_SURFACE_ERROR_INVALID_SCALE,
                              "invalid surface");
        return;
    }
    
    // Check if surface already has a viewport
    if (surface->viewport) {
        wl_resource_post_error(resource, WP_VIEWPORTER_ERROR_VIEWPORT_EXISTS,
                              "surface already has a viewport");
        return;
    }
    
    struct wl_viewport_impl *viewport = calloc(1, sizeof(*viewport));
    if (!viewport) {
        wl_client_post_no_memory(client);
        return;
    }
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *viewport_resource = wl_resource_create(client, &wp_viewport_interface, (int)version, id);
    if (!viewport_resource) {
        free(viewport);
        wl_client_post_no_memory(client);
        return;
    }
    
    viewport->resource = viewport_resource;
    viewport->surface = surface;
    surface->viewport = viewport;
    
    wl_resource_set_implementation(viewport_resource, &viewport_interface, viewport, NULL);
    
    log_printf("[VIEWPORTER] ", "get_viewport() - client=%p, surface=%p, viewport=%p\n",
               (void *)client, (void *)surface, (void *)viewport);
}

static void viewporter_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static const struct wp_viewporter_interface viewporter_interface = {
    .destroy = viewporter_destroy,
    .get_viewport = viewporter_get_viewport,
};

static void viewporter_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_viewporter_impl *viewporter = data;
    
    struct wl_resource *resource = wl_resource_create(client, &wp_viewporter_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(resource, &viewporter_interface, viewporter, NULL);
    
    log_printf("[VIEWPORTER] ", "viewporter_bind() - client=%p, version=%u, id=%u\n",
               (void *)client, version, id);
}

struct wl_viewporter_impl *wl_viewporter_create(struct wl_display *display) {
    struct wl_viewporter_impl *viewporter = calloc(1, sizeof(*viewporter));
    if (!viewporter) {
        return NULL;
    }
    
    viewporter->display = display;
    viewporter->global = wl_global_create(display, &wp_viewporter_interface, 1, viewporter, viewporter_bind);
    
    if (!viewporter->global) {
        free(viewporter);
        return NULL;
    }
    
    log_printf("[VIEWPORTER] ", "wl_viewporter_create() - global created\n");
    return viewporter;
}

void wl_viewporter_destroy(struct wl_viewporter_impl *viewporter) {
    if (!viewporter) {
        return;
    }
    
    if (viewporter->global) {
        wl_global_destroy(viewporter->global);
    }
    
    free(viewporter);
}

