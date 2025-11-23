#ifndef _GBM_H_
#define _GBM_H_

#ifdef __APPLE__
// macOS stub GBM (Generic Buffer Manager) header - allows compilation but functions will fail at runtime
// GBM is Linux-specific; on macOS we use IOSurface/Metal instead

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

// Stub function declarations - these will fail at runtime
struct gbm_device *gbm_create_device(int fd);
void gbm_device_destroy(struct gbm_device *gbm);
int gbm_device_get_fd(struct gbm_device *gbm);

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

#ifdef __cplusplus
}
#endif

#endif // __APPLE__
#endif // _GBM_H_

