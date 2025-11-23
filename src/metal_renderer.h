#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "wayland_compositor.h"

// Metal renderer for full compositor rendering
// Used when forwarding entire compositor (like Weston) via waypipe

@class MetalSurface;

@interface MetalRenderer : NSObject <MTKViewDelegate>

@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, MetalSurface *> *surfaceTextures;
@property (nonatomic, assign) struct metal_waypipe_context *waypipeContext;

- (instancetype)initWithMetalView:(MTKView *)view;
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)setNeedsDisplay;

@end

