#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <CoreGraphics/CoreGraphics.h>
#include "wayland_compositor.h"

// Forward declaration
@class SurfaceImage;

// Surface Renderer - Converts Wayland buffers to Cocoa/UIKit drawing
// Uses NSView/UIView drawing (like OWL compositor) instead of CALayer
@interface SurfaceRenderer : NSObject

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property (nonatomic, assign) UIView *compositorView;  // The view we draw into (assign for MRC compatibility)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SurfaceImage *> *surfaceImages;

- (instancetype)initWithCompositorView:(UIView *)view;
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)drawSurfacesInRect:(CGRect)dirtyRect;  // Called from drawRect:
#else
@property (nonatomic, assign) NSView *compositorView;  // The view we draw into (assign for MRC compatibility)
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SurfaceImage *> *surfaceImages;

- (instancetype)initWithCompositorView:(NSView *)view;
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)drawSurfacesInRect:(NSRect)dirtyRect;  // Called from drawRect:
#endif

@end
