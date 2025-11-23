#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <stdio.h>
#include <stdlib.h>

static void dump_config(EGLDisplay dpy, EGLConfig cfg, int index)
{
    EGLint value;
    printf("Config %d:\n", index);

    eglGetConfigAttrib(dpy, cfg, EGL_RED_SIZE, &value);
    printf("  EGL_RED_SIZE: %d\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_GREEN_SIZE, &value);
    printf("  EGL_GREEN_SIZE: %d\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_BLUE_SIZE, &value);
    printf("  EGL_BLUE_SIZE: %d\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_ALPHA_SIZE, &value);
    printf("  EGL_ALPHA_SIZE: %d\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_DEPTH_SIZE, &value);
    printf("  EGL_DEPTH_SIZE: %d\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_STENCIL_SIZE, &value);
    printf("  EGL_STENCIL_SIZE: %d\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_RENDERABLE_TYPE, &value);
    printf("  EGL_RENDERABLE_TYPE: 0x%x\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_SURFACE_TYPE, &value);
    printf("  EGL_SURFACE_TYPE: 0x%x\n", value);

    eglGetConfigAttrib(dpy, cfg, EGL_CONFIG_ID, &value);
    printf("  EGL_CONFIG_ID: %d\n", value);
}

int main(void)
{
    EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (dpy == EGL_NO_DISPLAY) {
        fprintf(stderr, "eglGetDisplay failed\n");
        return 1;
    }

    if (!eglInitialize(dpy, NULL, NULL)) {
        fprintf(stderr, "eglInitialize failed\n");
        return 1;
    }

    EGLint num_configs = 0;
    if (!eglGetConfigs(dpy, NULL, 0, &num_configs) || num_configs == 0) {
        fprintf(stderr, "eglGetConfigs returned no configs\n");
        return 1;
    }

    EGLConfig *configs = calloc(num_configs, sizeof(EGLConfig));
    if (!configs)
        return 1;

    if (!eglGetConfigs(dpy, configs, num_configs, &num_configs)) {
        fprintf(stderr, "eglGetConfigs(list) failed\n");
        free(configs);
        return 1;
    }

    printf("Found %d configs\n", num_configs);
    for (EGLint i = 0; i < num_configs; i++)
        dump_config(dpy, configs[i], i);

    free(configs);
    eglTerminate(dpy);
    return 0;
}

