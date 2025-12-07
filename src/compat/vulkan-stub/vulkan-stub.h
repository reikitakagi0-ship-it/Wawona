/*
 * Minimal Vulkan Stub for Waypipe
 * 
 * This stub exists solely to satisfy waypipe's linking requirements.
 * It does NOT implement any actual Vulkan functionality.
 * 
 * All GPU operations go through the Metal/IOSurface pipeline instead.
 */

#ifndef VULKAN_STUB_H
#define VULKAN_STUB_H

#include <vulkan/vulkan.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * ICD entry point - required for static linking
 * This is what waypipe will actually call
 */
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL 
vk_icdGetInstanceProcAddr(VkInstance instance, const char* pName);

/*
 * Standard Vulkan loader entry point
 * Redirects to vk_icdGetInstanceProcAddr
 */
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL 
vkGetInstanceProcAddr(VkInstance instance, const char* pName);

/*
 * Minimal instance/device stubs
 * All return VK_ERROR_EXTENSION_NOT_PRESENT to indicate no real support
 */
VKAPI_ATTR VkResult VKAPI_CALL
vkCreateInstance(const VkInstanceCreateInfo* pCreateInfo,
                 const VkAllocationCallbacks* pAllocator,
                 VkInstance* pInstance);

VKAPI_ATTR void VKAPI_CALL
vkDestroyInstance(VkInstance instance,
                  const VkAllocationCallbacks* pAllocator);

VKAPI_ATTR VkResult VKAPI_CALL
vkEnumeratePhysicalDevices(VkInstance instance,
                           uint32_t* pPhysicalDeviceCount,
                           VkPhysicalDevice* pPhysicalDevices);

VKAPI_ATTR void VKAPI_CALL
vkGetPhysicalDeviceProperties(VkPhysicalDevice physicalDevice,
                               VkPhysicalDeviceProperties* pProperties);

VKAPI_ATTR void VKAPI_CALL
vkGetPhysicalDeviceMemoryProperties(VkPhysicalDevice physicalDevice,
                                     VkPhysicalDeviceMemoryProperties* pMemoryProperties);

VKAPI_ATTR VkResult VKAPI_CALL
vkCreateDevice(VkPhysicalDevice physicalDevice,
               const VkDeviceCreateInfo* pCreateInfo,
               const VkAllocationCallbacks* pAllocator,
               VkDevice* pDevice);

VKAPI_ATTR void VKAPI_CALL
vkDestroyDevice(VkDevice device,
                 const VkAllocationCallbacks* pAllocator);

VKAPI_ATTR VkResult VKAPI_CALL
vkEnumerateInstanceExtensionProperties(const char* pLayerName,
                                       uint32_t* pPropertyCount,
                                       VkExtensionProperties* pProperties);

VKAPI_ATTR VkResult VKAPI_CALL
vkEnumerateDeviceExtensionProperties(VkPhysicalDevice physicalDevice,
                                      const char* pLayerName,
                                      uint32_t* pPropertyCount,
                                      VkExtensionProperties* pProperties);

/*
 * Extension stubs for waypipe's dmabuf requirements
 * These return errors to indicate the extensions are not supported
 */
VKAPI_ATTR void VKAPI_CALL
vkGetPhysicalDeviceExternalBufferProperties(VkPhysicalDevice physicalDevice,
                                             const VkPhysicalDeviceExternalBufferInfo* pExternalBufferInfo,
                                             VkExternalBufferProperties* pExternalBufferProperties);

VKAPI_ATTR VkResult VKAPI_CALL
vkGetMemoryFdKHR(VkDevice device,
                 const VkMemoryGetFdInfoKHR* pGetFdInfo,
                 int* pFd);

VKAPI_ATTR VkResult VKAPI_CALL
vkGetMemoryFdPropertiesKHR(VkDevice device,
                           VkExternalMemoryHandleTypeFlagBits handleType,
                           int fd,
                           VkMemoryFdPropertiesKHR* pMemoryFdProperties);

#ifdef __cplusplus
}
#endif

#endif /* VULKAN_STUB_H */
