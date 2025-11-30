#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "WawonaCompositor.h"

// Metal renderer for full compositor rendering
// Used when forwarding entire compositor (like Weston) via waypipe

@class MetalSurface;
@class VulkanRenderer;

@interface MetalRenderer : NSObject <MTKViewDelegate, RenderingBackend>

@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, MetalSurface *> *surfaceTextures;
@property (nonatomic, assign) struct metal_waypipe_context *waypipeContext;
@property (nonatomic, strong) VulkanRenderer *vulkanRenderer;

- (instancetype)initWithMetalView:(MTKView *)view;
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)setNeedsDisplay;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)drawSurfacesInRect:(CGRect)dirtyRect;
#else
- (void)drawSurfacesInRect:(NSRect)dirtyRect;
#endif

@end

