#!/usr/bin/env python3
"""
Generate stubs for missing vk_common_* functions.

These functions are referenced in KosmicKrisp entrypoints but not all are implemented.
This script generates stubs for the missing ones.
"""

import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).parent.parent
LIB_PATH = ROOT_DIR / "build/ios-install/lib/libvulkan_kosmickrisp.a"
OUTPUT_FILE = ROOT_DIR / "src/vulkan_common_stubs.c"

def get_available_vk_common_functions():
    """Get all available vk_common_* functions from the library."""
    if not LIB_PATH.exists():
        print(f"Warning: Library not found at {LIB_PATH}", file=sys.stderr)
        return set()
    
    result = subprocess.run(['nm', str(LIB_PATH)], capture_output=True, text=True)
    functions = set()
    for line in result.stdout.split('\n'):
        if ' T ' in line and 'vk_common_' in line:
            # Extract function name
            parts = line.split()
            if len(parts) >= 3:
                func_name = parts[-1]
                if func_name.startswith('_vk_common_'):
                    func_name = func_name[1:]  # Remove leading underscore
                functions.add(func_name)
    return functions

def get_needed_vk_common_functions():
    """Get list of vk_common_* functions needed from linker errors."""
    # For now, return common missing ones - in practice, parse from build output
    # This is a comprehensive list of optional extensions
    return set()

def generate_stub(func_name):
    """Generate a stub function for vk_common_* function."""
    # Remove vk_common_ prefix to get base name
    base_name = func_name.replace('vk_common_', '')
    
    # Determine return type based on function name patterns
    if base_name.startswith('Cmd'):
        return_type = 'void'
    elif base_name.startswith('Get') or base_name.startswith('Enumerate') or base_name.startswith('Acquire'):
        return_type = 'VkResult'
    elif base_name.startswith('Set') or base_name.startswith('Bind') or base_name.startswith('Create') or base_name.startswith('Destroy') or base_name.startswith('Free') or base_name.startswith('Reset') or base_name.startswith('Update') or base_name.startswith('Merge') or base_name.startswith('Map') or base_name.startswith('Unmap') or base_name.startswith('Flush') or base_name.startswith('Invalidate') or base_name.startswith('Queue') or base_name.startswith('Wait') or base_name.startswith('Signal') or base_name.startswith('Import') or base_name.startswith('Export') or base_name.startswith('Release') or base_name.startswith('Register') or base_name.startswith('Copy') or base_name.startswith('Build') or base_name.startswith('Compile'):
        return_type = 'VkResult'
    else:
        return_type = 'VkResult'
    
    if return_type == 'void':
        return f"""VKAPI_ATTR void VKAPI_CALL {func_name}(void* dummy, ...) {{
    (void)dummy;
    // Stub for optional extension
}}"""
    else:
        return f"""VKAPI_ATTR {return_type} VKAPI_CALL {func_name}(void* dummy, ...) {{
    (void)dummy;
    return VK_ERROR_EXTENSION_NOT_PRESENT;
}}"""

def get_kosmickrisp_common_entrypoints():
    """Extract all vk_common_* function names from KosmicKrisp source."""
    entrypoint_file = ROOT_DIR / "dependencies/kosmickrisp/build-host/src/vulkan/runtime/vk_common_entrypoints.c"
    if not entrypoint_file.exists():
        print(f"Warning: KosmicKrisp common entrypoint file not found at {entrypoint_file}", file=sys.stderr)
        return set()
    
    import re
    content = entrypoint_file.read_text()
    # Extract all vk_common_* function names
    funcs = set(re.findall(r'vk_common_([A-Za-z0-9_]+)', content))
    # Filter out entrypoint table symbols (these are data structures, not functions)
    funcs = {f for f in funcs if not f.endswith('_entrypoints') and f != 'entrypoints'}
    return funcs

def main():
    print("Getting available vk_common_* functions...")
    available = get_available_vk_common_functions()
    print(f"Found {len(available)} available vk_common_* functions")
    
    # Get all functions from KosmicKrisp source
    kosmickrisp_funcs = get_kosmickrisp_common_entrypoints()
    if kosmickrisp_funcs:
        print(f"Found {len(kosmickrisp_funcs)} functions in KosmicKrisp common entrypoints")
        # Convert to full function names
        missing_functions = {f"vk_common_{f}" for f in kosmickrisp_funcs}
    else:
        # Fallback: read from linker error output if available
        missing_functions = set()
        missing_file = Path("/tmp/all_missing_vk_common.txt")
        if missing_file.exists():
            lines = missing_file.read_text().strip().split('\n')
            for line in lines:
                line = line.strip()
                # Extract function name from lines like: '  "_vk_common_FunctionName", referenced from:'
                if '"vk_common_' in line or '"_vk_common_' in line:
                    # Find the function name between quotes
                    import re
                    match = re.search(r'["\'](_?vk_common_[^"\']+)["\']', line)
                    if match:
                        func_name = match.group(1)
                        if func_name.startswith('_'):
                            func_name = func_name[1:]  # Remove leading underscore
                        missing_functions.add(func_name)
            print(f"Found {len(missing_functions)} missing functions from linker errors")
        
        # Always merge with fallback list to ensure critical functions are included
        fallback_functions = {
            "vk_common_CreateMacOSSurfaceMVK",
            "vk_common_WriteAccelerationStructuresPropertiesKHR",
            "vk_common_WriteMicromapsPropertiesEXT",
        }
        missing_functions.update(fallback_functions)
        if not missing_file.exists():
            print("Using fallback list of missing functions")
    
    # Filter out ones that exist
    missing_functions = [f for f in missing_functions if f not in available]
    
    if not missing_functions:
        print("No missing functions to generate stubs for")
        return
    
    output_lines = []
    output_lines.append("/*")
    output_lines.append(" * Vulkan Common Runtime Stubs")
    output_lines.append(" * ")
    output_lines.append(" * AUTO-GENERATED FILE - DO NOT EDIT MANUALLY")
    output_lines.append(" * Generated by: scripts/generate-vk-common-stubs.py")
    output_lines.append(" * ")
    output_lines.append(" * Stubs for vk_common_* functions that are referenced")
    output_lines.append(" * in KosmicKrisp entrypoints but not implemented (optional extensions).")
    output_lines.append(" */")
    output_lines.append("")
    output_lines.append("#include <vulkan/vulkan.h>")
    output_lines.append("")
    
    for func_name in sorted(missing_functions):
        output_lines.append(generate_stub(func_name))
        output_lines.append("")
    
    OUTPUT_FILE.write_text('\n'.join(output_lines))
    print(f"Generated {len(missing_functions)} stub functions")
    print(f"Output written to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()

