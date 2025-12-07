#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <Metal/Metal.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#define VK_USE_PLATFORM_IOS_MVK
#else
#define VK_USE_PLATFORM_MACOS_MVK
#endif
#define VK_USE_PLATFORM_METAL_EXT
#import <vulkan/vulkan.h>
#include "WawonaCompositor.h"

// Vulkan renderer using KosmicKrisp for EGL/OpenGL ES rendering
// Converts Vulkan output to Metal textures for display in Metal view

@class VulkanSurface;

@interface VulkanRenderer : NSObject

@property (nonatomic, strong) id<MTLDevice> metalDevice; // Metal device for texture conversion
@property (nonatomic, strong) id<MTLCommandQueue> metalCommandQueue;
@property (nonatomic, assign) VkInstance vkInstance;
@property (nonatomic, assign) VkPhysicalDevice vkPhysicalDevice;
@property (nonatomic, assign) VkDevice vkDevice;
@property (nonatomic, assign) VkQueue vkQueue;
@property (nonatomic, assign) uint32_t vkQueueFamilyIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, VulkanSurface *> *vulkanSurfaces;

- (instancetype)initWithMetalDevice:(id<MTLDevice>)metalDevice;
- (BOOL)initializeVulkan; // Initialize Vulkan using KosmicKrisp
- (void)cleanupVulkan;
- (id<MTLTexture>)renderEGLSurface:(struct wl_surface_impl *)surface; // Render EGL surface using Vulkan
- (id<MTLTexture>)convertVulkanImageToMetalTexture:(VkImage)vkImage width:(uint32_t)width height:(uint32_t)height; // Convert Vulkan image to Metal texture
- (void)removeSurface:(struct wl_surface_impl *)surface;

@end

