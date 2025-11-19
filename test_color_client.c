// Wayland Color Management & HDR Test Client
// Tests color operations and HDR support in Wawona compositor
//
// This client:
// 1. Connects to Wawona compositor via Wayland socket
// 2. Queries color manager capabilities (features, intents, transfer functions, primaries)
// 3. Cycles through different color space tests:
//    - sRGB (standard)
//    - BT.2020 with ST.2084 PQ (HDR)
//    - DCI-P3 (wide gamut)
//    - Display P3 (macOS wide gamut)
//    - Windows scRGB (HDR extended range)
// 4. Creates image descriptions for each color space
// 5. Sets image descriptions on surface with rendering intents
// 6. Renders test patterns optimized for each color space
// 7. Verifies color operations work correctly
//
// Usage:
//   1. Start compositor: make compositor
//   2. Run test client: make client
//   3. Watch window cycle through color space tests every 5 seconds

#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include "test_xdg-shell-client-protocol.h"
#include "test_color-management-v1-client-protocol.h"
#include "src/logging.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <math.h>
#include <stdbool.h>

struct wl_display *display = NULL;
struct wl_compositor *compositor = NULL;
struct wl_surface *surface = NULL;
struct wl_shm *shm = NULL;
struct wl_buffer *buffer = NULL;
struct xdg_wm_base *wm_base = NULL;
struct xdg_surface *xdg_surface = NULL;
struct xdg_toplevel *toplevel = NULL;
struct wp_color_manager_v1 *color_manager = NULL;
struct wp_color_management_surface_v1 *color_surface = NULL;
struct wp_color_management_output_v1 *color_output = NULL;
struct wp_image_description_v1 *current_image_description = NULL;

int width = 800;
int height = 600;
int stride;
void *data = NULL;
int shm_fd = -1;
int test_phase = 0;
int frame_count = 0;

// Test configuration
enum test_mode {
    TEST_SRGB,
    TEST_BT2020,
    TEST_DCI_P3,
    TEST_DISPLAY_P3,
    TEST_WINDOWS_SCRGB,
    TEST_ICC_PROFILE,
    TEST_PARAMETRIC,
    TEST_MAX
};

enum test_mode current_test = TEST_SRGB;
const char *test_names[] = {
    "sRGB",
    "BT.2020 (HDR)",
    "DCI-P3",
    "Display P3",
    "Windows scRGB (HDR)",
    "ICC Profile",
    "Parametric",
    "MAX"
};

// Color manager state
uint32_t supported_features = 0;
uint32_t supported_intents = 0;
uint32_t supported_tf_named = 0;
uint32_t supported_primaries_named = 0;
bool color_manager_done = false;

// Image description state
bool image_description_ready = false;
uint32_t image_description_identity = 0;

static void shm_format(void *data, struct wl_shm *shm, uint32_t format) {
    (void)data;
    (void)shm;
    (void)format;
}

static const struct wl_shm_listener shm_listener = {
    shm_format,
};

// Color manager listeners
static void color_manager_supported_intent(void *data, struct wp_color_manager_v1 *manager, uint32_t intent) {
    (void)data;
    (void)manager;
    supported_intents |= (1U << intent);
    log_printf("[COLOR_TEST] ", "Supported render intent: %u\n", intent);
}

static void color_manager_supported_feature(void *data, struct wp_color_manager_v1 *manager, uint32_t feature) {
    (void)data;
    (void)manager;
    supported_features |= (1U << feature);
    log_printf("[COLOR_TEST] ", "Supported feature: %u\n", feature);
}

static void color_manager_supported_tf_named(void *data, struct wp_color_manager_v1 *manager, uint32_t tf) {
    (void)data;
    (void)manager;
    supported_tf_named |= (1U << tf);
    log_printf("[COLOR_TEST] ", "Supported transfer function: %u\n", tf);
}

static void color_manager_supported_primaries_named(void *data, struct wp_color_manager_v1 *manager, uint32_t primaries) {
    (void)data;
    (void)manager;
    supported_primaries_named |= (1U << primaries);
    log_printf("[COLOR_TEST] ", "Supported primaries: %u\n", primaries);
}

// Helper function to print color operations protocol summary
static void print_color_operations_summary(void) {
    printf("\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("                    Wawona Compositor Color Operations Protocol\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("\n");
    
    // Color Operations Support
    bool color_ops_supported = (supported_features != 0);
    printf("Color Operations Support: %s\n", color_ops_supported ? "yes" : "no");
    
    // HDR Support
    bool hdr_supported = (supported_features & (1U << WP_COLOR_MANAGER_V1_FEATURE_WINDOWS_SCRGB)) ||
                         (supported_tf_named & (1U << WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ)) ||
                         (supported_tf_named & (1U << WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG));
    printf("HDR Support: %s\n", hdr_supported ? "yes" : "no");
    
    // ICC Profile Support
    bool icc_supported = (supported_features & (1U << WP_COLOR_MANAGER_V1_FEATURE_ICC_V2_V4));
    printf("ICC Profile Support: %s\n", icc_supported ? "yes" : "no");
    
    printf("\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("Supported Features:\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    const char *feature_names[] = {
        [WP_COLOR_MANAGER_V1_FEATURE_ICC_V2_V4] = "ICC v2/v4 Profiles",
        [WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC] = "Parametric Image Descriptions",
        [WP_COLOR_MANAGER_V1_FEATURE_SET_PRIMARIES] = "Custom Primaries",
        [WP_COLOR_MANAGER_V1_FEATURE_SET_TF_POWER] = "Power Transfer Functions",
        [WP_COLOR_MANAGER_V1_FEATURE_SET_LUMINANCES] = "Luminance Settings",
        [WP_COLOR_MANAGER_V1_FEATURE_SET_MASTERING_DISPLAY_PRIMARIES] = "Mastering Display Primaries",
        [WP_COLOR_MANAGER_V1_FEATURE_EXTENDED_TARGET_VOLUME] = "Extended Target Volume",
        [WP_COLOR_MANAGER_V1_FEATURE_WINDOWS_SCRGB] = "Windows scRGB (HDR)",
    };
    
    int feature_count = 0;
    for (int i = 0; i < 8; i++) {
        if (supported_features & (1U << i)) {
            printf("  ✓ %s\n", feature_names[i] ? feature_names[i] : "Unknown");
            feature_count++;
        }
    }
    if (feature_count == 0) {
        printf("  ✗ None\n");
    }
    
    printf("\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("Supported Render Intents:\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    const char *intent_names[] = {
        [WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL] = "Perceptual",
        [WP_COLOR_MANAGER_V1_RENDER_INTENT_RELATIVE] = "Relative Colorimetric",
        [WP_COLOR_MANAGER_V1_RENDER_INTENT_SATURATION] = "Saturation",
        [WP_COLOR_MANAGER_V1_RENDER_INTENT_ABSOLUTE] = "Absolute Colorimetric",
        [WP_COLOR_MANAGER_V1_RENDER_INTENT_RELATIVE_BPC] = "Relative Colorimetric (BPC)",
    };
    
    int intent_count = 0;
    for (int i = 0; i < 5; i++) {
        if (supported_intents & (1U << i)) {
            printf("  ✓ %s\n", intent_names[i] ? intent_names[i] : "Unknown");
            intent_count++;
        }
    }
    if (intent_count == 0) {
        printf("  ✗ None\n");
    }
    
    printf("\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("Supported Transfer Functions:\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    int tf_count = 0;
    // Check all possible transfer function values (they're enum values, not bit positions)
    struct {
        uint32_t value;
        const char *name;
    } tf_list[] = {
        {WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB, "sRGB"},
        {WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_BT1886, "BT.1886 (EOTF)"},
        {WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ, "ST.2084 PQ (HDR)"},
        {WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG, "HLG (HDR)"},
        {WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_EXT_SRGB, "Extended sRGB"},
        {WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_EXT_LINEAR, "Extended Linear"},
    };
    
    for (size_t i = 0; i < sizeof(tf_list)/sizeof(tf_list[0]); i++) {
        if (supported_tf_named & (1U << tf_list[i].value)) {
            printf("  ✓ %s\n", tf_list[i].name);
            tf_count++;
        }
    }
    if (tf_count == 0) {
        printf("  ✗ None\n");
    }
    
    printf("\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("Supported Color Primaries:\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    int primaries_count = 0;
    // Check all possible primaries values (they're enum values, not bit positions)
    struct {
        uint32_t value;
        const char *name;
    } primaries_list[] = {
        {WP_COLOR_MANAGER_V1_PRIMARIES_SRGB, "sRGB"},
        {WP_COLOR_MANAGER_V1_PRIMARIES_BT2020, "BT.2020 (UHDTV)"},
        {WP_COLOR_MANAGER_V1_PRIMARIES_DCI_P3, "DCI-P3"},
        {WP_COLOR_MANAGER_V1_PRIMARIES_DISPLAY_P3, "Display P3"},
        {WP_COLOR_MANAGER_V1_PRIMARIES_ADOBE_RGB, "Adobe RGB"},
    };
    
    for (size_t i = 0; i < sizeof(primaries_list)/sizeof(primaries_list[0]); i++) {
        if (supported_primaries_named & (1U << primaries_list[i].value)) {
            printf("  ✓ %s\n", primaries_list[i].name);
            primaries_count++;
        }
    }
    if (primaries_count == 0) {
        printf("  ✗ None\n");
    }
    
    printf("\n");
    printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    printf("\n");
}

static void color_manager_done_event(void *data, struct wp_color_manager_v1 *manager) {
    (void)data;
    (void)manager;
    color_manager_done = true;
    log_printf("[COLOR_TEST] ", "Color manager capabilities received\n");
    log_printf("[COLOR_TEST] ", "  Features: 0x%x\n", supported_features);
    log_printf("[COLOR_TEST] ", "  Intents: 0x%x\n", supported_intents);
    log_printf("[COLOR_TEST] ", "  Transfer functions: 0x%x\n", supported_tf_named);
    log_printf("[COLOR_TEST] ", "  Primaries: 0x%x\n", supported_primaries_named);
    
    // Print comprehensive summary to stdout
    print_color_operations_summary();
}

static const struct wp_color_manager_v1_listener color_manager_listener = {
    .supported_intent = color_manager_supported_intent,
    .supported_feature = color_manager_supported_feature,
    .supported_tf_named = color_manager_supported_tf_named,
    .supported_primaries_named = color_manager_supported_primaries_named,
    .done = color_manager_done_event,
};

// Image description listeners
static void image_description_failed(void *data, struct wp_image_description_v1 *desc, uint32_t cause, const char *reason) {
    (void)data;
    log_printf("[COLOR_TEST] ", "Image description failed: cause=%u, reason=%s\n", cause, reason ? reason : "unknown");
    image_description_ready = false;
}

static void image_description_ready_event(void *data, struct wp_image_description_v1 *desc, uint32_t identity) {
    (void)data;
    log_printf("[COLOR_TEST] ", "Image description ready: identity=%u\n", identity);
    image_description_ready = true;
    image_description_identity = identity;
}

static const struct wp_image_description_v1_listener image_description_listener = {
    .failed = image_description_failed,
    .ready = image_description_ready_event,
};

// Output color management listeners
static void color_output_image_description_changed(void *data, struct wp_color_management_output_v1 *output) {
    (void)data;
    (void)output;
    log_printf("[COLOR_TEST] ", "Output image description changed\n");
}

static const struct wp_color_management_output_v1_listener color_output_listener = {
    .image_description_changed = color_output_image_description_changed,
};

static void registry_handle_global(void *data, struct wl_registry *registry,
                                   uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    log_printf("[CLIENT] ", "registry_handle_global() - name=%u, interface=%s, version=%u\n", 
               name, interface, version);
    
    if (strcmp(interface, "wl_compositor") == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, "wl_shm") == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
        wl_shm_add_listener(shm, &shm_listener, NULL);
    } else if (strcmp(interface, "xdg_wm_base") == 0) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 4);
    } else if (strcmp(interface, "wp_color_manager_v1") == 0) {
        log_printf("[COLOR_TEST] ", "Found color manager protocol!\n");
        color_manager = wl_registry_bind(registry, name, &wp_color_manager_v1_interface, 1);
        wp_color_manager_v1_add_listener(color_manager, &color_manager_listener, NULL);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry,
                                          uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    registry_handle_global,
    registry_handle_global_remove,
};

static void wm_base_ping(void *data, struct xdg_wm_base *wm, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(wm, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
    wm_base_ping,
};

static bool surface_configured = false;

// Forward declaration
static struct wl_buffer *create_test_buffer(int w, int h, enum test_mode mode);

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
                                  uint32_t serial) {
    (void)data;
    log_printf("[COLOR_TEST] ", "Surface configured, serial=%u (size: %dx%d)\n", serial, width, height);
    xdg_surface_ack_configure(xdg_surface, serial);
    surface_configured = true;
    
    // If we have a buffer but size changed, destroy it to force immediate recreation
    // The frame callback will recreate it on the next frame
    if (buffer && (width > 0 && height > 0)) {
        // Mark buffer for recreation - frame callback will handle it
        // We don't destroy here to avoid issues, just let frame callback detect size change
    }
}

static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_configure,
};

static void xdg_toplevel_configure(void *data, struct xdg_toplevel *toplevel,
                                   int32_t w, int32_t h, struct wl_array *states) {
    (void)data;
    (void)toplevel;
    (void)states;
    if (w > 0 && h > 0) {
        bool size_changed = (width != w || height != h);
        int32_t old_width = width;
        int32_t old_height = height;
        width = w;
        height = h;
        
        if (size_changed) {
            log_printf("[CLIENT] ", "Window resized: %dx%d -> %dx%d\n", old_width, old_height, width, height);
            
            // Destroy old buffer immediately to force recreation
            if (buffer) {
                wl_buffer_destroy(buffer);
                buffer = NULL;
            }
            
            // If surface is already configured and we have valid size, try to create buffer immediately
            if (surface_configured && surface && width > 0 && height > 0 && shm) {
                log_printf("[CLIENT] ", "Creating new buffer immediately for resize...\n");
                buffer = create_test_buffer(width, height, current_test);
                if (buffer) {
                    wl_surface_attach(surface, buffer, 0, 0);
                    wl_surface_damage(surface, 0, 0, width, height);
                    wl_surface_commit(surface);
                    wl_display_flush(display);
                    log_printf("[CLIENT] ", "Buffer recreated and attached for resize\n");
                }
            }
        } else {
            log_printf("[CLIENT] ", "Window configure: %dx%d (no size change)\n", width, height);
        }
    }
}

static void xdg_toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)data;
    (void)toplevel;
    log_printf("[CLIENT] ", "Window close requested\n");
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    xdg_toplevel_configure,
    xdg_toplevel_close,
};

// Create SHM buffer with test pattern (animated)
static struct wl_buffer *create_test_buffer(int w, int h, enum test_mode mode) {
    if (w <= 0 || h <= 0) {
        fprintf(stderr, "[COLOR_TEST] Invalid buffer size: %dx%d\n", w, h);
        return NULL;
    }
    
    if (!shm) {
        fprintf(stderr, "[COLOR_TEST] SHM not available\n");
        return NULL;
    }
    
    stride = w * 4;
    size_t size = stride * h;
    
    // Use unique name with PID to avoid conflicts
    char shm_name[64];
    snprintf(shm_name, sizeof(shm_name), "/tmp/wayland-shm-test-%d", getpid());
    shm_unlink(shm_name);
    shm_fd = shm_open(shm_name, O_CREAT | O_RDWR | O_EXCL, 0600);
    if (shm_fd < 0) {
        fprintf(stderr, "[COLOR_TEST] Failed to create SHM: %s\n", strerror(errno));
        return NULL;
    }
    
    if (ftruncate(shm_fd, size) < 0) {
        close(shm_fd);
        shm_unlink(shm_name);
        fprintf(stderr, "[COLOR_TEST] Failed to truncate SHM: %s\n", strerror(errno));
        return NULL;
    }
    
    data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    if (data == MAP_FAILED) {
        close(shm_fd);
        shm_unlink(shm_name);
        fprintf(stderr, "[COLOR_TEST] Failed to mmap SHM: %s\n", strerror(errno));
        return NULL;
    }
    
    // Fill with animated test pattern based on color space
    uint32_t *pixels = (uint32_t *)data;
    
    // Animation time parameter (cycles every 2 seconds at 60fps for more visible animation)
    float anim_time = fmodf((float)frame_count / 60.0f, 2.0f); // 2 second cycle
    float anim_phase = anim_time * 2.0f * M_PI; // 0 to 2π
    
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint32_t pixel = 0xFF000000; // ARGB
            
            // Normalized coordinates
            float fx = (float)x / w;
            float fy = (float)y / h;
            
            // Animation parameters - make animation more visible
            float anim_speed = anim_time * 2.0f; // Faster animation speed
            float anim_offset = sinf(anim_phase) * 0.5f; // Larger offset for more movement
            float fx_anim = fx + anim_offset;
            if (fx_anim < 0.0f) fx_anim += 1.0f;
            if (fx_anim > 1.0f) fx_anim -= 1.0f;
            
            // Pulsing brightness for visibility - faster pulse
            float pulse = 0.3f + 0.7f * sinf(anim_phase); // 0.3 to 1.0 for better visibility
            
            // Different animated patterns for different color spaces
            switch (mode) {
                case TEST_SRGB:
                    // Animated sRGB gradient (red to blue, moving horizontally)
                    {
                        float offset_x = sinf(anim_phase) * 0.3f; // Moving offset
                        float fx_moved = fx + offset_x;
                        if (fx_moved > 1.0f) fx_moved -= 1.0f;
                        if (fx_moved < 0.0f) fx_moved += 1.0f;
                        float r = fx_moved * pulse;
                        float b = (1.0f - fx_moved) * pulse;
                        pixel = 0xFF000000 | 
                               ((uint32_t)(r * 255) << 16) |
                               ((uint32_t)(b * 255) << 0);
                    }
                    break;
                    
                case TEST_BT2020:
                case TEST_DCI_P3:
                case TEST_DISPLAY_P3:
                    // Animated wide gamut gradient (rotating colors with moving wave)
                    {
                        float wave = sinf((fx + anim_speed) * 4.0f * M_PI) * 0.5f + 0.5f;
                        float angle = anim_phase + fx * 2.0f * M_PI;
                        float r = (sinf(angle) + 1.0f) * 0.5f * pulse * wave;
                        float g = (sinf(angle + 2.0f * M_PI / 3.0f) + 1.0f) * 0.5f * pulse * wave;
                        float b = (sinf(angle + 4.0f * M_PI / 3.0f) + 1.0f) * 0.5f * pulse * wave;
                        pixel = 0xFF000000 |
                               ((uint32_t)(r * 255) << 16) |
                               ((uint32_t)(g * 255) << 8) |
                               ((uint32_t)(b * 255) << 0);
                    }
                    break;
                    
                case TEST_WINDOWS_SCRGB:
                    // Animated HDR test pattern (bright pulsing gradient with moving wave)
                    {
                        float wave = sinf((fx + anim_speed) * 3.0f * M_PI) * 0.5f + 0.5f;
                        float brightness = fx * pulse * wave * 1.5f; // Extended range
                        if (brightness > 1.0f) brightness = 1.0f;
                        uint32_t val = (uint32_t)(brightness * 255);
                        pixel = 0xFF000000 | (val << 16) | (val << 8) | val;
                    }
                    break;
                    
                default:
                    // Animated checkerboard pattern (moving)
                    {
                        int checker_size = 40;
                        int checker_x = (int)(x + sinf(anim_phase) * 20.0f) / checker_size;
                        int checker_y = (int)(y + cosf(anim_phase) * 20.0f) / checker_size;
                        if ((checker_x + checker_y) % 2 == 0) {
                            pixel = 0xFF000000 | ((uint32_t)(pulse * 255) << 16) | 
                                   ((uint32_t)(pulse * 255) << 8) | (uint32_t)(pulse * 255);
                        } else {
                            pixel = 0xFF000000;
                        }
                    }
                    break;
            }
            
            pixels[y * w + x] = pixel;
        }
    }
    
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, shm_fd, size);
    if (!pool) {
        munmap(data, size);
        close(shm_fd);
        shm_unlink(shm_name);
        fprintf(stderr, "[COLOR_TEST] Failed to create SHM pool\n");
        return NULL;
    }
    
    struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(shm_fd);
    shm_fd = -1;
    shm_unlink(shm_name);
    
    if (!buf) {
        munmap(data, size);
        fprintf(stderr, "[COLOR_TEST] Failed to create buffer\n");
        return NULL;
    }
    
    return buf;
}

// Test color operations
static void test_color_operations(void) {
    if (!color_manager || !color_manager_done) {
        return;
    }
    
    if (!surface || !surface_configured) {
        return;
    }
    
    // Get color management surface
    if (!color_surface) {
        log_printf("[COLOR_TEST] ", "Creating color management surface...\n");
        color_surface = wp_color_manager_v1_get_surface(color_manager, surface);
        if (!color_surface) {
            log_printf("[COLOR_TEST] ", "Failed to create color management surface\n");
            return;
        }
        log_printf("[COLOR_TEST] ", "Color management surface created\n");
    }
    
    // Cycle through different color space tests
    if (frame_count > 0 && frame_count % 300 == 0) { // Change every 5 seconds at 60fps
        current_test = (current_test + 1) % (TEST_MAX - 1);
        log_printf("[COLOR_TEST] ", "Switching to test: %s\n", test_names[current_test]);
        
        // Destroy previous image description
        if (current_image_description) {
            wp_image_description_v1_destroy(current_image_description);
            current_image_description = NULL;
            image_description_ready = false;
        }
        
        // Create new image description based on test
        struct wp_image_description_creator_params_v1 *creator = NULL;
        
        switch (current_test) {
            case TEST_SRGB:
                if (supported_features & (1U << WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC)) {
                    creator = wp_color_manager_v1_create_parametric_creator(color_manager);
                    if (creator) {
                        wp_image_description_creator_params_v1_set_primaries_named(
                            creator, WP_COLOR_MANAGER_V1_PRIMARIES_SRGB);
                        wp_image_description_creator_params_v1_set_tf_named(
                            creator, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB);
                        wp_image_description_creator_params_v1_set_luminances(
                            creator, 2, 800, 800); // 0.2-80 cd/m²
                        current_image_description = wp_image_description_creator_params_v1_create(creator);
                        // Creator is destroyed by create() call
                    }
                }
                break;
                
            case TEST_BT2020:
                if (supported_features & (1U << WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC)) {
                    creator = wp_color_manager_v1_create_parametric_creator(color_manager);
                    if (creator) {
                        wp_image_description_creator_params_v1_set_primaries_named(
                            creator, WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);
                        wp_image_description_creator_params_v1_set_tf_named(
                            creator, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ);
                        wp_image_description_creator_params_v1_set_luminances(
                            creator, 0, 10000, 203); // HDR: 0-10000 cd/m²
                        current_image_description = wp_image_description_creator_params_v1_create(creator);
                    }
                }
                break;
                
            case TEST_DCI_P3:
                if (supported_features & (1U << WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC)) {
                    creator = wp_color_manager_v1_create_parametric_creator(color_manager);
                    if (creator) {
                        wp_image_description_creator_params_v1_set_primaries_named(
                            creator, WP_COLOR_MANAGER_V1_PRIMARIES_DCI_P3);
                        wp_image_description_creator_params_v1_set_tf_named(
                            creator, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB);
                        wp_image_description_creator_params_v1_set_luminances(
                            creator, 2, 800, 800);
                        current_image_description = wp_image_description_creator_params_v1_create(creator);
                    }
                }
                break;
                
            case TEST_DISPLAY_P3:
                if (supported_features & (1U << WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC)) {
                    creator = wp_color_manager_v1_create_parametric_creator(color_manager);
                    if (creator) {
                        wp_image_description_creator_params_v1_set_primaries_named(
                            creator, WP_COLOR_MANAGER_V1_PRIMARIES_DISPLAY_P3);
                        wp_image_description_creator_params_v1_set_tf_named(
                            creator, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB);
                        wp_image_description_creator_params_v1_set_luminances(
                            creator, 2, 800, 800);
                        current_image_description = wp_image_description_creator_params_v1_create(creator);
                    }
                }
                break;
                
            case TEST_WINDOWS_SCRGB:
                if (supported_features & (1U << WP_COLOR_MANAGER_V1_FEATURE_WINDOWS_SCRGB)) {
                    current_image_description = wp_color_manager_v1_create_windows_scrgb(color_manager);
                } else {
                    log_printf("[COLOR_TEST] ", "Windows scRGB not supported, skipping\n");
                    current_test = (current_test + 1) % (TEST_MAX - 1);
                    return;
                }
                break;
                
            default:
                break;
        }
        
        if (current_image_description) {
            wp_image_description_v1_add_listener(current_image_description, &image_description_listener, NULL);
            image_description_ready = false; // Reset ready state
            wl_display_flush(display);
            // Dispatch events to receive ready/failed event
            wl_display_dispatch_pending(display);
        }
    }
    
    // Set image description on surface when ready
    static int last_test_set = -1;
    if (current_image_description && image_description_ready && last_test_set != current_test) {
        log_printf("[COLOR_TEST] ", "Setting image description on surface (test: %s)\n", 
                   test_names[current_test]);
        wp_color_management_surface_v1_set_image_description(
            color_surface, current_image_description, 
            WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
        last_test_set = current_test;
        wl_display_flush(display);
    }
}

static void frame_callback(void *data, struct wl_callback *callback, uint32_t time);

// Frame callback listener (defined at file scope so it persists)
static const struct wl_callback_listener frame_listener = {
    .done = frame_callback
};

static void frame_callback(void *data, struct wl_callback *callback, uint32_t time) {
    (void)data;
    
    if (callback) {
        wl_callback_destroy(callback);
    }
    
    frame_count++;
    
    // Log every 60th frame to avoid spam (once per second at 60fps)
    if (frame_count % 60 == 0) {
        log_printf("[COLOR_TEST] ", "Frame callback received! frame=%d, time=%u\n", frame_count, time);
    }
    
    // Check if display is still valid
    if (!display || !surface) {
        log_printf("[COLOR_TEST] ", "Frame callback: display or surface invalid, returning\n");
        return;
    }
    
    // Dispatch pending events (for image description ready events)
    wl_display_dispatch_pending(display);
    
    // Test color operations
    test_color_operations();
    
    // Create new buffer with animated test pattern
    // Always recreate buffer every frame for animation
    static int last_width = 0, last_height = 0;
    static enum test_mode last_test_mode = TEST_MAX;
    
    bool size_changed = (width != last_width || height != last_height);
    bool test_changed = (current_test != last_test_mode);
    
    // Always recreate buffer for animation (frame_count changes each frame)
    if (buffer) {
        wl_buffer_destroy(buffer);
        buffer = NULL;
    }
    
    // Create new animated buffer
    if (width > 0 && height > 0) {
        buffer = create_test_buffer(width, height, current_test);
        if (!buffer) {
            fprintf(stderr, "[COLOR_TEST] Failed to create buffer (%dx%d), skipping frame\n", width, height);
            // Still request next frame callback even if buffer creation failed
            struct wl_callback *cb = wl_surface_frame(surface);
            if (cb) {
                wl_callback_add_listener(cb, &frame_listener, NULL);
            }
            wl_surface_commit(surface);
            wl_display_flush(display);
            return;
        }
        
        last_width = width;
        last_height = height;
        last_test_mode = current_test;
    } else {
        // Invalid size, wait for configure - but still request frame callback
        struct wl_callback *cb = wl_surface_frame(surface);
        if (cb) {
            wl_callback_add_listener(cb, &frame_listener, NULL);
        }
        wl_surface_commit(surface);
        wl_display_flush(display);
        return;
    }
    
    // Attach new animated buffer and request next frame callback
    if (buffer && surface) {
        wl_surface_attach(surface, buffer, 0, 0);
        wl_surface_damage(surface, 0, 0, width, height);
        
        // CRITICAL: Always request next frame callback to continue animation
        struct wl_callback *cb = wl_surface_frame(surface);
        if (cb) {
            wl_callback_add_listener(cb, &frame_listener, NULL);
        }
        
        wl_surface_commit(surface);
        wl_display_flush(display);
    }
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    init_client_logging();
    
    // Set up XDG_RUNTIME_DIR if not set
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    if (!runtime_dir) {
        const char *tmpdir = getenv("TMPDIR");
        if (!tmpdir) tmpdir = "/tmp";
        char runtime_path[512];
        snprintf(runtime_path, sizeof(runtime_path), "%s/wayland-runtime", tmpdir);
        mkdir(runtime_path, 0700);
        setenv("XDG_RUNTIME_DIR", runtime_path, 0);
        printf("Set XDG_RUNTIME_DIR to: %s\n", runtime_path);
    }
    
    log_printf("[COLOR_TEST] ", "=== Wayland Color Management & HDR Test Client ===\n");
    log_printf("[COLOR_TEST] ", "Connecting to Wawona compositor...\n");
    
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "[COLOR_TEST] Failed to connect to Wayland display\n");
        fprintf(stderr, "[COLOR_TEST] Make sure compositor is running and WAYLAND_DISPLAY is set\n");
        return 1;
    }
    
    log_printf("[COLOR_TEST] ", "Connected to Wayland display\n");
    
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_flush(display);
    
    log_printf("[COLOR_TEST] ", "Waiting for registry globals...\n");
    if (wl_display_roundtrip(display) < 0) {
        fprintf(stderr, "[COLOR_TEST] Failed to receive registry\n");
        return 1;
    }
    
    if (!color_manager) {
        fprintf(stderr, "[COLOR_TEST] Color manager protocol not available!\n");
        fprintf(stderr, "[COLOR_TEST] Make sure Wawona compositor supports color operations\n");
        return 1;
    }
    
    log_printf("[COLOR_TEST] ", "Waiting for color manager capabilities...\n");
    while (!color_manager_done) {
        if (wl_display_dispatch(display) < 0) {
            fprintf(stderr, "[COLOR_TEST] Display dispatch failed\n");
            return 1;
        }
    }
    
    log_printf("[COLOR_TEST] ", "Color manager ready! Starting tests...\n");
    
    if (!compositor || !shm || !wm_base) {
        fprintf(stderr, "[COLOR_TEST] Missing required protocols\n");
        return 1;
    }
    
    // Create surface
    surface = wl_compositor_create_surface(compositor);
    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &xdg_toplevel_listener, NULL);
    xdg_toplevel_set_title(toplevel, "Wawona Color & HDR Test");
    xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
    
    wl_surface_commit(surface);
    wl_display_flush(display);
    
    log_printf("[COLOR_TEST] ", "Window created, waiting for configure...\n");
    
    // Wait for surface to be configured
    while (!surface_configured) {
        if (wl_display_dispatch(display) < 0) {
            fprintf(stderr, "[COLOR_TEST] Display dispatch failed while waiting for configure\n");
            return 1;
        }
    }
    
    log_printf("[COLOR_TEST] ", "Surface configured! Starting render loop...\n");
    log_printf("[COLOR_TEST] ", "Tests will cycle through: sRGB, BT.2020 (HDR), DCI-P3, Display P3, Windows scRGB\n");
    log_printf("[COLOR_TEST] ", "Window should be visible now! (size: %dx%d)\n", width, height);
    
    // Create initial buffer (only if we have valid dimensions)
    if (width > 0 && height > 0) {
        buffer = create_test_buffer(width, height, current_test);
        if (buffer) {
            wl_surface_attach(surface, buffer, 0, 0);
            wl_surface_damage(surface, 0, 0, width, height);
            wl_surface_commit(surface);
            wl_display_flush(display);
        } else {
            fprintf(stderr, "[COLOR_TEST] Failed to create initial buffer\n");
        }
    } else {
        log_printf("[COLOR_TEST] ", "Waiting for valid window size...\n");
    }
    
    // Start frame callback loop
    struct wl_callback *cb = wl_surface_frame(surface);
    wl_callback_add_listener(cb, &frame_listener, NULL);
    wl_surface_commit(surface);
    wl_display_flush(display);
    
    // Event loop - continue running until compositor disconnects
    int ret = 0;
    while (ret >= 0) {
        // Dispatch pending events first (non-blocking)
        ret = wl_display_dispatch_pending(display);
        if (ret < 0) {
            // Check if it's a real error
            int err = wl_display_get_error(display);
            if (err != 0) {
                fprintf(stderr, "[COLOR_TEST] Display error: %d\n", err);
                break;
            }
            // No events available, continue
            ret = 0;
        }
        
        // Flush any outgoing requests
        wl_display_flush(display);
        
        // Then do a blocking dispatch (waits for events)
        // This will block until frame callbacks arrive
        ret = wl_display_dispatch(display);
        if (ret < 0) {
            int err = wl_display_get_error(display);
            if (err != 0) {
                // Real error (like EPIPE when compositor closes)
                fprintf(stderr, "[COLOR_TEST] Display dispatch failed: ret=%d, err=%d\n", ret, err);
                const struct wl_interface *iface = NULL;
                uint32_t id = 0;
                uint32_t protocol_error = wl_display_get_protocol_error(display, &iface, &id);
                if (protocol_error != 0) {
                    fprintf(stderr, "[COLOR_TEST] Protocol error: interface=%s, id=%u, code=%u\n",
                            iface ? iface->name : "unknown", id, protocol_error);
                }
                break;
            }
            // No error, just no events - continue
            ret = 0;
        }
    }
    
    log_printf("[COLOR_TEST] ", "Test complete\n");
    
    if (current_image_description) {
        wp_image_description_v1_destroy(current_image_description);
    }
    if (color_surface) {
        wp_color_management_surface_v1_destroy(color_surface);
    }
    if (color_output) {
        wp_color_management_output_v1_destroy(color_output);
    }
    if (color_manager) {
        wp_color_manager_v1_destroy(color_manager);
    }
    if (buffer) {
        wl_buffer_destroy(buffer);
    }
    if (data && data != MAP_FAILED) {
        munmap(data, stride * height);
    }
    if (toplevel) {
        xdg_toplevel_destroy(toplevel);
    }
    if (xdg_surface) {
        xdg_surface_destroy(xdg_surface);
    }
    if (surface) {
        wl_surface_destroy(surface);
    }
    if (shm) {
        wl_shm_destroy(shm);
    }
    if (compositor) {
        wl_compositor_destroy(compositor);
    }
    if (wm_base) {
        xdg_wm_base_destroy(wm_base);
    }
    if (display) {
        wl_display_disconnect(display);
    }
    
    return 0;
}

