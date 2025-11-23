#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "wayland_compositor.h"

// Rendering backend selection
typedef enum {
    RENDERING_BACKEND_COCOA,  // NSWindow + Cocoa drawing (single window)
    RENDERING_BACKEND_METAL   // Metal rendering (full compositor)
} RenderingBackend;

// Forward declarations
@class SurfaceRenderer;
@class MetalRenderer;

// Rendering backend interface
@protocol RenderingBackendProtocol
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)setNeedsDisplay;
@end

// Cocoa/Cocoa rendering backend (for single Wayland windows)
@interface CocoaRenderer : NSObject <RenderingBackendProtocol>
@property (nonatomic, assign) NSView *compositorView;
- (instancetype)initWithCompositorView:(NSView *)view;
- (void)drawSurfacesInRect:(NSRect)dirtyRect;
@end

// Metal rendering backend (for full compositor like Weston)
@interface MetalRenderer : NSObject <RenderingBackendProtocol>
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
- (instancetype)initWithMetalView:(MTKView *)view;
- (void)drawInMTKView:(MTKView *)view;
@end

