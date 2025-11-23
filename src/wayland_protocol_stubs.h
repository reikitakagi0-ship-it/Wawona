#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>

struct wl_decoration_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_activation_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_fractional_scale_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_cursor_shape_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_toplevel_icon_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_text_input_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_decoration_manager_impl *wl_decoration_create(struct wl_display *display);
void wl_decoration_destroy(struct wl_decoration_manager_impl *manager);

struct wl_activation_manager_impl *wl_activation_create(struct wl_display *display);
void wl_activation_destroy(struct wl_activation_manager_impl *manager);

struct wl_fractional_scale_manager_impl *wl_fractional_scale_create(struct wl_display *display);
void wl_fractional_scale_destroy(struct wl_fractional_scale_manager_impl *manager);

struct wl_cursor_shape_manager_impl *wl_cursor_shape_create(struct wl_display *display);
void wl_cursor_shape_destroy(struct wl_cursor_shape_manager_impl *manager);

// Cursor shape bridge function (implemented in cursor_shape_bridge.m)
void set_macos_cursor_shape(uint32_t shape);

struct wl_toplevel_icon_manager_impl *wl_toplevel_icon_create(struct wl_display *display);
void wl_toplevel_icon_destroy(struct wl_toplevel_icon_manager_impl *manager);

struct wl_text_input_manager_impl *wl_text_input_create(struct wl_display *display);
void wl_text_input_destroy(struct wl_text_input_manager_impl *manager);

// Text Input Protocol v1 (for weston-editor compatibility)
struct wl_text_input_manager_v1_impl {
    struct wl_display *display;
    struct wl_global *global;
};
struct wl_text_input_manager_v1_impl *wl_text_input_v1_create(struct wl_display *display);
void wl_text_input_v1_destroy(struct wl_text_input_manager_v1_impl *manager);

// Text input event helpers (called when surfaces gain/lose focus)
void wl_text_input_send_enter(struct wl_resource *surface);
void wl_text_input_send_leave(struct wl_resource *surface);
void wl_text_input_send_commit_string(const char *text);
void wl_text_input_send_preedit_string(const char *text, int32_t cursor_begin, int32_t cursor_end);

