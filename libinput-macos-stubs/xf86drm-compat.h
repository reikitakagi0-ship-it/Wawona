#ifndef XF86DRM_COMPAT_H
#define XF86DRM_COMPAT_H

#ifdef __APPLE__
// macOS compatibility for xf86drm.h
// xf86drm.h provides the fourcc_code macro
// We use Weston's own weston-drm-fourcc.h which already provides this for macOS

#include <stdint.h>

// Define fourcc_code macro (same as in weston-drm-fourcc.h)
#ifndef fourcc_code
#define fourcc_code(a, b, c, d) ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | ((uint32_t)(d) << 24))
#endif

// xf86drm.h typically also provides some DRM-related macros, but for Vulkan renderer
// we mainly need fourcc_code

#endif // __APPLE__

#endif // XF86DRM_COMPAT_H

