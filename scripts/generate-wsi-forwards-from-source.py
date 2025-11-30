#!/usr/bin/env python3
"""
Generate WSI forwarding functions by parsing KosmicKrisp source code.

This script:
1. Extracts all wsi_* function names from the entrypoints table
2. Checks which ones have vk_common_* equivalents in the library
3. Generates forwarding functions for those that do
4. Generates stubs for optional extensions that don't
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).parent.parent
ENTRYPOINTS_FILE = ROOT_DIR / "dependencies/kosmickrisp/build-ios/src/vulkan/wsi/wsi_common_entrypoints.c"
LIB_PATH = ROOT_DIR / "build/ios-install/lib/libvulkan_kosmickrisp.a"
VULKAN_HEADER = ROOT_DIR / "build/ios-install/include/vulkan/vulkan_core.h"
OUTPUT_FILE = ROOT_DIR / "src/wsi_entrypoint_forwards.c"

def extract_wsi_functions_from_entrypoints():
    """Extract all wsi_* function names from the entrypoints table."""
    if not ENTRYPOINTS_FILE.exists():
        print(f"Error: Entrypoints file not found at {ENTRYPOINTS_FILE}", file=sys.stderr)
        return set()
    
    content = ENTRYPOINTS_FILE.read_text()
    functions = set()
    
    # Extract from instance entrypoints
    instance_match = re.search(r'const struct vk_instance_entrypoint_table wsi_instance_entrypoints = \{([^}]+)\};', content, re.DOTALL)
    if instance_match:
        for match in re.finditer(r'\.(\w+)\s*=\s*wsi_(\w+)', instance_match.group(1)):
            functions.add(f"wsi_{match.group(2)}")
    
    # Extract from physical device entrypoints
    pdev_match = re.search(r'const struct vk_physical_device_entrypoint_table wsi_physical_device_entrypoints = \{([^}]+)\};', content, re.DOTALL)
    if pdev_match:
        for match in re.finditer(r'\.(\w+)\s*=\s*wsi_(\w+)', pdev_match.group(1)):
            functions.add(f"wsi_{match.group(2)}")
    
    # Extract from device entrypoints
    device_match = re.search(r'const struct vk_device_entrypoint_table wsi_device_entrypoints = \{([^}]+)\};', content, re.DOTALL)
    if device_match:
        for match in re.finditer(r'\.(\w+)\s*=\s*wsi_(\w+)', device_match.group(1)):
            functions.add(f"wsi_{match.group(2)}")
    
    return functions

def get_available_vk_common_functions():
    """Get all available vk_common_* functions from the library."""
    if not LIB_PATH.exists():
        print(f"Warning: Library not found at {LIB_PATH}", file=sys.stderr)
        return set()
    
    result = subprocess.run(['nm', '-gU', str(LIB_PATH)], capture_output=True, text=True)
    functions = set()
    for line in result.stdout.split('\n'):
        if ' T ' in line and 'vk_common_' in line:
            match = re.search(r'vk_common_([^ @]+)', line)
            if match:
                functions.add(match.group(1))
    return functions

def get_implemented_wsi_functions():
    """Get all wsi_* functions that are already implemented in the library."""
    if not LIB_PATH.exists():
        print(f"Warning: Library not found at {LIB_PATH}", file=sys.stderr)
        return set()
    
    result = subprocess.run(['nm', '-gU', str(LIB_PATH)], capture_output=True, text=True)
    functions = set()
    for line in result.stdout.split('\n'):
        if ' T ' in line and 'wsi_' in line:
            match = re.search(r'wsi_([^ @]+)', line)
            if match:
                functions.add(f"wsi_{match.group(1)}")
    return functions

def parse_vulkan_function_signature(func_name):
    """Parse Vulkan function signature from header."""
    if not VULKAN_HEADER.exists():
        return None
    
    content = VULKAN_HEADER.read_text()
    # Remove wsi_ prefix to get base name
    base_name = func_name.replace('wsi_', '')
    
    # Try to find vk{BaseName} pattern
    pattern = rf'VKAPI_ATTR\s+(\w+(?:\s*\*)?)\s+VKAPI_CALL\s+vk{base_name}\s*\(([^)]*)\)'
    match = re.search(pattern, content, re.MULTILINE | re.DOTALL)
    
    if match:
        return_type = match.group(1).strip()
        params_str = match.group(2).strip()
        
        # Parse parameters
        params = []
        if params_str:
            # Simple parameter parsing - split by comma, handle nested structures
            param_lines = []
            current_param = []
            paren_depth = 0
            
            for char in params_str:
                if char == '(':
                    paren_depth += 1
                    current_param.append(char)
                elif char == ')':
                    paren_depth -= 1
                    current_param.append(char)
                elif char == ',' and paren_depth == 0:
                    param_lines.append(''.join(current_param).strip())
                    current_param = []
                else:
                    current_param.append(char)
            
            if current_param:
                param_lines.append(''.join(current_param).strip())
            
            for param in param_lines:
                param = param.strip()
                if param:
                    # Extract parameter name (last identifier)
                    parts = param.split()
                    if parts:
                        name = parts[-1]
                        type_part = ' '.join(parts[:-1])
                        params.append((type_part.strip(), name))
        
        return {
            'return_type': return_type,
            'params': params,
            'param_list': ', '.join([f"{ptype} {pname}" for ptype, pname in params]),
            'param_names': ', '.join([pname for _, pname in params])
        }
    
    return None

def generate_forwarding_function(func_name, signature, vk_common_name):
    """Generate a forwarding function."""
    return_type = signature['return_type']
    param_list = signature['param_list']
    param_names = signature['param_names']
    
    # Fix array parameter passing - don't pass array[index], just pass array
    # Handle cases like blendConstants[4] -> blendConstants
    param_names_fixed = []
    for pname in param_names.split(', '):
        pname = pname.strip()
        # If parameter name ends with [number], remove the [number] part
        if '[' in pname and ']' in pname:
            # Extract just the base name before [
            base_name = pname.split('[')[0]
            param_names_fixed.append(base_name)
        else:
            param_names_fixed.append(pname)
    param_names = ', '.join(param_names_fixed)
    
    if return_type == 'void':
        return f"""VKAPI_ATTR void VKAPI_CALL {func_name}({param_list}) {{
    vk_common_{vk_common_name}({param_names});
}}"""
    else:
        return f"""VKAPI_ATTR {return_type} VKAPI_CALL {func_name}({param_list}) {{
    return vk_common_{vk_common_name}({param_names});
}}"""

def generate_stub_function(func_name, signature):
    """Generate a stub function."""
    if not signature:
        # Minimal stub without signature - use variadic with at least one named parameter
        return f"""VKAPI_ATTR VkResult VKAPI_CALL {func_name}(void* dummy, ...) {{
    (void)dummy;
    return VK_ERROR_EXTENSION_NOT_PRESENT;
}}"""
    
    return_type = signature['return_type']
    param_list = signature['param_list']
    param_names = signature['param_names']
    
    void_params = ', '.join([f"(void){pname}" for _, pname in signature['params']])
    
    # Special handling for GetInstanceProcAddr - returns function pointer, not VkResult
    if func_name == 'wsi_GetInstanceProcAddr':
        return f"""VKAPI_ATTR {return_type} VKAPI_CALL {func_name}({param_list}) {{
    {void_params};
    return NULL;
}}"""
    
    if return_type == 'void':
        return f"""VKAPI_ATTR void VKAPI_CALL {func_name}({param_list}) {{
    {void_params};
    // Stub for optional extension
}}"""
    else:
        return f"""VKAPI_ATTR {return_type} VKAPI_CALL {func_name}({param_list}) {{
    {void_params};
    return VK_ERROR_EXTENSION_NOT_PRESENT;
}}"""

def main():
    print("Extracting wsi_* functions from entrypoints table...")
    wsi_functions = extract_wsi_functions_from_entrypoints()
    print(f"Found {len(wsi_functions)} wsi_* functions")
    
    print("Getting available vk_common_* functions...")
    available_vk_common = get_available_vk_common_functions()
    print(f"Found {len(available_vk_common)} vk_common_* functions")
    
    print("Getting implemented wsi_* functions...")
    implemented_wsi = get_implemented_wsi_functions()
    print(f"Found {len(implemented_wsi)} implemented wsi_* functions")
    
    # Filter out wsi_* functions that are already implemented
    wsi_functions = wsi_functions - implemented_wsi
    print(f"After filtering, {len(wsi_functions)} wsi_* functions need forwarding/stubs")
    
    # Generate output
    output_lines = []
    output_lines.append("/*")
    output_lines.append(" * WSI Entrypoint Forwarding Functions for iOS Static Framework")
    output_lines.append(" * ")
    output_lines.append(" * AUTO-GENERATED FILE - DO NOT EDIT MANUALLY")
    output_lines.append(" * Generated by: scripts/generate-wsi-forwards-from-source.py")
    output_lines.append(" * ")
    output_lines.append(" * Provides forwarding implementations for wsi_* functions that are referenced")
    output_lines.append(" * in the WSI entrypoints table but need to forward to vk_common_* runtime functions")
    output_lines.append(" * for static linking on iOS.")
    output_lines.append(" * ")
    output_lines.append(" * KosmicKrisp already implements Vulkan 1.3 - this file just forwards")
    output_lines.append(" * wsi_* entrypoints to their vk_common_* runtime implementations.")
    output_lines.append(" */")
    output_lines.append("")
    output_lines.append("#include <vulkan/vulkan.h>")
    output_lines.append("#include <stddef.h>")
    output_lines.append("")
    output_lines.append("// Forward declarations from Vulkan runtime")
    output_lines.append("// These are implemented in libvulkan_kosmickrisp.a")
    output_lines.append("")
    
    # Collect extern declarations and functions
    extern_decls = []
    forwarding_funcs = []
    stub_funcs = []
    
    for wsi_func in sorted(wsi_functions):
        base_name = wsi_func.replace('wsi_', '')
        
        # Try to get signature
        signature = parse_vulkan_function_signature(wsi_func)
        
        if base_name in available_vk_common:
            # We have a vk_common_* equivalent - generate forwarding
            if signature:
                extern_decls.append(f"extern {signature['return_type']} vk_common_{base_name}({signature['param_list']});")
                forwarding_funcs.append(generate_forwarding_function(wsi_func, signature, base_name))
            else:
                # Can't parse signature, skip for now
                print(f"Warning: Could not parse signature for {wsi_func}, skipping", file=sys.stderr)
        else:
            # No vk_common_* equivalent - generate stub
            stub_funcs.append(generate_stub_function(wsi_func, signature))
    
    # Add extern declarations
    output_lines.extend(extern_decls)
    output_lines.append("")
    output_lines.append("// Forwarding implementations")
    output_lines.append("")
    
    # Add forwarding functions
    output_lines.extend(forwarding_funcs)
    output_lines.append("")
    output_lines.append("// Stub implementations for optional extensions")
    output_lines.append("")
    
    # Add stub functions
    output_lines.extend(stub_funcs)
    
    # Write output
    OUTPUT_FILE.write_text('\n'.join(output_lines))
    print(f"\nGenerated {len(forwarding_funcs)} forwarding functions")
    print(f"Generated {len(stub_funcs)} stub functions")
    print(f"Output written to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()

