/*
 * Comprehensive EGL Test for macOS (KosmicKrisp + Zink)
 * Tests EGL initialization, context creation, and basic functionality
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#ifdef __APPLE__
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
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

static bool test_egl_initialization(void) {
    EGLDisplay display;
    EGLint major, minor;
    EGLBoolean result;

    fprintf(stdout, "\n=== Test 1: EGL Initialization ===\n");

    // Test eglGetDisplay
    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay should not return EGL_NO_DISPLAY");
    TEST_PASS("eglGetDisplay returned valid display");

    // Test eglInitialize
    result = eglInitialize(display, &major, &minor);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize should return EGL_TRUE");
    TEST_ASSERT(major > 0, "EGL major version should be > 0");
    TEST_ASSERT(minor >= 0, "EGL minor version should be >= 0");
    fprintf(stdout, "  EGL Version: %d.%d\n", major, minor);
    TEST_PASS("eglInitialize succeeded");

    // Test eglQueryString for vendor
    const char *vendor = eglQueryString(display, EGL_VENDOR);
    TEST_ASSERT(vendor != NULL, "eglQueryString(EGL_VENDOR) should not return NULL");
    fprintf(stdout, "  EGL Vendor: %s\n", vendor);
    TEST_PASS("eglQueryString(EGL_VENDOR) succeeded");

    // Test eglQueryString for version
    const char *version = eglQueryString(display, EGL_VERSION);
    TEST_ASSERT(version != NULL, "eglQueryString(EGL_VERSION) should not return NULL");
    fprintf(stdout, "  EGL Version String: %s\n", version);
    TEST_PASS("eglQueryString(EGL_VERSION) succeeded");

    // Test eglQueryString for extensions
    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    TEST_ASSERT(extensions != NULL, "eglQueryString(EGL_EXTENSIONS) should not return NULL");
    fprintf(stdout, "  EGL Extensions: %s\n", extensions);
    TEST_PASS("eglQueryString(EGL_EXTENSIONS) succeeded");

    // Test eglTerminate
    result = eglTerminate(display);
    TEST_ASSERT(result == EGL_TRUE, "eglTerminate should return EGL_TRUE");
    TEST_PASS("eglTerminate succeeded");

    return true;
}

static bool test_egl_configs(void) {
    EGLDisplay display;
    EGLint num_configs;
    EGLConfig *configs;
    EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 2: EGL Config Enumeration ===\n");

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

    // Allocate and get configs
    configs = (EGLConfig *)malloc(num_configs * sizeof(EGLConfig));
    TEST_ASSERT(configs != NULL, "malloc failed");

    result = eglChooseConfig(display, attribs, configs, num_configs, &num_configs);
    TEST_ASSERT(result == EGL_TRUE, "eglChooseConfig should return EGL_TRUE");
    TEST_PASS("eglChooseConfig retrieved configs");

    // Test eglGetConfigAttrib for first config
    EGLint value;
    result = eglGetConfigAttrib(display, configs[0], EGL_RED_SIZE, &value);
    TEST_ASSERT(result == EGL_TRUE, "eglGetConfigAttrib should return EGL_TRUE");
    fprintf(stdout, "  Config[0] RED_SIZE: %d\n", value);
    TEST_PASS("eglGetConfigAttrib succeeded");

    free(configs);
    eglTerminate(display);

    return true;
}

static bool test_egl_context_creation(void) {
    EGLDisplay display;
    EGLConfig config;
    EGLContext context;
    EGLint num_configs;
    EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 3: EGL Context Creation ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    // Get a config
    result = eglChooseConfig(display, attribs, &config, 1, &num_configs);
    TEST_ASSERT(result == EGL_TRUE && num_configs > 0, "eglChooseConfig failed");

    // Bind API
    result = eglBindAPI(EGL_OPENGL_ES_API);
    TEST_ASSERT(result == EGL_TRUE, "eglBindAPI should return EGL_TRUE");
    TEST_PASS("eglBindAPI(EGL_OPENGL_ES_API) succeeded");

    // Create context
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attribs);
    TEST_ASSERT(context != EGL_NO_CONTEXT, "eglCreateContext should not return EGL_NO_CONTEXT");
    TEST_PASS("eglCreateContext succeeded");

    // Test eglGetCurrentContext (should be EGL_NO_CONTEXT before makeCurrent)
    EGLContext current = eglGetCurrentContext();
    TEST_ASSERT(current == EGL_NO_CONTEXT, "eglGetCurrentContext should return EGL_NO_CONTEXT before makeCurrent");
    TEST_PASS("eglGetCurrentContext returned EGL_NO_CONTEXT (expected)");

    // Destroy context
    result = eglDestroyContext(display, context);
    TEST_ASSERT(result == EGL_TRUE, "eglDestroyContext should return EGL_TRUE");
    TEST_PASS("eglDestroyContext succeeded");

    eglTerminate(display);

    return true;
}

static bool test_gles2_functions(void) {
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
        EGL_WIDTH, 64,
        EGL_HEIGHT, 64,
        EGL_NONE
    };

    fprintf(stdout, "\n=== Test 4: OpenGL ES 2.0 Functions ===\n");

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

    // Create pbuffer surface
    surface = eglCreatePbufferSurface(display, config, pbuffer_attribs);
    TEST_ASSERT(surface != EGL_NO_SURFACE, "eglCreatePbufferSurface should not return EGL_NO_SURFACE");
    TEST_PASS("eglCreatePbufferSurface succeeded");

    // Make current
    result = eglMakeCurrent(display, surface, surface, context);
    TEST_ASSERT(result == EGL_TRUE, "eglMakeCurrent should return EGL_TRUE");
    TEST_PASS("eglMakeCurrent succeeded");

    // Test GLES2 functions
    const char *gl_version = (const char *)glGetString(GL_VERSION);
    TEST_ASSERT(gl_version != NULL, "glGetString(GL_VERSION) should not return NULL");
    fprintf(stdout, "  OpenGL ES Version: %s\n", gl_version);
    TEST_PASS("glGetString(GL_VERSION) succeeded");

    const char *gl_vendor = (const char *)glGetString(GL_VENDOR);
    TEST_ASSERT(gl_vendor != NULL, "glGetString(GL_VENDOR) should not return NULL");
    fprintf(stdout, "  OpenGL ES Vendor: %s\n", gl_vendor);
    TEST_PASS("glGetString(GL_VENDOR) succeeded");

    const char *gl_renderer = (const char *)glGetString(GL_RENDERER);
    TEST_ASSERT(gl_renderer != NULL, "glGetString(GL_RENDERER) should not return NULL");
    fprintf(stdout, "  OpenGL ES Renderer: %s\n", gl_renderer);
    TEST_PASS("glGetString(GL_RENDERER) succeeded");

    const char *gl_extensions = (const char *)glGetString(GL_EXTENSIONS);
    TEST_ASSERT(gl_extensions != NULL, "glGetString(GL_EXTENSIONS) should not return NULL");
    fprintf(stdout, "  OpenGL ES Extensions: %s\n", gl_extensions);
    TEST_PASS("glGetString(GL_EXTENSIONS) succeeded");

    // Test glViewport
    glViewport(0, 0, 64, 64);
    GLenum error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glViewport should not generate error");
    TEST_PASS("glViewport succeeded");

    // Test glClearColor and glClear
    glClearColor(0.5f, 0.5f, 0.5f, 1.0f);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glClearColor should not generate error");
    TEST_PASS("glClearColor succeeded");

    glClear(GL_COLOR_BUFFER_BIT);
    error = glGetError();
    TEST_ASSERT(error == GL_NO_ERROR, "glClear should not generate error");
    TEST_PASS("glClear succeeded");

    // Test eglSwapBuffers (should work with pbuffer)
    result = eglSwapBuffers(display, surface);
    TEST_ASSERT(result == EGL_TRUE, "eglSwapBuffers should return EGL_TRUE");
    TEST_PASS("eglSwapBuffers succeeded");

    // Cleanup
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);

    return true;
}

static bool test_egl_extensions(void) {
    EGLDisplay display;
    const char *extensions;

    fprintf(stdout, "\n=== Test 5: EGL Extensions ===\n");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    TEST_ASSERT(display != EGL_NO_DISPLAY, "eglGetDisplay failed");

    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    extensions = eglQueryString(display, EGL_EXTENSIONS);
    TEST_ASSERT(extensions != NULL, "eglQueryString(EGL_EXTENSIONS) failed");

    fprintf(stdout, "  Checking for key extensions:\n");

    // Check for platform extensions
    bool has_platform_wayland = strstr(extensions, "EGL_KHR_platform_wayland") != NULL ||
                                 strstr(extensions, "EGL_EXT_platform_wayland") != NULL;
    fprintf(stdout, "    EGL_KHR/EXT_platform_wayland: %s\n", has_platform_wayland ? "YES" : "NO");

    bool has_platform_surfaceless = strstr(extensions, "EGL_MESA_platform_surfaceless") != NULL;
    fprintf(stdout, "    EGL_MESA_platform_surfaceless: %s\n", has_platform_surfaceless ? "YES" : "NO");

    bool has_image_base = strstr(extensions, "EGL_KHR_image_base") != NULL;
    fprintf(stdout, "    EGL_KHR_image_base: %s\n", has_image_base ? "YES" : "NO");

    bool has_gl_image = strstr(extensions, "EGL_KHR_gl_image") != NULL;
    fprintf(stdout, "    EGL_KHR_gl_image: %s\n", has_gl_image ? "YES" : "NO");

    TEST_PASS("EGL extensions query succeeded");

    eglTerminate(display);

    return true;
}

static bool test_egl_error_handling(void) {
    EGLDisplay display;
    EGLint error;

    fprintf(stdout, "\n=== Test 6: EGL Error Handling ===\n");

    // Test eglGetError with no error
    error = eglGetError();
    TEST_ASSERT(error == EGL_SUCCESS, "eglGetError should return EGL_SUCCESS initially");
    TEST_PASS("eglGetError returned EGL_SUCCESS (expected)");

    // Test invalid display
    display = eglGetDisplay((EGLNativeDisplayType)0xDEADBEEF);
    error = eglGetError();
    // Note: eglGetDisplay might not set error, so we check if display is invalid
    if (display == EGL_NO_DISPLAY) {
        TEST_PASS("eglGetDisplay correctly rejected invalid display");
    } else {
        fprintf(stdout, "  Warning: eglGetDisplay accepted invalid display (implementation-specific)\n");
    }

    // Test eglInitialize with invalid display
    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLBoolean result = eglInitialize(display, NULL, NULL);
    TEST_ASSERT(result == EGL_TRUE, "eglInitialize failed");

    // Test eglCreateContext with invalid config
    EGLContext context = eglCreateContext(display, NULL, EGL_NO_CONTEXT, NULL);
    error = eglGetError();
    TEST_ASSERT(context == EGL_NO_CONTEXT, "eglCreateContext should return EGL_NO_CONTEXT with invalid config");
    TEST_ASSERT(error == EGL_BAD_CONFIG, "eglGetError should return EGL_BAD_CONFIG");
    fprintf(stdout, "  Error code: 0x%04x (EGL_BAD_CONFIG)\n", error);
    TEST_PASS("EGL error handling works correctly");

    eglTerminate(display);

    return true;
}

int main(void) {
    fprintf(stdout, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    fprintf(stdout, "EGL Comprehensive Test for macOS\n");
    fprintf(stdout, "Testing KosmicKrisp + Zink EGL Implementation\n");
    fprintf(stdout, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    int tests_passed = 0;
    int tests_failed = 0;

    if (test_egl_initialization()) {
        tests_passed++;
    } else {
        tests_failed++;
    }

    if (test_egl_configs()) {
        tests_passed++;
    } else {
        tests_failed++;
    }

    if (test_egl_context_creation()) {
        tests_passed++;
    } else {
        tests_failed++;
    }

    if (test_gles2_functions()) {
        tests_passed++;
    } else {
        tests_failed++;
    }

    if (test_egl_extensions()) {
        tests_passed++;
    } else {
        tests_failed++;
    }

    if (test_egl_error_handling()) {
        tests_passed++;
    } else {
        tests_failed++;
    }

    fprintf(stdout, "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    fprintf(stdout, "Test Results:\n");
    fprintf(stdout, "  Passed: %d\n", tests_passed);
    fprintf(stdout, "  Failed: %d\n", tests_failed);
    fprintf(stdout, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    if (tests_failed == 0) {
        fprintf(stdout, "\n✓ All tests passed! EGL is working correctly.\n");
        return 0;
    } else {
        fprintf(stderr, "\n✗ Some tests failed. EGL may not be fully functional.\n");
        return 1;
    }
}

