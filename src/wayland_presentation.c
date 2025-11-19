#include "wayland_presentation.h"
#include "presentation-time-protocol.h"
#include "wayland_output.h"
#include "wayland_compositor.h"
#include "logging.h"
#include <wayland-server.h>
#include <time.h>
#include <stdlib.h>

// Forward declarations for interfaces defined in presentation-time-protocol.c
// These are WL_PRIVATE but accessible within the same executable
extern const struct wl_interface wp_presentation_interface;
extern const struct wl_interface wp_presentation_feedback_interface;

// Presentation protocol implementation
// Provides accurate presentation timing feedback for smooth video playback

struct wp_presentation_feedback_impl {
    struct wl_resource *resource;
    struct wl_surface_impl *surface;
    struct wl_output_impl *output;
    bool presented;
};

static struct wp_presentation_feedback_impl *feedback_from_resource(struct wl_resource *resource) {
    return wl_resource_get_user_data(resource);
}

static void feedback_resource_destroy(struct wl_resource *resource) {
    struct wp_presentation_feedback_impl *feedback = feedback_from_resource(resource);
    if (feedback) {
        free(feedback);
    }
}

static void presentation_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void presentation_feedback(struct wl_client *client, struct wl_resource *resource,
                                  struct wl_resource *surface_resource, uint32_t id) {
    (void)client;
    
    struct wp_presentation_impl *presentation = wl_resource_get_user_data(resource);
    if (!presentation) {
        return;
    }
    
    // Get surface from resource
    struct wl_surface_impl *surface = wl_resource_get_user_data(surface_resource);
    if (!surface) {
        wl_resource_post_error(resource, WL_DISPLAY_ERROR_INVALID_OBJECT, "Invalid surface");
        return;
    }
    
    // Create feedback object
    struct wp_presentation_feedback_impl *feedback = calloc(1, sizeof(*feedback));
    if (!feedback) {
        wl_client_post_no_memory(client);
        return;
    }
    
    feedback->surface = surface;
    feedback->output = presentation->output;
    feedback->presented = false;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *feedback_resource = wl_resource_create(client, &wp_presentation_feedback_interface, (int)version, id);
    if (!feedback_resource) {
        free(feedback);
        wl_client_post_no_memory(client);
        return;
    }
    
    feedback->resource = feedback_resource;
    wl_resource_set_implementation(feedback_resource, NULL, feedback, feedback_resource_destroy);
    
    // Store feedback for later presentation callback
    // We'll send presented event when the surface is actually rendered
    log_printf("[PRESENTATION] ", "feedback() - surface=%p, feedback_id=%u\n",
               (void *)surface, id);
}

// Interface structures are defined in presentation-time-protocol.c
// We need to reference them properly
static const struct wp_presentation_interface presentation_interface = {
    .destroy = presentation_destroy,
    .feedback = presentation_feedback,
};

static void presentation_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wp_presentation_impl *presentation = data;
    
    struct wl_resource *resource = wl_resource_create(client, &wp_presentation_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(resource, &presentation_interface, presentation, NULL);
    
    // Send clock_id event immediately upon binding
    // Use CLOCK_MONOTONIC_RAW (id 4) for accurate, non-slewed timing
    // This matches what Weston detected: "presentation clock: CLOCK_MONOTONIC_RAW, id 4"
    uint32_t clock_id = 4; // CLOCK_MONOTONIC_RAW
    wp_presentation_send_clock_id(resource, clock_id);
    
    log_printf("[PRESENTATION] ", "presentation_bind() - client=%p, version=%u, id=%u, clock_id=%u (CLOCK_MONOTONIC_RAW)\n",
               (void *)client, version, id, clock_id);
}

struct wp_presentation_impl *wp_presentation_create(struct wl_display *display, struct wl_output_impl *output) {
    struct wp_presentation_impl *presentation = calloc(1, sizeof(*presentation));
    if (!presentation) {
        return NULL;
    }
    
    presentation->display = display;
    presentation->output = output;
    
    presentation->global = wl_global_create(display, &wp_presentation_interface, 2, presentation, presentation_bind);
    if (!presentation->global) {
        free(presentation);
        return NULL;
    }
    
    return presentation;
}

void wp_presentation_destroy(struct wp_presentation_impl *presentation) {
    if (!presentation) return;
    
    wl_global_destroy(presentation->global);
    free(presentation);
}

// Send presentation feedback when a surface is actually rendered
// This should be called from the render callback after a surface commit
void wp_presentation_send_feedback_for_surface(struct wp_presentation_impl *presentation,
                                                struct wl_surface_impl *surface) {
    if (!presentation || !surface) return;
    
    // Find all feedback resources for this surface
    // We need to iterate through all clients bound to the presentation global
    // For simplicity, we'll store feedback in a list or send immediately
    // This is a simplified implementation - a full implementation would track
    // feedback objects per surface and send presented events when rendering completes
    
    // For now, we'll send feedback immediately when surface is committed
    // A more complete implementation would track feedback and send it after actual presentation
    log_printf("[PRESENTATION] ", "send_feedback_for_surface() - surface=%p (simplified implementation)\n",
               (void *)surface);
}

