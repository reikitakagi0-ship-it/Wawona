#include "wayland_seat.h"
#include <wayland-server-protocol.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static void
seat_get_pointer(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *pointer = wl_resource_create(client, &wl_pointer_interface, wl_resource_get_version(resource), id);
    if (!pointer) {
        wl_client_post_no_memory(client);
        return;
    }
    // We should set implementation for pointer (empty for now or standard)
    // wl_resource_set_implementation(pointer, &pointer_interface, seat, NULL);
    seat->pointer_resource = pointer; // Simple tracking (last one wins)
}

static void
seat_get_keyboard(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *keyboard = wl_resource_create(client, &wl_keyboard_interface, wl_resource_get_version(resource), id);
    if (!keyboard) {
        wl_client_post_no_memory(client);
        return;
    }
    // wl_resource_set_implementation(keyboard, &keyboard_interface, seat, NULL);
    seat->keyboard_resource = keyboard;
    
    // Send keymap if we have one (todo)
}

static void
seat_get_touch(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *touch = wl_resource_create(client, &wl_touch_interface, wl_resource_get_version(resource), id);
    if (!touch) {
        wl_client_post_no_memory(client);
        return;
    }
    seat->touch_resource = touch;
}

static void
seat_release(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static const struct wl_seat_interface seat_interface = {
    .get_pointer = seat_get_pointer,
    .get_keyboard = seat_get_keyboard,
    .get_touch = seat_get_touch,
    .release = seat_release,
};

static void
bind_seat(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wl_seat_impl *seat = data;
    struct wl_resource *resource;

    resource = wl_resource_create(client, &wl_seat_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &seat_interface, seat, NULL);
    
    if (version >= WL_SEAT_CAPABILITIES_SINCE_VERSION) {
        wl_seat_send_capabilities(resource, seat->capabilities);
    }
    
    if (version >= WL_SEAT_NAME_SINCE_VERSION) {
        wl_seat_send_name(resource, "seat0");
    }
    
    seat->seat_resource = resource; // Track last bound resource (should be list)
}

struct wl_seat_impl *
wl_seat_create(struct wl_display *display)
{
    struct wl_seat_impl *seat = calloc(1, sizeof(struct wl_seat_impl));
    if (!seat) return NULL;

    seat->display = display;
    seat->capabilities = WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD | WL_SEAT_CAPABILITY_TOUCH;
    seat->serial = 1;
    
    seat->global = wl_global_create(display, &wl_seat_interface, 7, seat, bind_seat);
    if (!seat->global) {
        free(seat);
        return NULL;
    }

    return seat;
}

void
wl_seat_destroy(struct wl_seat_impl *seat)
{
    if (!seat) return;
    if (seat->global) wl_global_destroy(seat->global);
    free(seat);
}

void
wl_seat_set_capabilities(struct wl_seat_impl *seat, uint32_t capabilities)
{
    if (!seat) return;
    seat->capabilities = capabilities;
    if (seat->seat_resource) {
        wl_seat_send_capabilities(seat->seat_resource, capabilities);
    }
}

uint32_t
wl_seat_get_serial(struct wl_seat_impl *seat)
{
    return seat ? seat->serial++ : 0;
}

void
wl_seat_set_focused_surface(struct wl_seat_impl *seat, void *surface)
{
    if (seat) seat->focused_surface = surface;
}

// Input event handlers stubs
void wl_seat_send_pointer_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, double x, double y) {
    (void)seat; (void)surface; (void)serial; (void)x; (void)y;
}
void wl_seat_send_pointer_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial) {
    (void)seat; (void)surface; (void)serial;
}
void wl_seat_send_pointer_motion(struct wl_seat_impl *seat, uint32_t time, double x, double y) {
    (void)seat; (void)time; (void)x; (void)y;
}
void wl_seat_send_pointer_button(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    (void)seat; (void)serial; (void)time; (void)button; (void)state;
}
void wl_seat_send_keyboard_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, struct wl_array *keys) {
    (void)seat; (void)surface; (void)serial; (void)keys;
}
void wl_seat_send_keyboard_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial) {
    (void)seat; (void)surface; (void)serial;
}
void wl_seat_send_keyboard_key(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t key, uint32_t state) {
    (void)seat; (void)serial; (void)time; (void)key; (void)state;
}
void wl_seat_send_keyboard_modifiers(struct wl_seat_impl *seat, uint32_t serial) {
    (void)seat; (void)serial;
}
void wl_seat_send_touch_down(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, struct wl_resource *surface, int32_t id, wl_fixed_t x, wl_fixed_t y) {
    (void)seat; (void)serial; (void)time; (void)surface; (void)id; (void)x; (void)y;
}
void wl_seat_send_touch_up(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, int32_t id) {
    (void)seat; (void)serial; (void)time; (void)id;
}
void wl_seat_send_touch_motion(struct wl_seat_impl *seat, uint32_t time, int32_t id, wl_fixed_t x, wl_fixed_t y) {
    (void)seat; (void)time; (void)id; (void)x; (void)y;
}
void wl_seat_send_touch_frame(struct wl_seat_impl *seat) {
    (void)seat;
}
void wl_seat_send_touch_cancel(struct wl_seat_impl *seat) {
    (void)seat;
}
