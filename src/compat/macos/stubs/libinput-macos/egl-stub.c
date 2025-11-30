/*
 * macOS stub implementation of EGL functions
 * These are weak symbols that allow linking but fail at runtime
 */

#ifdef __APPLE__

#include "EGL/egl.h"
#include <stdio.h>
#include <stdlib.h>

// Weak attribute allows these to be overridden if real implementations exist
#define WEAK __attribute__((weak))

// Stub implementations that fail at runtime
static void stub_error(const char *func) {
    fprintf(stderr, "Error: %s called but EGL is not available on macOS (stub implementation)\n", func);
    exit(1);
}

// EGL function stubs
WEAK EGLDisplay eglGetDisplay(EGLNativeDisplayType display_id) { stub_error("eglGetDisplay"); return EGL_NO_DISPLAY; }
WEAK EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor) { stub_error("eglInitialize"); return EGL_FALSE; }
WEAK EGLBoolean eglTerminate(EGLDisplay dpy) { stub_error("eglTerminate"); return EGL_FALSE; }
WEAK const char *eglQueryString(EGLDisplay dpy, EGLint name) { stub_error("eglQueryString"); return NULL; }
WEAK EGLBoolean eglGetConfigs(EGLDisplay dpy, EGLConfig *configs, EGLint config_size, EGLint *num_config) { stub_error("eglGetConfigs"); return EGL_FALSE; }
WEAK EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list, EGLConfig *configs, EGLint config_size, EGLint *num_config) { stub_error("eglChooseConfig"); return EGL_FALSE; }
WEAK EGLBoolean eglGetConfigAttrib(EGLDisplay dpy, EGLConfig config, EGLint attribute, EGLint *value) { stub_error("eglGetConfigAttrib"); return EGL_FALSE; }
WEAK EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list) { stub_error("eglCreateWindowSurface"); return EGL_NO_SURFACE; }
WEAK EGLSurface eglCreatePbufferSurface(EGLDisplay dpy, EGLConfig config, const EGLint *attrib_list) { stub_error("eglCreatePbufferSurface"); return EGL_NO_SURFACE; }
WEAK EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface) { stub_error("eglDestroySurface"); return EGL_FALSE; }
WEAK EGLBoolean eglQuerySurface(EGLDisplay dpy, EGLSurface surface, EGLint attribute, EGLint *value) { stub_error("eglQuerySurface"); return EGL_FALSE; }
WEAK EGLBoolean eglBindAPI(EGLenum api) { stub_error("eglBindAPI"); return EGL_FALSE; }
WEAK EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *attrib_list) { stub_error("eglCreateContext"); return EGL_NO_CONTEXT; }
WEAK EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx) { stub_error("eglDestroyContext"); return EGL_FALSE; }
WEAK EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx) { stub_error("eglMakeCurrent"); return EGL_FALSE; }
WEAK EGLContext eglGetCurrentContext(void) { stub_error("eglGetCurrentContext"); return EGL_NO_CONTEXT; }
WEAK EGLDisplay eglGetCurrentDisplay(void) { stub_error("eglGetCurrentDisplay"); return EGL_NO_DISPLAY; }
WEAK EGLSurface eglGetCurrentSurface(EGLint readdraw) { stub_error("eglGetCurrentSurface"); return EGL_NO_SURFACE; }
WEAK EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface) { stub_error("eglSwapBuffers"); return EGL_FALSE; }
WEAK EGLBoolean eglSwapInterval(EGLDisplay dpy, EGLint interval) { stub_error("eglSwapInterval"); return EGL_FALSE; }
WEAK EGLint eglGetError(void) { return EGL_SUCCESS; }
WEAK EGLBoolean eglReleaseThread(void) { stub_error("eglReleaseThread"); return EGL_FALSE; }
WEAK EGLBoolean eglQueryContext(EGLDisplay dpy, EGLContext ctx, EGLint attribute, EGLint *value) { stub_error("eglQueryContext"); return EGL_FALSE; }
WEAK EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *native_display, const EGLAttrib *attrib_list) { stub_error("eglGetPlatformDisplay"); return EGL_NO_DISPLAY; }
WEAK void *eglGetProcAddress(const char *procname) { stub_error("eglGetProcAddress"); return NULL; }

#endif // __APPLE__

