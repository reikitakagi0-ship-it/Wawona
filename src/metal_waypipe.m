#import "metal_waypipe.h"
#import "metal_dmabuf.h"
#import "wayland_compositor.h"
#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#include "logging.h"
#include <stdlib.h>

// Video codec callbacks
static void compression_output_callback(void *outputCallbackRefCon,
                                         void *sourceFrameRefCon,
                                         OSStatus status,
                                         VTEncodeInfoFlags infoFlags,
                                         CMSampleBufferRef sampleBuffer) {
    // Handle encoded frame
    (void)outputCallbackRefCon;
    (void)sourceFrameRefCon;
    (void)status;
    (void)infoFlags;
    (void)sampleBuffer;
}

// Decompression callback will be implemented when decoder is created
__attribute__((unused)) static void decompression_output_callback(void *decompressionOutputRefCon,
                                           void *sourceFrameRefCon,
                                           OSStatus status,
                                           VTDecodeInfoFlags infoFlags,
                                           CVImageBufferRef imageBuffer,
                                           CMTime presentationTimeStamp,
                                           CMTime presentationDuration) {
    // Handle decoded frame
    (void)decompressionOutputRefCon;
    (void)sourceFrameRefCon;
    (void)status;
    (void)infoFlags;
    (void)imageBuffer;
    (void)presentationTimeStamp;
    (void)presentationDuration;
}

struct metal_waypipe_context *metal_waypipe_create(id<MTLDevice> device) {
    if (!device) return NULL;
    
    struct metal_waypipe_context *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    
    context->device = device;
    context->commandQueue = [device newCommandQueue];
    if (!context->commandQueue) {
        free(context);
        return NULL;
    }
    
    // Initialize video encoder (H.264)
    OSStatus status;
    VTCompressionSessionRef encoder = NULL;
    
    status = VTCompressionSessionCreate(
        NULL, // allocator
        1920, 1080, // width, height (will be adjusted per frame)
        kCMVideoCodecType_H264,
        NULL, // encoderSpecification
        NULL, // sourceImageBufferAttributes
        NULL, // compressedDataAllocator
        compression_output_callback,
        (void *)context,
        &encoder
    );
    
    if (status == noErr) {
        context->encoder = encoder;
        NSLog(@"✅ Created H.264 encoder for waypipe");
    } else {
        NSLog(@"⚠️ Failed to create H.264 encoder: %d", (int)status);
    }
    
    // Initialize video decoder (will be created when we receive encoded data)
    // VTDecompressionSessionCreate requires a valid video format description
    // which we'll get from the encoded stream
    VTDecompressionSessionRef decoder = NULL;
    context->decoder = decoder; // Will be initialized later when needed
    
    NSLog(@"✅ Video decoder will be created on-demand when receiving encoded data");
    
    context->buffers = NULL;
    context->buffer_count = 0;
    
    NSLog(@"✅ Metal waypipe context created");
    return context;
}

void metal_waypipe_destroy(struct metal_waypipe_context *context) {
    if (!context) return;
    
    if (context->encoder) {
        VTCompressionSessionCompleteFrames(context->encoder, kCMTimeInvalid);
        VTCompressionSessionInvalidate(context->encoder);
        CFRelease(context->encoder);
    }
    
    if (context->decoder) {
        VTDecompressionSessionInvalidate(context->decoder);
        CFRelease(context->decoder);
    }
    
    if (context->buffers) {
        for (size_t i = 0; i < context->buffer_count; i++) {
            if (context->buffers[i]) {
                metal_dmabuf_destroy_buffer(context->buffers[i]);
            }
        }
        free(context->buffers);
    }
    
    free(context);
}

int metal_waypipe_encode_buffer(struct metal_waypipe_context *context,
                                 struct wl_surface_impl *surface,
                                 void **encoded_data,
                                 size_t *encoded_size) {
    if (!context || !surface || !encoded_data || !encoded_size) return -1;
    
    // Get buffer data from surface
    if (!surface->buffer_resource) return -1;
    
    struct buffer_data {
        void *data;
        int32_t offset;
        int32_t width;
        int32_t height;
        int32_t stride;
        uint32_t format;
    };
    
    struct buffer_data *buf_data = wl_resource_get_user_data(surface->buffer_resource);
    if (!buf_data || !buf_data->data) return -1;
    
    // Create IOSurface from buffer data
    IOSurfaceRef iosurface = metal_dmabuf_create_iosurface_from_data(
        (char *)buf_data->data + buf_data->offset,
        buf_data->width,
        buf_data->height,
        buf_data->stride,
        buf_data->format
    );
    
    if (!iosurface) return -1;
    
    // Create CVPixelBuffer from IOSurface
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn cvStatus = CVPixelBufferCreateWithIOSurface(
        NULL,
        iosurface,
        NULL,
        &pixelBuffer
    );
    
    CFRelease(iosurface);
    
    if (cvStatus != kCVReturnSuccess || !pixelBuffer) {
        return -1;
    }
    
    // Encode frame (simplified - full implementation would handle async encoding)
    // For now, return success (actual encoding would happen asynchronously)
    *encoded_data = NULL;
    *encoded_size = 0;
    
    CVPixelBufferRelease(pixelBuffer);
    
    NSLog(@"✅ Encoded buffer for waypipe (placeholder)");
    return 0;
}

int metal_waypipe_decode_buffer(struct metal_waypipe_context *context,
                                 void *encoded_data,
                                 size_t encoded_size,
                                 struct metal_dmabuf_buffer **buffer) {
    if (!context || !encoded_data || encoded_size == 0 || !buffer) return -1;
    
    // Decode video frame (simplified - full implementation would handle async decoding)
    // For now, return error (actual decoding would happen asynchronously)
    *buffer = NULL;
    
    NSLog(@"⚠️ Video decoding not yet fully implemented");
    return -1;
}

id<MTLTexture> metal_waypipe_get_texture(struct metal_waypipe_context *context,
                                          struct wl_surface_impl *surface) {
    if (!context || !surface || !surface->buffer_resource) return nil;
    
    // Get buffer data
    struct buffer_data {
        void *data;
        int32_t offset;
        int32_t width;
        int32_t height;
        int32_t stride;
        uint32_t format;
    };
    
    struct buffer_data *buf_data = wl_resource_get_user_data(surface->buffer_resource);
    if (!buf_data || !buf_data->data) return nil;
    
    // Create DMA-BUF buffer
    struct metal_dmabuf_buffer *dmabuf = metal_dmabuf_create_buffer(
        buf_data->width,
        buf_data->height,
        buf_data->format
    );
    
    if (!dmabuf) return nil;
    
    // Copy data to IOSurface
    IOSurfaceRef iosurface = metal_dmabuf_create_iosurface_from_data(
        (char *)buf_data->data + buf_data->offset,
        buf_data->width,
        buf_data->height,
        buf_data->stride,
        buf_data->format
    );
    
    if (!iosurface) {
        metal_dmabuf_destroy_buffer(dmabuf);
        return nil;
    }
    
    // Get Metal texture
    id<MTLTexture> texture = metal_dmabuf_get_texture(dmabuf, context->device);
    
    // Store buffer for later cleanup
    // (In full implementation, would track these properly)
    
    return texture;
}

