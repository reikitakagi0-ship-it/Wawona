#pragma once

#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include "metal_dmabuf.h"
#include "WawonaCompositor.h"

// Metal waypipe integration
// Supports video codec encoding/decoding and Metal buffer sharing

struct metal_waypipe_context {
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    
    // Video codec support
    VTCompressionSessionRef encoder;
    VTDecompressionSessionRef decoder;
    
    // Buffer management
    struct metal_dmabuf_buffer **buffers;
    size_t buffer_count;
};

// Initialize Metal waypipe context
struct metal_waypipe_context *metal_waypipe_create(id<MTLDevice> device);

// Destroy Metal waypipe context
void metal_waypipe_destroy(struct metal_waypipe_context *context);

// Encode Wayland buffer to video (H.264/H.265)
int metal_waypipe_encode_buffer(struct metal_waypipe_context *context, 
                                 struct wl_surface_impl *surface,
                                 void **encoded_data,
                                 size_t *encoded_size);

// Decode video to Wayland buffer
int metal_waypipe_decode_buffer(struct metal_waypipe_context *context,
                                 void *encoded_data,
                                 size_t encoded_size,
                                 struct metal_dmabuf_buffer **buffer);

// Create Metal texture from Wayland buffer for waypipe forwarding
id<MTLTexture> metal_waypipe_get_texture(struct metal_waypipe_context *context,
                                          struct wl_surface_impl *surface);

