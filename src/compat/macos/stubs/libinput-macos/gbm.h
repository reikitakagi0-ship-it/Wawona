#ifndef _GBM_H_
#define _GBM_H_

#ifdef __APPLE__
// macOS/iOS GBM (Generic Buffer Manager) header
// Complete GBM API implementation using IOSurface/Metal
// Provides Linux-compatible GBM API for macOS/iOS

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct gbm_device;
struct gbm_bo;
struct gbm_surface;

union gbm_bo_handle {
   void *ptr;
   int32_t s32;
   uint32_t u32;
   int64_t s64;
   uint64_t u64;
};

enum gbm_bo_format {
   GBM_BO_FORMAT_XRGB8888,
   GBM_BO_FORMAT_ARGB8888
};

// Extended format definitions (DRM fourcc codes)
#define GBM_FORMAT_XRGB8888 0x34325258  // 'XR24'
#define GBM_FORMAT_ARGB8888 0x34325241  // 'AR24'
#define GBM_FORMAT_XBGR8888 0x34324258  // 'XB24'
#define GBM_FORMAT_ABGR8888 0x34324241  // 'AB24'
#define GBM_FORMAT_RGB565   0x32315258  // 'RGB5'
#define GBM_FORMAT_RGB888   0x34324752  // 'RGB8'
#define GBM_FORMAT_BGR888   0x34324742  // 'BGR8'
#define GBM_FORMAT_XRGB2101010 0x30335258  // 'X30'
#define GBM_FORMAT_ARGB2101010 0x30335241  // 'A30'

// GBM buffer usage flags
#define GBM_BO_USE_RENDERING 0x0001
#define GBM_BO_USE_SCANOUT 0x0002
#define GBM_BO_USE_CURSOR 0x0004
#define GBM_BO_USE_CURSOR_64X64 0x0008
#define GBM_BO_USE_WRITE 0x0010
#define GBM_BO_USE_LINEAR 0x0020
#define GBM_BO_USE_PROTECTED 0x0040
#define GBM_BO_USE_FRONT_RENDERING 0x0080
#define GBM_BO_USE_TEXTURING 0x0100

// Format name descriptor
struct gbm_format_name_desc {
    char name[16];
};

// ============================================================================
// Device Functions
// ============================================================================
struct gbm_device *gbm_create_device(int fd);
void gbm_device_destroy(struct gbm_device *gbm);
int gbm_device_get_fd(struct gbm_device *gbm);
const char *gbm_device_get_backend_name(struct gbm_device *gbm);
int gbm_device_is_format_supported(struct gbm_device *gbm, uint32_t format, uint32_t flags);
int gbm_device_get_format_modifier_plane_count(struct gbm_device *gbm, uint32_t format, uint64_t modifier);
uint32_t gbm_device_get_major(struct gbm_device *gbm);
uint32_t gbm_device_get_minor(struct gbm_device *gbm);
uint32_t gbm_device_get_patch(struct gbm_device *gbm);

// ============================================================================
// Buffer Object Functions
// ============================================================================
struct gbm_bo *gbm_bo_create(struct gbm_device *gbm,
                              uint32_t width, uint32_t height,
                              uint32_t format, uint32_t flags);
struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm,
                                             uint32_t width, uint32_t height,
                                             uint32_t format,
                                             const uint64_t *modifiers,
                                             const unsigned int count);
struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *gbm,
                                              uint32_t width, uint32_t height,
                                              uint32_t format,
                                              const uint64_t *modifiers,
                                              const unsigned int count,
                                              uint32_t flags);
void gbm_bo_destroy(struct gbm_bo *bo);
struct gbm_bo *gbm_bo_ref(struct gbm_bo *bo);
uint32_t gbm_bo_get_width(struct gbm_bo *bo);
uint32_t gbm_bo_get_height(struct gbm_bo *bo);
uint32_t gbm_bo_get_stride(struct gbm_bo *bo);
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane);
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane);
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo);
int gbm_bo_get_fd(struct gbm_bo *bo);
int gbm_bo_get_plane_count(struct gbm_bo *bo);
union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo);
uint32_t gbm_bo_get_format(struct gbm_bo *bo);
void *gbm_bo_get_user_data(struct gbm_bo *bo);
void gbm_bo_set_user_data(struct gbm_bo *bo, void *data);
struct gbm_device *gbm_bo_get_device(struct gbm_bo *bo);
void *gbm_bo_map(struct gbm_bo *bo, uint32_t x, uint32_t y, uint32_t width, uint32_t height,
                uint32_t flags, uint32_t *stride, void **map_data);
void gbm_bo_unmap(struct gbm_bo *bo, void *map_data);

// ============================================================================
// Surface Functions (Critical for EGL)
// ============================================================================
struct gbm_surface *gbm_surface_create(struct gbm_device *gbm,
                                       uint32_t width, uint32_t height,
                                       uint32_t format, uint32_t flags);
struct gbm_surface *gbm_surface_create_with_modifiers(struct gbm_device *gbm,
                                                       uint32_t width, uint32_t height,
                                                       uint32_t format,
                                                       const uint64_t *modifiers,
                                                       const unsigned int count);
void gbm_surface_destroy(struct gbm_surface *surface);
struct gbm_bo *gbm_surface_lock_front_buffer(struct gbm_surface *surface);
void gbm_surface_release_buffer(struct gbm_surface *surface, struct gbm_bo *bo);
int gbm_surface_has_free_buffers(struct gbm_surface *surface);
void gbm_surface_set_user_data(struct gbm_surface *surface, void *data);
void *gbm_surface_get_user_data(struct gbm_surface *surface);

// ============================================================================
// Format Query Functions
// ============================================================================
const char *gbm_format_get_name(uint32_t format, struct gbm_format_name_desc *desc);

// ============================================================================
// macOS/iOS Specific Helpers
// ============================================================================
#ifdef __OBJC__
#import <IOSurface/IOSurfaceRef.h>
IOSurfaceRef gbm_bo_get_iosurface(struct gbm_bo *bo);
#else
void *gbm_bo_get_iosurface(struct gbm_bo *bo);
#endif
uint32_t gbm_bo_get_iosurface_id(struct gbm_bo *bo);

#ifdef __cplusplus
}
#endif

#endif // __APPLE__
#endif // _GBM_H_

