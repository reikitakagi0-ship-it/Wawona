#ifndef __eglext_h_
#define __eglext_h_

#ifdef __APPLE__
// macOS stub EGL extensions header

#include "egl.h"

// Extension strings
#define EGL_EXT_swap_buffers_with_damage "EGL_EXT_swap_buffers_with_damage"
#define EGL_KHR_swap_buffers_with_damage "EGL_KHR_swap_buffers_with_damage"
#define EGL_KHR_no_config_context "EGL_KHR_no_config_context"
#define EGL_KHR_surfaceless_context "EGL_KHR_surfaceless_context"
#define EGL_EXT_image_dma_buf_import "EGL_EXT_image_dma_buf_import"
#define EGL_PLATFORM_WAYLAND_KHR_EXTENSION "EGL_KHR_platform_wayland"
#define EGL_PLATFORM_GBM_KHR_EXTENSION "EGL_KHR_platform_gbm"

// Stub extension function declarations
typedef EGLBoolean (EGLAPIENTRYP PFNEGLSWAPBUFFERSWITHDAMAGEEXTPROC)(EGLDisplay dpy, EGLSurface surface, EGLint *rects, EGLint n_rects);
typedef EGLBoolean (EGLAPIENTRYP PFNEGLSWAPBUFFERSWITHDAMAGEKHRPROC)(EGLDisplay dpy, EGLSurface surface, EGLint *rects, EGLint n_rects);

EGLAPI EGLBoolean EGLAPIENTRY eglSwapBuffersWithDamageEXT(EGLDisplay dpy, EGLSurface surface, EGLint *rects, EGLint n_rects);
EGLAPI EGLBoolean EGLAPIENTRY eglSwapBuffersWithDamageKHR(EGLDisplay dpy, EGLSurface surface, EGLint *rects, EGLint n_rects);

#endif // __APPLE__
#endif // __eglext_h_

