#pragma once

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <wayland-server-core.h>

// EGL buffer handler for rendering EGL buffers using KosmicKrisp+Zink
// This handler initializes EGL, binds the Wayland display, and can query/access EGL buffers

struct egl_buffer_handler {
    EGLDisplay egl_display;
    EGLContext egl_context;
    EGLConfig egl_config;
    bool initialized;
    bool display_bound;
};

// Initialize EGL buffer handler
// Returns 0 on success, -1 on failure
int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display);

// Cleanup EGL buffer handler
void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler);

// Query EGL buffer properties
// Returns 0 on success, -1 if buffer is not an EGL buffer or query fails
int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                     struct wl_resource *buffer_resource,
                                     int32_t *width, int32_t *height,
                                     EGLint *texture_format);

// Create EGL image from Wayland buffer
// Returns EGL_NO_IMAGE_KHR on failure
EGLImageKHR egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource);

// Check if a buffer is an EGL buffer
bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                       struct wl_resource *buffer_resource);

