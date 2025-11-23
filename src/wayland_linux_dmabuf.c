#include "wayland_linux_dmabuf.h"
#include "wayland_compositor.h"
#include "metal_dmabuf.h"
#include "logging.h"
#include <wayland-server.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#ifdef __APPLE__
#include <sys/shm.h>
#endif

// Forward declarations
// wl_surface_interface is defined in wayland-server-protocol.h
// Include it here to ensure it's available
#include <wayland-server-protocol.h>

// Helper function to create an anonymous file suitable for mmap
// On macOS, we use a temp file in XDG_RUNTIME_DIR or /tmp
static int create_anonymous_file(size_t size) {
    int fd = -1;
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    char *path = NULL;
    
    if (runtime_dir) {
        // Use XDG_RUNTIME_DIR if available
        size_t path_len = strlen(runtime_dir) + 50;
        path = malloc(path_len);
        if (path) {
            snprintf(path, path_len, "%s/wawona-dmabuf-XXXXXX", runtime_dir);
            fd = mkstemp(path);
            if (fd >= 0) {
                unlink(path); // Remove name, keep fd
            }
            free(path);
        }
    }
    
    // Fallback to /tmp if XDG_RUNTIME_DIR failed
    if (fd < 0) {
        char template[] = "/tmp/wawona-dmabuf-XXXXXX";
        fd = mkstemp(template);
        if (fd >= 0) {
            unlink(template); // Remove name, keep fd
        }
    }
    
    if (fd < 0) {
        return -1;
    }
    
    // Set file size - on macOS, mmap requires at least 1 byte for empty files
    // Use max(size, 1) to ensure the file is mmap-able
    off_t file_size = (off_t)(size > 0 ? size : 1);
    if (ftruncate(fd, file_size) < 0) {
        close(fd);
        return -1;
    }
    
    return fd;
}

// Stub interfaces for types referenced in messages
// These will be properly defined later
static const struct wl_interface zwp_linux_buffer_params_v1_interface_stub = {
    "zwp_linux_buffer_params_v1", 4,
    0, NULL,
    0, NULL
};

// Define method messages for zwp_linux_dmabuf_feedback_v1
// Only one method: destroy
static const struct wl_message zwp_linux_dmabuf_feedback_v1_requests[] = {
    { "destroy", "", NULL },  // opcode 0: destroy (no arguments)
};

// Define event messages for zwp_linux_dmabuf_feedback_v1
// Event order from XML: done=0, format_table=1, main_device=2, tranche_done=3, tranche_target_device=4, tranche_flags=5, tranche_formats=6
static const struct wl_message zwp_linux_dmabuf_feedback_v1_events[] = {
    { "done", "", NULL },                                    // opcode 0
    { "format_table", "hu", NULL },                         // opcode 1: fd, size
    { "main_device", "a", NULL },                           // opcode 2: device (array)
    { "tranche_done", "", NULL },                           // opcode 3
    { "tranche_target_device", "a", NULL },                // opcode 4: device (array)
    { "tranche_flags", "u", NULL },                        // opcode 5: flags
    { "tranche_formats", "a", NULL },                      // opcode 6: formats (array)
};

// Define the feedback interface with proper method and event signatures
const struct wl_interface zwp_linux_dmabuf_feedback_v1_interface = {
    "zwp_linux_dmabuf_feedback_v1", 1,
    1, zwp_linux_dmabuf_feedback_v1_requests,  // 1 method: destroy
    7, zwp_linux_dmabuf_feedback_v1_events,   // 7 events
};

// Define method and event message arrays for zwp_linux_dmabuf_v1
// CRITICAL: Ensure all interface pointers are valid before use
static const struct wl_interface *linux_dmabuf_types[] = {
    NULL,
    NULL,
    &zwp_linux_buffer_params_v1_interface_stub,
    &zwp_linux_dmabuf_feedback_v1_interface,
    &wl_surface_interface, // Defined in wayland-server-protocol.h
};

// CRITICAL: For methods with multiple parameters, we need separate type arrays
// get_surface_feedback has signature "no" (new_id + object)
// types[0] = interface for new_id (zwp_linux_dmabuf_feedback_v1_interface)
// types[1] = interface for object (wl_surface_interface)
static const struct wl_interface *get_surface_feedback_types[] = {
    &zwp_linux_dmabuf_feedback_v1_interface, // new_id parameter
    &wl_surface_interface,                    // object parameter
};

static const struct wl_message zwp_linux_dmabuf_v1_requests[] = {
    { "destroy", "", linux_dmabuf_types + 0 },
    { "create_params", "n", linux_dmabuf_types + 2 },
    { "get_default_feedback", "n", linux_dmabuf_types + 3 },
    { "get_surface_feedback", "no", get_surface_feedback_types }, // n=new_id (feedback), o=object (surface)
};

static const struct wl_message zwp_linux_dmabuf_v1_events[] = {
    { "format", "u", linux_dmabuf_types + 0 },
    { "modifier", "uuu", linux_dmabuf_types + 0 },
};

// Define interface structures
const struct wl_interface zwp_linux_dmabuf_v1_interface = {
    "zwp_linux_dmabuf_v1", 4,  // Version 4 supports feedback
    4, zwp_linux_dmabuf_v1_requests,  // 4 methods: destroy, create_params, get_default_feedback, get_surface_feedback
    2, zwp_linux_dmabuf_v1_events,     // 2 events: format, modifier
};


// Actual interface definition (references the stub in types array above)
const struct wl_interface zwp_linux_buffer_params_v1_interface = {
    "zwp_linux_buffer_params_v1", 4,
    0, NULL,
    0, NULL
};

// DRM format codes (from drm_fourcc.h)
#define DRM_FORMAT_ARGB8888 0x34325241
#define DRM_FORMAT_XRGB8888 0x34325258
#define DRM_FORMAT_ABGR8888 0x34324241
#define DRM_FORMAT_XBGR8888 0x34324258
#define DRM_FORMAT_RGBA8888 0x41424752
#define DRM_FORMAT_RGBX8888 0x58424752
#define DRM_FORMAT_BGRA8888 0x41424742
#define DRM_FORMAT_BGRX8888 0x58424742
#define DRM_FORMAT_MOD_INVALID 0x00ffffffffffffffULL

// Buffer plane data
struct dmabuf_plane {
    int32_t fd;
    uint32_t offset;
    uint32_t stride;
    uint64_t modifier;
    bool used;
};

// Buffer params implementation
struct wl_linux_buffer_params_impl {
    struct wl_resource *resource;
    struct dmabuf_plane planes[4];  // Max 4 planes
    uint32_t num_planes;
    bool used;
    int32_t width;
    int32_t height;
    uint32_t format;
    uint32_t flags;
};

static struct wl_linux_buffer_params_impl *params_from_resource(struct wl_resource *resource) {
    return wl_resource_get_user_data(resource);
}

// Buffer destroy handler
static void buffer_destroy_handler(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    
    // Clear buffer reference from any surfaces
    wl_compositor_clear_buffer_reference(resource);
    
    wl_resource_destroy(resource);
}

static const struct wl_buffer_interface buffer_interface = {
    .destroy = buffer_destroy_handler,
};

// Buffer destructor
static void buffer_destroy(struct wl_resource *resource) {
    struct metal_dmabuf_buffer *buf_data = wl_resource_get_user_data(resource);
    if (buf_data) {
        metal_dmabuf_destroy_buffer(buf_data);
    }
}

// Create wl_buffer from DMA-BUF params
static struct wl_resource *create_dmabuf_buffer(struct wl_client *client,
                                                struct wl_linux_buffer_params_impl *params,
                                                uint32_t buffer_id) {
    // Validate we have at least one plane
    if (params->num_planes == 0) {
        wl_resource_post_error(params->resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INCOMPLETE,
                              "no planes added");
        return NULL;
    }
    
    // Validate dimensions
    if (params->width <= 0 || params->height <= 0) {
        wl_resource_post_error(params->resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_DIMENSIONS,
                              "invalid dimensions");
        return NULL;
    }
    
    // For macOS, we'll use IOSurface to create Metal-compatible buffers
    // In a real implementation, we'd import the DMA-BUF fd and convert to IOSurface
    // For now, create a basic buffer structure
    
    // Create buffer resource
    uint32_t version = (uint32_t)wl_resource_get_version(params->resource);
    struct wl_resource *buffer_resource = wl_resource_create(client, &wl_buffer_interface, (int)version, buffer_id);
    if (!buffer_resource) {
        wl_client_post_no_memory(client);
        return NULL;
    }
    
    // Create Metal DMA-BUF buffer wrapper
    // Note: In a full implementation, we'd import the actual DMA-BUF fd
    // For now, create a placeholder that can be used with IOSurface
    struct metal_dmabuf_buffer *dmabuf_buf = metal_dmabuf_create_buffer(
        (uint32_t)params->width, (uint32_t)params->height, (uint32_t)params->format);
    
    if (!dmabuf_buf) {
        wl_resource_destroy(buffer_resource);
        return NULL;
    }
    
    // Store buffer data
    wl_resource_set_implementation(buffer_resource, &buffer_interface, dmabuf_buf, buffer_destroy);
    
    log_printf("[DMABUF] ", "create_dmabuf_buffer() - buffer=%p, size=%dx%d, format=0x%x\n",
               (void *)buffer_resource, params->width, params->height, params->format);
    
    return buffer_resource;
}

// Buffer params: add plane
static void params_add(struct wl_client *client, struct wl_resource *resource,
                      int32_t fd, uint32_t plane_idx, uint32_t offset, uint32_t stride,
                      uint32_t modifier_hi, uint32_t modifier_lo) {
    (void)client;
    struct wl_linux_buffer_params_impl *params = params_from_resource(resource);
    if (!params) {
        return;
    }
    
    if (params->used) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED,
                              "params already used");
        close(fd);
        return;
    }
    
    if (plane_idx >= 4) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_IDX,
                              "plane index out of bounds");
        close(fd);
        return;
    }
    
    if (params->planes[plane_idx].used) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_SET,
                              "plane already set");
        close(fd);
        return;
    }
    
    params->planes[plane_idx].fd = fd;
    params->planes[plane_idx].offset = offset;
    params->planes[plane_idx].stride = stride;
    params->planes[plane_idx].modifier = ((uint64_t)modifier_hi << 32) | modifier_lo;
    params->planes[plane_idx].used = true;
    
    if (plane_idx >= params->num_planes) {
        params->num_planes = plane_idx + 1;
    }
    
    log_printf("[DMABUF] ", "params_add() - plane=%u, fd=%d, stride=%u, modifier=0x%llx\n",
               plane_idx, fd, stride, (unsigned long long)params->planes[plane_idx].modifier);
}

// Buffer params: create (async)
static void params_create(struct wl_client *client, struct wl_resource *resource,
                         int32_t width, int32_t height, uint32_t format, uint32_t flags) {
    (void)client;
    struct wl_linux_buffer_params_impl *params = params_from_resource(resource);
    if (!params) {
        return;
    }
    
    if (params->used) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED,
                              "params already used");
        return;
    }
    
    params->used = true;
    params->width = width;
    params->height = height;
    params->format = format;
    params->flags = flags;
    
    // Create buffer
    uint32_t buffer_id = wl_resource_get_id(resource) + 1000;  // Simple ID generation
    struct wl_resource *buffer_resource = create_dmabuf_buffer(client, params, buffer_id);
    
    if (buffer_resource) {
        // Send created event
        wl_resource_post_event(resource, ZWP_LINUX_BUFFER_PARAMS_V1_CREATED, buffer_resource);
    } else {
        // Send failed event
        wl_resource_post_event(resource, ZWP_LINUX_BUFFER_PARAMS_V1_FAILED);
    }
}

// Buffer params: create_immed (synchronous)
static void params_create_immed(struct wl_client *client, struct wl_resource *resource,
                               uint32_t buffer_id, int32_t width, int32_t height,
                               uint32_t format, uint32_t flags) {
    struct wl_linux_buffer_params_impl *params = params_from_resource(resource);
    if (!params) {
        return;
    }
    
    if (params->used) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED,
                              "params already used");
        return;
    }
    
    params->used = true;
    params->width = width;
    params->height = height;
    params->format = format;
    params->flags = flags;
    
    // Create buffer immediately
    struct wl_resource *buffer_resource = create_dmabuf_buffer(client, params, buffer_id);
    
    if (!buffer_resource) {
        // On failure, send failed event
        wl_resource_post_event(resource, ZWP_LINUX_BUFFER_PARAMS_V1_FAILED);
    }
    // On success, no event is sent (buffer is ready immediately)
}

// Buffer params: destroy
static void params_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wl_linux_buffer_params_impl *params = params_from_resource(resource);
    if (params) {
        // Close all FDs
        for (uint32_t i = 0; i < params->num_planes; i++) {
            if (params->planes[i].used && params->planes[i].fd >= 0) {
                close(params->planes[i].fd);
            }
        }
        free(params);
    }
    wl_resource_destroy(resource);
}

static const struct zwp_linux_buffer_params_v1_interface params_interface = {
    .destroy = params_destroy,
    .add = params_add,
    .create = params_create,
    .create_immed = params_create_immed,
};

// Manager: create_params
static void dmabuf_create_params(struct wl_client *client, struct wl_resource *resource,
                                 uint32_t params_id) {
    log_printf("[DMABUF] ", "create_params() - CALLED! client=%p, resource=%p, params_id=%u\n",
               (void *)client, (void *)resource, params_id);
    struct wl_linux_buffer_params_impl *params = calloc(1, sizeof(*params));
    if (!params) {
        wl_client_post_no_memory(client);
        return;
    }
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *params_resource = wl_resource_create(client, &zwp_linux_buffer_params_v1_interface, (int)version, params_id);
    if (!params_resource) {
        free(params);
        wl_client_post_no_memory(client);
        return;
    }
    
    params->resource = params_resource;
    params->num_planes = 0;
    params->used = false;
    
    // Initialize planes
    for (int i = 0; i < 4; i++) {
        params->planes[i].fd = -1;
        params->planes[i].used = false;
    }
    
    wl_resource_set_implementation(params_resource, &params_interface, params, NULL);
    
    log_printf("[DMABUF] ", "dmabuf_create_params() - params=%p\n", (void *)params_resource);
}

// Manager: destroy
static void dmabuf_destroy(struct wl_client *client, struct wl_resource *resource) {
    log_printf("[DMABUF] ", "destroy() - CALLED! client=%p, resource=%p\n", (void *)client, (void *)resource);
    (void)client;
    wl_resource_destroy(resource);
}

// Feedback resource user data to track the format_table fd
struct dmabuf_feedback_data {
    int format_table_fd;
};

// Resource destroy callback (called when resource is destroyed)
static void feedback_resource_destroy(struct wl_resource *resource) {
    struct dmabuf_feedback_data *data = wl_resource_get_user_data(resource);
    if (data) {
        // Close the format_table fd if it's still open
        if (data->format_table_fd >= 0) {
            close(data->format_table_fd);
            data->format_table_fd = -1;
        }
        free(data);
    }
}

// Feedback resource destroy handler (protocol method)
static void dmabuf_feedback_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

// Feedback interface implementation
// We use a simple implementation struct since we only need the destroy method
typedef struct {
    void (*destroy)(struct wl_client *client, struct wl_resource *resource);
} zwp_linux_dmabuf_feedback_v1_interface_impl;

static zwp_linux_dmabuf_feedback_v1_interface_impl dmabuf_feedback_interface_impl = {
    .destroy = dmabuf_feedback_destroy,
};

// Manager: get_default_feedback (version 4+)
static void dmabuf_get_default_feedback(struct wl_client *client, struct wl_resource *resource,
                                       uint32_t id) {
    log_printf("[DMABUF] ", "get_default_feedback() - CALLED! client=%p, resource=%p, id=%u\n",
               (void *)client, (void *)resource, id);
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    
    // Create feedback resource
    struct wl_resource *feedback_resource = wl_resource_create(client, &zwp_linux_dmabuf_feedback_v1_interface, (int)version, id);
    if (!feedback_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // Allocate user data to track the format_table fd
    struct dmabuf_feedback_data *feedback_data = calloc(1, sizeof(*feedback_data));
    if (!feedback_data) {
        wl_client_post_no_memory(client);
        wl_resource_destroy(feedback_resource);
        return;
    }
    feedback_data->format_table_fd = -1;
    
    // Set implementation with user data for cleanup
    wl_resource_set_implementation(feedback_resource, &dmabuf_feedback_interface_impl, feedback_data, feedback_resource_destroy);
    
    log_printf("[DMABUF] ", "get_default_feedback() - created feedback resource %p\n", (void *)feedback_resource);
    
    // On macOS, we don't have DRM devices, so we send minimal feedback
    // This tells the client to use software rendering via Zink/Vulkan
    // Event opcodes from XML order: done=0, format_table=1, main_device=2, tranche_done=3, tranche_target_device=4, tranche_flags=5, tranche_formats=6
    
    // Send format_table event (empty table = no hardware formats)
    // The format table is a binary format: each entry is 16 bytes (format: u32, padding: u32, modifier: u64)
    // Empty table (0 bytes) indicates no hardware formats are supported
    // 
    // CRITICAL: On macOS, mmap(NULL, 0, ...) fails, so we need to send at least 1 byte
    // However, the protocol allows size=0 for empty tables. To work around macOS mmap limitations,
    // we send size=16 (one empty entry) with all zeros, which the client will interpret as an empty table
    // since the size indicates no entries (size / 16 = 0 entries)
    //
    // Actually, let's check: if size=0, the client should skip mmap. But if it doesn't, we need a workaround.
    // The safest approach: send a minimal 16-byte entry (all zeros) and size=16.
    // The client will parse it as 0 entries since format=0 and modifier=0 means "no format"
    uint32_t table_size = 16; // Send one 16-byte entry (all zeros) for macOS mmap compatibility
    int table_fd = create_anonymous_file(table_size);
    if (table_fd >= 0) {
        // Write zeros to the file (format=0, padding=0, modifier=0 means "no format")
        // This allows mmap to succeed on macOS while still indicating an empty table
        uint64_t zero_entry[2] = {0, 0}; // format (u32) + padding (u32) = u64, modifier (u64)
        if (write(table_fd, zero_entry, 16) != 16) {
            log_printf("[DMABUF] ", "get_default_feedback() - failed to write format table data\n");
            close(table_fd);
            table_fd = -1;
        } else {
            // Seek back to beginning for reading
            lseek(table_fd, 0, SEEK_SET);
            
            // Store fd in user data so we can close it when resource is destroyed
            feedback_data->format_table_fd = table_fd;
            
            // Send format_table event - Wayland will send the fd via SCM_RIGHTS
            // CRITICAL: Keep the fd open until the resource is destroyed
            // Even though SCM_RIGHTS creates a copy in the client, the server fd must
            // remain valid until the client has finished reading it (mmap)
            // We'll close it in feedback_resource_destroy when the resource is destroyed
            wl_resource_post_event(feedback_resource, 1, table_fd, table_size); // format_table event (opcode 1: fd, size)
            
            log_printf("[DMABUF] ", "get_default_feedback() - sent format_table (fd=%d, size=%u, empty table)\n", table_fd, table_size);
        }
    } else {
        log_printf("[DMABUF] ", "get_default_feedback() - failed to create format table file: %s\n", strerror(errno));
        // Continue without format_table - client should handle gracefully
    }
    
    // Send main_device event with dummy device ID (0 = no hardware device)
    struct wl_array device_array;
    wl_array_init(&device_array);
    dev_t dummy_device = 0; // 0 indicates no hardware device
    dev_t *dev = wl_array_add(&device_array, sizeof(dev_t));
    if (dev) {
        *dev = dummy_device;
        wl_resource_post_event(feedback_resource, 2, &device_array); // main_device event (opcode 2)
    }
    wl_array_release(&device_array);
    
    // Send tranche_target_device (same dummy device)
    wl_array_init(&device_array);
    dev = wl_array_add(&device_array, sizeof(dev_t));
    if (dev) {
        *dev = dummy_device;
        wl_resource_post_event(feedback_resource, 4, &device_array); // tranche_target_device event (opcode 4)
    }
    wl_array_release(&device_array);
    
    // Send tranche_flags (0 = no special flags)
    wl_resource_post_event(feedback_resource, 5, 0); // tranche_flags event (opcode 5)
    
    // Send tranche_formats (empty array = no formats)
    struct wl_array formats_array;
    wl_array_init(&formats_array);
    wl_resource_post_event(feedback_resource, 6, &formats_array); // tranche_formats event (opcode 6)
    wl_array_release(&formats_array);
    
    // Send tranche_done
    wl_resource_post_event(feedback_resource, 3); // tranche_done event (opcode 3)
    
    // Send done event
    wl_resource_post_event(feedback_resource, 0); // done event (opcode 0)
    
    log_printf("[DMABUF] ", "get_default_feedback() - sent minimal feedback (no hardware device)\n");
}

// Manager: get_surface_feedback (version 4+)
static void dmabuf_get_surface_feedback(struct wl_client *client, struct wl_resource *resource,
                                        uint32_t id, struct wl_resource *surface) {
    log_printf("[DMABUF] ", "get_surface_feedback() - CALLED! client=%p, resource=%p, id=%u, surface=%p\n", 
               (void *)client, (void *)resource, id, (void *)surface);
    
    // Validate inputs
    if (!client || !resource) {
        log_printf("[DMABUF] ", "get_surface_feedback() - ERROR: invalid client or resource\n");
        return;
    }
    
    if (!surface) {
        log_printf("[DMABUF] ", "get_surface_feedback() - ERROR: surface is NULL\n");
        // Don't post error - just log and return (client will handle gracefully)
        return;
    }
    
    // Validate surface resource
    if (wl_resource_get_user_data(surface) == NULL) {
        log_printf("[DMABUF] ", "get_surface_feedback() - ERROR: surface resource has no user data\n");
        return;
    }
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    log_printf("[DMABUF] ", "get_surface_feedback() - resource version=%u\n", version);
    
    // Create feedback resource
    struct wl_resource *feedback_resource = wl_resource_create(client, &zwp_linux_dmabuf_feedback_v1_interface, (int)version, id);
    if (!feedback_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // Allocate user data to track the format_table fd
    struct dmabuf_feedback_data *feedback_data = calloc(1, sizeof(*feedback_data));
    if (!feedback_data) {
        wl_client_post_no_memory(client);
        wl_resource_destroy(feedback_resource);
        return;
    }
    feedback_data->format_table_fd = -1;
    
    // Set implementation with user data for cleanup
    wl_resource_set_implementation(feedback_resource, &dmabuf_feedback_interface_impl, feedback_data, feedback_resource_destroy);
    
    log_printf("[DMABUF] ", "get_surface_feedback() - created feedback resource %p for surface %p\n", (void *)feedback_resource, (void *)surface);
    
    // Send the same minimal feedback as get_default_feedback
    // On macOS, we don't have DRM devices, so we send minimal feedback
    // This tells the client to use software rendering via Zink/Vulkan
    // Event opcodes from XML order: done=0, format_table=1, main_device=2, tranche_done=3, tranche_target_device=4, tranche_flags=5, tranche_formats=6
    
    // Send format_table event (empty table = no hardware formats)
    uint32_t table_size = 16; // Send one 16-byte entry (all zeros) for macOS mmap compatibility
    int table_fd = create_anonymous_file(table_size);
    if (table_fd >= 0) {
        // Write zeros to the file (format=0, padding=0, modifier=0 means "no format")
        // This allows mmap to succeed on macOS while still indicating an empty table
        uint64_t zero_entry[2] = {0, 0}; // format (u32) + padding (u32) = u64, modifier (u64)
        if (write(table_fd, zero_entry, 16) != 16) {
            log_printf("[DMABUF] ", "get_surface_feedback() - failed to write format table data\n");
            close(table_fd);
            table_fd = -1;
        } else {
            // Seek back to beginning for reading
            lseek(table_fd, 0, SEEK_SET);
            
            // Store fd in user data so we can close it when resource is destroyed
            feedback_data->format_table_fd = table_fd;
            
            // Send format_table event - Wayland will send the fd via SCM_RIGHTS
            // CRITICAL: Keep the fd open until the resource is destroyed
            // Even though SCM_RIGHTS creates a copy in the client, the server fd must
            // remain valid until the client has finished reading it (mmap)
            // We'll close it in feedback_resource_destroy when the resource is destroyed
            wl_resource_post_event(feedback_resource, 1, table_fd, table_size); // format_table event (opcode 1: fd, size)
            
            log_printf("[DMABUF] ", "get_surface_feedback() - sent format_table (fd=%d, size=%u, empty table)\n", table_fd, table_size);
        }
    } else {
        log_printf("[DMABUF] ", "get_surface_feedback() - failed to create format table file: %s\n", strerror(errno));
        // Continue without format_table - client should handle gracefully
    }
    
    // Send main_device event with dummy device ID (0 = no hardware device)
    struct wl_array device_array;
    wl_array_init(&device_array);
    dev_t dummy_device = 0; // 0 indicates no hardware device
    dev_t *dev = wl_array_add(&device_array, sizeof(dev_t));
    if (dev) {
        *dev = dummy_device;
        wl_resource_post_event(feedback_resource, 2, &device_array); // main_device event (opcode 2)
    }
    wl_array_release(&device_array);
    
    // Send tranche_target_device (same dummy device)
    wl_array_init(&device_array);
    dev = wl_array_add(&device_array, sizeof(dev_t));
    if (dev) {
        *dev = dummy_device;
        wl_resource_post_event(feedback_resource, 4, &device_array); // tranche_target_device event (opcode 4)
    }
    wl_array_release(&device_array);
    
    // Send tranche_flags (0 = no special flags)
    wl_resource_post_event(feedback_resource, 5, 0); // tranche_flags event (opcode 5)
    
    // Send tranche_formats (empty array = no formats)
    struct wl_array formats_array;
    wl_array_init(&formats_array);
    wl_resource_post_event(feedback_resource, 6, &formats_array); // tranche_formats event (opcode 6)
    wl_array_release(&formats_array);
    
    // Send tranche_done
    wl_resource_post_event(feedback_resource, 3); // tranche_done event (opcode 3)
    
    // Send done event
    wl_resource_post_event(feedback_resource, 0); // done event (opcode 0)
    
    log_printf("[DMABUF] ", "get_surface_feedback() - sent minimal feedback (no hardware device)\n");
}

static const struct zwp_linux_dmabuf_v1_interface dmabuf_interface = {
    .destroy = dmabuf_destroy,
    .create_params = dmabuf_create_params,
    .get_default_feedback = dmabuf_get_default_feedback,
    .get_surface_feedback = dmabuf_get_surface_feedback,
};

struct wl_linux_dmabuf_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

static void dmabuf_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_linux_dmabuf_manager_impl *dmabuf = data;
    
    log_printf("[DMABUF] ", "dmabuf_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
    
    // CRITICAL: Log the actual function pointers to verify they're set correctly
    log_printf("[DMABUF] ", "dmabuf_bind() - function pointers: destroy=%p, create_params=%p, get_default_feedback=%p, get_surface_feedback=%p\n",
               (void *)dmabuf_interface.destroy,
               (void *)dmabuf_interface.create_params,
               (void *)dmabuf_interface.get_default_feedback,
               (void *)dmabuf_interface.get_surface_feedback);
    
    struct wl_resource *resource = wl_resource_create(client, &zwp_linux_dmabuf_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    log_printf("[DMABUF] ", "dmabuf_bind() - setting implementation (resource=%p, get_surface_feedback=%p)\n",
               (void *)resource, (void *)dmabuf_interface.get_surface_feedback);
    
    wl_resource_set_implementation(resource, &dmabuf_interface, dmabuf, NULL);
    
    log_printf("[DMABUF] ", "dmabuf_bind() - implementation set, version=%u (supports get_surface_feedback=%s)\n",
               version, version >= 4 ? "yes" : "no");
    
    // CRITICAL: Log the wl_interface structure to verify it's correct
    log_printf("[DMABUF] ", "dmabuf_bind() - wl_interface: name=%s, version=%d, method_count=%d, event_count=%d\n",
               zwp_linux_dmabuf_v1_interface.name,
               zwp_linux_dmabuf_v1_interface.version,
               zwp_linux_dmabuf_v1_interface.method_count,
               zwp_linux_dmabuf_v1_interface.event_count);
    
    // CRITICAL: Verify wl_surface_interface pointer is valid
    log_printf("[DMABUF] ", "dmabuf_bind() - wl_surface_interface pointer: %p\n", (const void *)&wl_surface_interface);
    log_printf("[DMABUF] ", "dmabuf_bind() - wl_surface_interface: name=%s, version=%d, method_count=%d, event_count=%d\n",
               wl_surface_interface.name,
               wl_surface_interface.version,
               wl_surface_interface.method_count,
               wl_surface_interface.event_count);
    
    // CRITICAL: Verify the wl_message structure for get_surface_feedback
    log_printf("[DMABUF] ", "dmabuf_bind() - get_surface_feedback message: name=%s, signature=%s, types=%p\n",
               zwp_linux_dmabuf_v1_requests[3].name,
               zwp_linux_dmabuf_v1_requests[3].signature,
               (const void *)zwp_linux_dmabuf_v1_requests[3].types);
    if (zwp_linux_dmabuf_v1_requests[3].types) {
        log_printf("[DMABUF] ", "dmabuf_bind() - get_surface_feedback types[0]=%p, types[1]=%p\n",
                   (const void *)zwp_linux_dmabuf_v1_requests[3].types[0],
                   (const void *)zwp_linux_dmabuf_v1_requests[3].types[1]);
    }
    
    // Advertise supported formats (deprecated in v4+, but send for compatibility)
    if (version < 4) {
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_ARGB8888);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_XRGB8888);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_ABGR8888);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_XBGR8888);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_RGBA8888);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_RGBX8888);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_BGRA8888);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_FORMAT, DRM_FORMAT_BGRX8888);
        
        // Advertise modifiers (DRM_FORMAT_MOD_INVALID means implicit modifier)
        uint32_t mod_hi = (DRM_FORMAT_MOD_INVALID >> 32) & 0xFFFFFFFF;
        uint32_t mod_lo = DRM_FORMAT_MOD_INVALID & 0xFFFFFFFF;
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_ARGB8888, mod_hi, mod_lo);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_XRGB8888, mod_hi, mod_lo);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_ABGR8888, mod_hi, mod_lo);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_XBGR8888, mod_hi, mod_lo);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_RGBA8888, mod_hi, mod_lo);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_RGBX8888, mod_hi, mod_lo);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_BGRA8888, mod_hi, mod_lo);
        wl_resource_post_event(resource, ZWP_LINUX_DMABUF_V1_MODIFIER, DRM_FORMAT_BGRX8888, mod_hi, mod_lo);
    }
    
    log_printf("[DMABUF] ", "dmabuf_bind() - client=%p, version=%u, id=%u\n",
               (void *)client, version, id);
}

struct wl_linux_dmabuf_manager_impl *wl_linux_dmabuf_create(struct wl_display *display) {
    struct wl_linux_dmabuf_manager_impl *dmabuf = calloc(1, sizeof(*dmabuf));
    if (!dmabuf) {
        return NULL;
    }
    
    dmabuf->display = display;
    // Version 4 supports feedback, but we advertise v4 for compatibility
    dmabuf->global = wl_global_create(display, &zwp_linux_dmabuf_v1_interface, 4, dmabuf, dmabuf_bind);
    
    if (!dmabuf->global) {
        free(dmabuf);
        return NULL;
    }
    
    log_printf("[DMABUF] ", "wl_linux_dmabuf_create() - global created\n");
    return dmabuf;
}

void wl_linux_dmabuf_destroy(struct wl_linux_dmabuf_manager_impl *dmabuf) {
    if (!dmabuf) {
        return;
    }
    
    if (dmabuf->global) {
        wl_global_destroy(dmabuf->global);
    }
    
    free(dmabuf);
}

