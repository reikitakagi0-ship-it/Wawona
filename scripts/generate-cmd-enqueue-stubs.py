#!/usr/bin/env python3
"""
Generate stubs for missing vk_cmd_enqueue_* functions.

These functions are referenced in KosmicKrisp entrypoints but not all are implemented.
This script generates stubs for the missing ones.
"""

import sys
from pathlib import Path

ROOT_DIR = Path(__file__).parent.parent
OUTPUT_FILE = ROOT_DIR / "src/vulkan_cmd_enqueue_stubs.c"

def get_missing_functions():
    """Get list of missing vk_cmd_enqueue_* functions from linker errors."""
    missing = []
    
    # Try to read from linker error output (try current first, then old)
    missing_file = Path("/tmp/current_missing_cmd_enqueue.txt")
    if not missing_file.exists():
        missing_file = Path("/tmp/all_missing_cmd_enqueue.txt")
    if missing_file.exists():
        lines = missing_file.read_text().strip().split('\n')
        linker_missing = set()
        for line in lines:
            line = line.strip()
            # Handle lines that are just function names (with or without underscore)
            if line.startswith('_vk_cmd_enqueue') or line.startswith('vk_cmd_enqueue'):
                func_name = line
                if func_name.startswith('_'):
                    func_name = func_name[1:]  # Remove leading underscore
                linker_missing.add(func_name)
            # Also handle lines with quotes: '  "_vk_cmd_enqueue_FunctionName", referenced from:'
            elif '\"_vk_cmd_enqueue' in line or '\"vk_cmd_enqueue' in line:
                # Split by quote and take the part between quotes
                parts = line.split('"')
                if len(parts) >= 2:
                    func_name = parts[1]
                    if func_name.startswith('_'):
                        func_name = func_name[1:]  # Remove leading underscore
                    linker_missing.add(func_name)
        
        if linker_missing:
            print(f"Found {len(linker_missing)} missing functions from linker errors")
            # Determine return type and add to missing list
            # Also generate unless_primary_ versions for all functions
            unless_primary_prefix = "vk_cmd_enqueue_unless_primary_"
            seen = set()  # Track functions we've already added to avoid duplicates
            for func_name in sorted(linker_missing):
                if func_name in seen:
                    continue
                seen.add(func_name)
                
                if func_name.startswith('vk_cmd_enqueue_Cmd'):
                    missing.append(("void", func_name))
                    # Also add unless_primary version if not already present
                    if not func_name.startswith(unless_primary_prefix):
                        unless_primary_name = func_name.replace('vk_cmd_enqueue_', unless_primary_prefix)
                        if unless_primary_name not in seen:
                            missing.append(("void", unless_primary_name))
                            seen.add(unless_primary_name)
                else:
                    missing.append(("VkResult", func_name))
                    # Also add unless_primary version if not already present
                    if not func_name.startswith(unless_primary_prefix):
                        unless_primary_name = func_name.replace('vk_cmd_enqueue_', unless_primary_prefix)
                        if unless_primary_name not in seen:
                            missing.append(("VkResult", unless_primary_name))
                            seen.add(unless_primary_name)
            # Don't return early - continue to add hardcoded functions that might be missing
    
    # Fallback: generate from common patterns
    # Also include vk_cmd_enqueue_unless_primary_* functions
    unless_primary_prefix = "vk_cmd_enqueue_unless_primary_"
    
    # Common device-level functions (return VkResult)
    device_functions = [
        "AcquireDrmDisplayEXT",
        "AcquireNextImage2KHR",
        "AcquireNextImageKHR",
        "AcquirePerformanceConfigurationINTEL",
        "AcquireProfilingLockKHR",
        "AllocateCommandBuffers",
        "AllocateDescriptorSets",
        "AllocateMemory",
        "BeginCommandBuffer",
        "BindAccelerationStructureMemoryNV",
        "BindBufferMemory",
        "BindBufferMemory2",
        "BindBufferMemory2KHR",
        "BindDataGraphPipelineSessionMemoryARM",
        "BindImageMemory",
        "BindImageMemory2",
        "BindImageMemory2KHR",
        "BindOpticalFlowSessionImageNV",
        "BindTensorMemoryARM",
        "BindVideoSessionMemoryKHR",
        "BuildAccelerationStructuresKHR",
        "BuildMicromapsEXT",
        "CompileDeferredOperationsKHR",
        "CopyAccelerationStructureKHR",
        "CopyAccelerationStructureToMemoryKHR",
        "CopyMemoryToAccelerationStructureKHR",
        "CreateAccelerationStructureKHR",
        "CreateAccelerationStructureNV",
        "CreateBuffer",
        "CreateBufferView",
        "CreateCommandPool",
        "CreateComputePipelines",
        "CreateDeferredOperationKHR",
        "CreateDescriptorPool",
        "CreateDescriptorSetLayout",
        "CreateDescriptorUpdateTemplate",
        "CreateDescriptorUpdateTemplateKHR",
        "CreateEvent",
        "CreateFence",
        "CreateFramebuffer",
        "CreateGraphicsPipelines",
        "CreateImage",
        "CreateImageView",
        "CreateIndirectCommandsLayoutNV",
        "CreateMacOSSurfaceMVK",
        "CreateMicromapEXT",
        "CreateOpticalFlowSessionNV",
        "CreatePipelineCache",
        "CreatePipelineLayout",
        "CreatePrivateDataSlot",
        "CreatePrivateDataSlotEXT",
        "CreateQueryPool",
        "CreateRayTracingPipelinesKHR",
        "CreateRayTracingPipelinesNV",
        "CreateRenderPass",
        "CreateRenderPass2",
        "CreateRenderPass2KHR",
        "CreateSampler",
        "CreateSamplerYcbcrConversion",
        "CreateSamplerYcbcrConversionKHR",
        "CreateSemaphore",
        "CreateShaderModule",
        "CreateSwapchainKHR",
        "CreateVideoSessionKHR",
        "CreateVideoSessionParametersKHR",
        "DebugMarkerSetObjectNameEXT",
        "DebugMarkerSetObjectTagEXT",
        "DestroyAccelerationStructureKHR",
        "DestroyAccelerationStructureNV",
        "DestroyBuffer",
        "DestroyBufferView",
        "DestroyCommandPool",
        "DestroyDeferredOperationKHR",
        "DestroyDescriptorPool",
        "DestroyDescriptorSetLayout",
        "DestroyDescriptorUpdateTemplate",
        "DestroyDescriptorUpdateTemplateKHR",
        "DestroyEvent",
        "DestroyFence",
        "DestroyFramebuffer",
        "DestroyImage",
        "DestroyImageView",
        "DestroyIndirectCommandsLayoutNV",
        "DestroyMicromapEXT",
        "DestroyOpticalFlowSessionNV",
        "DestroyPipeline",
        "DestroyPipelineCache",
        "DestroyPipelineLayout",
        "DestroyPrivateDataSlot",
        "DestroyPrivateDataSlotEXT",
        "DestroyQueryPool",
        "DestroyRenderPass",
        "DestroySampler",
        "DestroySamplerYcbcrConversion",
        "DestroySamplerYcbcrConversionKHR",
        "DestroySemaphore",
        "DestroyShaderModule",
        "DestroySwapchainKHR",
        "DestroyVideoSessionKHR",
        "DestroyVideoSessionParametersKHR",
        "EndCommandBuffer",
        "FlushMappedMemoryRanges",
        "FreeCommandBuffers",
        "FreeDescriptorSets",
        "FreeMemory",
        "GetAccelerationStructureBuildSizesKHR",
        "GetAccelerationStructureDeviceAddressKHR",
        "GetAccelerationStructureHandleNV",
        "GetAccelerationStructureMemoryRequirementsNV",
        "GetBufferDeviceAddress",
        "GetBufferDeviceAddressEXT",
        "GetBufferMemoryRequirements",
        "GetBufferMemoryRequirements2",
        "GetBufferMemoryRequirements2KHR",
        "GetBufferOpaqueCaptureAddress",
        "GetBufferOpaqueCaptureAddressKHR",
        "GetCalibratedTimestampsKHR",
        "GetDeferredOperationMaxConcurrencyKHR",
        "GetDeferredOperationResultKHR",
        "GetDescriptorSetHostMappingVALVE",
        "GetDescriptorSetLayoutBindingOffsetEXT",
        "GetDescriptorSetLayoutHostMappingInfoVALVE",
        "GetDescriptorSetLayoutSizeEXT",
        "GetDeviceAccelerationStructureCompatibilityKHR",
        "GetDeviceGroupPeerMemoryFeatures",
        "GetDeviceGroupPeerMemoryFeaturesKHR",
        "GetDeviceMemoryCommitment",
        "GetDeviceMemoryOpaqueCaptureAddress",
        "GetDeviceMemoryOpaqueCaptureAddressKHR",
        "GetDeviceProcAddr",
        "GetEventStatus",
        "GetFenceStatus",
        "GetImageDrmFormatModifierPropertiesEXT",
        "GetImageMemoryRequirements",
        "GetImageMemoryRequirements2",
        "GetImageMemoryRequirements2KHR",
        "GetImageSparseMemoryRequirements",
        "GetImageSparseMemoryRequirements2",
        "GetImageSparseMemoryRequirements2KHR",
        "GetImageSubresourceLayout",
        "GetMemoryHostPointerPropertiesEXT",
        "GetMicromapBuildSizesEXT",
        "GetOpticalFlowImagePropertiesNV",
        "GetPerformanceParameterINTEL",
        "GetPipelineCacheData",
        "GetPipelineExecutablePropertiesKHR",
        "GetPipelineExecutableStatisticsKHR",
        "GetPipelineExecutableInternalRepresentationsKHR",
        "GetPrivateData",
        "GetPrivateDataEXT",
        "GetQueryPoolResults",
        "GetRayTracingCaptureReplayShaderGroupHandlesKHR",
        "GetRayTracingShaderGroupHandlesKHR",
        "GetRayTracingShaderGroupHandlesNV",
        "GetRayTracingShaderGroupStackSizeKHR",
        "GetSemaphoreCounterValue",
        "GetSemaphoreCounterValueKHR",
        "GetSwapchainImagesKHR",
        "GetVideoSessionMemoryRequirementsKHR",
        "ImportFenceFdKHR",
        "ImportSemaphoreFdKHR",
        "InvalidateMappedMemoryRanges",
        "MapMemory",
        "MapMemory2KHR",
        "MergePipelineCaches",
        "QueueBindSparse",
        "QueuePresentKHR",
        "QueueSetPerformanceConfigurationINTEL",
        "QueueSubmit",
        "QueueSubmit2",
        "QueueSubmit2KHR",
        "QueueWaitIdle",
        "RegisterDeviceEventEXT",
        "ReleasePerformanceConfigurationINTEL",
        "ReleaseProfilingLockKHR",
        "ResetCommandBuffer",
        "ResetCommandPool",
        "ResetDescriptorPool",
        "ResetEvent",
        "ResetFences",
        "SetDebugUtilsObjectNameEXT",
        "SetDebugUtilsObjectTagEXT",
        "SetEvent",
        "SetHdrMetadataEXT",
        "SetPrivateData",
        "SetPrivateDataEXT",
        "SignalSemaphore",
        "SignalSemaphoreKHR",
        "UnmapMemory",
        "UnmapMemory2KHR",
        "UpdateIndirectExecutionSetPipelineEXT",
        "UpdateIndirectExecutionSetShaderEXT",
        "UpdateVideoSessionParametersKHR",
        "WaitForFences",
        "WaitForPresent2KHR",
        "WaitForPresentKHR",
        "WaitSemaphores",
        "WaitSemaphoresKHR",
        "WriteAccelerationStructuresPropertiesKHR",
        "WriteMicromapsPropertiesEXT",
    ]
    
    # Also add Write functions explicitly since they might be missing
    if "WriteAccelerationStructuresPropertiesKHR" not in device_functions:
        device_functions.append("WriteAccelerationStructuresPropertiesKHR")
    if "WriteMicromapsPropertiesEXT" not in device_functions:
        device_functions.append("WriteMicromapsPropertiesEXT")
    
    # Command buffer functions (return void)
    cmd_functions = [
        "CmdBeginConditionalRenderingEXT",
        "CmdBeginDebugUtilsLabelEXT",
        "CmdBeginQuery",
        "CmdBeginQueryIndexedEXT",
        "CmdBeginRenderPass",
        "CmdBeginRenderPass2",
        "CmdBeginRenderPass2KHR",
        "CmdBeginRendering",
        "CmdBeginRenderingKHR",
        "CmdBeginTransformFeedbackEXT",
        "CmdBeginVideoCodingKHR",
        "CmdBindDescriptorBufferEmbeddedSamplersEXT",
        "CmdBindDescriptorBuffersEXT",
        "CmdBindDescriptorSets",
        "CmdBindDescriptorSets2KHR",
        "CmdBindIndexBuffer",
        "CmdBindIndexBuffer2KHR",
        "CmdBindInvocationMaskHUAWEI",
        "CmdBindPipeline",
        "CmdBindShadersEXT",
        "CmdBindTransformFeedbackBuffersEXT",
        "CmdBindVertexBuffers",
        "CmdBindVertexBuffers2",
        "CmdBindVertexBuffers2EXT",
        "CmdBlitImage",
        "CmdBlitImage2KHR",
        "CmdBuildAccelerationStructuresIndirectKHR",
        "CmdBuildAccelerationStructuresKHR",
        "CmdBuildMicromapsEXT",
        "CmdClearAttachments",
        "CmdClearColorImage",
        "CmdClearDepthStencilImage",
        "CmdCopyAccelerationStructureKHR",
        "CmdCopyAccelerationStructureToMemoryKHR",
        "CmdCopyBuffer",
        "CmdCopyBuffer2KHR",
        "CmdCopyBufferToImage",
        "CmdCopyImage",
        "CmdCopyImage2KHR",
        "CmdCopyImageToBuffer",
        "CmdCopyMemoryIndirectNV",
        "CmdCopyMemoryToAccelerationStructureKHR",
        "CmdCopyMemoryToImageIndirectNV",
        "CmdCopyMemoryToMicromapEXT",
        "CmdCopyMicromapEXT",
        "CmdCopyMicromapToMemoryEXT",
        "CmdCopyQueryPoolResults",
        "CmdCuLaunchKernelNVX",
        "CmdDebugMarkerBeginEXT",
        "CmdDebugMarkerEndEXT",
        "CmdDebugMarkerInsertEXT",
        "CmdDecodeVideoKHR",
        "CmdDispatch",
        "CmdDispatchBase",
        "CmdDispatchBaseKHR",
        "CmdDispatchIndirect",
        "CmdDraw",
        "CmdDrawIndexed",
        "CmdDrawIndexedIndirect",
        "CmdDrawIndexedIndirectCount",
        "CmdDrawIndexedIndirectCountAMD",
        "CmdDrawIndexedIndirectCountKHR",
        "CmdDrawIndirect",
        "CmdDrawIndirectByteCountEXT",
        "CmdDrawIndirectCount",
        "CmdDrawIndirectCountAMD",
        "CmdDrawIndirectCountKHR",
        "CmdDrawMeshTasksEXT",
        "CmdDrawMeshTasksIndirectCountEXT",
        "CmdDrawMeshTasksIndirectCountNV",
        "CmdDrawMeshTasksIndirectEXT",
        "CmdDrawMeshTasksIndirectNV",
        "CmdDrawMeshTasksNV",
        "CmdDrawMultiEXT",
        "CmdDrawMultiIndexedEXT",
        "CmdEndConditionalRenderingEXT",
        "CmdEndDebugUtilsLabelEXT",
        "CmdEndQuery",
        "CmdEndQueryIndexedEXT",
        "CmdEndRenderPass",
        "CmdEndRenderPass2",
        "CmdEndRenderPass2KHR",
        "CmdEndRendering",
        "CmdEndRenderingKHR",
        "CmdEndTransformFeedbackEXT",
        "CmdEndVideoCodingKHR",
        "CmdExecuteCommands",
        "CmdExecuteGeneratedCommandsNV",
        "CmdFillBuffer",
        "CmdInsertDebugUtilsLabelEXT",
        "CmdNextSubpass",
        "CmdNextSubpass2",
        "CmdNextSubpass2KHR",
        "CmdPipelineBarrier",
        "CmdPipelineBarrier2KHR",
        "CmdPreprocessGeneratedCommandsNV",
        "CmdPushConstants",
        "CmdResetEvent",
        "CmdResetEvent2KHR",
        "CmdResetQueryPool",
        "CmdResetQueryPoolEXT",
        "CmdResolveImage",
        "CmdResolveImage2KHR",
        "CmdSetAlphaToCoverageEnableEXT",
        "CmdSetAlphaToOneEnableEXT",
        "CmdSetAttachmentFeedbackLoopEnableEXT",
        "CmdSetBlendConstants",
        "CmdSetCheckpointNV",
        "CmdSetCoarseSampleOrderNV",
        "CmdSetColorBlendAdvancedEXT",
        "CmdSetColorBlendEnableEXT",
        "CmdSetColorBlendEquationEXT",
        "CmdSetColorWriteMaskEXT",
        "CmdSetConservativeRasterizationModeEXT",
        "CmdSetCoverageModulationModeNV",
        "CmdSetCoverageModulationTableEnableNV",
        "CmdSetCoverageModulationTableNV",
        "CmdSetCoverageReductionModeNV",
        "CmdSetCoverageToColorEnableNV",
        "CmdSetCoverageToColorLocationNV",
        "CmdSetCullMode",
        "CmdSetCullModeEXT",
        "CmdSetDepthBias",
        "CmdSetDepthBiasEnable",
        "CmdSetDepthBiasEnableEXT",
        "CmdSetDepthBounds",
        "CmdSetDepthBoundsTestEnable",
        "CmdSetDepthBoundsTestEnableEXT",
        "CmdSetDepthClampEnableEXT",
        "CmdSetDepthClipEnableEXT",
        "CmdSetDepthClipNegativeOneToOneEXT",
        "CmdSetDepthCompareOp",
        "CmdSetDepthCompareOpEXT",
        "CmdSetDepthTestEnable",
        "CmdSetDepthTestEnableEXT",
        "CmdSetDepthWriteEnable",
        "CmdSetDepthWriteEnableEXT",
        "CmdSetDescriptorBufferOffsetsEXT",
        "CmdSetDeviceMask",
        "CmdSetDeviceMaskKHR",
        "CmdSetDiscardRectangle",
        "CmdSetDiscardRectangleEXT",
        "CmdSetDiscardRectangleEnableEXT",
        "CmdSetDiscardRectangleModeEXT",
        "CmdSetEvent",
        "CmdSetEvent2KHR",
        "CmdSetExclusiveScissorEnableNV",
        "CmdSetExclusiveScissorNV",
        "CmdSetExtraPrimitiveOverestimationSizeEXT",
        "CmdSetFragmentShadingRateEnumNV",
        "CmdSetFragmentShadingRateKHR",
        "CmdSetFragmentShadingRateNV",
        "CmdSetFrontFace",
        "CmdSetFrontFaceEXT",
        "CmdSetLineRasterizationModeEXT",
        "CmdSetLineStipple",
        "CmdSetLineStippleEnableEXT",
        "CmdSetLineStippleEXT",
        "CmdSetLineWidth",
        "CmdSetLogicOpEXT",
        "CmdSetPatchControlPointsEXT",
        "CmdSetPerformanceMarkerINTEL",
        "CmdSetPerformanceOverrideINTEL",
        "CmdSetPerformanceStreamMarkerINTEL",
        "CmdSetPolygonModeEXT",
        "CmdSetPrimitiveRestartEnable",
        "CmdSetPrimitiveRestartEnableEXT",
        "CmdSetPrimitiveTopology",
        "CmdSetPrimitiveTopologyEXT",
        "CmdSetProvokingVertexModeEXT",
        "CmdSetRasterizationSamplesEXT",
        "CmdSetRasterizationStreamEXT",
        "CmdSetRayTracingPipelineStackSizeKHR",
        "CmdSetRepresentativeFragmentTestEnableNV",
        "CmdSetSampleLocations",
        "CmdSetSampleLocationsEnableEXT",
        "CmdSetSampleLocationsEXT",
        "CmdSetSampleMaskEXT",
        "CmdSetScissor",
        "CmdSetScissorWithCount",
        "CmdSetScissorWithCountEXT",
        "CmdSetShadingRateImageEnableNV",
        "CmdSetStencilCompareMask",
        "CmdSetStencilOp",
        "CmdSetStencilOpEXT",
        "CmdSetStencilReference",
        "CmdSetStencilTestEnable",
        "CmdSetStencilTestEnableEXT",
        "CmdSetStencilWriteMask",
        "CmdSetTessellationDomainOriginEXT",
        "CmdSetVertexInputEXT",
        "CmdSetViewport",
        "CmdSetViewportShadingRatePaletteNV",
        "CmdSetViewportSwizzleNV",
        "CmdSetViewportWithCount",
        "CmdSetViewportWithCountEXT",
        "CmdSetViewportWScalingNV",
        "CmdSubpassShadingHUAWEI",
        "CmdTraceRaysIndirect2KHR",
        "CmdTraceRaysIndirectKHR",
        "CmdTraceRaysKHR",
        "CmdTraceRaysNV",
        "CmdUpdateBuffer",
        "CmdWaitEvents",
        "CmdWaitEvents2",
        "CmdWaitEvents2KHR",
        "CmdWriteAccelerationStructuresPropertiesKHR",
        "CmdWriteAccelerationStructuresPropertiesNV",
        "CmdWriteBufferMarker2AMD",
        "CmdWriteBufferMarkerAMD",
        "CmdWriteMicromapsPropertiesEXT",
        "CmdWriteTimestamp",
        "CmdWriteTimestamp2",
        "CmdWriteTimestamp2KHR",
    ]
    
    # Add hardcoded functions, avoiding duplicates
    seen_funcs = {name for _, name in missing}  # Track what we already have
    
    for func in device_functions:
        cmd_enqueue_name = f"vk_cmd_enqueue_{func}"
        unless_primary_name = f"{unless_primary_prefix}{func}"
        if cmd_enqueue_name not in seen_funcs:
            missing.append(("VkResult", cmd_enqueue_name))
            seen_funcs.add(cmd_enqueue_name)
        if unless_primary_name not in seen_funcs:
            missing.append(("VkResult", unless_primary_name))
            seen_funcs.add(unless_primary_name)
    
    for func in cmd_functions:
        cmd_enqueue_name = f"vk_cmd_enqueue_{func}"
        unless_primary_name = f"{unless_primary_prefix}{func}"
        if cmd_enqueue_name not in seen_funcs:
            missing.append(("void", cmd_enqueue_name))
            seen_funcs.add(cmd_enqueue_name)
        if unless_primary_name not in seen_funcs:
            missing.append(("void", unless_primary_name))
            seen_funcs.add(unless_primary_name)
    
    return missing

def generate_stub(return_type, func_name):
    """Generate a stub function."""
    if return_type == "void":
        return f"""VKAPI_ATTR void VKAPI_CALL {func_name}(void* dummy, ...) {{
    (void)dummy;
    // Stub for optional extension
}}"""
    else:
        return f"""VKAPI_ATTR {return_type} VKAPI_CALL {func_name}(void* dummy, ...) {{
    (void)dummy;
    return VK_ERROR_EXTENSION_NOT_PRESENT;
}}"""

def get_kosmickrisp_entrypoints():
    """Extract all entrypoint function names from KosmicKrisp source."""
    entrypoint_file = ROOT_DIR / "dependencies/kosmickrisp/build-host/src/vulkan/runtime/vk_cmd_enqueue_entrypoints.c"
    if not entrypoint_file.exists():
        print(f"Warning: KosmicKrisp entrypoint file not found at {entrypoint_file}", file=sys.stderr)
        return set()
    
    import re
    content = entrypoint_file.read_text()
    # Extract all vk_cmd_enqueue_* function names (excluding unless_primary variants)
    funcs = set(re.findall(r'vk_cmd_enqueue_([A-Za-z0-9_]+)', content))
    # Remove unless_primary variants (they'll be generated separately)
    funcs = {f for f in funcs if not f.startswith('unless_primary_')}
    return funcs

def get_available_cmd_enqueue_functions():
    """Get all available vk_cmd_enqueue_* functions from the library."""
    lib_path = ROOT_DIR / "build/ios-install/lib/libvulkan_kosmickrisp.a"
    if not lib_path.exists():
        print(f"Warning: Library not found at {lib_path}", file=sys.stderr)
        return set()
    
    import subprocess
    result = subprocess.run(['nm', str(lib_path)], capture_output=True, text=True)
    functions = set()
    for line in result.stdout.split('\n'):
        # Look for defined symbols (T = text/code section, uppercase T means global/exported)
        if ' T ' in line and ('vk_cmd_enqueue_' in line or 'vk_cmd_enqueue_unless_primary_' in line):
            # Extract function name - it's the last field
            parts = line.split()
            if len(parts) >= 3:
                func_name = parts[-1]
                # Remove leading underscore if present (macOS/iOS symbol naming)
                if func_name.startswith('_'):
                    func_name = func_name[1:]
                # Only add if it's actually a function name (not a stub reference or cold section)
                if func_name and not func_name.endswith('_stub') and '.cold.' not in func_name:
                    functions.add(func_name)
    print(f"Found {len(functions)} implemented functions in library")
    return functions

def main():
    missing = get_missing_functions()
    
    # Get available functions from library to avoid duplicates
    print("Getting available vk_cmd_enqueue_* functions from library...")
    available = get_available_cmd_enqueue_functions()
    print(f"Found {len(available)} available functions in library")
    
    # Filter out functions that are already implemented in the library
    missing = [(ret_type, name) for ret_type, name in missing if name not in available]
    print(f"After filtering library functions: {len(missing)} missing functions")
    
    # Also get all functions from KosmicKrisp source
    kosmickrisp_funcs = get_kosmickrisp_entrypoints()
    if kosmickrisp_funcs:
        print(f"Found {len(kosmickrisp_funcs)} functions in KosmicKrisp entrypoints")
        unless_primary_prefix = "vk_cmd_enqueue_unless_primary_"
        seen_funcs = {name for _, name in missing}
        
        # Add all KosmicKrisp functions that aren't already in missing list AND aren't in the library
        skipped_count = 0
        for func_base in kosmickrisp_funcs:
            # Skip entrypoint table symbols (these are data structures, not functions)
            if func_base.endswith('_entrypoints') or func_base == 'entrypoints':
                skipped_count += 1
                continue
            
            cmd_enqueue_name = f"vk_cmd_enqueue_{func_base}"
            unless_primary_name = f"{unless_primary_prefix}{func_base}"
            
            # Skip if already implemented in library
            if cmd_enqueue_name in available:
                skipped_count += 1
                continue
            if unless_primary_name in available:
                skipped_count += 1
                continue
            
            # Determine return type
            if func_base.startswith('Cmd'):
                return_type = "void"
            else:
                return_type = "VkResult"
            
            if cmd_enqueue_name not in seen_funcs:
                missing.append((return_type, cmd_enqueue_name))
                seen_funcs.add(cmd_enqueue_name)
            
            if unless_primary_name not in seen_funcs:
                missing.append((return_type, unless_primary_name))
                seen_funcs.add(unless_primary_name)
        
        if skipped_count > 0:
            print(f"Skipped {skipped_count} functions (entrypoint tables or already in library)")
    
    output_lines = []
    output_lines.append("/*")
    output_lines.append(" * Vulkan Command Enqueue Stubs")
    output_lines.append(" * ")
    output_lines.append(" * AUTO-GENERATED FILE - DO NOT EDIT MANUALLY")
    output_lines.append(" * Generated by: scripts/generate-cmd-enqueue-stubs.py")
    output_lines.append(" * ")
    output_lines.append(" * Stubs for vk_cmd_enqueue_* functions that are referenced")
    output_lines.append(" * in KosmicKrisp entrypoints but not implemented (optional extensions).")
    output_lines.append(" */")
    output_lines.append("")
    output_lines.append("#include <vulkan/vulkan.h>")
    output_lines.append("")
    
    for return_type, func_name in sorted(missing, key=lambda x: x[1]):
        output_lines.append(generate_stub(return_type, func_name))
        output_lines.append("")
    
    OUTPUT_FILE.write_text('\n'.join(output_lines))
    print(f"Generated {len(missing)} stub functions")
    print(f"Output written to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()

