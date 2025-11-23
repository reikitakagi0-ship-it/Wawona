#pragma once

#include <wayland-server-core.h>

// wl_drm error codes
#define WL_DRM_ERROR_AUTHENTICATE_FAIL 0
#define WL_DRM_ERROR_INVALID_FORMAT 1
#define WL_DRM_ERROR_INVALID_NAME 2

// Forward declaration
struct wl_drm_impl;

// Create wl_drm global
struct wl_drm_impl *wl_drm_create(struct wl_display *display);

// Destroy wl_drm global
void wl_drm_destroy(struct wl_drm_impl *drm);

// wl_drm interface (for wayland-server)
extern const struct wl_interface wl_drm_interface;

