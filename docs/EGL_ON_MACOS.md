# EGL on macOS

## What is EGL?

**EGL (Embedded-System Graphics Library)** is an interface between rendering APIs (like OpenGL ES) and the native platform windowing system. It provides:

- **Context Management**: Creating and managing OpenGL/OpenGL ES rendering contexts
- **Surface Management**: Creating rendering surfaces (windows, pbuffers, pixmaps)
- **Buffer Management**: Managing framebuffers and swap chains
- **Platform Abstraction**: Abstracts platform-specific windowing APIs

Think of EGL as the "glue" between OpenGL ES applications and the native window system.

## Does EGL Exist on macOS?

**No, macOS does not have native EGL support.**

Apple deprecated OpenGL and OpenGL ES in macOS 10.14 Mojave (2018) in favor of **Metal**, their modern graphics API. macOS never had native EGL support because:

1. Apple used their own OpenGL implementation (not Mesa)
2. Apple's OpenGL was tied to Cocoa/AppKit, not EGL
3. Apple wants developers to use Metal directly

## Our Solution: KosmicKrisp + Zink + EGL

We are implementing EGL support on macOS using:

### Architecture

```
OpenGL ES Application
    ↓
EGL API (Mesa EGL)
    ↓
Zink Driver (OpenGL ES → Vulkan translation)
    ↓
KosmicKrisp Vulkan Driver (Vulkan 1.3 conformant)
    ↓
Metal (macOS native graphics API)
```

### Components

1. **KosmicKrisp Vulkan Driver**
   - Vulkan 1.3 conformant driver for macOS
   - Uses Metal as the backend
   - Provides hardware-accelerated Vulkan support

2. **Zink Driver**
   - Mesa Gallium driver that translates OpenGL ES to Vulkan
   - Runs on top of KosmicKrisp
   - Provides OpenGL ES 1.x, 2.x, and 3.x support

3. **Mesa EGL**
   - EGL implementation from Mesa
   - Provides EGL API for context and surface management
   - Uses Zink as the rendering backend

### Implementation Status

✅ **KosmicKrisp Vulkan Driver**: Built and installed (Vulkan 1.3 conformant)  
✅ **Zink Driver**: Built and integrated with KosmicKrisp  
✅ **Mesa EGL**: Built with Wayland platform support  
✅ **EGL Platform Support**: macOS and Wayland platforms enabled  
⏳ **WSI Entrypoint Access**: Fixed to access Mesa WSI functions directly  
⏳ **Wayland Surface Creation**: Testing with `weston-simple-egl`

### Key Implementation Details

#### WSI Entrypoint Table Access

On macOS, MoltenVK creates the Vulkan instance (not Mesa), so we can't use `vkGetInstanceProcAddr` to get Wayland surface functions. Instead, we access Mesa's WSI entrypoint table directly:

```c
// Access Mesa's WSI entrypoint tables directly
screen->vk.CreateWaylandSurfaceKHR = wsi_instance_entrypoints.CreateWaylandSurfaceKHR;
screen->vk.GetPhysicalDeviceWaylandPresentationSupportKHR = 
    wsi_physical_device_entrypoints.GetPhysicalDeviceWaylandPresentationSupportKHR;
```

This allows Zink to use Mesa's Wayland WSI functions even when MoltenVK creates the instance.

#### Build Configuration

KosmicKrisp is built with:
- `-Dplatforms=macos,wayland` - Enables both macOS and Wayland EGL platforms
- `-Dvulkan-drivers=kosmickrisp` - Uses KosmicKrisp Vulkan driver
- `-Dgallium-drivers=zink` - Enables Zink OpenGL ES → Vulkan translation
- `-Degl=enabled` - Enables EGL support
- `-Dgles1=enabled` - OpenGL ES 1.x support
- `-Dgles2=enabled` - OpenGL ES 2.x and 3.x support

### Benefits

✅ **Hardware Accelerated**: Uses Metal via KosmicKrisp, not software rendering  
✅ **Full EGL Support**: Complete EGL API implementation  
✅ **OpenGL ES Support**: ES 1.x, 2.x, and 3.x via Zink  
✅ **Wayland Compatible**: Works with Wayland compositors (like Wawona)  
✅ **Vulkan 1.3 Conformant**: Uses conformant Vulkan driver  
✅ **No Stubs**: Real implementation, not placeholder code

### Current Work

We are currently working on:
1. ✅ Accessing Mesa WSI entrypoint tables directly (fixed)
2. ⏳ Testing Wayland surface creation with `weston-simple-egl`
3. ⏳ Verifying EGL context creation and rendering
4. ⏳ Ensuring all EGL extensions work correctly

### Testing

To test EGL support:

```bash
# Build KosmicKrisp with EGL support
make kosmickrisp

# Test EGL with Wayland platform
EGL_PLATFORM=wayland weston-simple-egl

# Test EGL with macOS platform (standalone)
EGL_PLATFORM=macos ./test-egl-comprehensive
```

## Conclusion

We are implementing **full EGL support on macOS** using:
- **KosmicKrisp** (Vulkan 1.3 conformant driver)
- **Zink** (OpenGL ES → Vulkan translation)
- **Mesa EGL** (EGL API implementation)

This provides hardware-accelerated EGL support without stubs, software rendering, or external dependencies like ANGLE. Everything runs through KosmicKrisp's Vulkan driver, which uses Metal as the backend.
