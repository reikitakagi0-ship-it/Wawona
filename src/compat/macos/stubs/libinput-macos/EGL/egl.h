#ifndef __egl_h_
#define __egl_h_

#ifdef __APPLE__
// macOS stub EGL header - allows compilation but functions will fail at runtime
// For a real implementation, use Mesa's EGL or implement EGL on top of Metal/OpenGL

#include <stdint.h>
#include <stddef.h>

typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLContext;
typedef void *EGLSurface;
typedef int32_t EGLint;
typedef uint32_t EGLBoolean;
typedef void *EGLSync;
typedef void *EGLImage;
typedef EGLImage EGLImageKHR;  // EGLImageKHR is the same as EGLImage
typedef uint64_t EGLuint64KHR;  // For EGL extensions
typedef intptr_t EGLAttrib;
// On macOS, use void* for native types to match platform expectations
typedef void* EGLNativeDisplayType;
typedef void* EGLNativeWindowType;
typedef void *EGLClientBuffer;
typedef unsigned int EGLenum;
typedef char GLchar;

// API calling conventions
#ifndef EGLAPIENTRY
#define EGLAPIENTRY
#endif
#ifndef EGLAPIENTRYP
#define EGLAPIENTRYP EGLAPIENTRY *
#endif
#ifndef EGLAPI
#define EGLAPI extern
#endif

#define EGL_FALSE 0
#define EGL_TRUE 1
#define EGL_DEFAULT_DISPLAY ((EGLNativeDisplayType)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_NO_SYNC ((EGLSync)0)
#define EGL_NO_IMAGE ((EGLImage)0)
#define EGL_NO_IMAGE_KHR ((EGLImageKHR)0)

// EGL_ANDROID_native_fence_sync extension
#define EGL_SYNC_NATIVE_FENCE_FD_ANDROID 0x3144

// EGL image attributes
#define EGL_WIDTH 0x3056
#define EGL_HEIGHT 0x3057
#define EGL_TEXTURE_FORMAT 0x3080
#define EGL_TEXTURE_RGB 0x305D
#define EGL_TEXTURE_RGBA 0x305E
#define EGL_IMAGE_PRESERVED_KHR 0x30D2
#define EGL_LINUX_DRM_FOURCC_EXT 0x3271

// EGL_EXT_image_dma_buf_import extension constants
#define EGL_DMA_BUF_PLANE0_FD_EXT 0x3272
#define EGL_DMA_BUF_PLANE0_OFFSET_EXT 0x3273
#define EGL_DMA_BUF_PLANE0_PITCH_EXT 0x3274
#define EGL_DMA_BUF_PLANE1_FD_EXT 0x3275
#define EGL_DMA_BUF_PLANE1_OFFSET_EXT 0x3276
#define EGL_DMA_BUF_PLANE1_PITCH_EXT 0x3277
#define EGL_DMA_BUF_PLANE2_FD_EXT 0x3278
#define EGL_DMA_BUF_PLANE2_OFFSET_EXT 0x3279
#define EGL_DMA_BUF_PLANE2_PITCH_EXT 0x327A
// Note: EGL_DMA_BUF_PLANE3_* and modifier constants are defined in weston-egl-ext.h
// Only add constants that aren't already defined there
#define EGL_YUV_FULL_RANGE_EXT 0x3335
#define EGL_ITU_REC601_EXT 0x3336
#define EGL_ITU_REC2020_EXT 0x3337

// EGL_IMG_context_priority extension
#define EGL_CONTEXT_PRIORITY_LEVEL_IMG 0x3100
#define EGL_CONTEXT_PRIORITY_HIGH_IMG 0x3101
#define EGL_CONTEXT_PRIORITY_MEDIUM_IMG 0x3102
#define EGL_CONTEXT_PRIORITY_LOW_IMG 0x3103

// EGL_EXT_yuv_surface extension
#define EGL_YUV_COLOR_SPACE_HINT_EXT 0x3331
#define EGL_ITU_REC709_EXT 0x3332
#define EGL_SAMPLE_RANGE_HINT_EXT 0x3333
#define EGL_YUV_NARROW_RANGE_EXT 0x3334
#define EGL_LINUX_DMA_BUF_EXT 0x3270

#define EGL_NONE 0x3038
#define EGL_SUCCESS 0x3000
#define EGL_NOT_INITIALIZED 0x3001
#define EGL_BAD_ACCESS 0x3002
#define EGL_BAD_ALLOC 0x3003
#define EGL_BAD_ATTRIBUTE 0x3004
#define EGL_BAD_CONFIG 0x3005
#define EGL_BAD_CONTEXT 0x3006
#define EGL_BAD_CURRENT_SURFACE 0x3007
#define EGL_BAD_DISPLAY 0x3008
#define EGL_BAD_MATCH 0x3009
#define EGL_BAD_NATIVE_PIXMAP 0x300A
#define EGL_BAD_NATIVE_WINDOW 0x300B
#define EGL_BAD_PARAMETER 0x300C
#define EGL_BAD_SURFACE 0x300D

#define EGL_WINDOW_BIT 0x0004
#define EGL_PIXMAP_BIT 0x0002
#define EGL_PBUFFER_BIT 0x0001

#define EGL_RED_SIZE 0x3020
#define EGL_GREEN_SIZE 0x3021
#define EGL_BLUE_SIZE 0x3022
#define EGL_ALPHA_SIZE 0x3023
#define EGL_BUFFER_SIZE 0x3024
#define EGL_SURFACE_TYPE 0x3033
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_CONFIG_ID 0x3028
#define EGL_MIN_SWAP_INTERVAL 0x303B
#define EGL_MAX_SWAP_INTERVAL 0x303C
#define EGL_DEPTH_SIZE 0x3025
#define EGL_STENCIL_SIZE 0x3026
#define EGL_SAMPLES 0x3031
#define EGL_SAMPLE_BUFFERS 0x3032
#define EGL_ALPHA_MASK_SIZE 0x303E
#define EGL_LUMINANCE_SIZE 0x303D
#define EGL_NATIVE_VISUAL_ID 0x302E
#define EGL_NATIVE_VISUAL_TYPE 0x302F
#define EGL_TRANSPARENT_TYPE 0x3034
#define EGL_TRANSPARENT_RED_VALUE 0x3035
#define EGL_TRANSPARENT_GREEN_VALUE 0x3036
#define EGL_TRANSPARENT_BLUE_VALUE 0x3037
#define EGL_BIND_TO_TEXTURE_RGB 0x3039
#define EGL_BIND_TO_TEXTURE_RGBA 0x303A
#define EGL_CONTEXT_LOST 0x300E
#define EGL_MULTISAMPLE_RESOLVE_BOX_BIT 0x0200
#define EGL_SWAP_BEHAVIOR_PRESERVED_BIT 0x0400
#define EGL_DONT_CARE ((EGLint)-1)

#define EGL_OPENGL_ES_BIT 0x0001
#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_OPENGL_BIT 0x0008

#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_CONTEXT_MAJOR_VERSION 0x3098
#define EGL_CONTEXT_MINOR_VERSION 0x30FB

#define EGL_PLATFORM_WAYLAND_KHR 0x31D8
#define EGL_PLATFORM_GBM_KHR 0x31D7

#define EGL_OPENGL_ES_API 0x30A0
#define EGL_OPENGL_API 0x30A2
#define EGL_EXTENSIONS 0x3055
#define EGL_VERSION 0x3054
#define EGL_VENDOR 0x3053
#define EGL_CLIENT_APIS 0x308D

// Extension constants
#define EGL_NO_CONFIG_KHR ((EGLConfig)0)

#define EGL_PRESENT_OPAQUE_EXT 0x31DF
// Note: EGL_SURFACE_COMPRESSION_EXT value may differ between headers
// Weston uses 0x34B0, standard uses 0x34A0 - we'll use Weston's value
#define EGL_SURFACE_COMPRESSION_EXT 0x34B0
// Weston uses different values for compression rates - use Weston's values
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_DEFAULT_EXT 0x34B2
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_1BPC_EXT 0x34B4
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_2BPC_EXT 0x34B5
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_3BPC_EXT 0x34B6
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_4BPC_EXT 0x34B7
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_5BPC_EXT 0x34B8
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_6BPC_EXT 0x34B9
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_7BPC_EXT 0x34BA
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_8BPC_EXT 0x34BB
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_9BPC_EXT 0x34BC
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_10BPC_EXT 0x34BD
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_11BPC_EXT 0x34BE
#define EGL_SURFACE_COMPRESSION_FIXED_RATE_12BPC_EXT 0x34BF

// Stub function declarations - these will fail at runtime
EGLAPI EGLDisplay EGLAPIENTRY eglGetDisplay(EGLNativeDisplayType display_id);
EGLAPI EGLBoolean EGLAPIENTRY eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor);
EGLAPI EGLBoolean EGLAPIENTRY eglTerminate(EGLDisplay dpy);
EGLAPI const char *EGLAPIENTRY eglQueryString(EGLDisplay dpy, EGLint name);
EGLAPI EGLBoolean EGLAPIENTRY eglGetConfigs(EGLDisplay dpy, EGLConfig *configs, EGLint config_size, EGLint *num_config);
EGLAPI EGLBoolean EGLAPIENTRY eglChooseConfig(EGLDisplay dpy, const EGLint *attrib_list, EGLConfig *configs, EGLint config_size, EGLint *num_config);
EGLAPI EGLBoolean EGLAPIENTRY eglGetConfigAttrib(EGLDisplay dpy, EGLConfig config, EGLint attribute, EGLint *value);
EGLAPI EGLSurface EGLAPIENTRY eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list);
EGLAPI EGLSurface EGLAPIENTRY eglCreatePbufferSurface(EGLDisplay dpy, EGLConfig config, const EGLint *attrib_list);
EGLAPI EGLBoolean EGLAPIENTRY eglDestroySurface(EGLDisplay dpy, EGLSurface surface);
EGLAPI EGLBoolean EGLAPIENTRY eglQuerySurface(EGLDisplay dpy, EGLSurface surface, EGLint attribute, EGLint *value);
EGLAPI EGLBoolean EGLAPIENTRY eglBindAPI(EGLenum api);
EGLAPI EGLContext EGLAPIENTRY eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *attrib_list);
EGLAPI EGLBoolean EGLAPIENTRY eglDestroyContext(EGLDisplay dpy, EGLContext ctx);
EGLAPI EGLBoolean EGLAPIENTRY eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx);
EGLAPI EGLContext EGLAPIENTRY eglGetCurrentContext(void);
EGLAPI EGLDisplay EGLAPIENTRY eglGetCurrentDisplay(void);
EGLAPI EGLSurface EGLAPIENTRY eglGetCurrentSurface(EGLint readdraw);
EGLAPI EGLBoolean EGLAPIENTRY eglSwapBuffers(EGLDisplay dpy, EGLSurface surface);
EGLAPI EGLBoolean EGLAPIENTRY eglSwapInterval(EGLDisplay dpy, EGLint interval);
EGLAPI EGLint EGLAPIENTRY eglGetError(void);
EGLAPI EGLBoolean EGLAPIENTRY eglReleaseThread(void);
EGLAPI EGLBoolean EGLAPIENTRY eglQueryContext(EGLDisplay dpy, EGLContext ctx, EGLint attribute, EGLint *value);

// Platform extension
EGLAPI EGLDisplay EGLAPIENTRY eglGetPlatformDisplay(EGLenum platform, void *native_display, const EGLAttrib *attrib_list);
EGLAPI void *EGLAPIENTRY eglGetProcAddress(const char *procname);

// Platform extension function pointer types
// Note: Weston uses EGLint * for attrib_list, not EGLAttrib *
typedef EGLDisplay (EGLAPIENTRYP PFNEGLGETPLATFORMDISPLAYEXTPROC)(EGLenum platform, void *native_display, const EGLint *attrib_list);
typedef EGLSurface (EGLAPIENTRYP PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC)(EGLDisplay dpy, EGLConfig config, void *native_window, const EGLint *attrib_list);

// EGL_KHR_image extension function pointer types
typedef EGLImageKHR (EGLAPIENTRYP PFNEGLCREATEIMAGEKHRPROC)(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buffer, const EGLint *attrib_list);
typedef EGLBoolean (EGLAPIENTRYP PFNEGLDESTROYIMAGEKHRPROC)(EGLDisplay dpy, EGLImageKHR image);

// EGL_KHR_swap_buffers_with_damage extension
typedef EGLBoolean (EGLAPIENTRYP PFNEGLSWAPBUFFERSWITHDAMAGEEXTPROC)(EGLDisplay dpy, EGLSurface surface, EGLint *rects, EGLint n_rects);

// EGL_KHR_partial_update extension
typedef EGLBoolean (EGLAPIENTRYP PFNEGLSETDAMAGEREGIONKHRPROC)(EGLDisplay dpy, EGLSurface surface, EGLint *rects, EGLint n_rects);

// EGL_KHR_fence_sync extension
typedef EGLint (EGLAPIENTRYP PFNEGLWAITSYNCKHRPROC)(EGLDisplay dpy, EGLSync sync, EGLint flags);

#endif // __APPLE__
#endif // __egl_h_

