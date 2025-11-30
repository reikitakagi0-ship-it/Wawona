# App Store Compliance Guide

This document outlines the requirements and implementation for making Wawona App Store compliant.

## Overview

Apple's App Store has strict requirements:
- **No .dylib files** - All libraries must be statically linked or bundled as frameworks
- **Code Signing** - All binaries must be properly signed
- **Sandboxing** - Must respect App Sandbox restrictions
- **Entitlements** - Proper entitlements for required capabilities

## Current Issues

### 1. KosmicKrisp as .dylib

**Problem**: Currently builds as system-wide `.dylib` driver
- Installed to `/opt/homebrew/lib/libvulkan_kosmickrisp.dylib`
- Not allowed in App Store apps

**Solution**: Convert to static framework
- Build as `.framework` bundle
- Statically link into Wawona
- No system-wide installation

### 2. Other Dependencies

**Problem**: Various dependencies may be built as `.dylib`
- Wayland libraries
- Other system libraries

**Solution**: Static linking or framework bundling
- Link statically where possible
- Bundle as frameworks if needed
- Ensure all dependencies are included in app bundle

## Implementation Plan

### Phase 1: KosmicKrisp Framework Conversion

#### 1.1 Update Meson Build

Modify `dependencies/kosmickrisp/meson.build`:

```meson
# Build as framework instead of dylib
if host_machine.system() == 'darwin'
    framework = true
    static_library = true
else
    framework = false
    static_library = false
endif

# Create framework structure
if framework
    framework_dir = meson.current_build_dir() / 'KosmicKrisp.framework'
    framework_headers = framework_dir / 'Headers'
    framework_libs = framework_dir / 'Libraries'
    # ... framework setup
endif
```

#### 1.2 Update Makefile

Modify `Makefile` to build framework:

```makefile
kosmickrisp-framework:
	@echo "Building KosmicKrisp as framework..."
	cd dependencies/kosmickrisp && \
	meson setup build-framework \
		-Dframework=true \
		-Dstatic=true \
		-Dprefix=$(PWD)/frameworks/KosmicKrisp.framework
```

#### 1.3 Framework Structure

```
KosmicKrisp.framework/
├── Headers/
│   ├── vulkan.h
│   └── ...
├── Libraries/
│   └── libKosmicKrisp.a  # Static library
├── Resources/
│   └── Info.plist
└── KosmicKrisp          # Symbolic link to library
```

### Phase 2: Static Linking

#### 2.1 Wayland Libraries

Build Wayland as static libraries:

```meson
# wayland/meson.build
static_library('wayland-server', ...)
static_library('wayland-client', ...)
```

#### 2.2 Other Dependencies

Ensure all dependencies are statically linked:
- Pixman
- libffi
- epoll-shim
- Other required libraries

### Phase 3: App Bundle Structure

```
Wawona.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── Wawona          # Main executable
│   ├── Frameworks/         # Frameworks (not .dylibs)
│   │   ├── KosmicKrisp.framework/
│   │   └── Wayland.framework/  # If needed
│   ├── Resources/
│   │   ├── launcher/       # Launcher UI resources
│   │   └── icons/          # App icons
│   └── PlugIns/            # App extensions (if any)
```

### Phase 4: Code Signing

#### 4.1 Sign Frameworks

```bash
codesign --force --deep --sign "Developer ID Application: Your Name" \
    Wawona.app/Contents/Frameworks/KosmicKrisp.framework
```

#### 4.2 Sign App Bundle

```bash
codesign --force --deep --sign "Developer ID Application: Your Name" \
    Wawona.app
```

#### 4.3 Verify Signing

```bash
codesign --verify --verbose Wawona.app
spctl --assess --verbose Wawona.app
```

### Phase 5: Entitlements

Create `Wawona.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

## Build Configuration

### CMakeLists.txt Updates

```cmake
# App Store build configuration
set(APP_STORE_BUILD TRUE)

# Static linking
set(BUILD_SHARED_LIBS OFF)

# Framework paths
set(CMAKE_FRAMEWORK_PATH
    ${CMAKE_SOURCE_DIR}/frameworks
    ${CMAKE_SOURCE_DIR}/dependencies/kosmickrisp/build-framework
)

# Link frameworks
if(APP_STORE_BUILD)
    find_library(KOSMICKRISP_FRAMEWORK
        NAMES KosmicKrisp
        PATHS ${CMAKE_FRAMEWORK_PATH}
        NO_DEFAULT_PATH
    )
    target_link_frameworks(Wawona PRIVATE ${KOSMICKRISP_FRAMEWORK})
endif()
```

### Makefile Updates

```makefile
# App Store build target
app-store-build: kosmickrisp-framework wayland-static
	@echo "Building for App Store..."
	cmake -B build-appstore \
		-DAPP_STORE_BUILD=ON \
		-DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build build-appstore
	codesign --sign "Developer ID" build-appstore/Wawona.app
```

## Testing App Store Compliance

### 1. Check for .dylibs

```bash
find Wawona.app -name "*.dylib"
# Should return nothing
```

### 2. Check Frameworks

```bash
find Wawona.app -name "*.framework"
# Should list all frameworks
```

### 3. Verify Static Linking

```bash
otool -L Wawona.app/Contents/MacOS/Wawona
# Should only show system frameworks
```

### 4. Test Sandboxing

```bash
# Run with sandbox enabled
sandbox-exec -f sandbox.sb Wawona.app/Contents/MacOS/Wawona
```

## Migration Checklist

- [ ] Convert KosmicKrisp to framework
- [ ] Update Makefile build targets
- [ ] Update CMakeLists.txt for static linking
- [ ] Build all dependencies statically
- [ ] Create proper app bundle structure
- [ ] Set up code signing
- [ ] Create entitlements file
- [ ] Test App Store compliance
- [ ] Update documentation
- [ ] Test on clean system

## Resources

- [Apple App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/)

## Notes

- **Framework vs Static Library**: Frameworks are preferred for App Store
- **Sandbox Restrictions**: May need to adjust for Wayland socket access
- **Entitlements**: May need additional entitlements for specific features
- **Testing**: Test thoroughly before App Store submission

