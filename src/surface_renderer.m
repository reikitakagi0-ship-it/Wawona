#import "surface_renderer.h"
#import <CoreGraphics/CoreGraphics.h>
#include "wayland_compositor.h"
#include <wayland-server-core.h>
#include <wayland-server.h>

// Surface image data - stores CGImage and position for drawing
// OPTIMIZED: Cache CGImage to avoid recreating on every frame
@interface SurfaceImage : NSObject
@property (nonatomic, assign) CGImageRef image;
@property (nonatomic, assign) NSRect frame;
@property (nonatomic, assign) struct wl_surface_impl *surface;
@property (nonatomic, assign) void *lastBufferData;  // Track buffer to avoid unnecessary recreations
@property (nonatomic, assign) int32_t lastWidth;
@property (nonatomic, assign) int32_t lastHeight;
@property (nonatomic, assign) uint32_t lastFormat;
@end

@implementation SurfaceImage
- (void)dealloc {
    if (_image) {
        CGImageRelease(_image);
        _image = NULL;
    }
    [super dealloc];
}
@end

// Helper to convert raw pixel data to CGImage
static CGImageRef createCGImageFromData(void *data, int32_t width, int32_t height, int32_t stride, uint32_t format) {
    if (!data || width <= 0 || height <= 0 || stride <= 0) {
        return NULL;
    }
    
    // Convert format to CGImage format
    // Note: macOS is little-endian, so ARGB8888/XRGB8888 formats are stored as BGRA in memory
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = 0;
    
    if (format == WL_SHM_FORMAT_ARGB8888 || format == WL_SHM_FORMAT_XRGB8888) {
        // ARGB8888/XRGB8888: Alpha/Red/Green/Blue logical order
        // On little-endian (macOS), bytes in memory are BGRA (blue byte first)
        // Use little-endian byte order with alpha first (most significant byte)
        bitmapInfo = kCGBitmapByteOrder32Little;
        if (format == WL_SHM_FORMAT_ARGB8888) {
            bitmapInfo |= kCGImageAlphaPremultipliedFirst;
        } else {
            bitmapInfo |= kCGImageAlphaNoneSkipFirst; // XRGB8888 has no alpha
        }
    } else if (format == WL_SHM_FORMAT_RGBA8888 || format == WL_SHM_FORMAT_RGBX8888) {
        // RGBA8888/RGBX8888: Red/Green/Blue/Alpha logical order
        // On little-endian, bytes in memory are ABGR (alpha byte first, but alpha is last logically)
        bitmapInfo = kCGBitmapByteOrder32Little;
        if (format == WL_SHM_FORMAT_RGBA8888) {
            bitmapInfo |= kCGImageAlphaPremultipliedLast;
        } else {
            bitmapInfo |= kCGImageAlphaNoneSkipLast; // RGBX8888 has no alpha
        }
    } else if (format == WL_SHM_FORMAT_ABGR8888 || format == WL_SHM_FORMAT_XBGR8888) {
        // ABGR8888/XBGR8888: Alpha/Blue/Green/Red logical order
        // On little-endian, bytes in memory are RGBA
        bitmapInfo = kCGBitmapByteOrder32Little;
        if (format == WL_SHM_FORMAT_ABGR8888) {
            bitmapInfo |= kCGImageAlphaPremultipliedFirst;
        } else {
            bitmapInfo |= kCGImageAlphaNoneSkipFirst;
        }
    } else if (format == WL_SHM_FORMAT_BGRA8888 || format == WL_SHM_FORMAT_BGRX8888) {
        // BGRA8888/BGRX8888: Blue/Green/Red/Alpha logical order
        // On little-endian, bytes in memory are ARGB
        bitmapInfo = kCGBitmapByteOrder32Little;
        if (format == WL_SHM_FORMAT_BGRA8888) {
            bitmapInfo |= kCGImageAlphaPremultipliedLast;
        } else {
            bitmapInfo |= kCGImageAlphaNoneSkipLast;
        }
    } else {
        // Default: assume ARGB8888-like format
        bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
    }
    
    // Create CGImage directly from data (like OWL compositor)
    // Use CGDataProviderCreateWithData for efficient zero-copy image creation
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, data, stride * height, NULL);
    if (!provider) {
        CGColorSpaceRelease(colorSpace);
        return NULL;
    }
    
    // Create CGImage from data provider
    // Note: CGImageCreate will use the data directly without copying
    CGImageRef image = CGImageCreate(width, height, 8, 32, stride, colorSpace, bitmapInfo, provider,
                                     NULL, NO, kCGRenderingIntentDefault);
    
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}

@implementation SurfaceRenderer

- (instancetype)initWithCompositorView:(NSView *)view {
    self = [super init];
    if (self) {
        _compositorView = view;
        _surfaceImages = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)renderSurface:(struct wl_surface_impl *)surface {
    if (!surface) {
        return;
    }
    
    // CRITICAL: Verify the wl_surface resource is still valid before accessing it
    // The render callback is async, so the surface may have been destroyed
    if (!surface->resource) {
        // Surface was destroyed - remove image and return
        [self removeSurface:surface];
        return;
    }
    
    // SAFETY: Check user_data FIRST before calling wl_resource_get_client
    // This is safer because user_data access doesn't dereference as many internal fields
    // If the resource is destroyed, user_data will be NULL or point to wrong object
    struct wl_surface_impl *surface_check = wl_resource_get_user_data(surface->resource);
    if (!surface_check || surface_check != surface) {
        // Resource was destroyed or reused - remove image and return
        surface->resource = NULL;
        [self removeSurface:surface];
        return;
    }
    
    // Now verify resource is still valid by checking if we can get the client
    // This prevents crashes when resource is destroyed but pointer isn't NULL yet
    // Use signal-safe approach: check user_data first, then client
    struct wl_client *client = wl_resource_get_client(surface->resource);
    if (!client) {
        // Resource is destroyed - remove image and return
        surface->resource = NULL;
        [self removeSurface:surface];
        return;
    }
    
    // Get compositor window bounds to clamp surface rendering
    NSRect compositorBounds = self.compositorView ? self.compositorView.bounds : NSMakeRect(0, 0, 800, 600);
    CGFloat maxWidth = compositorBounds.size.width;
    CGFloat maxHeight = compositorBounds.size.height;
    
    // Check if buffer is still attached (might have been detached between commit and render)
    if (!surface->buffer_resource) {
        // No buffer - remove image but keep surface entry
        NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
        SurfaceImage *surfaceImage = self.surfaceImages[key];
        if (surfaceImage) {
            surfaceImage.image = NULL;  // Clear image but keep entry
        }
        if (self.compositorView) {
            [self.compositorView setNeedsDisplay:YES];
        }
        return;
    }
    
    // Verify buffer resource is still valid before accessing it
    // SAFETY: Check user_data FIRST before calling wl_resource_get_client
    void *buffer_user_data = wl_resource_get_user_data(surface->buffer_resource);
    if (!buffer_user_data) {
        // Buffer resource was destroyed - clear image and return
        surface->buffer_resource = NULL;
        surface->buffer_release_sent = true;
        NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
        SurfaceImage *surfaceImage = self.surfaceImages[key];
        if (surfaceImage) {
            surfaceImage.image = NULL;
        }
        if (self.compositorView) {
            [self.compositorView setNeedsDisplay:YES];
        }
        return;
    }
    
    // Now verify buffer resource client is still valid
    struct wl_client *buffer_client = wl_resource_get_client(surface->buffer_resource);
    if (!buffer_client) {
        // Buffer resource was destroyed - clear image and return
        surface->buffer_resource = NULL;
        surface->buffer_release_sent = true;
        NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
        SurfaceImage *surfaceImage = self.surfaceImages[key];
        if (surfaceImage) {
            surfaceImage.image = NULL;
        }
        if (self.compositorView) {
            [self.compositorView setNeedsDisplay:YES];
        }
        return;
    }
    
    // Try to get buffer info - first check if it's our custom buffer or standard Wayland SHM buffer
    struct buffer_data {
        void *data;
        int32_t offset;
        int32_t width;
        int32_t height;
        int32_t stride;
        uint32_t format;
    };
    
    struct buffer_data *buf_data = wl_resource_get_user_data(surface->buffer_resource);
    int32_t width, height, stride;
    uint32_t format;
    void *data = NULL;
    struct wl_shm_buffer *shm_buffer = NULL;
    
    // Verify buffer data is valid
    if (!buf_data || !buf_data->data) {
        // Buffer was destroyed or invalid - clear image and return
        surface->buffer_resource = NULL;
        surface->buffer_release_sent = true;
        NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
        SurfaceImage *surfaceImage = self.surfaceImages[key];
        if (surfaceImage) {
            surfaceImage.image = NULL;
        }
        if (self.compositorView) {
            [self.compositorView setNeedsDisplay:YES];
        }
        return;
    }
    
    width = buf_data->width;
    height = buf_data->height;
    stride = buf_data->stride;
    format = buf_data->format;
    data = (char *)buf_data->data + buf_data->offset;
    
    if ((uintptr_t)data < (uintptr_t)buf_data->data) {
        NSLog(@"[RENDERER] ❌ Invalid data pointer calculation");
        return;
    }
    
    if (!data) {
        if (shm_buffer) {
            wl_shm_buffer_end_access(shm_buffer);
        }
        if (self.compositorView) {
            [self.compositorView setNeedsDisplay:YES];
        }
        return;
    }
    
    // Update surface dimensions
    surface->width = width;
    surface->height = height;
    surface->buffer_width = width;
    surface->buffer_height = height;
    
    // Validate data pointer is in reasonable address range
    uintptr_t data_addr = (uintptr_t)data;
    if (data_addr < 0x1000 || data_addr > 0x7FFFFFFFFFFF) {
        if (shm_buffer) {
            wl_shm_buffer_end_access(shm_buffer);
        }
        return;
    }
    
    // OPTIMIZED: Check if we can reuse existing CGImage
    // Only recreate if buffer data pointer, dimensions, or format changed
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    SurfaceImage *surfaceImage = self.surfaceImages[key];
    BOOL needsNewImage = YES;
    
    if (surfaceImage && surfaceImage.image) {
        // Check if buffer data, dimensions, or format changed
        if (surfaceImage.lastBufferData == data &&
            surfaceImage.lastWidth == width &&
            surfaceImage.lastHeight == height &&
            surfaceImage.lastFormat == format) {
            // Buffer hasn't changed - reuse existing CGImage
            needsNewImage = NO;
        }
    }
    
    CGImageRef image = NULL;
    if (needsNewImage) {
        // Convert buffer to CGImage using direct data access
        image = createCGImageFromData(data, width, height, stride, format);
        
        // End access if using standard SHM buffer (must be before using image)
        if (shm_buffer) {
            wl_shm_buffer_end_access(shm_buffer);
        }
        
        if (!surfaceImage) {
            surfaceImage = [[SurfaceImage alloc] init];
            surfaceImage.surface = surface;
            self.surfaceImages[key] = surfaceImage;
        }
        
        // Update image and cache buffer info
        if (surfaceImage.image) {
            CGImageRelease(surfaceImage.image);
        }
        surfaceImage.image = image ? CGImageRetain(image) : NULL;
        surfaceImage.lastBufferData = data;
        surfaceImage.lastWidth = width;
        surfaceImage.lastHeight = height;
        surfaceImage.lastFormat = format;
    } else {
        // Reuse existing image - just end buffer access
        if (shm_buffer) {
            wl_shm_buffer_end_access(shm_buffer);
        }
    }
    
    if (surfaceImage && surfaceImage.image) {
        
        // Clamp frame to compositor window bounds
        CGFloat clampedWidth = (width < maxWidth) ? width : maxWidth;
        CGFloat clampedHeight = (height < maxHeight) ? height : maxHeight;
        NSRect newFrame = NSMakeRect(surface->x, surface->y, clampedWidth, clampedHeight);
        
        // Only update frame if it changed (optimization)
        if (!NSEqualRects(surfaceImage.frame, newFrame)) {
            surfaceImage.frame = newFrame;
        }
        
        // Release our reference if we created a new image (SurfaceImage retains it)
        if (image) {
            CGImageRelease(image);
        }
        
        // Release the buffer for this frame if we haven't already
        if (surface->buffer_resource && !surface->buffer_release_sent) {
            struct buffer_data *release_data = wl_resource_get_user_data(surface->buffer_resource);
            if (release_data != NULL) {
                wl_buffer_send_release(surface->buffer_resource);
            }
            surface->buffer_release_sent = true;
        }
        
        // Trigger redraw
        if (self.compositorView) {
            [self.compositorView setNeedsDisplay:YES];
        }
    } else {
        NSLog(@"[RENDER] Failed to create CGImage from buffer data: width=%d, height=%d, stride=%d, format=0x%x",
              width, height, stride, format);
    }
}

- (void)removeSurface:(struct wl_surface_impl *)surface {
    if (!surface) return;
    
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    SurfaceImage *surfaceImage = self.surfaceImages[key];
    if (surfaceImage) {
        // Clear image but keep entry if surface still exists (buffer detached)
        // Only remove entry completely if surface is being destroyed (resource is NULL)
        if (!surface->resource) {
            // Surface is being destroyed - remove entry completely
            [self.surfaceImages removeObjectForKey:key];
        } else {
            // Surface still exists, just clearing image (buffer detached)
            surfaceImage.image = NULL;
        }
        if (self.compositorView) {
            [self.compositorView setNeedsDisplay:YES];
        }
    }
}

- (void)drawSurfacesInRect:(NSRect)dirtyRect {
    // Draw all surfaces using CoreGraphics (like OWL compositor)
    // This is called from CompositorView's drawRect: method
    
    if (!self.compositorView) {
        return;
    }
    
    // Draw background
    [[NSColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:1.0] setFill];
    NSRectFill(dirtyRect);
    
    // Get graphics context
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    if (!context) {
        return;
    }
    
    CGContextRef cgContext = [context CGContext];
    if (!cgContext) {
        return;
    }
    
    // Draw all surfaces
    for (SurfaceImage *surfaceImage in [self.surfaceImages allValues]) {
        if (!surfaceImage.image || !surfaceImage.surface) {
            continue;
        }
        
        NSRect frame = surfaceImage.frame;
        
        // Only draw if frame intersects dirty rect
        if (!NSIntersectsRect(frame, dirtyRect)) {
            continue;
        }
        
        // Save graphics state
        CGContextSaveGState(cgContext);
        
        // CompositorView.isFlipped returns YES, so view coordinates use top-left origin (like Wayland)
        // Wayland buffers have Y=0 at top, which matches our flipped view coordinate system
        // However, CGContextDrawImage expects bottom-left origin and will flip images vertically
        // We need to flip the Y coordinate to compensate
        
        // Calculate drawing rectangle in view coordinates (top-left origin)
        CGRect drawRect = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        
        // CGContextDrawImage flips images vertically (expects bottom-left origin)
        // To compensate: translate to bottom of image, flip Y axis, then draw
        // This ensures Wayland's top-left origin image displays correctly
        CGContextTranslateCTM(cgContext, drawRect.origin.x, drawRect.origin.y + drawRect.size.height);
        CGContextScaleCTM(cgContext, 1.0, -1.0);
        
        // Draw image at origin (0,0) after transformation
        CGRect imageRect = CGRectMake(0, 0, drawRect.size.width, drawRect.size.height);
        CGContextDrawImage(cgContext, imageRect, surfaceImage.image);
        
        // Restore graphics state
        CGContextRestoreGState(cgContext);
    }
}

@end
