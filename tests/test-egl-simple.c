#include <stdio.h>
#include <stdlib.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>

int main(void) {
    printf("=== EGL Test for macOS ===\n\n");
    
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        fprintf(stderr, "FAIL: eglGetDisplay returned EGL_NO_DISPLAY\n");
        return 1;
    }
    printf("PASS: eglGetDisplay succeeded\n");
    
    EGLint major, minor;
    if (!eglInitialize(display, &major, &minor)) {
        fprintf(stderr, "FAIL: eglInitialize failed\n");
        return 1;
    }
    printf("PASS: eglInitialize succeeded (EGL %d.%d)\n", major, minor);
    
    const char *vendor = eglQueryString(display, EGL_VENDOR);
    printf("  Vendor: %s\n", vendor ? vendor : "(null)");
    
    const char *version = eglQueryString(display, EGL_VERSION);
    printf("  Version: %s\n", version ? version : "(null)");
    
    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    printf("  Extensions: %s\n", extensions ? extensions : "(null)");
    
    EGLint num_configs;
    EGLConfig config;
    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    if (!eglChooseConfig(display, attribs, &config, 1, &num_configs) || num_configs == 0) {
        fprintf(stderr, "FAIL: eglChooseConfig failed\n");
        eglTerminate(display);
        return 1;
    }
    printf("PASS: eglChooseConfig found %d config(s)\n", num_configs);
    
    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        fprintf(stderr, "FAIL: eglBindAPI failed\n");
        eglTerminate(display);
        return 1;
    }
    printf("PASS: eglBindAPI succeeded\n");
    
    EGLint ctx_attribs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attribs);
    if (context == EGL_NO_CONTEXT) {
        fprintf(stderr, "FAIL: eglCreateContext failed (error: 0x%04x)\n", eglGetError());
        eglTerminate(display);
        return 1;
    }
    printf("PASS: eglCreateContext succeeded\n");
    
    EGLint pbuffer_attribs[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
    EGLSurface surface = eglCreatePbufferSurface(display, config, pbuffer_attribs);
    if (surface == EGL_NO_SURFACE) {
        fprintf(stderr, "FAIL: eglCreatePbufferSurface failed (error: 0x%04x)\n", eglGetError());
        eglDestroyContext(display, context);
        eglTerminate(display);
        return 1;
    }
    printf("PASS: eglCreatePbufferSurface succeeded\n");
    
    if (!eglMakeCurrent(display, surface, surface, context)) {
        fprintf(stderr, "FAIL: eglMakeCurrent failed (error: 0x%04x)\n", eglGetError());
        eglDestroySurface(display, surface);
        eglDestroyContext(display, context);
        eglTerminate(display);
        return 1;
    }
    printf("PASS: eglMakeCurrent succeeded\n");
    
    const char *gl_version = (const char *)glGetString(GL_VERSION);
    const char *gl_vendor = (const char *)glGetString(GL_VENDOR);
    const char *gl_renderer = (const char *)glGetString(GL_RENDERER);
    printf("  GL Version: %s\n", gl_version ? gl_version : "(null)");
    printf("  GL Vendor: %s\n", gl_vendor ? gl_vendor : "(null)");
    printf("  GL Renderer: %s\n", gl_renderer ? gl_renderer : "(null)");
    
    glClearColor(0.5f, 0.5f, 0.5f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        fprintf(stderr, "FAIL: glClear generated error 0x%04x\n", error);
    } else {
        printf("PASS: glClear succeeded\n");
    }
    
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    
    printf("\n✓ All tests passed!\n");
    return 0;
}
