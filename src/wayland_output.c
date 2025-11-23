#include "wayland_output.h"
#include "logging.h"
#include <wayland-server-protocol.h>
#include <wayland-server-core.h>
#include <stdlib.h>
#include <string.h>

static void output_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
static void output_release(struct wl_client *client, struct wl_resource *resource);

static const struct wl_output_interface output_interface = {
    .release = output_release,
};

struct wl_output_impl *wl_output_create(struct wl_display *display, int32_t width, int32_t height, const char *name) {
    struct wl_output_impl *output = calloc(1, sizeof(*output));
    if (!output) return NULL;
    
    output->display = display;
    output->width = width;
    output->height = height;
    output->scale = 1;
    output->transform = WL_OUTPUT_TRANSFORM_NORMAL;
    output->refresh_rate = 60000; // 60Hz in mHz
    output->name = name ? strdup(name) : strdup("macOS");
    output->description = strdup("macOS Wayland Output");
    
    // Initialize resource list for tracking all bound resources
    wl_list_init(&output->resource_list);
    
    output->global = wl_global_create(display, &wl_output_interface, 3, output, output_bind);
    
    if (!output->global) {
        free((void *)(uintptr_t)output->name);
        free((void *)(uintptr_t)output->description);
        free(output);
        return NULL;
    }
    
    return output;
}

void wl_output_destroy(struct wl_output_impl *output) {
    if (!output) return;
    
    wl_global_destroy(output->global);
    free((void *)(uintptr_t)output->name);
    free((void *)(uintptr_t)output->description);
    free(output);
}

// Resource destroy callback - removes resource from list when destroyed
static void output_resource_destroy(struct wl_resource *resource) {
    if (!resource) return;
    struct wl_list *link = wl_resource_get_link(resource);
    if (link) {
        // wl_list_remove is safe to call even if link is already removed
        // It checks if prev/next are valid before removing
        wl_list_remove(link);
        wl_list_init(link);
    }
}

static void output_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_output_impl *output = data;
    struct wl_resource *resource = wl_resource_create(client, &wl_output_interface, (int)version, id);
    
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // Store output pointer in resource user_data for later retrieval
    wl_resource_set_implementation(resource, &output_interface, output, NULL);
    
    // Initialize the resource link before adding to list
    struct wl_list *link = wl_resource_get_link(resource);
    wl_list_init(link);
    
    // Add resource to list for mode change notifications
    wl_resource_set_destructor(resource, output_resource_destroy);
    wl_list_insert(&output->resource_list, link);
    
    // Send geometry and mode events
    // This output represents Wawona's full framebuffer/window area
    // Nested compositors (like Weston) will query this and create matching outputs
    // Log output size for debugging nested compositor issues
    log_printf("[OUTPUT] ", "Sending output geometry: %dx%d (physical: %dx%d mm)\n",
               output->width, output->height, output->width * 10, output->height * 10);
    
    wl_output_send_geometry(resource,
        0, 0,                    // x, y
        output->width * 10,     // physical_width (mm) - approximate
        output->height * 10,    // physical_height (mm) - approximate
        WL_OUTPUT_SUBPIXEL_UNKNOWN, // subpixel
        output->name,           // make
        output->description,    // model
        output->transform);      // transform
    
    // Send mode with CURRENT and PREFERRED flags
    // This tells clients (like Weston) that this is the fullscreen output size
    // Weston's wayland backend will query this and create a matching output
    // The CURRENT flag indicates this is the active mode
    // The PREFERRED flag indicates this is the preferred/best mode
    log_printf("[OUTPUT] ", "Sending output mode: %dx%d @ %d mHz (CURRENT|PREFERRED)\n",
               output->width, output->height, output->refresh_rate);
    
    wl_output_send_mode(resource,
        WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED,
        output->width,
        output->height,
        output->refresh_rate);
    
    if (version >= WL_OUTPUT_SCALE_SINCE_VERSION) {
        wl_output_send_scale(resource, output->scale);
    }
    
    if (version >= WL_OUTPUT_NAME_SINCE_VERSION) {
        wl_output_send_name(resource, output->name);
    }
    
    if (version >= WL_OUTPUT_DESCRIPTION_SINCE_VERSION) {
        wl_output_send_description(resource, output->description);
    }
    
    // done event is only available since version 2
    // WL_OUTPUT_DONE_SINCE_VERSION is typically 2
    if (version >= 2) {
        wl_output_send_done(resource);
    }
}

static void output_release(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    // Resource will be removed from list by destroy listener
    wl_resource_destroy(resource);
}


// Helper function to send mode change events to a resource
static void send_mode_change_to_resource(struct wl_resource *resource, struct wl_output_impl *output) {
    if (!resource || !output) return;
    
    int version = wl_resource_get_version(resource);
    
    // Send updated geometry
    wl_output_send_geometry(resource,
        0, 0,                    // x, y
        output->width * 10,     // physical_width (mm) - approximate
        output->height * 10,    // physical_height (mm) - approximate
        WL_OUTPUT_SUBPIXEL_UNKNOWN, // subpixel
        output->name,           // make
        output->description,    // model
        output->transform);      // transform
    
    // Send updated mode with CURRENT and PREFERRED flags
    // This signals to nested compositors (like Weston) that Wawona supports arbitrary resolutions
    wl_output_send_mode(resource,
        WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED,
        output->width,
        output->height,
        output->refresh_rate);
    
    // Send scale if supported
    if (version >= WL_OUTPUT_SCALE_SINCE_VERSION) {
        wl_output_send_scale(resource, output->scale);
    }
    
    // Send done event if supported (version 2+)
    if (version >= 2) {
        wl_output_send_done(resource);
    }
}

// Update output size and notify all clients of the mode change
// This enables "arbitrary resolutions" capability - clients can see the output supports dynamic resizing
// By sending mode change events to existing clients, nested compositors like Weston will detect
// that Wawona supports arbitrary resolutions and enable WESTON_CAP_ARBITRARY_MODES
void wl_output_update_size(struct wl_output_impl *output, int32_t width, int32_t height) {
    if (!output) return;
    
    // Only update if size actually changed
    if (output->width == width && output->height == height) {
        return;
    }
    
    int32_t old_width = output->width;
    int32_t old_height = output->height;
    
    output->width = width;
    output->height = height;
    
    log_printf("[OUTPUT] ", "Output size changed: %dx%d -> %dx%d\n",
               old_width, old_height, width, height);
    
    // Send mode change events to all existing clients
    // This signals to nested compositors (like Weston) that Wawona supports arbitrary resolutions
    // Weston's wayland backend will detect these mode change events and enable WESTON_CAP_ARBITRARY_MODES
    struct wl_resource *resource;
    wl_resource_for_each(resource, &output->resource_list) {
        // Verify resource is still valid
        struct wl_client *client = wl_resource_get_client(resource);
        if (client) {
            send_mode_change_to_resource(resource, output);
        }
    }
    
    log_printf("[OUTPUT] ", "Sent mode change events to all clients (arbitrary resolutions: yes)\n");
}

// Helper functions removed - using wayland-server-protocol.h inline functions directly

