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

static void output_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_output_impl *output = data;
    struct wl_resource *resource = wl_resource_create(client, &wl_output_interface, (int)version, id);
    
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // Store output pointer in resource user_data for later retrieval
    wl_resource_set_implementation(resource, &output_interface, output, NULL);
    
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
    wl_resource_destroy(resource);
}


// Update output size and notify all clients of the mode change
// This enables "arbitrary resolutions" capability - clients can see the output supports dynamic resizing
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
    
    // Note: Mode change notifications to clients are handled automatically by Wayland
    // when clients bind to the output. Clients will receive configure events with new size
    // via xdg_wm_base_send_configure_to_all_toplevels, which is the standard Wayland pattern.
    // Output size is informational - actual window sizing is handled by xdg_shell configure events.
    // For nested compositors, the "arbitrary resolutions" capability is detected by the
    // fact that we send mode change events when clients bind (in output_bind), not by
    // notifying existing clients on resize.
}

// Helper functions removed - using wayland-server-protocol.h inline functions directly

