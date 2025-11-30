/*
 * macOS stub implementation of GBM functions
 * These are weak symbols that allow linking but fail at runtime
 */

#ifdef __APPLE__

#include "gbm.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

// Weak attribute allows these to be overridden if real implementations exist
#define WEAK __attribute__((weak))

// Stub implementations that fail at runtime
static void stub_error(const char *func) {
    fprintf(stderr, "Error: %s called but GBM is not available on macOS (stub implementation)\n", func);
    abort();
}

// GBM function stubs
WEAK struct gbm_device *gbm_create_device(int fd) { stub_error("gbm_create_device"); return NULL; }
WEAK void gbm_device_destroy(struct gbm_device *gbm) { stub_error("gbm_device_destroy"); }
WEAK int gbm_device_get_fd(struct gbm_device *gbm) { stub_error("gbm_device_get_fd"); return -1; }

WEAK struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags) { stub_error("gbm_bo_create"); return NULL; }
WEAK struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, const uint64_t *modifiers, const unsigned int count) { stub_error("gbm_bo_create_with_modifiers"); return NULL; }
WEAK struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, const uint64_t *modifiers, const unsigned int count, uint32_t flags) { stub_error("gbm_bo_create_with_modifiers2"); return NULL; }
WEAK void gbm_bo_destroy(struct gbm_bo *bo) { stub_error("gbm_bo_destroy"); }
WEAK uint32_t gbm_bo_get_width(struct gbm_bo *bo) { stub_error("gbm_bo_get_width"); return 0; }
WEAK uint32_t gbm_bo_get_height(struct gbm_bo *bo) { stub_error("gbm_bo_get_height"); return 0; }
WEAK uint32_t gbm_bo_get_stride(struct gbm_bo *bo) { stub_error("gbm_bo_get_stride"); return 0; }
WEAK uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane) { stub_error("gbm_bo_get_stride_for_plane"); return 0; }
WEAK uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane) { stub_error("gbm_bo_get_offset"); return 0; }
WEAK uint64_t gbm_bo_get_modifier(struct gbm_bo *bo) { stub_error("gbm_bo_get_modifier"); return 0; }
WEAK int gbm_bo_get_fd(struct gbm_bo *bo) { stub_error("gbm_bo_get_fd"); return -1; }
WEAK int gbm_bo_get_plane_count(struct gbm_bo *bo) { stub_error("gbm_bo_get_plane_count"); return 0; }
WEAK union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo) { stub_error("gbm_bo_get_handle"); union gbm_bo_handle h = {0}; return h; }
WEAK uint32_t gbm_bo_get_format(struct gbm_bo *bo) { stub_error("gbm_bo_get_format"); return 0; }

#endif // __APPLE__

