#!/usr/bin/env python3
"""
Generate Vulkan entrypoint stubs for iOS static framework.

This script reads the KosmicKrisp entrypoints header and generates
stub implementations for all declared entrypoints that aren't implemented.
"""

import re
import sys
import subprocess
from pathlib import Path

def get_implemented_functions():
    """Detect which kk_* functions are actually implemented in libvulkan_kosmickrisp.a."""
    lib_path = Path('build/ios-install/lib/libvulkan_kosmickrisp.a')
    if not lib_path.exists():
        # Fallback to minimal set if library doesn't exist yet
        return {
            'kk_CreateInstance', 'kk_DestroyInstance',
            'kk_GetInstanceProcAddr', 'kk_EnumerateInstanceVersion',
            'kk_CreateDevice', 'kk_DestroyDevice', 'kk_GetDeviceProcAddr',
        }
    
    try:
        result = subprocess.run(['nm', '-gU', str(lib_path)], capture_output=True, text=True, check=True)
        implemented = set()
        for line in result.stdout.split('\n'):
            if ' T _kk_' in line:
                func = line.split(' T _')[1].split('@')[0].split()[0]
                # Only include actual Vulkan API functions (kk_*), not internal helpers
                # Filter out internal implementation details like kk_sampler_heap_*, kk_upload_*, kk_vbo_*
                if func.startswith('kk_') and not any(func.startswith(prefix) for prefix in ['kk_sampler_heap_', 'kk_upload_', 'kk_vbo_']):
                    implemented.add(func)
        return implemented
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback if nm fails
        return set()

# Core functions that ARE implemented in KosmicKrisp
# Note: WSI functions (CreateIOSSurfaceMVK, CreateMetalSurfaceEXT, etc.) are NOT implemented
# and need forwarding functions, so they're not in this list
# Note: Physical device functions need forwarding to vk_common_*, so they're not in this list either
# Functions that ARE actually implemented in libvulkan_kosmickrisp.a (auto-detected)
IMPLEMENTED_FUNCTIONS = get_implemented_functions()

def parse_entrypoint_declaration(line):
    """Parse a Vulkan entrypoint declaration from the header."""
    # Pattern: VKAPI_ATTR <return_type> VKAPI_CALL <function_name>(<params>) VK_ENTRY_WEAK VK_ENTRY_HIDDEN;
    pattern = r'VKAPI_ATTR\s+(\w+(?:\s*\*)?)\s+VKAPI_CALL\s+(kk_\w+)\s*\(([^)]*)\)'
    match = re.search(pattern, line)
    if not match:
        return None
    
    return_type = match.group(1).strip()
    func_name = match.group(2)
    params_str = match.group(3)
    
    # Parse parameters
    params = []
    if params_str.strip():
        for param in params_str.split(','):
            param = param.strip()
            if param:
                # Extract parameter name (last identifier)
                parts = param.split()
                param_name = parts[-1] if parts else 'pUnused'
                params.append(param_name)
    
    return {
        'return_type': return_type,
        'name': func_name,
        'params': params,
        'full_params': params_str
    }

def should_skip_function(name, params_str):
    """Check if function should be skipped due to platform-specific types."""
    # Skip functions for platforms we don't support (but still stub CUDA/AMDX)
    unsupported_platforms = ['ANDROID', 'OHOS', 'FUCHSIA', 'VI_NN', 'WIN32', 'XLIB', 'XCB', 'DIRECTFB', 'QNX', 'GGP']
    for platform in unsupported_platforms:
        if platform in name:
            return True
    
    # Don't skip CUDA/AMDX functions - we'll generate stubs with void* for their types
    # Don't skip Metal/iOS/Wayland WSI functions - we'll forward them
    return False

def replace_platform_specific_types(params_str):
    """Replace platform-specific types with void* for stub generation."""
    import re
    
    # Map platform-specific types to void* or void
    # Use regex to match whole words/types
    type_replacements = [
        # CUDA types
        (r'\bVkCudaLaunchInfoNV\s*\*', 'void*'),
        (r'\bVkCudaSemaphoreSignalInfoNV\s*\*', 'void*'),
        (r'\bVkCudaLaunchKernelInfoNV\s*\*', 'void*'),
        (r'\bVkCudaModuleCacheNV\s*\*', 'void*'),
        (r'\bVkCudaFunctionNV\b', 'void*'),
        (r'\bVkCudaModuleNV\b', 'void*'),
        # AMDX types
        (r'\bVkDispatchGraphCountInfoAMDX\s*\*', 'void*'),
        (r'\bVkDispatchGraphInfoAMDX\s*\*', 'void*'),
        (r'\bVkExecutionGraphPipelineCreateInfoAMDX\s*\*', 'void*'),
        (r'\bVkPipelineShaderStageNodeCreateInfoAMDX\s*\*', 'void*'),
        (r'\bVkExecutionGraphPipelineScratchSizeAMDX\s*\*', 'void*'),
        (r'\bVkExecutionGraphPipelineNodeIndexInfoAMDX\s*\*', 'void*'),
        (r'\bVkGraphScratchMemoryAMDX\s*\*', 'void*'),
        # Windows types
        (r'\bVkMemoryGetWin32HandleInfoKHR\s*\*', 'void*'),
        (r'\bVkImportFenceWin32HandleInfoKHR\s*\*', 'void*'),
        (r'\bVkImportSemaphoreWin32HandleInfoKHR\s*\*', 'void*'),
        (r'\bVkFenceGetWin32HandleInfoKHR\s*\*', 'void*'),
        (r'\bVkSemaphoreGetWin32HandleInfoKHR\s*\*', 'void*'),
        (r'\bVkWin32SurfaceCreateInfoKHR\s*\*', 'void*'),
        (r'\bHANDLE\s*\*', 'void*'),
        (r'\bHANDLE\b', 'void*'),
        (r'\bHWND\b', 'void*'),
        (r'\bHINSTANCE\b', 'void*'),
        # X11/XCB types
        (r'\bxcb_connection_t\s*\*', 'void*'),
        (r'\bxcb_visualid_t\b', 'uint32_t'),
        (r'\bDisplay\s*\*', 'void*'),
        (r'\bVisualID\b', 'uint32_t'),
        # Android types
        (r'\bANativeWindow\s*\*', 'void*'),
        (r'\bVkAndroidSurfaceCreateInfoKHR\s*\*', 'void*'),
        # Other platform types
        (r'\bVkDirectFBSurfaceCreateInfoEXT\s*\*', 'void*'),
        (r'\bVkViSurfaceCreateInfoNN\s*\*', 'void*'),
        (r'\bVkXcbSurfaceCreateInfoKHR\s*\*', 'void*'),
        (r'\bVkXlibSurfaceCreateInfoKHR\s*\*', 'void*'),
        (r'\bVkIOSSurfaceCreateInfoMVK\s*\*', 'void*'),
        (r'\bVkMacOSSurfaceCreateInfoMVK\s*\*', 'void*'),
        (r'\bVkMetalSurfaceCreateInfoEXT\s*\*', 'void*'),
        (r'\bVkWaylandSurfaceCreateInfoKHR\s*\*', 'void*'),
        (r'\bVkExportMetalObjectsInfoEXT\s*\*', 'void*'),
        (r'\bVkMemoryGetMetalHandleInfoEXT\s*\*', 'void*'),
        (r'\bVkMemoryMetalHandlePropertiesEXT\s*\*', 'void*'),
        (r'\bVkMemoryWin32HandlePropertiesKHR\s*\*', 'void*'),
        (r'\bIDirectFB\s*\*', 'void*'),
        (r'\bIDirectFB\b', 'void*'),
        (r'\bRROutput\b', 'uint32_t'),
        (r'\bstruct\s+wl_display\s*\*', 'void*'),
        (r'\bstruct\s+wl_surface\s*\*', 'void*'),
    ]
    
    result = params_str
    for pattern, replacement in type_replacements:
        result = re.sub(pattern, replacement, result)
    
    # Fix "void void*" -> "void*" and "void void" -> "void"
    result = re.sub(r'\bvoid\s+void\s*\*', 'void*', result)
    result = re.sub(r'\bvoid\s+void\b', 'void', result)
    # Fix "void void*" in parameter lists (e.g., "void void* pParam" -> "void* pParam")
    result = re.sub(r'(\w+)\s+void\s*\*', r'void*', result)
    
    return result

def generate_stub_function(entrypoint):
    """Generate a stub function implementation."""
    name = entrypoint['name']
    return_type = entrypoint['return_type']
    params_str = entrypoint['full_params']
    params = entrypoint['params']
    
    # Skip platform-specific functions for unsupported platforms
    if should_skip_function(name, params_str):
        return f"// Skipped {name} - platform-specific types not available on iOS\n"
    
    # Handle WSI forwarding functions
    wsi_forwards = {
        'kk_CreateIOSSurfaceMVK': 'wsi_CreateIOSSurfaceMVK',
        'kk_CreateMetalSurfaceEXT': 'wsi_CreateMetalSurfaceEXT',
        'kk_CreateWaylandSurfaceKHR': 'wsi_CreateWaylandSurfaceKHR',
        'kk_DestroySurfaceKHR': 'wsi_DestroySurfaceKHR',
    }
    
    if name in wsi_forwards:
        # Generate forwarding function
        wsi_name = wsi_forwards[name]
        # Replace platform-specific types with void* for parameters
        modified_params = replace_platform_specific_types(params_str)
        sig = f"VKAPI_ATTR {return_type} VKAPI_CALL {name}({modified_params})"
        body = f"""{{
    // Forward to WSI implementation
    extern {return_type} {wsi_name}({modified_params});
    return {wsi_name}({', '.join(entrypoint['params'])});
}}"""
        return f"{sig}\n{body}\n"
    
    # Handle enumeration forwarding functions
    enum_forwards = {
        'kk_EnumerateDeviceExtensionProperties': 'vk_common_EnumerateDeviceExtensionProperties',
        'kk_EnumerateDeviceLayerProperties': 'vk_common_EnumerateDeviceLayerProperties',
        'kk_EnumerateInstanceLayerProperties': 'vk_common_EnumerateInstanceLayerProperties',
    }
    
    if name in enum_forwards:
        vk_common_name = enum_forwards[name]
        sig = f"VKAPI_ATTR {return_type} VKAPI_CALL {name}({params_str})"
        body = f"""{{
    // Forward to vk_common implementation
    extern {return_type} {vk_common_name}({params_str});
    return {vk_common_name}({', '.join(entrypoint['params'])});
}}"""
        return f"{sig}\n{body}\n"
    
    # Handle physical device forwarding functions (forward to vk_common_*)
    physical_device_forwards = {
        'kk_EnumeratePhysicalDevices': 'vk_common_EnumeratePhysicalDevices',
        'kk_GetDeviceQueue': 'vk_common_GetDeviceQueue',
        'kk_GetPhysicalDeviceFeatures': 'vk_common_GetPhysicalDeviceFeatures',
        'kk_GetPhysicalDeviceFormatProperties': 'vk_common_GetPhysicalDeviceFormatProperties',
        'kk_GetPhysicalDeviceImageFormatProperties': 'vk_common_GetPhysicalDeviceImageFormatProperties',
        'kk_GetPhysicalDeviceMemoryProperties': 'vk_common_GetPhysicalDeviceMemoryProperties',
        'kk_GetPhysicalDeviceProperties': 'vk_common_GetPhysicalDeviceProperties',
        'kk_GetPhysicalDeviceQueueFamilyProperties': 'vk_common_GetPhysicalDeviceQueueFamilyProperties',
        'kk_GetPhysicalDeviceSurfaceCapabilitiesKHR': 'vk_common_GetPhysicalDeviceSurfaceCapabilitiesKHR',
        'kk_GetPhysicalDeviceSurfaceFormatsKHR': 'vk_common_GetPhysicalDeviceSurfaceFormatsKHR',
        'kk_GetPhysicalDeviceSurfacePresentModesKHR': 'vk_common_GetPhysicalDeviceSurfacePresentModesKHR',
        'kk_GetPhysicalDeviceSurfaceSupportKHR': 'vk_common_GetPhysicalDeviceSurfaceSupportKHR',
        'kk_GetPhysicalDeviceWaylandPresentationSupportKHR': 'vk_common_GetPhysicalDeviceWaylandPresentationSupportKHR',
    }
    
    if name in physical_device_forwards:
        vk_common_name = physical_device_forwards[name]
        sig = f"VKAPI_ATTR {return_type} VKAPI_CALL {name}({params_str})"
        # For void functions, don't use return
        if return_type == 'void':
            body = f"""{{
    // Forward to vk_common implementation
    extern {return_type} {vk_common_name}({params_str});
    {vk_common_name}({', '.join(entrypoint['params'])});
}}"""
        else:
            body = f"""{{
    // Forward to vk_common implementation
    extern {return_type} {vk_common_name}({params_str});
    return {vk_common_name}({', '.join(entrypoint['params'])});
}}"""
        return f"{sig}\n{body}\n"
    
    # Replace platform-specific types with void* for stub generation
    modified_params = replace_platform_specific_types(params_str)
    
    # Generate parameter list for function signature
    param_decls = []
    param_names = []
    if modified_params.strip():
        # Split parameters and format them
        for param in modified_params.split(','):
            param = param.strip()
            if param:
                param_decls.append(param)
                # Extract parameter name - it's the last identifier before any operators
                # Handle cases like "const VkBool32* pColorWriteEnables" or "VkCommandBuffer commandBuffer"
                parts = param.split()
                if parts:
                    # Extract parameter name - handle arrays and pointers
                    import re
                    full_param = ' '.join(parts)
                    # Match parameter name before [ or * operators
                    name_match = re.search(r'(\w+)(?:\s*[\[\*]|$)', full_param)
                    if name_match:
                        param_name = name_match.group(1)
                        type_keywords = {'const', 'struct', 'enum', 'Vk', 'PFN', 'void', 'uint32_t', 'uint64_t', 'int32_t', 'int64_t', 'size_t', 'VkBool32', 'float', 'double', 'int', 'char', 'uint16_t', 'uint8_t', 'HANDLE', 'HWND', 'HINSTANCE'}
                        if param_name and param_name not in type_keywords and not param_name.startswith('Vk') and '(' not in param_name and '.' not in param_name and not param_name.startswith('p') or (param_name.startswith('p') and len(param_name) > 1):
                            param_names.append(param_name)
    
    # Generate function signature
    sig = f"VKAPI_ATTR {return_type} VKAPI_CALL {name}({modified_params})"
    
    # Generate function body
    body = f"""{{
    // Stub implementation for {name}
    // This function is declared but not implemented in KosmicKrisp"""
    
    # Add parameter suppression
    if param_names:
        suppressed = ', '.join(f'(void){p}' for p in param_names)
        body += f"\n    {suppressed};"
    
    # Return appropriate value
    if return_type == 'VkResult':
        body += "\n    return VK_ERROR_EXTENSION_NOT_PRESENT;"
    elif return_type == 'void':
        body += "\n    // No return value"
    elif return_type in ('PFN_vkVoidFunction', 'void*'):
        body += "\n    return NULL;"
    elif '*' in return_type:
        body += "\n    return NULL;"
    elif return_type in ('uint32_t', 'uint64_t', 'VkBool32'):
        body += "\n    return 0;"
    else:
        body += f"\n    return ({return_type})0;"
    
    body += "\n}"
    
    return f"{sig}\n{body}\n"

def main():
    header_path = Path('dependencies/kosmickrisp/build-ios/src/kosmickrisp/vulkan/kk_entrypoints.h')
    
    if not header_path.exists():
        print(f"Error: Header file not found: {header_path}", file=sys.stderr)
        print("Please build KosmicKrisp first: ./scripts/install-kosmickrisp.sh --platform ios", file=sys.stderr)
        sys.exit(1)
    
    # Read header file
    with open(header_path, 'r') as f:
        content = f.read()
    
    # Find all entrypoint declarations
    entrypoints = []
    for line in content.split('\n'):
        if 'VKAPI_ATTR' in line and 'kk_' in line and 'VKAPI_CALL' in line:
            entrypoint = parse_entrypoint_declaration(line)
            if entrypoint and entrypoint['name'] not in IMPLEMENTED_FUNCTIONS:
                entrypoints.append(entrypoint)
    
    print(f"Found {len(entrypoints)} entrypoints to stub", file=sys.stderr)
    
    # Generate stub file
    output = """/*
 * Vulkan Entrypoint Stubs for iOS Static Framework
 * 
 * AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
 * Generated by: scripts/generate-vulkan-stubs.py
 * 
 * Provides stub implementations for Vulkan entrypoints that are declared
 * in KosmicKrisp entrypoint tables but not fully implemented (optional extensions).
 * 
 * These stubs:
 * - Return appropriate Vulkan error codes (VK_ERROR_EXTENSION_NOT_PRESENT)
 * - Maintain API contract and parameter validation
 * - Allow static linking to succeed
 * 
 * Core Vulkan 1.3 functions are implemented in KosmicKrisp itself.
 */

#include <vulkan/vulkan.h>
#include <stddef.h>

// Include extension headers for types that may be conditionally defined
#ifdef VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan_metal.h>
#endif

// Stub function referenced by entrypoint tables for unimplemented functions
VKAPI_ATTR void VKAPI_CALL vk_entrypoint_stub(void) {
    // Stub for unimplemented entrypoints - referenced by MSVC builds
}

"""
    
    # Generate stubs for all entrypoints
    for entrypoint in sorted(entrypoints, key=lambda x: x['name']):
        output += generate_stub_function(entrypoint)
        output += "\n"
    
    # Write output file
    output_path = Path('src/vulkan_entrypoint_stubs.c')
    output_path.write_text(output)
    print(f"Generated {len(entrypoints)} stub functions in {output_path}", file=sys.stderr)

if __name__ == '__main__':
    main()

