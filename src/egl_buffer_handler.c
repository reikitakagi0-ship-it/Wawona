#include "egl_buffer_handler.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-server.h>

// EGL extension function pointers
static PFNEGLQUERYWAYLANDBUFFERWLPROC eglQueryWaylandBufferWL = NULL;
static PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR = NULL;
static PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR = NULL;
static PFNEGLBINDWAYLANDDISPLAYWLPROC eglBindWaylandDisplayWL = NULL;
static PFNEGLUNBINDWAYLANDDISPLAYWLPROC eglUnbindWaylandDisplayWL = NULL;

static bool load_egl_extensions(void) {
    // Load EGL extension functions
    eglQueryWaylandBufferWL = (PFNEGLQUERYWAYLANDBUFFERWLPROC)eglGetProcAddress("eglQueryWaylandBufferWL");
    eglCreateImageKHR = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    eglDestroyImageKHR = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    eglBindWaylandDisplayWL = (PFNEGLBINDWAYLANDDISPLAYWLPROC)eglGetProcAddress("eglBindWaylandDisplayWL");
    eglUnbindWaylandDisplayWL = (PFNEGLUNBINDWAYLANDDISPLAYWLPROC)eglGetProcAddress("eglUnbindWaylandDisplayWL");
    
    return eglQueryWaylandBufferWL != NULL &&
           eglCreateImageKHR != NULL &&
           eglDestroyImageKHR != NULL &&
           eglBindWaylandDisplayWL != NULL &&
           eglUnbindWaylandDisplayWL != NULL;
}

int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
    if (!handler || !display) {
        return -1;
    }
    
    memset(handler, 0, sizeof(*handler));
    
    // Initialize EGL display (use default display for macOS)
    handler->egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (handler->egl_display == EGL_NO_DISPLAY) {
        fprintf(stderr, "[EGL_BUFFER] Failed to get EGL display\n");
        return -1;
    }
    
    // Initialize EGL
    EGLint major, minor;
    if (!eglInitialize(handler->egl_display, &major, &minor)) {
        fprintf(stderr, "[EGL_BUFFER] Failed to initialize EGL\n");
        return -1;
    }
    
    // Load EGL extensions
    if (!load_egl_extensions()) {
        fprintf(stderr, "[EGL_BUFFER] Failed to load required EGL extensions\n");
        eglTerminate(handler->egl_display);
        return -1;
    }
    
    // Choose EGL config (surfaceless for compositor)
    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT | EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_NONE
    };
    
    EGLint num_configs;
    if (!eglChooseConfig(handler->egl_display, attribs, &handler->egl_config, 1, &num_configs) ||
        num_configs == 0) {
        fprintf(stderr, "[EGL_BUFFER] Failed to choose EGL config\n");
        eglTerminate(handler->egl_display);
        return -1;
    }
    
    // Create EGL context (surfaceless)
    EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };
    
    handler->egl_context = eglCreateContext(handler->egl_display, handler->egl_config,
                                            EGL_NO_CONTEXT, ctx_attribs);
    if (handler->egl_context == EGL_NO_CONTEXT) {
        fprintf(stderr, "[EGL_BUFFER] Failed to create EGL context\n");
        eglTerminate(handler->egl_display);
        return -1;
    }
    
    // Bind Wayland display to EGL
    if (!eglBindWaylandDisplayWL(handler->egl_display, display)) {
        fprintf(stderr, "[EGL_BUFFER] Failed to bind Wayland display to EGL\n");
        eglDestroyContext(handler->egl_display, handler->egl_context);
        eglTerminate(handler->egl_display);
        return -1;
    }
    
    handler->initialized = true;
    handler->display_bound = true;
    
    fprintf(stderr, "[EGL_BUFFER] EGL buffer handler initialized (EGL %d.%d)\n", major, minor);
    return 0;
}

void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
    if (!handler || !handler->initialized) {
        return;
    }
    
    if (handler->display_bound && handler->egl_display != EGL_NO_DISPLAY) {
        eglUnbindWaylandDisplayWL(handler->egl_display, NULL);
        handler->display_bound = false;
    }
    
    if (handler->egl_context != EGL_NO_CONTEXT) {
        eglDestroyContext(handler->egl_display, handler->egl_context);
        handler->egl_context = EGL_NO_CONTEXT;
    }
    
    if (handler->egl_display != EGL_NO_DISPLAY) {
        eglTerminate(handler->egl_display);
        handler->egl_display = EGL_NO_DISPLAY;
    }
    
    handler->initialized = false;
}

bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                       struct wl_resource *buffer_resource) {
    if (!handler || !handler->initialized || !buffer_resource) {
        return false;
    }
    
    // CRITICAL: Validate buffer resource is still valid before querying
    // If the client disconnected or buffer was destroyed, querying could crash
    if (wl_resource_get_user_data(buffer_resource) == NULL ||
        wl_resource_get_client(buffer_resource) == NULL) {
        return false; // Buffer resource is invalid
    }
    
    // Try to query the buffer - if it succeeds, it's an EGL buffer
    // Note: eglQueryWaylandBufferWL returns EGL_FALSE for non-EGL buffers (safe)
    EGLint width;
    EGLBoolean result = eglQueryWaylandBufferWL(handler->egl_display, buffer_resource,
                                                 EGL_WIDTH, &width);
    
    // Check for EGL errors - if there's an error, it's not an EGL buffer
    if (result != EGL_TRUE) {
        EGLint error = eglGetError();
        // EGL_BAD_PARAMETER is expected for non-EGL buffers, other errors indicate problems
        if (error != EGL_BAD_PARAMETER && error != EGL_SUCCESS) {
            // Log unexpected errors but don't crash
            fprintf(stderr, "[EGL_BUFFER] Warning: eglQueryWaylandBufferWL error: 0x%x\n", error);
        }
        return false;
    }
    
    return true;
}

int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                     struct wl_resource *buffer_resource,
                                     int32_t *width, int32_t *height,
                                     EGLint *texture_format) {
    if (!handler || !handler->initialized || !buffer_resource || !width || !height) {
        return -1;
    }
    
    // CRITICAL: Validate buffer resource is still valid before querying
    // If the client disconnected or buffer was destroyed, querying could crash
    if (wl_resource_get_user_data(buffer_resource) == NULL ||
        wl_resource_get_client(buffer_resource) == NULL) {
        return -1; // Buffer resource is invalid
    }
    
    EGLint egl_width, egl_height, egl_format;
    
    // Query buffer properties - check each query individually for better error handling
    if (eglQueryWaylandBufferWL(handler->egl_display, buffer_resource,
                                 EGL_WIDTH, &egl_width) != EGL_TRUE) {
        eglGetError(); // Clear error state
        return -1;
    }
    
    if (eglQueryWaylandBufferWL(handler->egl_display, buffer_resource,
                                 EGL_HEIGHT, &egl_height) != EGL_TRUE) {
        eglGetError(); // Clear error state
        return -1;
    }
    
    if (eglQueryWaylandBufferWL(handler->egl_display, buffer_resource,
                                 EGL_TEXTURE_FORMAT, &egl_format) != EGL_TRUE) {
        eglGetError(); // Clear error state
        return -1;
    }
    
    *width = (int32_t)egl_width;
    *height = (int32_t)egl_height;
    if (texture_format) {
        *texture_format = egl_format;
    }
    
    return 0;
}

EGLImageKHR egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource) {
    if (!handler || !handler->initialized || !buffer_resource) {
        return EGL_NO_IMAGE_KHR;
    }
    
    // CRITICAL: Validate buffer resource is still valid before creating image
    // If the client disconnected or buffer was destroyed, creating image could crash
    if (wl_resource_get_user_data(buffer_resource) == NULL ||
        wl_resource_get_client(buffer_resource) == NULL) {
        return EGL_NO_IMAGE_KHR; // Buffer resource is invalid
    }
    
    // Verify this is actually an EGL buffer before trying to create image
    if (!egl_buffer_handler_is_egl_buffer(handler, buffer_resource)) {
        return EGL_NO_IMAGE_KHR; // Not an EGL buffer
    }
    
    // Create EGL image from Wayland buffer
    EGLint attribs[] = { EGL_NONE };
    EGLImageKHR image = eglCreateImageKHR(handler->egl_display, EGL_NO_CONTEXT,
                                          EGL_WAYLAND_BUFFER_WL, buffer_resource, attribs);
    
    // Check for errors
    if (image == EGL_NO_IMAGE_KHR) {
        EGLint error = eglGetError();
        fprintf(stderr, "[EGL_BUFFER] Warning: eglCreateImageKHR failed: 0x%x\n", error);
    }
    
    return image;
}

