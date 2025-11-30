#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"
#include "color-management-v1-client-protocol.h"

struct client_state {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_shm *shm;
    struct xdg_wm_base *xdg_wm_base;
    struct wp_color_manager_v1 *color_manager;
    
    struct wl_surface *surface;
    struct xdg_surface *xdg_surface;
    struct xdg_toplevel *xdg_toplevel;
    
    struct wp_image_description_creator_icc_v1 *icc_creator;
    struct wp_image_description_v1 *image_description;
    struct wp_color_management_surface_v1 *color_surface;
    
    int width, height;
    int running;
};

static void
registry_handle_global(void *data, struct wl_registry *registry,
                       uint32_t name, const char *interface, uint32_t version)
{
    struct client_state *state = data;
    (void)version;

    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        state->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        state->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        state->xdg_wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    } else if (strcmp(interface, wp_color_manager_v1_interface.name) == 0) {
        state->color_manager = wl_registry_bind(registry, name, &wp_color_manager_v1_interface, 1);
    }
}

static void
registry_handle_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
    // Handle removal
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    registry_handle_global,
    registry_handle_global_remove
};

static void
xdg_surface_handle_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial)
{
    struct client_state *state = data;
    (void)state;
    xdg_surface_ack_configure(xdg_surface, serial);
    
    // Simple render loop or just commit
    // In a real app, we would buffer allocation and drawing here
}

static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_handle_configure,
};

static void
xdg_toplevel_handle_close(void *data, struct xdg_toplevel *xdg_toplevel)
{
    struct client_state *state = data;
    (void)xdg_toplevel;
    state->running = 0;
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    NULL, // configure
    xdg_toplevel_handle_close,
    NULL, // configure_bounds
    NULL  // wm_capabilities
};

// Image description creator listener (empty for now as we don't handle errors explicitly)
// static const struct wp_image_description_creator_icc_v1_listener icc_creator_listener = {
//    // No events in current version, mainly errors
// };

static void
setup_color_management(struct client_state *state)
{
    if (!state->color_manager) {
        fprintf(stderr, "Color manager not available\n");
        return;
    }

    // Create a color management surface object
    state->color_surface = wp_color_manager_v1_get_surface(state->color_manager, state->surface);
    
    // Create an image description (e.g. sRGB)
    // For this test, we'll try to create a parametric one as it's simpler than loading an ICC profile
    struct wp_image_description_creator_params_v1 *params_creator = 
        wp_color_manager_v1_create_parametric_creator(state->color_manager);
        
    // Set parameters for sRGB (approximate)
    wp_image_description_creator_params_v1_set_tf_named(params_creator, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB);
    wp_image_description_creator_params_v1_set_primaries_named(params_creator, WP_COLOR_MANAGER_V1_PRIMARIES_SRGB);
    
    // Create the description
    wp_image_description_creator_params_v1_create(params_creator);
    
    // Note: In the real protocol, we need to listen for the 'ready' event or similar on the description
    // This is a simplified test client
    
    fprintf(stderr, "Color management setup initiated\n");
}

int main(void)
{
    struct client_state state = {0};
    state.running = 1;
    state.width = 400;
    state.height = 300;

    state.display = wl_display_connect(NULL);
    if (!state.display) {
        fprintf(stderr, "Failed to connect to display\n");
        return 1;
    }

    state.registry = wl_display_get_registry(state.display);
    wl_registry_add_listener(state.registry, &registry_listener, &state);
    wl_display_roundtrip(state.display);

    if (!state.compositor || !state.xdg_wm_base) {
        fprintf(stderr, "Missing compositor or xdg_wm_base\n");
        return 1;
    }

    state.surface = wl_compositor_create_surface(state.compositor);
    state.xdg_surface = xdg_wm_base_get_xdg_surface(state.xdg_wm_base, state.surface);
    xdg_surface_add_listener(state.xdg_surface, &xdg_surface_listener, &state);
    
    state.xdg_toplevel = xdg_surface_get_toplevel(state.xdg_surface);
    xdg_toplevel_add_listener(state.xdg_toplevel, &xdg_toplevel_listener, &state);
    xdg_toplevel_set_title(state.xdg_toplevel, "Wawona Color Test");

    wl_surface_commit(state.surface);
    
    setup_color_management(&state);

    while (state.running && wl_display_dispatch(state.display) != -1) {
        // Event loop
    }

    wl_display_disconnect(state.display);
    return 0;
}
