#import "metal_dmabuf.h"
#import <Metal/Metal.h>
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <IOSurface/IOSurface.h>
#endif
#import <CoreVideo/CoreVideo.h>
#include "logging.h"
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>

// DMA-BUF emulation for macOS using IOSurface
// This allows efficient buffer sharing between processes (like waypipe)

struct metal_dmabuf_buffer *metal_dmabuf_create_buffer(uint32_t width, uint32_t height, uint32_t format) {
    struct metal_dmabuf_buffer *buffer = calloc(1, sizeof(*buffer));
    if (!buffer) return NULL;
    
    buffer->width = width;
    buffer->height = height;
    buffer->format = format;
    
    // Create IOSurface properties
    NSDictionary *properties = @{
        (NSString *)kIOSurfaceWidth: @(width),
        (NSString *)kIOSurfaceHeight: @(height),
        (NSString *)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA),
        (NSString *)kIOSurfaceBytesPerRow: @(width * 4),
        (NSString *)kIOSurfaceAllocSize: @(width * height * 4)
    };
    
    buffer->iosurface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!buffer->iosurface) {
        free(buffer);
        return NULL;
    }
    
    buffer->stride = width * 4;
    buffer->size = width * height * 4;
    
    NSLog(@"✅ Created IOSurface DMA-BUF buffer: %dx%d", width, height);
    return buffer;
}

id<MTLTexture> metal_dmabuf_get_texture(struct metal_dmabuf_buffer *buffer, id<MTLDevice> device) {
    if (!buffer || !buffer->iosurface || !device) return nil;
    
    // Create Metal texture from IOSurface
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                  width:buffer->width
                                                                                                 height:buffer->height
                                                                                              mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    textureDescriptor.storageMode = MTLStorageModeShared;
    
    id<MTLTexture> texture = [device newTextureWithDescriptor:textureDescriptor iosurface:buffer->iosurface plane:0];
    
    if (texture) {
        buffer->texture = texture;
        NSLog(@"✅ Created Metal texture from IOSurface");
    } else {
        NSLog(@"❌ Failed to create Metal texture from IOSurface");
    }
    
    return texture;
}

void metal_dmabuf_destroy_buffer(struct metal_dmabuf_buffer *buffer) {
    if (!buffer) return;
    
    if (buffer->texture) {
        buffer->texture = nil;
    }
    
    if (buffer->iosurface) {
        CFRelease(buffer->iosurface);
        buffer->iosurface = NULL;
    }
    
    if (buffer->data) {
        free(buffer->data);
        buffer->data = NULL;
    }
    
    free(buffer);
}

IOSurfaceRef metal_dmabuf_create_iosurface_from_data(void *data, uint32_t width, uint32_t height, uint32_t stride, uint32_t format __attribute__((unused))) {
    if (!data || width == 0 || height == 0) return NULL;
    
    // Metal requires IOSurface bytesPerRow to be aligned to 16 bytes
    // Align stride to 16 bytes for Metal compatibility
    uint32_t alignedStride = (stride + 15) & ~15;
    
    NSDictionary *properties = @{
        (NSString *)kIOSurfaceWidth: @(width),
        (NSString *)kIOSurfaceHeight: @(height),
        (NSString *)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA),
        (NSString *)kIOSurfaceBytesPerRow: @(alignedStride),
        (NSString *)kIOSurfaceAllocSize: @(alignedStride * height)
    };
    
    IOSurfaceRef iosurface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!iosurface) return NULL;
    
    // Lock and copy data
    IOSurfaceLock(iosurface, 0, NULL);
    void *surfaceBase = IOSurfaceGetBaseAddress(iosurface);
    size_t surfaceStride = IOSurfaceGetBytesPerRow(iosurface);
    
    // Always handle stride differences (source stride may differ from aligned stride)
    uint8_t *src = (uint8_t *)data;
    uint8_t *dst = (uint8_t *)surfaceBase;
    uint32_t copyWidth = (stride < surfaceStride) ? stride : surfaceStride;
    for (uint32_t y = 0; y < height; y++) {
        memcpy(dst, src, copyWidth);
        // Zero out padding if stride was extended
        if (surfaceStride > stride) {
            memset(dst + stride, 0, surfaceStride - stride);
        }
        src += stride;
        dst += surfaceStride;
    }
    
    IOSurfaceUnlock(iosurface, 0, NULL);
    
    return iosurface;
}

int metal_dmabuf_get_fd(struct metal_dmabuf_buffer *buffer) {
    if (!buffer || !buffer->iosurface) return -1;
    
    // On macOS, we can't directly get a file descriptor from IOSurface
    // Instead, we use a socket pair for IPC
    // This is a simplified version - full implementation would use proper IPC
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0) {
        return -1;
    }
    
    // Store IOSurface ID in the socket for the other process to retrieve
    // This is a placeholder - real implementation would serialize IOSurface properly
    uint64_t surfaceID = IOSurfaceGetID(buffer->iosurface);
    write(fds[1], &surfaceID, sizeof(surfaceID));
    
    return fds[0];
}

struct metal_dmabuf_buffer *metal_dmabuf_import(int fd, uint32_t width, uint32_t height, uint32_t format, uint32_t stride) {
    if (fd < 0) return NULL;
    
    uint64_t surfaceID = 0;
    ssize_t n = read(fd, &surfaceID, sizeof(surfaceID));
    close(fd);
    
    if (n != sizeof(surfaceID)) {
        NSLog(@"❌ Failed to read IOSurface ID from socket: %zd bytes read", n);
        return NULL;
    }
    
    IOSurfaceRef iosurface = IOSurfaceLookup((IOSurfaceID)surfaceID);
    if (!iosurface) {
        NSLog(@"❌ Failed to lookup IOSurface ID: %llu", surfaceID);
        return NULL;
    }
    
    struct metal_dmabuf_buffer *buffer = calloc(1, sizeof(*buffer));
    if (!buffer) {
        CFRelease(iosurface);
        return NULL;
    }
    
    buffer->iosurface = iosurface;
    buffer->width = width;
    buffer->height = height;
    buffer->format = format;
    buffer->stride = stride;
    
    NSLog(@"✅ Imported IOSurface DMA-BUF buffer: %dx%d (ID: %llu)", width, height, surfaceID);
    return buffer;
}
