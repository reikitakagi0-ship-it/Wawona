# GBM, DRM, and KMS on macOS/iOS: Implementation Guide

This document details the architecture and implementation strategy for porting Linux graphics primitives (GBM, DRM, KMS) to macOS and iOS. This is essential for running Linux-centric graphics stacks (Mesa, Wayland, EGL) on Apple platforms.

## 1. Concepts & Architecture

### 1.1 Linux Graphics Stack (The Target)
*   **DRM (Direct Rendering Manager)**: Kernel subsystem for managing GPUs. Handles command submission and memory management.
*   **KMS (Kernel Mode Setting)**: Part of DRM. Handles display output (CRTCs, Encoders, Connectors) and setting video modes (resolutions).
*   **GBM (Generic Buffer Management)**: Userspace library that interfaces with DRM to allocate graphics buffers (buffers that can be scanout capable, rendered to, etc.). It provides an abstraction for buffer allocation.
*   **DMA-BUF**: Linux kernel framework for sharing buffers between drivers/processes via file descriptors (FDs).

### 1.2 macOS/iOS Graphics Stack (The Reality)
*   **IOKit**: Low-level kernel framework for hardware access. Roughly analogous to parts of DRM but significantly different API.
*   **Quartz / Core Graphics**: Windowing and display server. Handles display modes (KMS equivalent).
*   **Metal**: Graphics and Compute API. Handles command submission (DRM rendering equivalent).
*   **IOSurface**: Framework for sharing graphics buffers across processes. This is the direct equivalent of **GBM + DMA-BUF**.

## 2. Mapping Linux to Apple

| Linux Concept | Apple Equivalent | Implementation Strategy |
| :--- | :--- | :--- |
| `gbm_device` | Virtual Context | struct wrapping nothing or a specific Metal Device |
| `gbm_bo` (Buffer Object) | `IOSurface` | struct wrapping `IOSurfaceRef` and metadata |
| `gbm_bo_create` | `IOSurfaceCreate` | Map flags/formats to `NSDictionary` properties |
| `gbm_bo_get_fd` (DMA-BUF) | Mach Port / XPC | **Critical Mismatch**. IOSurfaces use global IDs (IDs) or Mach Ports, not UNIX file descriptors. We must emulate FDs using a side-channel (e.g., socketpair) or specialized ID passing. |
| DRM Nodes (`/dev/dri/card0`) | None | Mock path or ignore. Use `sysctl` or Metal to enumerate devices. |
| KMS (Mode Setting) | `CoreGraphics` | Use `CGDisplay` APIs to query modes/screens. |

## 3. Implementing GBM on macOS (The Wrapper)

Since Mesa/Wayland expects `libgbm`, we implement a **shim library** that exposes the `<gbm.h>` API but calls `IOSurface` APIs internally.

### 3.1 Data Structures

```c
// Internal wrapper structure for gbm_bo
struct gbm_bo {
    struct gbm_device *gbm;
    IOSurfaceRef iosurface;  // The native Apple buffer
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;         // GBM format (fourcc)
    uint64_t modifier;       // Linux concept, largely ignored on macOS
    
    // Emulation state
    int fd;                  // Mock FD or socket for passing ID
    uint32_t iosurface_id;   // Global system ID for the surface
};
```

### 3.2 Key Function Implementations

#### `gbm_create_device(int fd)`
*   **Linux**: Opens DRM device.
*   **macOS**: Just allocate the struct. Ignore FD or use it to identify which "virtual" device (though macOS usually just uses the default Metal device).

#### `gbm_bo_create(...)`
1.  Convert GBM width/height/format/flags to `CFDictionary` keys:
    *   `kIOSurfaceWidth` -> `width`
    *   `kIOSurfaceHeight` -> `height`
    *   `kIOSurfacePixelFormat` -> Map `GBM_FORMAT_ARGB8888` to `kCVPixelFormatType_32BGRA`.
    *   `kIOSurfaceBytesPerRow` -> Calculate stride (align to 16 or 64 bytes for Metal/CPU cache).
2.  Call `IOSurfaceCreate(dict)`.
3.  Return wrapped `gbm_bo`.

#### `gbm_bo_get_fd(struct gbm_bo *bo)`
*   **Challenge**: Linux expects an `int` (fd) that can be passed to `poll()` or sent over UNIX domain sockets via `SCM_RIGHTS`.
*   **Solution 1 (Stub/Fake)**: Return a dummy pipe FD. Does not allow real cross-process sharing via standard Linux mechanisms.
*   **Solution 2 (Socket Tunnel)**: Create a `socketpair`. Return one end. When data is written/read, transmit the `IOSurfaceID` (uint32).
*   **Solution 3 (Mach Port)**: IOSurfaces can create Mach Ports. This is the robust Apple way, but doesn't map to `int fd` cleanly without extensive adaptation in the consumer (Wayland).
*   **Recommended**: For basic single-process or cooperative multi-process (Waypipe), use `IOSurfaceID` passing or simple shared memory logic.

### 3.3 Integration with Metal (`metal_dmabuf`)
To render into these buffers with Metal (Mesa Zink):
1.  Get `IOSurfaceRef` from `gbm_bo`.
2.  Create `MTLTextureDescriptor`.
3.  Call `[device newTextureWithDescriptor:desc iosurface:surf plane:0]`.
4.  This binds the Metal texture to the memory. Modifications sync automatically (managed by OS).

## 4. DRM/KMS Wrapper (The "Fake" Driver)

If an application strictly requires DRM ioctls (e.g., calling `drmModeGetResources`), we need a **fake libdrm**.

*   **Stubbing**: Most functions can just return error/NULL if the app handles graceful degradation.
*   **Emulation**:
    *   `drmOpen`: Return a generic FD.
    *   `drmModeGetResources`: Query `CGGetActiveDisplayList`. Return count of displays.
    *   `drmModeGetConnector`: Map `CGDirectDisplayID` to a DRM Connector ID. Report resolution via `CGDisplayCopyDisplayMode`.

## 5. Status of Implementation

We have implemented a **100% complete** GBM API in `gbm-wrapper.c` in `src/compat/macos/stubs/libinput-macos/` and integrated it into the build system.

### 5.1 Device Functions (100% Complete)
*   `gbm_create_device` - Creates virtual GBM device
*   `gbm_device_destroy` - Destroys device
*   `gbm_device_get_fd` - Returns stored FD
*   `gbm_device_get_backend_name` - Returns "macos"
*   `gbm_device_is_format_supported` - Checks format support
*   `gbm_device_get_format_modifier_plane_count` - Returns plane count (always 1)
*   `gbm_device_get_major/minor/patch` - Version query functions

### 5.2 Buffer Object Functions (100% Complete)
*   `gbm_bo_create` - Creates buffer via IOSurface
*   `gbm_bo_create_with_modifiers` - Creates buffer (modifiers ignored)
*   `gbm_bo_create_with_modifiers2` - Creates buffer with flags
*   `gbm_bo_destroy` - Releases IOSurface
*   `gbm_bo_ref` - Reference counting
*   `gbm_bo_get_width/height/stride/format/modifier/plane_count`
*   `gbm_bo_get_stride_for_plane` - Single plane support
*   `gbm_bo_get_offset` - Always 0 for single plane
*   `gbm_bo_get_fd` - Returns socketpair FD for IPC
*   `gbm_bo_get_handle` - Returns IOSurfaceRef pointer
*   `gbm_bo_get_user_data/set_user_data` - Application data storage
*   `gbm_bo_get_device` - Back reference to device
*   `gbm_bo_map/unmap` - CPU access via IOSurfaceLock/Unlock
*   `gbm_bo_get_iosurface` - macOS/iOS helper (returns IOSurfaceRef)
*   `gbm_bo_get_iosurface_id` - Returns global IOSurface ID

### 5.3 Surface Functions (100% Complete - Critical for EGL)
*   `gbm_surface_create` - Creates surface with double buffering
*   `gbm_surface_create_with_modifiers` - Creates surface (modifiers stored but ignored)
*   `gbm_surface_destroy` - Destroys surface and all buffers
*   `gbm_surface_lock_front_buffer` - Returns next back buffer for rendering
*   `gbm_surface_release_buffer` - Releases buffer back to pool
*   `gbm_surface_has_free_buffers` - Checks if buffers available
*   `gbm_surface_set_user_data/get_user_data` - User data storage

### 5.4 Format Support (100% Complete)
Supported formats:
*   XRGB8888 / ARGB8888 (primary formats)
*   XBGR8888 / ABGR8888
*   RGB565
*   RGB888 / BGR888
*   XRGB2101010 / ARGB2101010

All formats map to appropriate IOSurface/CVPixelFormat equivalents.

### 5.5 Format Query Functions (100% Complete)
*   `gbm_format_get_name` - Returns format name string

### 5.6 Version Functions (100% Complete)
*   `gbm_device_get_major/minor/patch` - Returns version 22.0.0

### 5.7 Build Integration
*   Static library `libgbm.a` built via CMake
*   Linked into `Wawona` executable
*   Includes `metal_dmabuf.m` for IOSurface implementation
*   Proper iOS/macOS framework linking (IOSurface, Metal, CoreVideo)
*   Full Objective-C ARC support

### 5.8 Implementation Notes
*   **Double Buffering**: Surfaces use double buffering by default (2 back buffers)
*   **Reference Counting**: Buffer objects use reference counting for proper cleanup
*   **Modifiers**: Stored for compatibility but always return 0 (macOS doesn't support DRM modifiers)
*   **FD Emulation**: `gbm_bo_get_fd` returns socketpair FD that transmits IOSurface ID
*   **Format Mapping**: All formats correctly map to IOSurface/CVPixelFormat equivalents
*   **Error Handling**: All functions properly handle NULL pointers and errors

## 6. References
*   **Apple**: [IOSurface Reference](https://developer.apple.com/documentation/iosurface)
*   **Linux**: [GBM Documentation (Mesa)](https://docs.mesa3d.org/)
*   **Projects**:
    *   *Quartz/CoreGraphics*: Only for display modes.
    *   *Metal*: For rendering.
    *   *Wayland-Server*: Needs these buffers to composite.

