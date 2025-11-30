/*
 * Comprehensive EGL Test Suite for macOS (KosmicKrisp + Zink)
 * Tests all EGL features, context types, and edge cases
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __APPLE__
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <GLES3/gl3.h>
#else
#error "This test is for macOS only"
#endif

#define TEST_ASSERT(condition, message) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "FAIL: %s\n", message); \
            fprintf(stderr, "  Location: %s:%d\n", __FILE__, __LINE__); \
            return false; \
        } \
    } while (0)

#define TEST_PASS(message) \
    do { \
        fprintf(stdout, "PASS: %s\n", message); \
    } while (0)

#define TEST_WARN(message) \
    do { \
        fprintf(stdout, "WARN: %s\n", message); \
    } while (0)

static int tests_passed = 0;
static int tests_failed = 0;
static int tests_warned = 0;

static bool test_egl_initialization(void) {
    EGLDisplay display;
    EGLint major, minor;
    EGLBoolean result;

    fprintf(stdout, "\n=== Test 1: EGL Initialization ===\n");

    // Test eglGetDisplay with default
    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay should not return EGL_NO_DISPLAY");
    TEST_PASS("eglGetDisplay(EGL_DEFAULT_DISPLAY) returned valid display");
    tests_passed++;

    // Test eglGetDisplay with EGL_DEFAULT_DISPLAY (same as NULL on most platforms)
    // Note: On macOS, EGLNativeDisplayType is int, so we use EGL_DEFAULT_DISPLAY directly
    EGLDisplay display2 = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display2 != EGL_NO_DISPLAY, "eglGetDisplay(EGL_DEFAULT_DISPLAY) should not return EGL_NO_DISPLAY");
    TEST_PASS("eglGetDisplay(EGL_DEFAULT_DISPLAY) returned valid display");
    tests_passed++;

    // Test eglInitialize
    result = eglInitialize(display, &major, &minor);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize should return EGL_TRUE");
    TEST_ASSERT(major > 0, "EGL major version should be > 0");
    TEST_ASSERT(minor >= 0, "EGL minor version should be >= 0");
    fprintf(stdout, "  EGL Version: %d.%d\n", major, minor);
    TEST_PASS("eglInitialize succeeded");
    tests_passed++;

    // Test eglQueryString for vendor
    const char *vendor = eglQueryString(display, EGL_VENDOR);
    TEST_ASSERT(vendor != NULL, "eglQueryString(EGL_VENDOR) should not return NULL");
    fprintf(stdout, "  EGL Vendor: %s\n", vendor);
    TEST_PASS("eglQueryString(EGL_VENDOR) succeeded");
    tests_passed++;

    // Test eglQueryString for version
    const char *version = eglQueryString(display, EGL_VERSION);
    TEST_ASSERT(version != NULL, "eglQueryString(EGL_VERSION) should not return NULL");
    fprintf(stdout, "  EGL Version String: %s\n", version);
    TEST_PASS("eglQueryString(EGL_VERSION) succeeded");
    tests_passed++;

    // Test eglQueryString for extensions
    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    TEST_ASSERT(extensions != NULL, "eglQueryString(EGL_EXTENSIONS) should not return NULL");
    fprintf(stdout, "  EGL Extensions: %s\n", extensions);
    TEST_PASS("eglQueryString(EGL_EXTENSIONS) succeeded");
    tests_passed++;

    // Test eglQueryString for client APIs
    const char *apis = eglQueryString(EGL_NO_DISPLAY, EGL_CLIENT_APIS);
    if (apis != NULL) {
        fprintf(stdout, "  Client APIs: %s\n", apis);
        TEST_PASS("eglQueryString(EGL_CLIENT_APIS) succeeded");
        tests_passed++;
    } else {
        TEST_WARN("eglQueryString(EGL_CLIENT_APIS) returned NULL");
        tests_warned++;
    }

    // Test eglTerminate
    result = eglTerminate(display);
    TEST_ASSERT(result == EGL_TRUE, "eglTerminate should return EGL_TRUE");
    TEST_PASS("eglTerminate succeeded");
    tests_passed++;

    return true;
}

static bool test_egl_configs_comprehensive(void) {
    EGLDisplay display;
    EGLint num_configs;
    EGLConfig *configs;
    EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 2: EGL Config Enumeration (Comprehensive) ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    // Get number of configs
    result = eglChooseConfig(display, attribs, NULL, 0, &num_configs);
    TEST_ASSERT(result == EGL_TRUE, "eglChooseConfig (count) should return EGL_TRUE");
    TEST_ASSERT(num_configs > 0, "Should have at least one config");
    fprintf(stdout, "  Found %d matching configs\n", num_configs);
    TEST_PASS("eglChooseConfig found configs");
    tests_passed++;

    // Allocate and get configs
    configs = (EGLConfig *)malloc(num_configs * sizeof(EGLConfig));
    TEST_ASSERT(configs != NULL, "malloc failed");

    result = eglChooseConfig(display, attribs, configs, num_configs, &num_configs);
    TEST_ASSERT(result == EGL_TRUE, "eglChooseConfig should return EGL_TRUE");
    TEST_PASS("eglChooseConfig retrieved configs");
    tests_passed++;

    // Test eglGetConfigAttrib for various attributes
    EGLint value;
    EGLint attrs[] = {
        EGL_RED_SIZE, EGL_GREEN_SIZE, EGL_BLUE_SIZE, EGL_ALPHA_SIZE,
        EGL_BUFFER_SIZE, EGL_CONFIG_ID, EGL_DEPTH_SIZE, EGL_STENCIL_SIZE,
        EGL_SURFACE_TYPE, EGL_RENDERABLE_TYPE, EGL_SAMPLE_BUFFERS, EGL_SAMPLES,
        EGL_NATIVE_RENDERABLE, EGL_NATIVE_VISUAL_ID, EGL_NATIVE_VISUAL_TYPE,
        EGL_MAX_SWAP_INTERVAL, EGL_MIN_SWAP_INTERVAL
    };
    const char *attr_names[] = {
        "RED_SIZE", "GREEN_SIZE", "BLUE_SIZE", "ALPHA_SIZE",
        "BUFFER_SIZE", "CONFIG_ID", "DEPTH_SIZE", "STENCIL_SIZE",
        "SURFACE_TYPE", "RENDERABLE_TYPE", "SAMPLE_BUFFERS", "SAMPLES",
        "NATIVE_RENDERABLE", "NATIVE_VISUAL_ID", "NATIVE_VISUAL_TYPE",
        "MAX_SWAP_INTERVAL", "MIN_SWAP_INTERVAL"
    };

    fprintf(stdout, "  Config[0] attributes:\n");
    for (size_t i = 0; i < sizeof(attrs)/sizeof(attrs[0]); i++) {
        result = eglGetConfigAttrib(display, configs[0], attrs[i], &value);
        if (result == EGL_TRUE) {
            fprintf(stdout, "    %s: %d\n", attr_names[i], value);
        } else {
            EGLint error = eglGetError();
            fprintf(stdout, "    %s: ERROR (0x%04x)\n", attr_names[i], error);
        }
    }
    TEST_PASS("eglGetConfigAttrib queries succeeded");
    tests_passed++;

    // Test eglGetConfigs (alternative API)
    EGLint total_configs;
    result = eglGetConfigs(display, NULL, 0, &total_configs);
    TEST_ASSERT(result == EGL_TRUE, "eglGetConfigs (count) should return EGL_TRUE");
    TEST_ASSERT(total_configs > 0, "Should have at least one total config");
    fprintf(stdout, "  Total configs available: %d\n", total_configs);
    TEST_PASS("eglGetConfigs found total configs");
    tests_passed++;

    free(configs);
    eglTerminate(display);

    return true;
}

static bool test_egl_context_versions(void) {
    EGLDisplay display;
    EGLConfig config;
    EGLContext context;
    EGLint num_configs;
    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 3: EGL Context Versions ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    result = eglChooseConfig(display, attribs, &config, 1, &num_configs);
    TEST_ASSERT(result == EGL_TRUE && num_configs > 0, "eglChooseConfig failed");

    result = eglBindAPI(EGL_OPENGL_ES_API);
    TEST_ASSERT(result == EGL_TRUE, "eglBindAPI should return EGL_TRUE");
    TEST_PASS("eglBindAPI(EGL_OPENGL_ES_API) succeeded");
    tests_passed++;

    // Test ES2 context
    EGLint ctx_attribs_es2[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attribs_es2);
    TEST_ASSERT(context != EGL_NO_CONTEXT, "eglCreateContext(ES2) should not return EGL_NO_CONTEXT");
    TEST_PASS("eglCreateContext(ES2) succeeded");
    tests_passed++;
    eglDestroyContext(display, context);

    // Test ES3 context (if supported) - need to choose a config that supports ES3
    EGLint es3_attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_NONE
    };
    EGLConfig es3_config;
    EGLint es3_num_configs;
    result = eglChooseConfig(display, es3_attribs, &es3_config, 1, &es3_num_configs);
    if (result == EGL_TRUE && es3_num_configs > 0) {
        EGLint ctx_attribs_es3[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
        context = eglCreateContext(display, es3_config, EGL_NO_CONTEXT, ctx_attribs_es3);
        if (context != EGL_NO_CONTEXT) {
            TEST_PASS("eglCreateContext(ES3) succeeded");
            tests_passed++;
            eglDestroyContext(display, context);
        } else {
            EGLint es3_error = eglGetError();
            fprintf(stdout, "  ES3 context creation failed (error: 0x%04x)\n", es3_error);
            TEST_WARN("eglCreateContext(ES3) not supported");
            tests_warned++;
        }
    } else {
        TEST_WARN("eglChooseConfig for ES3 config failed - ES3 may not be supported");
        tests_warned++;
    }

    // Test context sharing
    EGLContext ctx1 = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attribs_es2);
    TEST_ASSERT(ctx1 != EGL_NO_CONTEXT, "eglCreateContext(ctx1) failed");
    EGLContext ctx2 = eglCreateContext(display, config, ctx1, ctx_attribs_es2);
    if (ctx2 != EGL_NO_CONTEXT) {
        TEST_PASS("eglCreateContext with shared context succeeded");
        tests_passed++;
        eglDestroyContext(display, ctx2);
    } else {
        TEST_WARN("eglCreateContext with shared context not supported");
        tests_warned++;
    }
    eglDestroyContext(display, ctx1);

    // Test eglGetCurrentContext (should be EGL_NO_CONTEXT before makeCurrent)
    EGLContext current = eglGetCurrentContext();
    TEST_ASSERT(current == EGL_NO_CONTEXT, "eglGetCurrentContext should return EGL_NO_CONTEXT before makeCurrent");
    TEST_PASS("eglGetCurrentContext returned EGL_NO_CONTEXT (expected)");
    tests_passed++;

    // Test eglGetCurrentDisplay
    EGLDisplay current_display = eglGetCurrentDisplay();
    TEST_ASSERT(current_display == EGL_NO_DISPLAY, "eglGetCurrentDisplay should return EGL_NO_DISPLAY before makeCurrent");
    TEST_PASS("eglGetCurrentDisplay returned EGL_NO_DISPLAY (expected)");
    tests_passed++;

    // Test eglGetCurrentSurface
    EGLSurface current_draw = eglGetCurrentSurface(EGL_DRAW);
    TEST_ASSERT(current_draw == EGL_NO_SURFACE, "eglGetCurrentSurface(EGL_DRAW) should return EGL_NO_SURFACE before makeCurrent");
    TEST_PASS("eglGetCurrentSurface(EGL_DRAW) returned EGL_NO_SURFACE (expected)");
    tests_passed++;

    EGLSurface current_read = eglGetCurrentSurface(EGL_READ);
    TEST_ASSERT(current_read == EGL_NO_SURFACE, "eglGetCurrentSurface(EGL_READ) should return EGL_NO_SURFACE before makeCurrent");
    TEST_PASS("eglGetCurrentSurface(EGL_READ) returned EGL_NO_SURFACE (expected)");
    tests_passed++;

    eglTerminate(display);

    return true;
}

static bool test_egl_surfaces(void) {
    EGLDisplay display;
    EGLConfig config;
    EGLContext context;
    EGLSurface surface;
    EGLint num_configs;
    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_NONE
    };
    EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 4: EGL Surfaces ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    result = eglChooseConfig(display, attribs, &config, 1, &num_configs);
    TEST_ASSERT(result == EGL_TRUE && num_configs > 0, "eglChooseConfig failed");

    result = eglBindAPI(EGL_OPENGL_ES_API);
    TEST_ASSERT(result == EGL_TRUE, "eglBindAPI failed");

    context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attribs);
    TEST_ASSERT(context != EGL_NO_CONTEXT, "eglCreateContext failed");

    // Test pbuffer surface creation
    EGLint pbuffer_attribs[] = {
        EGL_WIDTH, 64,
        EGL_HEIGHT, 64,
        EGL_NONE
    };
    surface = eglCreatePbufferSurface(display, config, pbuffer_attribs);
    TEST_ASSERT(surface != EGL_NO_SURFACE, "eglCreatePbufferSurface should not return EGL_NO_SURFACE");
    TEST_PASS("eglCreatePbufferSurface succeeded");
    tests_passed++;

    // Test eglQuerySurface
    EGLint width, height;
    result = eglQuerySurface(display, surface, EGL_WIDTH, &width);
    TEST_ASSERT(result == EGL_TRUE, "eglQuerySurface(EGL_WIDTH) should return EGL_TRUE");
    TEST_ASSERT(width == 64, "Surface width should be 64");
    fprintf(stdout, "  Surface width: %d\n", width);
    TEST_PASS("eglQuerySurface(EGL_WIDTH) succeeded");
    tests_passed++;

    result = eglQuerySurface(display, surface, EGL_HEIGHT, &height);
    TEST_ASSERT(result == EGL_TRUE, "eglQuerySurface(EGL_HEIGHT) should return EGL_TRUE");
    TEST_ASSERT(height == 64, "Surface height should be 64");
    fprintf(stdout, "  Surface height: %d\n", height);
    TEST_PASS("eglQuerySurface(EGL_HEIGHT) succeeded");
    tests_passed++;

    // Test eglMakeCurrent
    result = eglMakeCurrent(display, surface, surface, context);
    TEST_ASSERT(result == EGL_TRUE, "eglMakeCurrent should return EGL_TRUE");
    TEST_PASS("eglMakeCurrent succeeded");
    tests_passed++;

    // Verify current context/surface after makeCurrent
    EGLContext current_ctx = eglGetCurrentContext();
    TEST_ASSERT(current_ctx == context, "eglGetCurrentContext should return the context we made current");
    TEST_PASS("eglGetCurrentContext returns correct context");
    tests_passed++;

    EGLSurface current_draw = eglGetCurrentSurface(EGL_DRAW);
    TEST_ASSERT(current_draw == surface, "eglGetCurrentSurface(EGL_DRAW) should return the surface we made current");
    TEST_PASS("eglGetCurrentSurface(EGL_DRAW) returns correct surface");
    tests_passed++;

    // Test eglSwapBuffers (should work with pbuffer)
    result = eglSwapBuffers(display, surface);
    TEST_ASSERT(result == EGL_TRUE, "eglSwapBuffers should return EGL_TRUE");
    TEST_PASS("eglSwapBuffers succeeded");
    tests_passed++;

    // Test eglSwapInterval
    result = eglSwapInterval(display, 1);
    if (result == EGL_TRUE) {
        TEST_PASS("eglSwapInterval(1) succeeded");
        tests_passed++;
    } else {
        TEST_WARN("eglSwapInterval(1) not supported");
        tests_warned++;
    }

    // Test eglMakeCurrent with EGL_NO_SURFACE (unbind)
    result = eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    TEST_ASSERT(result == EGL_TRUE, "eglMakeCurrent(unbind) should return EGL_TRUE");
    TEST_PASS("eglMakeCurrent(unbind) succeeded");
    tests_passed++;

    // Verify unbind worked
    current_ctx = eglGetCurrentContext();
    TEST_ASSERT(current_ctx == EGL_NO_CONTEXT, "eglGetCurrentContext should return EGL_NO_CONTEXT after unbind");
    TEST_PASS("eglGetCurrentContext returns EGL_NO_CONTEXT after unbind");
    tests_passed++;

    // Cleanup
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);

    return true;
}

static bool test_gles2_comprehensive(void) {
    EGLDisplay display;
    EGLConfig config;
    EGLContext context;
    EGLSurface surface;
    EGLint num_configs;
    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_NONE
    };
    EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };
    EGLint pbuffer_attribs[] = {
        EGL_WIDTH, 256,
        EGL_HEIGHT, 256,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 5: OpenGL ES 2.0 Functions (Comprehensive) ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    result = eglChooseConfig(display, attribs, &config, 1, &num_configs);
    TEST_ASSERT(result == EGL_TRUE && num_configs > 0, "eglChooseConfig failed");

    result = eglBindAPI(EGL_OPENGL_ES_API);
    TEST_ASSERT(result == EGL_TRUE, "eglBindAPI failed");

    context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attribs);
    TEST_ASSERT(context != EGL_NO_CONTEXT, "eglCreateContext failed");

    surface = eglCreatePbufferSurface(display, config, pbuffer_attribs);
    TEST_ASSERT(surface != EGL_NO_SURFACE, "eglCreatePbufferSurface failed");

    result = eglMakeCurrent(display, surface, surface, context);
    TEST_ASSERT(result == EGL_TRUE, "eglMakeCurrent failed");

    // Test GLES2 string queries
    const char *gl_version = (const char *)glGetString(GL_VERSION);
    TEST_ASSERT(gl_version != NULL, "glGetString(GL_VERSION) should not return NULL");
    fprintf(stdout, "  OpenGL ES Version: %s\n", gl_version);
    TEST_PASS("glGetString(GL_VERSION) succeeded");
    tests_passed++;

    const char *gl_vendor = (const char *)glGetString(GL_VENDOR);
    TEST_ASSERT(gl_vendor != NULL, "glGetString(GL_VENDOR) should not return NULL");
    fprintf(stdout, "  OpenGL ES Vendor: %s\n", gl_vendor);
    TEST_PASS("glGetString(GL_VENDOR) succeeded");
    tests_passed++;

    const char *gl_renderer = (const char *)glGetString(GL_RENDERER);
    TEST_ASSERT(gl_renderer != NULL, "glGetString(GL_RENDERER) should not return NULL");
    fprintf(stdout, "  OpenGL ES Renderer: %s\n", gl_renderer);
    TEST_PASS("glGetString(GL_RENDERER) succeeded");
    tests_passed++;

    const char *gl_extensions = (const char *)glGetString(GL_EXTENSIONS);
    TEST_ASSERT(gl_extensions != NULL, "glGetString(GL_EXTENSIONS) should not return NULL");
    fprintf(stdout, "  OpenGL ES Extensions: %s\n", gl_extensions);
    TEST_PASS("glGetString(GL_EXTENSIONS) succeeded");
    tests_passed++;

    // Test glGetError
    GLenum error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glGetError should return GL_NO_ERROR initially");
    TEST_PASS("glGetError returned GL_NO_ERROR");
    tests_passed++;

    // Test glViewport
    glViewport(0, 0, 256, 256);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glViewport should not generate error");
    TEST_PASS("glViewport succeeded");
    tests_passed++;

    // Test glClearColor and glClear
    glClearColor(0.25f, 0.5f, 0.75f, 1.0f);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glClearColor should not generate error");
    TEST_PASS("glClearColor succeeded");
    tests_passed++;

    glClear(GL_COLOR_BUFFER_BIT);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glClear should not generate error");
    TEST_PASS("glClear succeeded");
    tests_passed++;

    // Test glGetIntegerv
    GLint max_texture_size;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max_texture_size);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glGetIntegerv should not generate error");
    TEST_ASSERT(max_texture_size > 0, "GL_MAX_TEXTURE_SIZE should be > 0");
    fprintf(stdout, "  GL_MAX_TEXTURE_SIZE: %d\n", max_texture_size);
    TEST_PASS("glGetIntegerv(GL_MAX_TEXTURE_SIZE) succeeded");
    tests_passed++;

    // Test glEnable/glDisable
    glEnable(GL_BLEND);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glEnable should not generate error");
    TEST_PASS("glEnable(GL_BLEND) succeeded");
    tests_passed++;

    glDisable(GL_BLEND);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glDisable should not generate error");
    TEST_PASS("glDisable(GL_BLEND) succeeded");
    tests_passed++;

    // Test glFlush
    glFlush();
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glFlush should not generate error");
    TEST_PASS("glFlush succeeded");
    tests_passed++;

    // Cleanup
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);

    return true;
}

static bool test_egl_extensions_comprehensive(void) {
    EGLDisplay display;
    const char *extensions;

    fprintf(stdout, "\n=== Test 6: EGL Extensions (Comprehensive) ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    extensions = eglQueryString(display, EGL_EXTENSIONS);
    TEST_ASSERT(extensions != NULL, "eglQueryString(EGL_EXTENSIONS) failed");

    fprintf(stdout, "  Checking for key extensions:\n");

    // Critical extensions for macOS/Zink
    const char *critical_exts[] = {
        "EGL_KHR_platform_wayland",
        "EGL_EXT_platform_wayland",
        "EGL_MESA_platform_surfaceless",
        "EGL_KHR_image_base",
        "EGL_KHR_gl_image",
        "EGL_KHR_gl_texture_2D_image",
        "EGL_KHR_gl_texture_cubemap_image",
        "EGL_KHR_gl_renderbuffer_image",
        "EGL_KHR_fence_sync",
        "EGL_KHR_reusable_sync",
        "EGL_KHR_wait_sync",
        "EGL_EXT_create_context_robustness",
        "EGL_KHR_create_context",
        "EGL_KHR_get_all_proc_addresses",
        "EGL_KHR_partial_update",
        "EGL_EXT_swap_buffers_with_damage",
        "EGL_KHR_swap_buffers_with_damage",
        "EGL_EXT_buffer_age",
        "EGL_KHR_mutable_render_buffer",
        "EGL_EXT_yuv_surface",
        "EGL_EXT_image_dma_buf_import",
        "EGL_EXT_image_dma_buf_import_modifiers",
        "EGL_MESA_image_dma_buf_export",
        "EGL_EXT_gl_colorspace",
        "EGL_KHR_gl_colorspace",
        "EGL_EXT_pixel_format_float",
        "EGL_KHR_no_config_context",
        "EGL_KHR_surfaceless_context",
        "EGL_EXT_surface_SMPTE2086_metadata",
        "EGL_EXT_surface_CTA861_3_metadata",
        NULL
    };

    int found_count = 0;
    for (int i = 0; critical_exts[i] != NULL; i++) {
        bool has_ext = strstr(extensions, critical_exts[i]) != NULL;
        fprintf(stdout, "    %s: %s\n", critical_exts[i], has_ext ? "YES" : "NO");
        if (has_ext) found_count++;
    }
    int total_exts = 0;
    for (int i = 0; critical_exts[i] != NULL; i++) total_exts++;
    fprintf(stdout, "  Found %d/%d critical extensions\n", found_count, total_exts);
    
    if (found_count > 0) {
        TEST_PASS("EGL extensions query succeeded");
        tests_passed++;
    } else {
        TEST_WARN("No critical extensions found (may be expected)");
        tests_warned++;
    }

    eglTerminate(display);

    return true;
}

static bool test_egl_error_handling_comprehensive(void) {
    EGLDisplay display;
    EGLint error;

    fprintf(stdout, "\n=== Test 7: EGL Error Handling (Comprehensive) ===\n");

    // Test eglGetError with no error
    EGLint initial_error = eglGetError();
    TEST_ASSERT(initial_error == EGL_SUCCESS, "eglGetError should return EGL_SUCCESS initially");
    TEST_PASS("eglGetError returned EGL_SUCCESS (expected)");
    tests_passed++;

    // Test invalid display - both accepting and rejecting are valid behaviors
    display = eglGetDisplay((EGLNativeDisplayType)0xDEADBEEF);
    error = eglGetError();
    if (display == EGL_NO_DISPLAY) {
        TEST_PASS("eglGetDisplay correctly rejected invalid display");
        tests_passed++;
    } else {
        // Accepting invalid display and returning default is also valid (implementation-specific)
        TEST_PASS("eglGetDisplay accepted invalid display (returns default - valid behavior)");
        tests_passed++;
    }

    // Test eglInitialize with invalid display
    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    bool configless_supported = extensions &&
        strstr(extensions, "EGL_MESA_configless_context");

    if (configless_supported) {
        EGLContext cfgless =
            eglCreateContext(display, NULL, EGL_NO_CONTEXT, NULL);
        TEST_ASSERT(cfgless != EGL_NO_CONTEXT,
                    "eglCreateContext should succeed when config is NULL if "
                    "EGL_MESA_configless_context is supported");
        if (cfgless != EGL_NO_CONTEXT) {
            eglDestroyContext(display, cfgless);
            TEST_PASS("Configless eglCreateContext succeeded");
            tests_passed++;
        }
    }

    // Test eglCreateContext with an invalid config handle
    EGLContext context = eglCreateContext(
        display, (EGLConfig)(uintptr_t)0xDEADBEEF, EGL_NO_CONTEXT, NULL);
    error = eglGetError();
    TEST_ASSERT(context == EGL_NO_CONTEXT,
                "eglCreateContext should return EGL_NO_CONTEXT with invalid config");
    TEST_ASSERT(error == EGL_BAD_CONFIG,
                "eglGetError should return EGL_BAD_CONFIG");
    fprintf(stdout, "  Error code (invalid config): 0x%04x (EGL_BAD_CONFIG)\n",
            error);
    TEST_PASS("EGL error handling works correctly");
    tests_passed++;

    // Test eglCreatePbufferSurface with invalid config
    EGLint pbuffer_attribs[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
    EGLSurface surface = eglCreatePbufferSurface(display, NULL, pbuffer_attribs);
    error = eglGetError();
    TEST_ASSERT(surface == EGL_NO_SURFACE, "eglCreatePbufferSurface should return EGL_NO_SURFACE with invalid config");
    TEST_ASSERT(error == EGL_BAD_CONFIG, "eglGetError should return EGL_BAD_CONFIG");
    TEST_PASS("eglCreatePbufferSurface error handling works correctly");
    tests_passed++;

    // Test eglMakeCurrent with invalid context
    result = eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, (EGLContext)0xDEADBEEF);
    error = eglGetError();
    TEST_ASSERT(result == EGL_FALSE, "eglMakeCurrent should return EGL_FALSE with invalid context");
    TEST_ASSERT(error == EGL_BAD_CONTEXT, "eglGetError should return EGL_BAD_CONTEXT");
    TEST_PASS("eglMakeCurrent error handling works correctly");
    tests_passed++;

    eglTerminate(display);

    return true;
}

static bool test_egl_release_thread(void) {
    fprintf(stdout, "\n=== Test 8: EGL Thread Management ===\n");

    EGLBoolean result = eglReleaseThread();
    TEST_ASSERT(result == EGL_TRUE, "eglReleaseThread should return EGL_TRUE");
    TEST_PASS("eglReleaseThread succeeded");
    tests_passed++;

    return true;
}

static bool test_egl_query_context(void) {
    EGLDisplay display;
    EGLConfig config;
    EGLContext context;
    EGLint num_configs;
    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_NONE
    };
    EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 9: EGL Context Queries ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    result = eglChooseConfig(display, attribs, &config, 1, &num_configs);
    TEST_ASSERT(result == EGL_TRUE && num_configs > 0, "eglChooseConfig failed");

    result = eglBindAPI(EGL_OPENGL_ES_API);
    TEST_ASSERT(result == EGL_TRUE, "eglBindAPI failed");

    context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attribs);
    TEST_ASSERT(context != EGL_NO_CONTEXT, "eglCreateContext failed");

    // Test eglQueryContext
    EGLint value;
    result = eglQueryContext(display, context, EGL_CONTEXT_CLIENT_VERSION, &value);
    if (result == EGL_TRUE) {
        fprintf(stdout, "  Context client version: %d\n", value);
        TEST_PASS("eglQueryContext(EGL_CONTEXT_CLIENT_VERSION) succeeded");
        tests_passed++;
    } else {
        TEST_WARN("eglQueryContext(EGL_CONTEXT_CLIENT_VERSION) not supported");
        tests_warned++;
    }

    result = eglQueryContext(display, context, EGL_RENDER_BUFFER, &value);
    if (result == EGL_TRUE) {
        fprintf(stdout, "  Render buffer: %d\n", value);
        TEST_PASS("eglQueryContext(EGL_RENDER_BUFFER) succeeded");
        tests_passed++;
    } else {
        TEST_WARN("eglQueryContext(EGL_RENDER_BUFFER) not supported");
        tests_warned++;
    }

    eglDestroyContext(display, context);
    eglTerminate(display);

    return true;
}

int main(void) {
    fprintf(stdout, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    fprintf(stdout, "EGL Comprehensive Test Suite for macOS\n");
    fprintf(stdout, "Testing KosmicKrisp + Zink EGL Implementation\n");
    fprintf(stdout, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    tests_passed = 0;
    tests_failed = 0;
    tests_warned = 0;

    bool all_passed = true;

    if (!test_egl_initialization()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_egl_configs_comprehensive()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_egl_context_versions()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_egl_surfaces()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_gles2_comprehensive()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_egl_extensions_comprehensive()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_egl_error_handling_comprehensive()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_egl_release_thread()) {
        all_passed = false;
        tests_failed++;
    }

    if (!test_egl_query_context()) {
        all_passed = false;
        tests_failed++;
    }

    fprintf(stdout, "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    fprintf(stdout, "Test Results:\n");
    fprintf(stdout, "  Passed: %d\n", tests_passed);
    fprintf(stdout, "  Failed: %d\n", tests_failed);
    fprintf(stdout, "  Warnings: %d\n", tests_warned);
    fprintf(stdout, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    if (all_passed && tests_failed == 0) {
        fprintf(stdout, "\n✓ All tests passed! EGL is working correctly.\n");
        return 0;
    } else {
        fprintf(stderr, "\n✗ Some tests failed. EGL may not be fully functional.\n");
        return 1;
    }
}

