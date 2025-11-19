#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>

struct wl_output_impl;
struct wl_surface_impl;

struct wp_presentation_impl {
    struct wl_global *global;
    struct wl_display *display;
    struct wl_output_impl *output;
};

struct wp_presentation_impl *wp_presentation_create(struct wl_display *display, struct wl_output_impl *output);
void wp_presentation_destroy(struct wp_presentation_impl *presentation);
void wp_presentation_send_feedback_for_surface(struct wp_presentation_impl *presentation,
                                                struct wl_surface_impl *surface);

