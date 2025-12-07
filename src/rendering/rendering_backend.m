#import "rendering_backend.h"
#import "surface_renderer.h"
#import "metal_renderer.h"

@implementation RenderingBackendFactory

+ (id<RenderingBackend>)createBackend:(RenderingBackendType)type 
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
                         withView:(UIView *)view {
#else
                         withView:(NSView *)view {
#endif
    switch (type) {
        case RENDERING_BACKEND_SURFACE:
            return [[SurfaceRenderer alloc] initWithCompositorView:view];
            
        case RENDERING_BACKEND_METAL: {
            // For Metal renderer, we need to create a MTKView
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            MTKView *metalView = [[MTKView alloc] initWithFrame:view.bounds];
            metalView.device = MTLCreateSystemDefaultDevice();
            [view addSubview:metalView];
#else
            MTKView *metalView = [[MTKView alloc] initWithFrame:view.bounds];
            metalView.device = MTLCreateSystemDefaultDevice();
            [view addSubview:metalView];
#endif
            return [[MetalRenderer alloc] initWithMetalView:metalView];
        }
            
        case RENDERING_BACKEND_VULKAN:
            NSLog(@"❌ Vulkan renderer not implemented yet");
            return nil;
            
        default:
            NSLog(@"❌ Unknown rendering backend type: %ld", (long)type);
            return nil;
    }
}

@end