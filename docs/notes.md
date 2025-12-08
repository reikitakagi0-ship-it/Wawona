# Dependency Patching Notes

This document outlines future patching work needed for libwayland, waypipe-rs, and mesa-kosmickrisp to support iOS, macOS, and Android platforms.

## Table of Contents

1. [libwayland Patches](#libwayland-patches)
2. [waypipe-rs Patches](#waypipe-rs-patches)
3. [mesa-kosmickrisp Patches](#mesa-kosmickrisp-patches)
4. [Upstream Status](#upstream-status)

---

## libwayland Patches

### Android: Remove Linux-specific syscalls

**File**: `dependencies/patches/wayland/android-remove-linux-syscalls.patch`

**Status**: Placeholder (contains reference documentation)

**Issue**: Android's Bionic libc lacks `signalfd` and `timerfd` syscalls that are used by libwayland's event loop. These syscalls are Linux-specific and not available in Bionic.

**Reference**: Pekka Paalanen's 2012 blog post about porting Weston to Android mentions:
> "I also had to completely remove signal handling and timers from libwayland, because signalfd and timerfd interfaces do not exist in Bionic. Those need to be reinvented still."

**Action Required**:
- Investigate current libwayland source code (`src/event-loop.c`) for `signalfd` and `timerfd` usage
- Check if upstream has addressed this (as of Dec 2024, no upstream fixes found)
- Create patches to:
  - Replace `signalfd` with alternative signal handling (possibly using `sigaction` + `pipe` or `socketpair`)
  - Replace `timerfd` with alternative timer mechanism (possibly using `setitimer` or `alarm` + `pipe`)
  - Ensure event loop still functions correctly without these syscalls

**Current Implementation**: Not applied - `patches = []` in `dependencies/deps/libwayland/android.nix`

---

### Android: Mark scanner as native

**File**: `dependencies/patches/wayland/android-mark-scanner-native.patch`

**Status**: Has patch content but NOT applied (redundant with `postPatch`)

**Patch Content**:
```patch
--- a/src/meson.build
+++ b/src/meson.build
@@ -56,6 +56,7 @@ wayland_scanner = executable(
 	'wayland-scanner',
 	wayland_scanner_sources,
 	c_args: scanner_args,
 	include_directories: wayland_scanner_includes,
 	dependencies: [ scanner_deps, wayland_util_dep, ],
+	native: true,
 	install: true
 )
```

**Current Implementation**: Handled via `postPatch` Python script in `dependencies/deps/libwayland/android.nix` which:
- Marks scanner dependencies as `native: true`
- Creates `wayland_util_native` static library
- Creates `wayland_util_dep_native` dependency
- Updates `wayland_scanner` to use native dependencies and sets `native: true`
- Sets `install: false` for `wayland_scanner`

**Action Required**: This patch is redundant and can be removed - the `postPatch` implementation is more comprehensive.

---

### Android: Skip scanner dependency check

**File**: `dependencies/patches/wayland/android-skip-scanner-dependency.patch`

**Status**: Has patch content but NOT applied (redundant with `postPatch`)

**Patch Content**:
```patch
--- a/src/meson.build
+++ b/src/meson.build
@@ -80,8 +80,8 @@ if get_option('scanner')
 endif
 
 scanner_dep = dependency('wayland-scanner', native: true, required: false)
-if not scanner_dep.found()
-	error('wayland-scanner is required but not found')
+if not scanner_dep.found() and false
+	error('wayland-scanner is required but not found')
 endif
```

**Current Implementation**: Handled via `postPatch` - the scanner is built internally, so this check is bypassed.

**Action Required**: This patch is redundant and can be removed - the `postPatch` implementation handles scanner building internally.

---

### iOS: Remove Linux-specific syscalls

**File**: `dependencies/patches/wayland/ios-remove-linux-syscalls.patch`

**Status**: Placeholder

**Issue**: iOS (Darwin) doesn't support `signalfd`, `timerfd`, and other Linux-specific syscalls. Similar to Android, these need to be replaced with Darwin-compatible alternatives.

**Action Required**:
- Same investigation as Android syscall removal
- Use `kqueue` or `epoll-shim` for event loop on iOS
- Replace `signalfd`/`timerfd` with Darwin-compatible mechanisms
- Consider using `epoll-shim` library which provides epoll compatibility on Darwin

**Current Implementation**: Not applied - `patches = []` in `dependencies/deps/libwayland/ios.nix`

---

### macOS: epoll-shim integration

**File**: `dependencies/patches/wayland/macos-epoll-shim.patch`

**Status**: Placeholder

**Issue**: macOS doesn't have `epoll`, but `epoll-shim` provides a compatible interface using `kqueue`.

**Action Required**:
- Add `epoll-shim` as a build dependency for macOS
- Patch `#include <sys/epoll.h>` to `#include <epoll-shim/epoll.h>` where needed
- Ensure event loop uses epoll-shim on macOS
- Alternatively, use `postPatch` with `substituteInPlace` instead of a patch file

**Current Implementation**: Not applied - `patches = []` in `dependencies/deps/libwayland/macos.nix`

**Note**: The placeholder suggests using `postPatch` instead of a patch file for simple substitutions.

---

## waypipe-rs Patches

### Android: gralloc/DMA-BUF support

**File**: `dependencies/patches/waypipe/android-gralloc-support.patch`

**Status**: Placeholder

**Issue**: Android supports DMA-BUF via gralloc buffers. waypipe needs to properly integrate with Android's gralloc system for buffer sharing.

**Action Required**:
- Investigate waypipe-rs source for DMA-BUF/gralloc integration points
- Ensure waypipe properly detects and uses Android's gralloc system
- May need to add Android-specific build flags or feature gates

**Current Implementation**: Not applied - waypipe builds use Cargo flags but no patches

---

### iOS: Disable Linux GPU paths

**File**: `dependencies/patches/waypipe/ios-disable-linux-gpu.patch`

**Status**: Placeholder

**Issue**: iOS doesn't support Linux DMA-BUF or libgbm. waypipe should fall back to shared-memory or Vulkan/Metal.

**Action Required**:
- Use Meson/Cargo build flags: `-Ddmabuf=false -Dvaapi=false`
- Patch code paths that check for these features to ensure proper fallback
- Ensure waypipe uses Vulkan/Metal via KosmicKrisp on iOS

**Current Implementation**: Not applied - waypipe builds use Cargo target flags but no patches

---

### iOS: KosmicKrisp Vulkan integration

**File**: `dependencies/patches/waypipe/ios-kosmickrisp-vulkan.patch`

**Status**: Placeholder

**Issue**: waypipe-rs needs to properly detect and use the KosmicKrisp Vulkan driver on iOS.

**Action Required**:
- Set `VK_ICD_FILENAMES` to point to KosmicKrisp ICD
- Ensure Vulkan loader finds the KosmicKrisp `.dylib`
- Configure waypipe to use Vulkan features available in KosmicKrisp
- May need runtime environment variable setup or build-time configuration

**Current Implementation**: Not applied

---

### macOS: Disable Linux GPU paths

**File**: `dependencies/patches/waypipe/macos-disable-linux-gpu.patch`

**Status**: Placeholder

**Issue**: Similar to iOS - macOS doesn't support Linux DMA-BUF or libgbm. waypipe should use Vulkan/Metal fallback via Kosmickrisp.

**Action Required**:
- Same as iOS disable Linux GPU paths
- May need macOS-specific adjustments for Vulkan-on-Metal integration

**Current Implementation**: Not applied

---

### macOS: KosmicKrisp Vulkan integration

**File**: `dependencies/patches/waypipe/macos-kosmickrisp-vulkan.patch`

**Status**: Placeholder

**Issue**: waypipe-rs needs to properly detect and use the KosmicKrisp Vulkan driver on macOS.

**Action Required**:
- Set `VK_ICD_FILENAMES` to point to KosmicKrisp ICD
- Ensure Vulkan loader finds the KosmicKrisp `.dylib`
- Set `DYLD_LIBRARY_PATH` or use rpath to find KosmicKrisp library
- Configure waypipe to use Vulkan features available in KosmicKrisp

**Current Implementation**: Not applied

---

## mesa-kosmickrisp Patches

### iOS: Metal integration

**File**: `dependencies/patches/kosmickrisp-vulkan/ios-metal-integration.patch`

**Status**: Placeholder

**Issue**: Kosmickrisp-Vulkan needs iOS-specific Metal integration patches to work properly on iOS devices.

**Action Required**:
- Wait for Kosmickrisp repository to become available
- Investigate Metal backend integration requirements
- Create patches for iOS-specific Metal integration code

**Current Implementation**: Not applied - mesa-kosmickrisp builds exist but patches not implemented

---

### macOS: Metal integration

**File**: `dependencies/patches/kosmickrisp-vulkan/macos-metal-integration.patch`

**Status**: Placeholder

**Issue**: Kosmickrisp-Vulkan needs macOS-specific Metal integration patches to work properly on macOS.

**Action Required**:
- Wait for Kosmickrisp repository to become available
- Investigate Metal backend integration requirements
- Create patches for macOS-specific Metal integration code

**Current Implementation**: Not applied - mesa-kosmickrisp builds exist but patches not implemented

---

## Upstream Status

### libwayland syscall compatibility

**Status**: As of December 2024, upstream Wayland has NOT fixed syscall compatibility issues.

**Evidence**:
- GNU Hurd community discussions (October 2023) mention patches that remove `signalfd`/`timerfd` dependencies but also remove public APIs, making upstream acceptance unlikely
- No public information indicates these patches have been merged upstream
- The issue persists on non-Linux platforms (Android, iOS, macOS)

**Files to investigate**:
- `src/event-loop.c` - Contains `signalfd` and `timerfd` usage
- Check Wayland GitLab: https://gitlab.freedesktop.org/wayland/wayland

**Action Required**:
1. Clone wayland repository and check `src/event-loop.c` for current syscall usage
2. Check if there are any `#ifdef __linux__` guards around syscall usage
3. If no guards exist, patches will be needed for Android/iOS/macOS
4. Consider upstreaming platform-agnostic patches if possible

---

## Implementation Strategy

### Current Approach

All patches are currently handled via Nix `postPatch` hooks or build flags rather than patch files. This approach:
- Keeps patches inline with build logic
- Easier to maintain and understand
- Allows dynamic patching based on build context

### Future Work

1. ✅ **Investigate syscall usage**: Confirmed libwayland uses `signalfd`/`timerfd` in `src/event-loop.c` (based on research and upstream discussions)
2. ✅ **Create syscall compatibility patches**: Added `postPatch` hooks in all platform builds to remove/replace Linux syscalls
3. **Test on all platforms**: Ensure libwayland builds and runs correctly on iOS, macOS, and Android
4. **Upstream consideration**: If patches are platform-agnostic, consider upstreaming to Wayland project
5. **waypipe-rs integration**: Once libwayland is patched, ensure waypipe-rs works correctly with patched libwayland
6. **mesa-kosmickrisp integration**: Once Kosmickrisp repository is available, create Metal integration patches

### Implementation Status

**Syscall Compatibility Patches**: ✅ Implemented

All platform builds (`android.nix`, `ios.nix`, `macos.nix`) now include `postPatch` hooks that:
- Remove `signalfd` includes and calls (replaced with comments)
- Remove `timerfd` includes and calls (replaced with comments)
- Handle epoll compatibility on macOS using **epoll-shim** (see below)

**macOS epoll-shim Integration**: ✅ Implemented

Based on research (`docs/research-from-chatgpt-wayland-macos.md`):
- **epoll-shim is REQUIRED** for macOS Wayland builds
- MacPorts Wayland port explicitly depends on `epoll-shim`, `libffi`, and `libxml2`
- epoll-shim implements epoll on top of BSD's kqueue
- Successfully used to port Wayland to FreeBSD and macOS (tested on macOS 13.7.1)
- Implementation:
  - Uses `pkgs.epoll-shim` from nixpkgs (works on macOS)
  - Updated `postPatch` to replace `#include <sys/epoll.h>` with `#include <epoll-shim/epoll.h>`
  - Configure phase sets CFLAGS/LDFLAGS to include epoll-shim paths
  - Falls back gracefully if epoll-shim is not available

**iOS epoll-shim Integration**: ✅ Implemented

Cross-compiled epoll-shim for iOS using Xcode toolchains:
- Created `dependencies/deps/epoll-shim/ios.nix` for iOS cross-compilation
- Uses CMake with iOS toolchain file (same approach as expat/libffi/libxml2)
- Cross-compiles from macOS host to iOS target using Xcode SDK
- Implementation:
  - Fetches epoll-shim from GitHub (main branch)
  - Uses Xcode iOS toolchain (CMake iOS toolchain file)
  - Builds static library for iOS arm64
  - Integrated into iOS libwayland build as dependency
  - iOS libwayland updated to use epoll-shim (same as macOS)
  - `postPatch` replaces epoll includes with epoll-shim includes
  - Configure phase sets CFLAGS/LDFLAGS for epoll-shim paths

**Note**: Current builds use `-Dlibraries=false`, so only the scanner is built. The event loop (which contains syscall usage) is not compiled. These patches will be needed when enabling library builds (`-Dlibraries=true`).

**Patch Strategy**:
- Uses `substituteInPlace` to comment out syscall includes and calls
- Adds explanatory comments indicating platform-specific removals
- Patches are conditional - only applied if `src/event-loop.c` exists
- macOS: Integrates epoll-shim for epoll compatibility (critical for Wayland on macOS)
- Future work: Implement proper alternatives (e.g., `sigaction` + `pipe` for signals, `setitimer`/`alarm` for timers)

**Key Findings from macOS Research**:
- Wayland CAN be built on macOS with epoll-shim + libffi + libxml2
- Running a compositor requires custom Cocoa integration (like Owl compositor)
- Input handling must use Cocoa/NSEvents instead of libinput/evdev
- Graphics must use Cocoa/Metal instead of DRM/KMS

---

## References

- Pekka Paalanen's Android port blog: https://ppaalanen.blogspot.com/2012/04/first-light-from-weston-on-android.html
- Wayland GitLab: https://gitlab.freedesktop.org/wayland/wayland
- GNU Hurd discussion (Oct 2023): https://logs.guix.gnu.org/hurd/2023-10-09.log
- epoll-shim: Provides epoll compatibility on Darwin systems
