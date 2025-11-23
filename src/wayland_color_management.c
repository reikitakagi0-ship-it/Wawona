#include "wayland_color_management.h"
#include "color-management-v1-protocol.h"
#include "wayland_output.h"
#include "wayland_compositor.h"
#include "logging.h"
#include <wayland-server.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ColorSync/ColorSync.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>

// Include the protocol implementation directly to access WL_PRIVATE interfaces
#include "color-management-v1-protocol.c"

// Global counter for image description identities
uint32_t g_image_description_identity_counter = 1;

// Forward declarations
static void color_manager_destroy(struct wl_client *client, struct wl_resource *resource);
static void color_manager_get_output(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *output);
static void color_manager_get_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface);
static void color_manager_get_surface_feedback(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface);
static void color_manager_create_icc_creator(struct wl_client *client, struct wl_resource *resource, uint32_t obj);
static void color_manager_create_parametric_creator(struct wl_client *client, struct wl_resource *resource, uint32_t obj);
static void color_manager_create_windows_scrgb(struct wl_client *client, struct wl_resource *resource, uint32_t image_description);
static void color_management_output_destroy(struct wl_client *client, struct wl_resource *resource);
static void color_management_output_get_image_description(struct wl_client *client, struct wl_resource *resource, uint32_t image_description_id);
static void image_description_destroy(struct wl_client *client, struct wl_resource *resource);
static void image_description_get_information(struct wl_client *client, struct wl_resource *resource, uint32_t info_id);

static const struct wp_color_manager_v1_interface color_manager_interface = {
    .destroy = color_manager_destroy,
    .get_output = color_manager_get_output,
    .get_surface = color_manager_get_surface,
    .get_surface_feedback = color_manager_get_surface_feedback,
    .create_icc_creator = color_manager_create_icc_creator,
    .create_parametric_creator = color_manager_create_parametric_creator,
    .create_windows_scrgb = color_manager_create_windows_scrgb,
};

// ColorSync helper functions
bool detect_hdr_support(void) {
    // Check if display supports HDR
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Most devices support wide color (P3), but HDR support varies
    // Return false for now - can be enhanced later
    return false;
#else
    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    if (mainDisplay == kCGNullDirectDisplay) {
        return false;
    }
    
    // Check for HDR support (macOS 10.15+)
    // This is a simplified check - actual HDR detection requires more complex logic
    CGColorSpaceRef displayColorSpace = CGDisplayCopyColorSpace(mainDisplay);
    if (!displayColorSpace) {
        return false;
    }
    
    // Check if color space supports wide gamut (indicator of HDR capability)
    CFStringRef name = CGColorSpaceGetName(displayColorSpace);
    bool is_hdr = false;
    
    if (name) {
        CFStringRef p3 = CFSTR("kCGColorSpaceDisplayP3");
        CFStringRef rec2020 = CFSTR("kCGColorSpaceITUR_2020");
        if (CFStringCompare(name, p3, 0) == kCFCompareEqualTo ||
            CFStringCompare(name, rec2020, 0) == kCFCompareEqualTo) {
            is_hdr = true;
        }
    }
    
    CGColorSpaceRelease(displayColorSpace);
    return is_hdr;
#endif
}

CGColorSpaceRef get_display_color_space(void) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Use device RGB color space (typically P3 on modern devices)
    return CGColorSpaceCreateDeviceRGB();
#else
    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    if (mainDisplay == kCGNullDirectDisplay) {
        // Fallback to sRGB
        return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    }
    
    CGColorSpaceRef displayColorSpace = CGDisplayCopyColorSpace(mainDisplay);
    if (!displayColorSpace) {
        // Fallback to sRGB
        return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    }
    
    return displayColorSpace;
#endif
}

// Create ColorSpace from image description
CGColorSpaceRef create_colorspace_from_image_description(struct wp_image_description_impl *desc) {
    if (!desc) {
        return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    }
    
    // If already created, return cached version
    if (desc->color_space) {
        CGColorSpaceRetain(desc->color_space);
        return desc->color_space;
    }
    
    CGColorSpaceRef colorSpace = NULL;
    
    if (desc->is_icc && desc->icc_data) {
        // Create from ICC profile
        const void *icc_bytes = CFDataGetBytePtr(desc->icc_data);
        CFIndex icc_size = CFDataGetLength(desc->icc_data);
        
        if (icc_bytes && icc_size > 0) {
            colorSpace = CGColorSpaceCreateWithICCData(desc->icc_data);
        }
    } else if (desc->is_parametric) {
        // Create from parametric description
        // Map primaries to ColorSync
        if (desc->primaries_named == WP_COLOR_MANAGER_V1_PRIMARIES_SRGB) {
            colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        } else if (desc->primaries_named == WP_COLOR_MANAGER_V1_PRIMARIES_BT2020) {
            colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020);
        } else if (desc->primaries_named == WP_COLOR_MANAGER_V1_PRIMARIES_DCI_P3) {
            colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
        } else if (desc->primaries_named == WP_COLOR_MANAGER_V1_PRIMARIES_DISPLAY_P3) {
            colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
        } else {
            // Use chromaticity coordinates to create custom color space
            // This requires more complex ColorSync API usage
            // For now, fallback to sRGB
            colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        }
    } else if (desc->is_windows_scrgb) {
        // Windows scRGB - use extended sRGB
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
    }
    
    // Fallback to sRGB if creation failed
    if (!colorSpace) {
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    }
    
    // Cache the color space
    if (colorSpace) {
        desc->color_space = CGColorSpaceRetain(colorSpace);
    }
    
    return colorSpace;
}

// Create default sRGB image description for output
static struct wp_image_description_impl *create_default_output_image_description(struct wp_color_manager_impl *manager) {
    struct wp_image_description_impl *desc = calloc(1, sizeof(*desc));
    if (!desc) return NULL;
    
    desc->manager = manager;
    desc->ready = true;
    desc->is_parametric = true;
    desc->primaries_named = WP_COLOR_MANAGER_V1_PRIMARIES_SRGB;
    desc->tf_named = WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB;
    desc->min_lum = 2; // 0.2 cd/m² * 10
    desc->max_lum = 800; // 80 cd/m² * 10
    desc->reference_lum = 800; // 80 cd/m² * 10
    desc->identity = g_image_description_identity_counter++;
    
    // Create ColorSpace
    desc->color_space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    return desc;
}

// Protocol handlers
static void color_manager_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wp_color_manager_impl *manager = data;
    
    struct wl_resource *resource = wl_resource_create(client, &wp_color_manager_v1_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(resource, &color_manager_interface, manager, NULL);
    
    log_printf("[COLOR_MGMT] ", "color_manager_bind() - client=%p, version=%u, id=%u\n", (void *)client, version, id);
    
    // Send supported features
    // Advertise all features we support
    wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_ICC_V2_V4);
    wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC);
    wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_SET_PRIMARIES);
    wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_SET_TF_POWER);
    wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_SET_LUMINANCES);
    wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_SET_MASTERING_DISPLAY_PRIMARIES);
    wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_EXTENDED_TARGET_VOLUME);
    if (manager->hdr_supported) {
        wp_color_manager_v1_send_supported_feature(resource, WP_COLOR_MANAGER_V1_FEATURE_WINDOWS_SCRGB);
    }
    
    // Send supported render intents
    wp_color_manager_v1_send_supported_intent(resource, WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
    wp_color_manager_v1_send_supported_intent(resource, WP_COLOR_MANAGER_V1_RENDER_INTENT_RELATIVE);
    wp_color_manager_v1_send_supported_intent(resource, WP_COLOR_MANAGER_V1_RENDER_INTENT_SATURATION);
    wp_color_manager_v1_send_supported_intent(resource, WP_COLOR_MANAGER_V1_RENDER_INTENT_ABSOLUTE);
    wp_color_manager_v1_send_supported_intent(resource, WP_COLOR_MANAGER_V1_RENDER_INTENT_RELATIVE_BPC);
    
    // Send supported transfer functions
    wp_color_manager_v1_send_supported_tf_named(resource, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB);
    wp_color_manager_v1_send_supported_tf_named(resource, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_BT1886);
    wp_color_manager_v1_send_supported_tf_named(resource, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ);
    wp_color_manager_v1_send_supported_tf_named(resource, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG);
    wp_color_manager_v1_send_supported_tf_named(resource, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_EXT_SRGB);
    wp_color_manager_v1_send_supported_tf_named(resource, WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_EXT_LINEAR);
    
    // Send supported primaries
    wp_color_manager_v1_send_supported_primaries_named(resource, WP_COLOR_MANAGER_V1_PRIMARIES_SRGB);
    wp_color_manager_v1_send_supported_primaries_named(resource, WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);
    wp_color_manager_v1_send_supported_primaries_named(resource, WP_COLOR_MANAGER_V1_PRIMARIES_DCI_P3);
    wp_color_manager_v1_send_supported_primaries_named(resource, WP_COLOR_MANAGER_V1_PRIMARIES_DISPLAY_P3);
    wp_color_manager_v1_send_supported_primaries_named(resource, WP_COLOR_MANAGER_V1_PRIMARIES_ADOBE_RGB);
    
    // Send done event
    wp_color_manager_v1_send_done(resource);
}

static void color_manager_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void color_manager_get_output(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *output_resource) {
    struct wp_color_manager_impl *manager = wl_resource_get_user_data(resource);
    
    // Get output implementation from resource
    struct wl_output_impl *output = wl_resource_get_user_data(output_resource);
    if (!output) {
        wl_resource_post_error(resource, WP_COLOR_MANAGER_V1_ERROR_UNSUPPORTED_FEATURE, "Invalid output");
        return;
    }
    
    struct wp_color_management_output_impl *output_mgmt = calloc(1, sizeof(*output_mgmt));
    if (!output_mgmt) {
        wl_client_post_no_memory(client);
        return;
    }
    
    output_mgmt->manager = manager;
    output_mgmt->output = output;
    output_mgmt->output_resource = output_resource;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    output_mgmt->resource = wl_resource_create(client, &wp_color_management_output_v1_interface, (int)version, id);
    if (!output_mgmt->resource) {
        free(output_mgmt);
        wl_client_post_no_memory(client);
        return;
    }
    
    static const struct wp_color_management_output_v1_interface output_interface = {
        .destroy = color_management_output_destroy,
        .get_image_description = color_management_output_get_image_description,
    };
    wl_resource_set_implementation(output_mgmt->resource, &output_interface, output_mgmt, NULL);
    
    // Create default image description for output
    output_mgmt->image_description = create_default_output_image_description(manager);
    
    log_printf("[COLOR_MGMT] ", "color_manager_get_output() - client=%p, id=%u\n", (void *)client, id);
}

// Output color management handlers
static void color_management_output_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wp_color_management_output_impl *output_mgmt = wl_resource_get_user_data(resource);
    if (output_mgmt && output_mgmt->image_description) {
        if (output_mgmt->image_description->color_space) {
            CGColorSpaceRelease(output_mgmt->image_description->color_space);
        }
        if (output_mgmt->image_description->icc_data) {
            CFRelease(output_mgmt->image_description->icc_data);
        }
        free(output_mgmt->image_description);
    }
    free(output_mgmt);
    wl_resource_destroy(resource);
}

static void color_management_output_get_image_description(struct wl_client *client, struct wl_resource *resource, uint32_t image_description_id) {
    struct wp_color_management_output_impl *output_mgmt = wl_resource_get_user_data(resource);
    if (!output_mgmt || !output_mgmt->image_description) {
        return;
    }
    
    struct wp_image_description_impl *desc = output_mgmt->image_description;
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *desc_resource = wl_resource_create(client, &wp_image_description_v1_interface, (int)version, image_description_id);
    if (!desc_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // Use the standard image description interface
    static const struct wp_image_description_v1_interface desc_interface = {
        .destroy = image_description_destroy,
        .get_information = image_description_get_information,
    };
    wl_resource_set_implementation(desc_resource, &desc_interface, desc, NULL);
    
    // Send ready event immediately since we have a default description
    wp_image_description_v1_send_ready(desc_resource, desc->identity);
}

// Interface defined inline where used to avoid unused variable warning

// Surface color management handlers
static void color_management_surface_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wp_color_management_surface_impl *surface_mgmt = wl_resource_get_user_data(resource);
    
    if (!surface_mgmt) {
        // Already destroyed or invalid
        return;
    }
    
    // Clear reference from surface if it still exists and is valid
    // CRITICAL: The surface might have already been freed by client_destroy_listener
    // So we need to check if it's still valid before accessing it
    if (surface_mgmt->surface) {
        // Check if the surface's resource is still valid (not destroyed)
        // If surface->resource is NULL, the surface was already freed
        if (surface_mgmt->surface->resource) {
            // Surface is still valid, clear the color_management pointer
            surface_mgmt->surface->color_management = NULL;
        }
        // If surface->resource is NULL, the surface was already freed, so don't access it
    }
    
    free(surface_mgmt);
    // Don't call wl_resource_destroy here - Wayland will destroy it automatically
    // Calling it manually might cause double-destroy issues
}

static void color_management_surface_set_image_description(struct wl_client *client, struct wl_resource *resource, struct wl_resource *image_description_resource, uint32_t render_intent) {
    (void)client;
    struct wp_color_management_surface_impl *surface_mgmt = wl_resource_get_user_data(resource);
    struct wp_image_description_impl *desc = wl_resource_get_user_data(image_description_resource);
    
    if (!desc || !desc->ready) {
        wl_resource_post_error(resource, WP_COLOR_MANAGEMENT_SURFACE_V1_ERROR_IMAGE_DESCRIPTION, "Image description not ready");
        return;
    }
    
    // Store pending state (double-buffered)
    surface_mgmt->pending_image_description = desc;
    surface_mgmt->pending_render_intent = render_intent;
    
    log_printf("[COLOR_MGMT] ", "set_image_description() - surface=%p, render_intent=%u\n",
               (void *)surface_mgmt->surface, render_intent);
}

static void color_management_surface_unset_image_description(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wp_color_management_surface_impl *surface_mgmt = wl_resource_get_user_data(resource);
    surface_mgmt->pending_image_description = NULL;
    surface_mgmt->pending_render_intent = 0;
}

static const struct wp_color_management_surface_v1_interface color_management_surface_interface = {
    .destroy = color_management_surface_destroy,
    .set_image_description = color_management_surface_set_image_description,
    .unset_image_description = color_management_surface_unset_image_description,
};

static void color_manager_get_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface_resource) {
    struct wp_color_manager_impl *manager = wl_resource_get_user_data(resource);
    struct wl_surface_impl *surface = wl_surface_from_resource(surface_resource);
    
    if (!surface) {
        wl_resource_post_error(resource, WP_COLOR_MANAGER_V1_ERROR_SURFACE_EXISTS, "Invalid surface");
        return;
    }
    
    // Check if surface already has color management
    // TODO: Track surfaces with color management to prevent duplicates
    
    struct wp_color_management_surface_impl *surface_mgmt = calloc(1, sizeof(*surface_mgmt));
    if (!surface_mgmt) {
        wl_client_post_no_memory(client);
        return;
    }
    
    surface_mgmt->manager = manager;
    surface_mgmt->surface = surface;
    surface_mgmt->surface_resource = surface_resource;
    
    // Link color management to surface for renderer access
    surface->color_management = surface_mgmt;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    surface_mgmt->resource = wl_resource_create(client, &wp_color_management_surface_v1_interface, (int)version, id);
    if (!surface_mgmt->resource) {
        surface->color_management = NULL;
        free(surface_mgmt);
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(surface_mgmt->resource, &color_management_surface_interface, surface_mgmt, NULL);
    
    log_printf("[COLOR_MGMT] ", "get_surface() - client=%p, id=%u\n", (void *)client, id);
}

// Surface feedback handlers
static void color_management_surface_feedback_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wp_color_management_surface_feedback_impl *feedback = wl_resource_get_user_data(resource);
    free(feedback);
    wl_resource_destroy(resource);
}

static void color_management_surface_feedback_get_preferred(struct wl_client *client, struct wl_resource *resource, uint32_t image_description_id) {
    struct wp_color_management_surface_feedback_impl *feedback = wl_resource_get_user_data(resource);
    struct wp_color_manager_impl *manager = feedback->manager;
    
    // Create preferred image description (use output's default for now)
    struct wp_image_description_impl *desc = create_default_output_image_description(manager);
    if (!desc) {
        wl_client_post_no_memory(client);
        return;
    }
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *desc_resource = wl_resource_create(client, &wp_image_description_v1_interface, (int)version, image_description_id);
    if (!desc_resource) {
        free(desc);
        wl_client_post_no_memory(client);
        return;
    }
    
    // Use the standard image description interface
    static const struct wp_image_description_v1_interface desc_interface = {
        .destroy = image_description_destroy,
        .get_information = image_description_get_information,
    };
    wl_resource_set_implementation(desc_resource, &desc_interface, desc, NULL);
    wp_image_description_v1_send_ready(desc_resource, desc->identity);
}

static void color_management_surface_feedback_get_preferred_parametric(struct wl_client *client, struct wl_resource *resource, uint32_t image_description_id) {
    // Same as get_preferred but guaranteed parametric
    color_management_surface_feedback_get_preferred(client, resource, image_description_id);
}

static const struct wp_color_management_surface_feedback_v1_interface color_management_surface_feedback_interface = {
    .destroy = color_management_surface_feedback_destroy,
    .get_preferred = color_management_surface_feedback_get_preferred,
    .get_preferred_parametric = color_management_surface_feedback_get_preferred_parametric,
};

static void color_manager_get_surface_feedback(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface_resource) {
    struct wp_color_manager_impl *manager = wl_resource_get_user_data(resource);
    struct wl_surface_impl *surface = wl_surface_from_resource(surface_resource);
    
    if (!surface) {
        return;
    }
    
    struct wp_color_management_surface_feedback_impl *feedback = calloc(1, sizeof(*feedback));
    if (!feedback) {
        wl_client_post_no_memory(client);
        return;
    }
    
    feedback->manager = manager;
    feedback->surface = surface;
    feedback->surface_resource = surface_resource;
    feedback->preferred_identity = 1; // Default identity
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    feedback->resource = wl_resource_create(client, &wp_color_management_surface_feedback_v1_interface, (int)version, id);
    if (!feedback->resource) {
        free(feedback);
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(feedback->resource, &color_management_surface_feedback_interface, feedback, NULL);
    
    // Send preferred_changed event
    wp_color_management_surface_feedback_v1_send_preferred_changed(feedback->resource, feedback->preferred_identity);
}

// ICC creator handlers
// Destroy handler - resources are destroyed automatically by Wayland

static void image_description_creator_icc_set_icc_file(struct wl_client *client, struct wl_resource *resource, int32_t fd, uint32_t length, uint32_t offset) {
    struct wp_image_description_creator_icc_impl *creator = wl_resource_get_user_data(resource);
    if (!creator) return;
    
    if (creator->icc_set) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_ERROR_ALREADY_SET, "ICC file already set");
        close(fd);
        return;
    }
    
    // Read ICC data from fd
    lseek(fd, offset, SEEK_SET);
    void *data = malloc(length);
    if (!data) {
        close(fd);
        wl_client_post_no_memory(client);
        return;
    }
    
    ssize_t read_bytes = read(fd, data, length);
    close(fd);
    
    if (read_bytes != (ssize_t)length) {
        free(data);
        return;
    }
    
    creator->icc_data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, data, length, kCFAllocatorMalloc);
    creator->icc_set = true;
}

static void image_description_creator_icc_create(struct wl_client *client, struct wl_resource *resource, uint32_t image_description_id) {
    struct wp_image_description_creator_icc_impl *creator = wl_resource_get_user_data(resource);
    struct wp_color_manager_impl *manager = creator->manager;
    
    if (!creator->icc_set) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_CREATOR_ICC_V1_ERROR_INCOMPLETE_SET, "ICC file not set");
        return;
    }
    
    struct wp_image_description_impl *desc = calloc(1, sizeof(*desc));
    if (!desc) {
        wl_client_post_no_memory(client);
        return;
    }
    
    desc->manager = manager;
    desc->is_icc = true;
    desc->icc_data = CFRetain(creator->icc_data);
    desc->identity = g_image_description_identity_counter++;
    
    // Create ColorSpace from ICC
    desc->color_space = create_colorspace_from_image_description(desc);
    desc->ready = true;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *desc_resource = wl_resource_create(client, &wp_image_description_v1_interface, (int)version, image_description_id);
    if (!desc_resource) {
        if (desc->color_space) CGColorSpaceRelease(desc->color_space);
        if (desc->icc_data) CFRelease(desc->icc_data);
        free(desc);
        wl_client_post_no_memory(client);
        return;
    }
    
    // Use the standard image description interface
    static const struct wp_image_description_v1_interface desc_interface = {
        .destroy = image_description_destroy,
        .get_information = image_description_get_information,
    };
    wl_resource_set_implementation(desc_resource, &desc_interface, desc, NULL);
    wp_image_description_v1_send_ready(desc_resource, desc->identity);
    
    // Destroy creator
    wl_resource_destroy(resource);
}

static const struct wp_image_description_creator_icc_v1_interface image_description_creator_icc_interface = {
    .create = image_description_creator_icc_create,
    .set_icc_file = image_description_creator_icc_set_icc_file,
};

static void color_manager_create_icc_creator(struct wl_client *client, struct wl_resource *resource, uint32_t obj) {
    struct wp_color_manager_impl *manager = wl_resource_get_user_data(resource);
    
    struct wp_image_description_creator_icc_impl *creator = calloc(1, sizeof(*creator));
    if (!creator) {
        wl_client_post_no_memory(client);
        return;
    }
    
    creator->manager = manager;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    creator->resource = wl_resource_create(client, &wp_image_description_creator_icc_v1_interface, (int)version, obj);
    if (!creator->resource) {
        free(creator);
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(creator->resource, &image_description_creator_icc_interface, creator, NULL);
}

// Parametric creator handlers (simplified - full implementation would validate all parameters)
// Destroy handler - resources are destroyed automatically by Wayland

static void image_description_creator_params_set_tf_named(struct wl_client *client, struct wl_resource *resource, uint32_t tf) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    if (creator->tf_set) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_ALREADY_SET, "Transfer function already set");
        return;
    }
    creator->tf_named = tf;
    creator->tf_set = true;
}

static void image_description_creator_params_set_tf_power(struct wl_client *client, struct wl_resource *resource, uint32_t eexp) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    if (creator->tf_set) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_ALREADY_SET, "Transfer function already set");
        return;
    }
    creator->tf_power_eexp = eexp;
    creator->tf_set = true;
}

static void image_description_creator_params_set_primaries_named(struct wl_client *client, struct wl_resource *resource, uint32_t primaries) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    if (creator->primaries_set) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_ALREADY_SET, "Primaries already set");
        return;
    }
    creator->primaries_named = primaries;
    creator->primaries_set = true;
}

static void image_description_creator_params_set_primaries(struct wl_client *client, struct wl_resource *resource,
                                                          int32_t r_x, int32_t r_y, int32_t g_x, int32_t g_y,
                                                          int32_t b_x, int32_t b_y, int32_t w_x, int32_t w_y) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    if (creator->primaries_set) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_ALREADY_SET, "Primaries already set");
        return;
    }
    creator->r_x = r_x; creator->r_y = r_y;
    creator->g_x = g_x; creator->g_y = g_y;
    creator->b_x = b_x; creator->b_y = b_y;
    creator->w_x = w_x; creator->w_y = w_y;
    creator->primaries_set = true;
}

static void image_description_creator_params_set_luminances(struct wl_client *client, struct wl_resource *resource,
                                                             uint32_t min_lum, uint32_t max_lum, uint32_t reference_lum) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    creator->min_lum = min_lum;
    creator->max_lum = max_lum;
    creator->reference_lum = reference_lum;
    creator->luminances_set = true;
}

static void image_description_creator_params_set_mastering_display_primaries(struct wl_client *client, struct wl_resource *resource,
                                                                              int32_t r_x, int32_t r_y, int32_t g_x, int32_t g_y,
                                                                              int32_t b_x, int32_t b_y, int32_t w_x, int32_t w_y) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    creator->target_r_x = r_x; creator->target_r_y = r_y;
    creator->target_g_x = g_x; creator->target_g_y = g_y;
    creator->target_b_x = b_x; creator->target_b_y = b_y;
    creator->target_w_x = w_x; creator->target_w_y = w_y;
    creator->target_primaries_set = true;
}

static void image_description_creator_params_set_mastering_luminance(struct wl_client *client, struct wl_resource *resource,
                                                                      uint32_t min_lum, uint32_t max_lum) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    creator->target_min_lum = min_lum;
    creator->target_max_lum = max_lum;
    creator->target_luminance_set = true;
}

static void image_description_creator_params_set_max_cll(struct wl_client *client, struct wl_resource *resource, uint32_t max_cll) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    creator->target_max_cll = max_cll;
    creator->target_max_cll_set = true;
}

static void image_description_creator_params_set_max_fall(struct wl_client *client, struct wl_resource *resource, uint32_t max_fall) {
    (void)client;
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    creator->target_max_fall = max_fall;
    creator->target_max_fall_set = true;
}

static void image_description_creator_params_create(struct wl_client *client, struct wl_resource *resource, uint32_t image_description_id) {
    struct wp_image_description_creator_params_impl *creator = wl_resource_get_user_data(resource);
    struct wp_color_manager_impl *manager = creator->manager;
    
    if (!creator->tf_set || !creator->primaries_set) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_CREATOR_PARAMS_V1_ERROR_INCOMPLETE_SET, "Required parameters not set");
        return;
    }
    
    struct wp_image_description_impl *desc = calloc(1, sizeof(*desc));
    if (!desc) {
        wl_client_post_no_memory(client);
        return;
    }
    
    desc->manager = manager;
    desc->is_parametric = true;
    desc->primaries_named = creator->primaries_named;
    desc->r_x = creator->r_x; desc->r_y = creator->r_y;
    desc->g_x = creator->g_x; desc->g_y = creator->g_y;
    desc->b_x = creator->b_x; desc->b_y = creator->b_y;
    desc->w_x = creator->w_x; desc->w_y = creator->w_y;
    desc->tf_named = creator->tf_named;
    desc->tf_power_eexp = creator->tf_power_eexp;
    desc->min_lum = creator->min_lum;
    desc->max_lum = creator->max_lum;
    desc->reference_lum = creator->reference_lum;
    desc->target_r_x = creator->target_r_x; desc->target_r_y = creator->target_r_y;
    desc->target_g_x = creator->target_g_x; desc->target_g_y = creator->target_g_y;
    desc->target_b_x = creator->target_b_x; desc->target_b_y = creator->target_b_y;
    desc->target_w_x = creator->target_w_x; desc->target_w_y = creator->target_w_y;
    desc->target_min_lum = creator->target_min_lum;
    desc->target_max_lum = creator->target_max_lum;
    desc->target_max_cll = creator->target_max_cll;
    desc->target_max_fall = creator->target_max_fall;
    desc->identity = g_image_description_identity_counter++;
    
    desc->color_space = create_colorspace_from_image_description(desc);
    desc->ready = true;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *desc_resource = wl_resource_create(client, &wp_image_description_v1_interface, (int)version, image_description_id);
    if (!desc_resource) {
        if (desc->color_space) CGColorSpaceRelease(desc->color_space);
        free(desc);
        wl_client_post_no_memory(client);
        return;
    }
    
    // Use the standard image description interface
    static const struct wp_image_description_v1_interface desc_interface = {
        .destroy = image_description_destroy,
        .get_information = image_description_get_information,
    };
    wl_resource_set_implementation(desc_resource, &desc_interface, desc, NULL);
    wp_image_description_v1_send_ready(desc_resource, desc->identity);
    
    wl_resource_destroy(resource);
}

static const struct wp_image_description_creator_params_v1_interface image_description_creator_params_interface = {
    .create = image_description_creator_params_create,
    .set_tf_named = image_description_creator_params_set_tf_named,
    .set_tf_power = image_description_creator_params_set_tf_power,
    .set_primaries_named = image_description_creator_params_set_primaries_named,
    .set_primaries = image_description_creator_params_set_primaries,
    .set_luminances = image_description_creator_params_set_luminances,
    .set_mastering_display_primaries = image_description_creator_params_set_mastering_display_primaries,
    .set_mastering_luminance = image_description_creator_params_set_mastering_luminance,
    .set_max_cll = image_description_creator_params_set_max_cll,
    .set_max_fall = image_description_creator_params_set_max_fall,
};

static void color_manager_create_parametric_creator(struct wl_client *client, struct wl_resource *resource, uint32_t obj) {
    struct wp_color_manager_impl *manager = wl_resource_get_user_data(resource);
    
    struct wp_image_description_creator_params_impl *creator = calloc(1, sizeof(*creator));
    if (!creator) {
        wl_client_post_no_memory(client);
        return;
    }
    
    creator->manager = manager;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    creator->resource = wl_resource_create(client, &wp_image_description_creator_params_v1_interface, (int)version, obj);
    if (!creator->resource) {
        free(creator);
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(creator->resource, &image_description_creator_params_interface, creator, NULL);
}

static void color_manager_create_windows_scrgb(struct wl_client *client, struct wl_resource *resource, uint32_t image_description_id) {
    struct wp_color_manager_impl *manager = wl_resource_get_user_data(resource);
    
    if (!manager->hdr_supported) {
        wl_resource_post_error(resource, WP_COLOR_MANAGER_V1_ERROR_UNSUPPORTED_FEATURE, "Windows scRGB not supported");
        return;
    }
    
    struct wp_image_description_impl *desc = calloc(1, sizeof(*desc));
    if (!desc) {
        wl_client_post_no_memory(client);
        return;
    }
    
    desc->manager = manager;
    desc->is_windows_scrgb = true;
    desc->identity = g_image_description_identity_counter++;
    desc->color_space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
    desc->ready = true;
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *desc_resource = wl_resource_create(client, &wp_image_description_v1_interface, (int)version, image_description_id);
    if (!desc_resource) {
        if (desc->color_space) CGColorSpaceRelease(desc->color_space);
        free(desc);
        wl_client_post_no_memory(client);
        return;
    }
    
    // Use the standard image description interface
    static const struct wp_image_description_v1_interface desc_interface = {
        .destroy = image_description_destroy,
        .get_information = image_description_get_information,
    };
    wl_resource_set_implementation(desc_resource, &desc_interface, desc, NULL);
    wp_image_description_v1_send_ready(desc_resource, desc->identity);
}

// Image description handlers
static void image_description_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    struct wp_image_description_impl *desc = wl_resource_get_user_data(resource);
    if (desc) {
        if (desc->color_space) {
            CGColorSpaceRelease(desc->color_space);
        }
        if (desc->icc_data) {
            CFRelease(desc->icc_data);
        }
        free(desc);
    }
    wl_resource_destroy(resource);
}

static void image_description_get_information(struct wl_client *client, struct wl_resource *resource, uint32_t info_id) {
    struct wp_image_description_impl *desc = wl_resource_get_user_data(resource);
    if (!desc || !desc->ready) {
        wl_resource_post_error(resource, WP_IMAGE_DESCRIPTION_V1_ERROR_NOT_READY, "Image description not ready");
        return;
    }
    
    uint32_t version = (uint32_t)wl_resource_get_version(resource);
    struct wl_resource *info_resource = wl_resource_create(client, &wp_image_description_info_v1_interface, (int)version, info_id);
    if (!info_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    struct wp_image_description_info_impl *info = calloc(1, sizeof(*info));
    if (!info) {
        wl_resource_destroy(info_resource);
        wl_client_post_no_memory(client);
        return;
    }
    
    info->resource = info_resource;
    info->image_description = desc;
    wl_resource_set_implementation(info_resource, NULL, info, NULL);
    
    // Send information events
    if (desc->is_parametric) {
        if (desc->primaries_named) {
            wp_image_description_info_v1_send_primaries_named(info_resource, desc->primaries_named);
        } else {
            wp_image_description_info_v1_send_primaries(info_resource,
                desc->r_x, desc->r_y, desc->g_x, desc->g_y,
                desc->b_x, desc->b_y, desc->w_x, desc->w_y);
        }
        
        if (desc->tf_named) {
            wp_image_description_info_v1_send_tf_named(info_resource, desc->tf_named);
        } else if (desc->tf_power_eexp) {
            wp_image_description_info_v1_send_tf_power(info_resource, desc->tf_power_eexp);
        }
        
        wp_image_description_info_v1_send_luminances(info_resource,
            desc->min_lum, desc->max_lum, desc->reference_lum);
        
        if (desc->target_primaries_set) {
            wp_image_description_info_v1_send_target_primaries(info_resource,
                desc->target_r_x, desc->target_r_y, desc->target_g_x, desc->target_g_y,
                desc->target_b_x, desc->target_b_y, desc->target_w_x, desc->target_w_y);
        }
        
        if (desc->target_luminance_set) {
            wp_image_description_info_v1_send_target_luminance(info_resource,
                desc->target_min_lum, desc->target_max_lum);
        }
        
        if (desc->target_max_cll_set) {
            wp_image_description_info_v1_send_target_max_cll(info_resource, desc->target_max_cll);
        }
        
        if (desc->target_max_fall_set) {
            wp_image_description_info_v1_send_target_max_fall(info_resource, desc->target_max_fall);
        }
    }
    
    if (desc->is_icc && desc->icc_data) {
        CFIndex icc_size_cf = CFDataGetLength(desc->icc_data);
        uint32_t icc_size = (uint32_t)icc_size_cf;
        int32_t fd = -1; // TODO: Create fd from ICC data
        wp_image_description_info_v1_send_icc_file(info_resource, fd, icc_size);
    }
    
    wp_image_description_info_v1_send_done(info_resource);
}

// Interface defined inline where used to avoid unused variable warning

// Main creation/destruction functions
struct wp_color_manager_impl *wp_color_manager_create(struct wl_display *display, struct wl_output_impl *output) {
    struct wp_color_manager_impl *manager = calloc(1, sizeof(*manager));
    if (!manager) {
        return NULL;
    }
    
    manager->display = display;
    manager->output = output;
    manager->hdr_supported = detect_hdr_support();
    manager->display_color_space = get_display_color_space();
    
    manager->global = wl_global_create(display, &wp_color_manager_v1_interface, 1, manager, color_manager_bind);
    if (!manager->global) {
        if (manager->display_color_space) {
            CGColorSpaceRelease(manager->display_color_space);
        }
        free(manager);
        return NULL;
    }
    
    log_printf("[COLOR_MGMT] ", "wp_color_manager_create() - HDR supported: %s\n",
               manager->hdr_supported ? "yes" : "no");
    
    return manager;
}

void wp_color_manager_destroy(struct wp_color_manager_impl *manager) {
    if (!manager) return;
    
    wl_global_destroy(manager->global);
    if (manager->display_color_space) {
        CGColorSpaceRelease(manager->display_color_space);
    }
    free(manager);
}
