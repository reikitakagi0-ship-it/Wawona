#include "wayland_drm.h"
#include "wayland_compositor.h"
#include "logging.h"
#include <wayland-server.h>
#include <stdlib.h>
#include <string.h>

// Forward declarations
extern const struct wl_interface wl_buffer_interface;

// wl_drm interface definition
// Based on wayland-drm.xml protocol

// Format constants from drm_fourcc.h
#define WL_DRM_FORMAT_XRGB8888 0x34325258
#define WL_DRM_FORMAT_ARGB8888 0x34325241
#define WL_DRM_FORMAT_RGBX8888 0x34325852
#define WL_DRM_FORMAT_RGBA8888 0x34324152
#define WL_DRM_FORMAT_XBGR8888 0x34324258
#define WL_DRM_FORMAT_ABGR8888 0x34324241
#define WL_DRM_FORMAT_BGRX8888 0x34325842
#define WL_DRM_FORMAT_BGRA8888 0x34324142

// Event opcodes
#define WL_DRM_DEVICE 0
#define WL_DRM_FORMAT 1
#define WL_DRM_AUTHENTICATED 2
#define WL_DRM_CAPABILITIES 3

// Request opcodes
#define WL_DRM_AUTHENTICATE 0
#define WL_DRM_CREATE_BUFFER 1
#define WL_DRM_CREATE_PLANAR_BUFFER 2
#define WL_DRM_CREATE_PRIME_BUFFER 3

// Define wl_drm interface messages
static const struct wl_message wl_drm_requests[] = {
    { "authenticate", "u", NULL },                    // opcode 0
    { "create_buffer", "nuuiiu", NULL },             // opcode 1: id, name, width, height, stride, format
    { "create_planar_buffer", "nuuiiiiiiii", NULL }, // opcode 2: id, name, width, height, format, offset0, stride0, offset1, stride1, offset2, stride2
    { "create_prime_buffer", "huuiiiiiiii", NULL },  // opcode 3: id, name(fd), width, height, format, offset0, stride0, offset1, stride1, offset2, stride2
};

static const struct wl_message wl_drm_events[] = {
    { "device", "s", NULL },           // opcode 0: device name
    { "format", "u", NULL },           // opcode 1: format
    { "authenticated", "", NULL },     // opcode 2
    { "capabilities", "u", NULL },     // opcode 3: capabilities
};

const struct wl_interface wl_drm_interface = {
    "wl_drm", 2,
    4, wl_drm_requests,  // 4 requests
    4, wl_drm_events,    // 4 events
};

// wl_drm implementation
struct wl_drm_impl {
    struct wl_global *global;
    struct wl_display *display;
};

// Handle authenticate request
static void drm_authenticate(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    (void)client;
    (void)id;
    
    log_printf("[DRM] ", "authenticate() - client=%p, id=%u\n", (void *)client, id);
    
    // On macOS, we don't have DRM, so always succeed authentication
    // This allows EGL to proceed even though we can't actually create DRM buffers
    wl_resource_post_event(resource, WL_DRM_AUTHENTICATED);
    
    log_printf("[DRM] ", "authenticate() - sent authenticated event\n");
}

// Handle create_buffer request (stub - not supported on macOS)
static void drm_create_buffer(struct wl_client *client, struct wl_resource *resource,
                              uint32_t id, uint32_t name, int32_t width, int32_t height,
                              uint32_t stride, uint32_t format) {
    (void)client;
    (void)resource;
    (void)id;
    (void)name;
    (void)width;
    (void)height;
    (void)stride;
    (void)format;
    
    log_printf("[DRM] ", "create_buffer() - not supported on macOS (no DRM)\n");
    wl_resource_post_error(resource, WL_DRM_ERROR_INVALID_FORMAT, "DRM buffers not supported on macOS");
}

// Handle create_planar_buffer request (stub - not supported on macOS)
static void drm_create_planar_buffer(struct wl_client *client, struct wl_resource *resource,
                                     uint32_t id, uint32_t name, int32_t width, int32_t height,
                                     uint32_t format, int32_t offset0, int32_t stride0,
                                     int32_t offset1, int32_t stride1, int32_t offset2, int32_t stride2) {
    (void)client;
    (void)resource;
    (void)id;
    (void)name;
    (void)width;
    (void)height;
    (void)format;
    (void)offset0;
    (void)stride0;
    (void)offset1;
    (void)stride1;
    (void)offset2;
    (void)stride2;
    
    log_printf("[DRM] ", "create_planar_buffer() - not supported on macOS (no DRM)\n");
    wl_resource_post_error(resource, WL_DRM_ERROR_INVALID_FORMAT, "DRM buffers not supported on macOS");
}

// Handle create_prime_buffer request (stub - not supported on macOS)
static void drm_create_prime_buffer(struct wl_client *client, struct wl_resource *resource,
                                    uint32_t id, int32_t name_fd, int32_t width, int32_t height,
                                    uint32_t format, int32_t offset0, int32_t stride0,
                                    int32_t offset1, int32_t stride1, int32_t offset2, int32_t stride2) {
    (void)client;
    (void)resource;
    (void)id;
    (void)name_fd;
    (void)width;
    (void)height;
    (void)format;
    (void)offset0;
    (void)stride0;
    (void)offset1;
    (void)stride1;
    (void)offset2;
    (void)stride2;
    
    log_printf("[DRM] ", "create_prime_buffer() - not supported on macOS (no DRM)\n");
    wl_resource_post_error(resource, WL_DRM_ERROR_INVALID_FORMAT, "DRM buffers not supported on macOS");
}

// Define the interface implementation structure
// wayland-server uses function pointers, not a struct
// We need to use wl_resource_set_implementation with individual function pointers
// But wayland-scanner generates a struct, so we'll define it manually

// For wayland-server, we use wl_resource_set_implementation directly with function pointers
// The interface struct is just for organization
typedef struct {
    void (*authenticate)(struct wl_client *client, struct wl_resource *resource, uint32_t id);
    void (*create_buffer)(struct wl_client *client, struct wl_resource *resource, uint32_t id, uint32_t name, int32_t width, int32_t height, uint32_t stride, uint32_t format);
    void (*create_planar_buffer)(struct wl_client *client, struct wl_resource *resource, uint32_t id, uint32_t name, int32_t width, int32_t height, uint32_t format, int32_t offset0, int32_t stride0, int32_t offset1, int32_t stride1, int32_t offset2, int32_t stride2);
    void (*create_prime_buffer)(struct wl_client *client, struct wl_resource *resource, uint32_t id, int32_t name_fd, int32_t width, int32_t height, uint32_t format, int32_t offset0, int32_t stride0, int32_t offset1, int32_t stride1, int32_t offset2, int32_t stride2);
} wl_drm_interface_impl;

static const wl_drm_interface_impl drm_interface_impl = {
    .authenticate = drm_authenticate,
    .create_buffer = drm_create_buffer,
    .create_planar_buffer = drm_create_planar_buffer,
    .create_prime_buffer = drm_create_prime_buffer,
};

// Handle client binding to wl_drm global
static void drm_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    (void)data; // Not used in stub implementation
    
    struct wl_resource *resource = wl_resource_create(client, &wl_drm_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // Cast away const - wayland-server expects non-const but our implementation is const
    wl_resource_set_implementation(resource, (void *)(uintptr_t)&drm_interface_impl, NULL, NULL);
    
    log_printf("[DRM] ", "drm_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
    
    // On macOS, we don't have DRM devices, so we send a special device name
    // that EGL will recognize as "no device available" and use software mode
    // Sending NULL or empty string might cause issues, so we send a special marker
    // that indicates software rendering should be used
    // 
    // Actually, EGL will try to open whatever device name we send, so if it fails,
    // EGL should handle it gracefully. But we need to ensure EGL can still proceed
    // with software mode when the device open fails.
    //
    // The best approach: send a device name that will fail to open, but EGL should
    // detect this and use software mode. However, looking at the EGL code, it seems
    // like it might not handle this gracefully.
    //
    // Alternative: Don't send device event at all? But that might break EGL.
    //
    // Let's send the device name but log that it will fail on macOS
    wl_resource_post_event(resource, WL_DRM_DEVICE, "/dev/dri/renderD128"); // Will fail on macOS, EGL should use software mode
    log_printf("[DRM] ", "  Sent device event: /dev/dri/renderD128 (will fail on macOS - EGL should use software mode)\n");
    
    // Send format events for common formats (even though we can't actually use them)
    // This allows EGL to see what formats are "supported" (even if they won't work)
    wl_resource_post_event(resource, WL_DRM_FORMAT, WL_DRM_FORMAT_XRGB8888);
    wl_resource_post_event(resource, WL_DRM_FORMAT, WL_DRM_FORMAT_ARGB8888);
    wl_resource_post_event(resource, WL_DRM_FORMAT, WL_DRM_FORMAT_RGBX8888);
    wl_resource_post_event(resource, WL_DRM_FORMAT, WL_DRM_FORMAT_RGBA8888);
    
    // Send capabilities event (version 2+)
    // WL_DRM_CAPABILITY_PRIME = 1 means PRIME is available (even though it won't work on macOS)
    if (version >= 2) {
        wl_resource_post_event(resource, WL_DRM_CAPABILITIES, 1); // PRIME capability
    }
    
    log_printf("[DRM] ", "drm_bind() - sent device, formats, and capabilities events\n");
}

// Create wl_drm global
struct wl_drm_impl *wl_drm_create(struct wl_display *display) {
    struct wl_drm_impl *drm = calloc(1, sizeof(*drm));
    if (!drm) {
        return NULL;
    }
    
    drm->display = display;
    // Advertise version 2 (supports PRIME)
    drm->global = wl_global_create(display, &wl_drm_interface, 2, drm, drm_bind);
    
    if (!drm->global) {
        free(drm);
        return NULL;
    }
    
    log_printf("[DRM] ", "wl_drm_create() - created wl_drm global (version 2)\n");
    log_printf("[DRM] ", "  Note: This is a stub implementation for macOS compatibility\n");
    log_printf("[DRM] ", "  EGL will try to use it as fallback but buffer creation will fail\n");
    
    return drm;
}

// Destroy wl_drm global
void wl_drm_destroy(struct wl_drm_impl *drm) {
    if (!drm) {
        return;
    }
    
    if (drm->global) {
        wl_global_destroy(drm->global);
    }
    
    free(drm);
}

