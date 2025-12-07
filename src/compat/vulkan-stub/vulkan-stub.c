/*
 * Minimal Vulkan Stub for Waypipe
 *
 * This stub provides just enough Vulkan symbols to satisfy waypipe's
 * linking requirements. It does NOT implement any actual Vulkan functionality.
 *
 * All GPU operations are handled by the Metal/IOSurface pipeline instead.
 *
 * Philosophy:
 * - Return VK_ERROR_EXTENSION_NOT_PRESENT for extension queries
 * - Return VK_ERROR_INITIALIZATION_FAILED for device/instance creation
 * - Return NULL/zero for query functions
 *
 * This ensures waypipe can link but will never actually use Vulkan.
 */

#include "vulkan-stub.h"
#include <stddef.h>
#include <string.h>

/*
 * Function pointer lookup table
 * Maps function names to their stub implementations
 */
typedef struct {
  const char *name;
  PFN_vkVoidFunction function;
} VulkanFunctionEntry;

static const VulkanFunctionEntry g_function_table[] = {
    /* Core 1.0 functions */
    {"vkCreateInstance", (PFN_vkVoidFunction)vkCreateInstance},
    {"vkDestroyInstance", (PFN_vkVoidFunction)vkDestroyInstance},
    {"vkEnumeratePhysicalDevices",
     (PFN_vkVoidFunction)vkEnumeratePhysicalDevices},
    {"vkGetPhysicalDeviceProperties",
     (PFN_vkVoidFunction)vkGetPhysicalDeviceProperties},
    {"vkGetPhysicalDeviceMemoryProperties",
     (PFN_vkVoidFunction)vkGetPhysicalDeviceMemoryProperties},
    {"vkCreateDevice", (PFN_vkVoidFunction)vkCreateDevice},
    {"vkDestroyDevice", (PFN_vkVoidFunction)vkDestroyDevice},
    {"vkGetInstanceProcAddr", (PFN_vkVoidFunction)vkGetInstanceProcAddr},
    {"vkEnumerateInstanceExtensionProperties",
     (PFN_vkVoidFunction)vkEnumerateInstanceExtensionProperties},
    {"vkEnumerateDeviceExtensionProperties",
     (PFN_vkVoidFunction)vkEnumerateDeviceExtensionProperties},

    /* Extension functions for waypipe dmabuf support */
    {"vkGetPhysicalDeviceExternalBufferProperties",
     (PFN_vkVoidFunction)vkGetPhysicalDeviceExternalBufferProperties},
    {"vkGetMemoryFdKHR", (PFN_vkVoidFunction)vkGetMemoryFdKHR},
    {"vkGetMemoryFdPropertiesKHR",
     (PFN_vkVoidFunction)vkGetMemoryFdPropertiesKHR},

    /* Sentinel */
    {NULL, NULL}};

/*
 * ICD entry point - this is what gets called when linking statically
 */
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
vk_icdGetInstanceProcAddr(VkInstance instance, const char *pName) {
  (void)instance; /* Unused - we don't actually create instances */

  if (pName == NULL) {
    return NULL;
  }

  /* Look up function in table */
  for (const VulkanFunctionEntry *entry = g_function_table; entry->name != NULL;
       entry++) {
    if (strcmp(pName, entry->name) == 0) {
      return entry->function;
    }
  }

  /* Function not found - return NULL */
  return NULL;
}

/*
 * Standard Vulkan entry point
 * Just redirects to ICD entry point
 */
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
vkGetInstanceProcAddr(VkInstance instance, const char *pName) {
  return vk_icdGetInstanceProcAddr(instance, pName);
}

/*
 * Instance creation - always fails
 * Waypipe should never actually call this since we're using Metal/IOSurface
 */
VKAPI_ATTR VkResult VKAPI_CALL vkCreateInstance(
    const VkInstanceCreateInfo *pCreateInfo,
    const VkAllocationCallbacks *pAllocator, VkInstance *pInstance) {
  (void)pCreateInfo;
  (void)pAllocator;

  if (pInstance != NULL) {
    *pInstance = VK_NULL_HANDLE;
  }

  return VK_ERROR_INITIALIZATION_FAILED;
}

/*
 * Instance destruction - no-op
 */
VKAPI_ATTR void VKAPI_CALL vkDestroyInstance(
    VkInstance instance, const VkAllocationCallbacks *pAllocator) {
  (void)instance;
  (void)pAllocator;
  /* No-op - we never create real instances */
}

/*
 * Physical device enumeration - returns zero devices
 */
VKAPI_ATTR VkResult VKAPI_CALL
vkEnumeratePhysicalDevices(VkInstance instance, uint32_t *pPhysicalDeviceCount,
                           VkPhysicalDevice *pPhysicalDevices) {
  (void)instance;

  if (pPhysicalDeviceCount == NULL) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }

  if (pPhysicalDevices == NULL) {
    /* Query mode - return zero devices */
    *pPhysicalDeviceCount = 0;
    return VK_SUCCESS;
  }

  /* Enumeration mode - no devices available */
  *pPhysicalDeviceCount = 0;
  return VK_SUCCESS;
}

/*
 * Physical device properties - returns empty properties
 */
VKAPI_ATTR void VKAPI_CALL vkGetPhysicalDeviceProperties(
    VkPhysicalDevice physicalDevice, VkPhysicalDeviceProperties *pProperties) {
  (void)physicalDevice;

  if (pProperties != NULL) {
    memset(pProperties, 0, sizeof(VkPhysicalDeviceProperties));
    pProperties->apiVersion = VK_API_VERSION_1_0;
    strcpy(pProperties->deviceName, "Vulkan Stub (Metal/IOSurface)");
    pProperties->deviceType = VK_PHYSICAL_DEVICE_TYPE_OTHER;
  }
}

/*
 * Physical device memory properties - returns empty properties
 */
VKAPI_ATTR void VKAPI_CALL vkGetPhysicalDeviceMemoryProperties(
    VkPhysicalDevice physicalDevice,
    VkPhysicalDeviceMemoryProperties *pMemoryProperties) {
  (void)physicalDevice;

  if (pMemoryProperties != NULL) {
    memset(pMemoryProperties, 0, sizeof(VkPhysicalDeviceMemoryProperties));
  }
}

/*
 * Device creation - always fails
 */
VKAPI_ATTR VkResult VKAPI_CALL vkCreateDevice(
    VkPhysicalDevice physicalDevice, const VkDeviceCreateInfo *pCreateInfo,
    const VkAllocationCallbacks *pAllocator, VkDevice *pDevice) {
  (void)physicalDevice;
  (void)pCreateInfo;
  (void)pAllocator;

  if (pDevice != NULL) {
    *pDevice = VK_NULL_HANDLE;
  }

  return VK_ERROR_INITIALIZATION_FAILED;
}

/*
 * Device destruction - no-op
 */
VKAPI_ATTR void VKAPI_CALL
vkDestroyDevice(VkDevice device, const VkAllocationCallbacks *pAllocator) {
  (void)device;
  (void)pAllocator;
  /* No-op - we never create real devices */
}

/*
 * External buffer properties - indicates no external memory support
 * This tells waypipe that Vulkan external memory extensions are NOT available
 */
VKAPI_ATTR void VKAPI_CALL vkGetPhysicalDeviceExternalBufferProperties(
    VkPhysicalDevice physicalDevice,
    const VkPhysicalDeviceExternalBufferInfo *pExternalBufferInfo,
    VkExternalBufferProperties *pExternalBufferProperties) {
  (void)physicalDevice;
  (void)pExternalBufferInfo;

  if (pExternalBufferProperties != NULL) {
    memset(pExternalBufferProperties, 0, sizeof(VkExternalBufferProperties));
    /* Set all flags to 0 to indicate no external memory support */
    pExternalBufferProperties->externalMemoryProperties.externalMemoryFeatures =
        0;
    pExternalBufferProperties->externalMemoryProperties
        .exportFromImportedHandleTypes = 0;
    pExternalBufferProperties->externalMemoryProperties.compatibleHandleTypes =
        0;
  }
}

/*
 * Get memory FD - not supported
 * Returns error to indicate dmabuf export is not available via Vulkan
 */
VKAPI_ATTR VkResult VKAPI_CALL vkGetMemoryFdKHR(
    VkDevice device, const VkMemoryGetFdInfoKHR *pGetFdInfo, int *pFd) {
  (void)device;
  (void)pGetFdInfo;

  if (pFd != NULL) {
    *pFd = -1;
  }

  return VK_ERROR_EXTENSION_NOT_PRESENT;
}

/*
 * Get memory FD properties - not supported
 * Returns error to indicate dmabuf import is not available via Vulkan
 */
VKAPI_ATTR VkResult VKAPI_CALL vkGetMemoryFdPropertiesKHR(
    VkDevice device, VkExternalMemoryHandleTypeFlagBits handleType, int fd,
    VkMemoryFdPropertiesKHR *pMemoryFdProperties) {
  (void)device;
  (void)handleType;
  (void)fd;

  if (pMemoryFdProperties != NULL) {
    memset(pMemoryFdProperties, 0, sizeof(VkMemoryFdPropertiesKHR));
  }

  return VK_ERROR_EXTENSION_NOT_PRESENT;
}

/*
 * Enumerate instance extensions - returns zero extensions
 * This tells waypipe that no Vulkan extensions are available
 */
VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateInstanceExtensionProperties(
    const char *pLayerName, uint32_t *pPropertyCount,
    VkExtensionProperties *pProperties) {
  (void)pLayerName; /* Layers not supported */

  if (pPropertyCount == NULL) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }

  if (pProperties == NULL) {
    /* Query mode - return zero extensions */
    *pPropertyCount = 0;
    return VK_SUCCESS;
  }

  /* Enumeration mode - no extensions available */
  *pPropertyCount = 0;
  return VK_SUCCESS;
}

/*
 * Enumerate device extensions - returns zero extensions
 * This tells waypipe that no device extensions are available
 */
VKAPI_ATTR VkResult VKAPI_CALL vkEnumerateDeviceExtensionProperties(
    VkPhysicalDevice physicalDevice, const char *pLayerName,
    uint32_t *pPropertyCount, VkExtensionProperties *pProperties) {
  (void)physicalDevice;
  (void)pLayerName; /* Layers not supported */

  if (pPropertyCount == NULL) {
    return VK_ERROR_INITIALIZATION_FAILED;
  }

  if (pProperties == NULL) {
    /* Query mode - return zero extensions */
    *pPropertyCount = 0;
    return VK_SUCCESS;
  }

  /* Enumeration mode - no extensions available */
  *pPropertyCount = 0;
  return VK_SUCCESS;
}
