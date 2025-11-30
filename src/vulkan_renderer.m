#import "vulkan_renderer.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import "egl_buffer_handler.h"
#endif
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#include <dlfcn.h>
#endif

// Vulkan instance extensions
const char *instance_extensions[] = {
    "VK_KHR_surface",
    "VK_MVK_macos_surface",
    "VK_EXT_metal_surface"
};

// Vulkan device extensions
const char *device_extensions[] = {
    "VK_KHR_swapchain",
    "VK_EXT_external_memory_host" // Useful for sharing memory
};

@implementation VulkanRenderer

- (instancetype)initWithMetalDevice:(id<MTLDevice>)metalDevice {
    self = [super init];
    if (self) {
        _metalDevice = metalDevice;
        _vulkanSurfaces = [NSMutableDictionary dictionary];
        
        if (![self initializeVulkan]) {
            NSLog(@"[VULKAN] ❌ Failed to initialize Vulkan");
            return nil;
        }
        NSLog(@"[VULKAN] ✅ Initialized Vulkan renderer");
    }
    return self;
}

- (BOOL)initializeVulkan {
    // 1. Create Vulkan Instance
    VkApplicationInfo appInfo = {};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Wawona Compositor";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "KosmicKrisp";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    
    // Enable extensions
    createInfo.enabledExtensionCount = sizeof(instance_extensions) / sizeof(instance_extensions[0]);
    createInfo.ppEnabledExtensionNames = instance_extensions;
    
    // Enable validation layers if needed (for debug)
    // const char *validationLayers[] = { "VK_LAYER_KHRONOS_validation" };
    // createInfo.enabledLayerCount = 1;
    // createInfo.ppEnabledLayerNames = validationLayers;
    
    // Vulkan functions are provided by KosmicKrisp library
    // On iOS, these should be available via the linked library
    // If linking fails, we'll need to load them dynamically or disable Vulkan renderer
    if (vkCreateInstance(&createInfo, NULL, &_vkInstance) != VK_SUCCESS) {
        NSLog(@"[VULKAN] Failed to create instance");
        return NO;
    }
    
    // 2. Pick Physical Device
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(_vkInstance, &deviceCount, NULL);
    if (deviceCount == 0) {
        NSLog(@"[VULKAN] No Vulkan devices found");
        return NO;
    }
    
    VkPhysicalDevice *devices = malloc(sizeof(VkPhysicalDevice) * deviceCount);
    vkEnumeratePhysicalDevices(_vkInstance, &deviceCount, devices);
    _vkPhysicalDevice = devices[0]; // Pick first device
    free(devices);
    
    // 3. Create Logical Device
    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueCreateInfo = {};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = 0; // Assume family 0 supports graphics (usually true on MoltenVK)
    queueCreateInfo.queueCount = 1;
    queueCreateInfo.pQueuePriorities = &queuePriority;
    
    VkDeviceCreateInfo deviceCreateInfo = {};
    deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;
    deviceCreateInfo.queueCreateInfoCount = 1;
    deviceCreateInfo.enabledExtensionCount = sizeof(device_extensions) / sizeof(device_extensions[0]);
    deviceCreateInfo.ppEnabledExtensionNames = device_extensions;
    
    if (vkCreateDevice(_vkPhysicalDevice, &deviceCreateInfo, NULL, &_vkDevice) != VK_SUCCESS) {
        NSLog(@"[VULKAN] Failed to create logical device");
        return NO;
    }
    
    vkGetDeviceQueue(_vkDevice, 0, 0, &_vkQueue);
    _vkQueueFamilyIndex = 0;
    
    return YES;
}

- (void)cleanupVulkan {
    if (_vkDevice) {
        vkDestroyDevice(_vkDevice, NULL);
        _vkDevice = VK_NULL_HANDLE;
    }
    if (_vkInstance) {
        vkDestroyInstance(_vkInstance, NULL);
        _vkInstance = VK_NULL_HANDLE;
    }
}

- (id<MTLTexture>)renderEGLSurface:(struct wl_surface_impl *)surface {
    if (!surface || !surface->buffer_resource) return nil;
    
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    struct egl_buffer_handler *handler = macos_compositor_get_egl_buffer_handler();
    if (!handler) return nil;
    
    int32_t width, height;
    EGLint format;
    if (egl_buffer_handler_query_buffer(handler, surface->buffer_resource, &width, &height, &format) != 0) {
        return nil;
    }
    
    // Check if we already have a Vulkan image for this surface
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    // VulkanSurface would be a class holding VkImage and MTLTexture
    // For now, we'll just log and maybe create a placeholder texture
    
    NSLog(@"[VULKAN] Rendering EGL surface: %dx%d fmt=%d", width, height, format);
#endif
    
    // TODO: Import EGL buffer as VkImage
    // This requires specific extensions (e.g. VK_EXT_external_memory_host) and knowing how KosmicKrisp exports buffers.
    // For now, we will create a dummy VkImage to simulate the process.
    
    // Mock implementation:
    // 1. Create a VkImage (representing the EGL content)
    // 2. Convert it to Metal Texture
    
    // In a real implementation, we would use VK_EXT_external_memory to bind the EGL buffer memory.
    
    return nil;
}

- (id<MTLTexture>)convertVulkanImageToMetalTexture:(VkImage)vkImage width:(uint32_t)width height:(uint32_t)height {
    // In MoltenVK, we can potentially access the underlying MTLTexture if the VkImage is backed by one.
    // However, if we created the VkImage via Vulkan, we might need to export it.
    
    // For now, return nil as we don't have a real VkImage from EGL yet.
    return nil;
}

- (void)removeSurface:(struct wl_surface_impl *)surface {
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    [_vulkanSurfaces removeObjectForKey:key];
}

@end
