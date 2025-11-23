#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

static void die(const char *msg, VkResult err)
{
    fprintf(stderr, "%s (VkResult %d)\n", msg, err);
    exit(EXIT_FAILURE);
}

int main(void)
{
    VkResult err;

    const char *instance_extensions[] = {
        "VK_KHR_portability_enumeration",
    };

    VkApplicationInfo app_info = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "vk_dump_features",
        .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "vk_dump_features",
        .engineVersion = VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = VK_API_VERSION_1_3,
    };

    VkInstanceCreateInfo instance_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = (uint32_t)(sizeof(instance_extensions) / sizeof(instance_extensions[0])),
        .ppEnabledExtensionNames = instance_extensions,
        .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
    };

    VkInstance instance;
    err = vkCreateInstance(&instance_info, NULL, &instance);
    if (err != VK_SUCCESS)
        die("vkCreateInstance failed", err);

    uint32_t phys_count = 0;
    err = vkEnumeratePhysicalDevices(instance, &phys_count, NULL);
    if (err != VK_SUCCESS || phys_count == 0)
        die("Failed to enumerate physical devices", err);

    VkPhysicalDevice *phys_devices = calloc(phys_count, sizeof(VkPhysicalDevice));
    if (!phys_devices) {
        fprintf(stderr, "Out of memory\n");
        vkDestroyInstance(instance, NULL);
        return EXIT_FAILURE;
    }

    err = vkEnumeratePhysicalDevices(instance, &phys_count, phys_devices);
    if (err != VK_SUCCESS)
        die("vkEnumeratePhysicalDevices failed", err);

    for (uint32_t i = 0; i < phys_count; i++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(phys_devices[i], &props);

        printf("Physical Device %u: %s (vendor 0x%04x device 0x%04x)\n",
               i, props.deviceName, props.vendorID, props.deviceID);

        VkPhysicalDeviceRobustness2FeaturesEXT rb2 = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT,
            .pNext = NULL,
        };

        VkPhysicalDeviceFeatures2 features2 = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
            .pNext = &rb2,
        };

        vkGetPhysicalDeviceFeatures2(phys_devices[i], &features2);

        printf("  Robustness2 Features:\n");
        printf("    robustBufferAccess2: %s\n", rb2.robustBufferAccess2 ? "true" : "false");
        printf("    robustImageAccess2 : %s\n", rb2.robustImageAccess2 ? "true" : "false");
        printf("    nullDescriptor     : %s\n", rb2.nullDescriptor ? "true" : "false");
        printf("\n");
    }

    free(phys_devices);
    vkDestroyInstance(instance, NULL);
    return EXIT_SUCCESS;
}

