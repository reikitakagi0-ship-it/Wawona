/*
 * Vulkan iOS Wrapper
 * 
 * This file provides standard Vulkan API entry points for iOS static linking.
 * KosmicKrisp generates entrypoints with the 'kk_' prefix and weak linkage,
 * which doesn't work for static libraries. This wrapper maps standard Vulkan
 * function names to the KosmicKrisp implementations.
 * 
 * For iOS App Store compliance, we need a static framework with standard
 * Vulkan symbols exported.
 */

#include <vulkan/vulkan.h>

// For iOS builds, we need to access KosmicKrisp entrypoints
// The functions are implemented in the static library but declared as weak
// We'll use direct function calls - the linker will resolve them from the static library
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// Forward declarations for KosmicKrisp entrypoints
// These are implemented in libvulkan_kosmickrisp.a
extern VkResult kk_CreateInstance(const VkInstanceCreateInfo* pCreateInfo, 
                                   const VkAllocationCallbacks* pAllocator, 
                                   VkInstance* pInstance) __attribute__((weak));
extern void kk_DestroyInstance(VkInstance instance, 
                                const VkAllocationCallbacks* pAllocator) __attribute__((weak));
extern VkResult kk_EnumeratePhysicalDevices(VkInstance instance, 
                                             uint32_t* pPhysicalDeviceCount, 
                                             VkPhysicalDevice* pPhysicalDevices) __attribute__((weak));
extern void kk_GetDeviceQueue(VkDevice device, 
                              uint32_t queueFamilyIndex, 
                              uint32_t queueIndex, 
                              VkQueue* pQueue) __attribute__((weak));
extern VkResult kk_CreateDevice(VkPhysicalDevice physicalDevice, 
                                const VkDeviceCreateInfo* pCreateInfo, 
                                const VkAllocationCallbacks* pAllocator, 
                                VkDevice* pDevice) __attribute__((weak));
extern void kk_DestroyDevice(VkDevice device, 
                             const VkAllocationCallbacks* pAllocator) __attribute__((weak));
#endif

// Standard Vulkan entry points - map to KosmicKrisp implementations
// KosmicKrisp uses kk_CreateInstance (not kk_vkCreateInstance)
VKAPI_ATTR VkResult VKAPI_CALL vkCreateInstance(
    const VkInstanceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkInstance* pInstance) {
    return kk_CreateInstance(pCreateInfo, pAllocator, pInstance);
}

VKAPI_ATTR void VKAPI_CALL vkDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* pAllocator) {
    kk_DestroyInstance(instance, pAllocator);
}

VKAPI_ATTR VkResult VKAPI_CALL vkEnumeratePhysicalDevices(
    VkInstance instance,
    uint32_t* pPhysicalDeviceCount,
    VkPhysicalDevice* pPhysicalDevices) {
    return kk_EnumeratePhysicalDevices(instance, pPhysicalDeviceCount, pPhysicalDevices);
}

VKAPI_ATTR void VKAPI_CALL vkGetDeviceQueue(
    VkDevice device,
    uint32_t queueFamilyIndex,
    uint32_t queueIndex,
    VkQueue* pQueue) {
    kk_GetDeviceQueue(device, queueFamilyIndex, queueIndex, pQueue);
}

VKAPI_ATTR VkResult VKAPI_CALL vkCreateDevice(
    VkPhysicalDevice physicalDevice,
    const VkDeviceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDevice* pDevice) {
    return kk_CreateDevice(physicalDevice, pCreateInfo, pAllocator, pDevice);
}

VKAPI_ATTR void VKAPI_CALL vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* pAllocator) {
    kk_DestroyDevice(device, pAllocator);
}

