#!/bin/bash
# Build Weston compositor for macOS (nested Wayland backend)
# Weston will run nested within Wawona using the wayland backend

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WESTON_DIR="$PROJECT_ROOT/dependencies/weston"
WESTON_BUILD_DIR="$WESTON_DIR/build"
INSTALL_PREFIX="$PROJECT_ROOT/weston-install"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔨 Building Weston Compositor for macOS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check dependencies
echo -e "${YELLOW}ℹ${NC} Checking dependencies..."

if ! command -v meson &> /dev/null; then
    echo -e "${RED}✗${NC} meson not found. Install with: brew install meson"
    exit 1
fi

if ! command -v ninja &> /dev/null; then
    echo -e "${RED}✗${NC} ninja not found. Install with: brew install ninja"
    exit 1
fi

if ! pkg-config --exists wayland-client wayland-server; then
    echo -e "${RED}✗${NC} Wayland libraries not found. Install wayland first: make wayland"
    exit 1
fi

# Check for pixman
if ! pkg-config --exists pixman-1; then
    echo -e "${RED}✗${NC} pixman not found. Install with: brew install pixman"
    exit 1
fi

# Check for xkbcommon (required by Weston)
if ! pkg-config --exists xkbcommon; then
    echo -e "${RED}✗${NC} xkbcommon not found. Install with: make xkbcommon"
    exit 1
fi

# Setup PKG_CONFIG_PATH early to detect locally built dependencies
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# Check for locally built libinput BEFORE checking pkg-config
# This allows us to find libinput built via 'make libinput'
LIBINPUT_BUILD_PC="$PROJECT_ROOT/dependencies/libinput/build-macos/meson-private/libinput.pc"
if [ -f "$LIBINPUT_BUILD_PC" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/dependencies/libinput/build-macos/meson-private:$PKG_CONFIG_PATH"
    echo -e "${GREEN}✓${NC} Found locally built libinput (adding to PKG_CONFIG_PATH)"
fi

# Check for locally built xkbcommon
XKBCOMMON_BUILD_PC="$PROJECT_ROOT/dependencies/xkbcommon/build-macos/meson-private/xkbcommon.pc"
if [ -f "$XKBCOMMON_BUILD_PC" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/dependencies/xkbcommon/build-macos/meson-private:$PKG_CONFIG_PATH"
    echo -e "${GREEN}✓${NC} Found locally built xkbcommon (adding to PKG_CONFIG_PATH)"
fi

# Check for locally built libdisplay-info
LIBDISPLAY_INFO_BUILD_PC="$PROJECT_ROOT/libdisplay-info/build-macos/meson-private/libdisplay-info.pc"
if [ -f "$LIBDISPLAY_INFO_BUILD_PC" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/libdisplay-info/build-macos/meson-private:$PKG_CONFIG_PATH"
    echo -e "${GREEN}✓${NC} Found locally built libdisplay-info (adding to PKG_CONFIG_PATH)"
fi

# Check for locally built libdrm
LIBDRM_BUILD_PC="$PROJECT_ROOT/libdrm/build-macos/meson-private/libdrm.pc"
if [ -f "$LIBDRM_BUILD_PC" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/libdrm/build-macos/meson-private:$PKG_CONFIG_PATH"
    echo -e "${GREEN}✓${NC} Found locally built libdrm (adding to PKG_CONFIG_PATH)"
fi

# Check for locally built libevdev
LIBEVDEV_BUILD_PC="$PROJECT_ROOT/libevdev/build-macos/meson-private/libevdev.pc"
if [ -f "$LIBEVDEV_BUILD_PC" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/libevdev/build-macos/meson-private:$PKG_CONFIG_PATH"
    echo -e "${GREEN}✓${NC} Found locally built libevdev (adding to PKG_CONFIG_PATH)"
fi

# Check for locally built hwdata
HWDATA_BUILD_PC="$PROJECT_ROOT/hwdata/build-macos/meson-private/hwdata.pc"
if [ -f "$HWDATA_BUILD_PC" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/hwdata/build-macos/meson-private:$PKG_CONFIG_PATH"
    echo -e "${GREEN}✓${NC} Found locally built hwdata (adding to PKG_CONFIG_PATH)"
fi
# Also check for hwdata in common build locations
if [ -d "$PROJECT_ROOT/hwdata/build" ] && [ -f "$PROJECT_ROOT/hwdata/build/hwdata.pc" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/hwdata/build:$PKG_CONFIG_PATH"
    echo -e "${GREEN}✓${NC} Found locally built hwdata (adding to PKG_CONFIG_PATH)"
fi

# Check for libinput (required for compositor)
# Note: We check both pkg-config AND that headers actually exist
HAS_LIBINPUT=false
if pkg-config --exists libinput 2>/dev/null; then
    # Verify headers actually exist (pkg-config might find stub)
    # Check multiple possible locations for libinput.h
    LIBINPUT_INCLUDE=$(pkg-config --variable=includedir libinput 2>/dev/null || echo "")
    LIBINPUT_HEADER_FOUND=false
    
    # Check the include directory from pkg-config
    if [ -n "$LIBINPUT_INCLUDE" ] && [ -f "$LIBINPUT_INCLUDE/libinput.h" ]; then
        LIBINPUT_HEADER_FOUND=true
    fi
    
    # Also check common locations (libinput headers might be in src/ directory)
    if [ "$LIBINPUT_HEADER_FOUND" = false ]; then
        if [ -f "/opt/homebrew/include/libinput.h" ] || \
           [ -f "/usr/local/include/libinput.h" ] || \
           [ -f "$PROJECT_ROOT/dependencies/libinput/include/libinput.h" ] || \
           [ -f "$PROJECT_ROOT/dependencies/libinput/src/libinput.h" ] || \
           [ -f "$PROJECT_ROOT/dependencies/libinput/build-macos/include/libinput.h" ]; then
            LIBINPUT_HEADER_FOUND=true
        fi
    fi
    
    if [ "$LIBINPUT_HEADER_FOUND" = true ]; then
        HAS_LIBINPUT=true
        LIBINPUT_VERSION=$(pkg-config --modversion libinput 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} libinput found (version: $LIBINPUT_VERSION)"
    else
        echo -e "${YELLOW}⚠${NC} libinput pkg-config found but headers not available"
        echo -e "${YELLOW}ℹ${NC} Install with: make libinput"
    fi
else
    # Check if headers exist even if pkg-config doesn't find it
    if [ -f "$PROJECT_ROOT/dependencies/libinput/include/libinput.h" ] || \
       [ -f "$PROJECT_ROOT/dependencies/libinput/src/libinput.h" ] || \
       [ -f "$PROJECT_ROOT/dependencies/libinput/build-macos/include/libinput.h" ]; then
        HAS_LIBINPUT=true
        echo -e "${GREEN}✓${NC} libinput found (headers exist, but pkg-config not found - may need rebuild)"
    else
        echo -e "${YELLOW}⚠${NC} libinput not found - compositor may have limited functionality"
        echo -e "${YELLOW}ℹ${NC} Install with: make libinput"
    fi
fi

# Add macOS stubs to PKG_CONFIG_PATH BEFORE dependency verification
# This allows meson to find stubs for libevdev, libdrm, hwdata, libdisplay-info, etc.
# We add stubs AFTER checking for real libraries, so real ones take precedence
STUBS_DIR="$PROJECT_ROOT/dependencies/libinput-macos-stubs"
if [ -d "$STUBS_DIR" ]; then
    # Ensure all stub .pc files exist (create from -stub.pc if needed)
    STUB_PC_FILES=(
        "libevdev-stub.pc:libevdev.pc"
        "libdrm-stub.pc:libdrm.pc"
        "hwdata-stub.pc:hwdata.pc"
        "libdisplay-info.pc:libdisplay-info.pc"
    )
    
    for stub_pair in "${STUB_PC_FILES[@]}"; do
        stub_file="${stub_pair%%:*}"
        target_file="${stub_pair##*:}"
        if [ -f "$STUBS_DIR/$stub_file" ] && [ ! -f "$STUBS_DIR/$target_file" ]; then
            cp "$STUBS_DIR/$stub_file" "$STUBS_DIR/$target_file"
        fi
    done
    
    # Add stubs directory to PKG_CONFIG_PATH (at the end, so real libs take precedence)
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$STUBS_DIR"
    echo -e "${GREEN}✓${NC} Added macOS stubs directory to PKG_CONFIG_PATH (fallback)"
fi

# Check for EGL (optional but recommended)
# Note: wayland-egl is required for GL renderer with wayland backend
HAS_EGL=false
HAS_WAYLAND_EGL=false
if pkg-config --exists egl glesv2 2>/dev/null; then
    if pkg-config --exists wayland-egl 2>/dev/null; then
        HAS_EGL=true
        HAS_WAYLAND_EGL=true
        EGL_VERSION=$(pkg-config --modversion egl 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} EGL found (version: $EGL_VERSION)"
        echo -e "${GREEN}✓${NC} wayland-egl found (required for GL renderer)"
    else
        echo -e "${YELLOW}⚠${NC} EGL found but wayland-egl not found"
        echo -e "${YELLOW}⚠${NC} GL renderer will be disabled (wayland-egl required for wayland backend)"
        echo -e "${YELLOW}ℹ${NC} Install with: make kosmickrisp"
    fi
else
    echo -e "${YELLOW}⚠${NC} EGL not found - GL renderer will be disabled"
    echo -e "${YELLOW}ℹ${NC} Install with: make kosmickrisp"
fi

# Check for Vulkan (optional)
HAS_VULKAN=false
if pkg-config --exists vulkan 2>/dev/null && which glslangValidator >/dev/null 2>&1; then
    if [ -f "/opt/homebrew/lib/libvulkan_kosmickrisp.dylib" ] || \
       [ -f "/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json" ] || \
       [ -f "/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.x86_64.json" ]; then
        HAS_VULKAN=true
        echo -e "${GREEN}✓${NC} Vulkan support found (KosmicKrisp)"
    fi
fi

# Verify all required dependencies are found before continuing
echo ""
echo -e "${YELLOW}ℹ${NC} Verifying all dependencies..."
ALL_DEPS_OK=true

# Check required dependencies
REQUIRED_DEPS=(
    "wayland-server"
    "wayland-client"
    "pixman-1"
    "xkbcommon"
)

for dep in "${REQUIRED_DEPS[@]}"; do
    if ! pkg-config --exists "$dep" 2>/dev/null; then
        echo -e "${RED}✗${NC} Required dependency $dep not found"
        ALL_DEPS_OK=false
    else
        VERSION=$(pkg-config --modversion "$dep" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} $dep found (version: $VERSION)"
    fi
done

# Check dependencies that should be found (either real or stub)
# These are required for the compositor build, but stubs are acceptable
# Note: libdisplay-info will be built as a subproject by meson if not found
COMPOSITOR_DEPS=(
    "libinput"
    "libevdev"
    "libdrm"
    "hwdata"
)

for dep in "${COMPOSITOR_DEPS[@]}"; do
    if pkg-config --exists "$dep" 2>/dev/null; then
        VERSION=$(pkg-config --modversion "$dep" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} $dep found (version: $VERSION)"
    else
        echo -e "${RED}✗${NC} $dep not found (required for compositor)"
        ALL_DEPS_OK=false
    fi
done

# Check libdisplay-info separately (meson will build as subproject if not found)
if pkg-config --exists libdisplay-info 2>/dev/null; then
    VERSION=$(pkg-config --modversion libdisplay-info 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓${NC} libdisplay-info found (version: $VERSION)"
else
    echo -e "${YELLOW}ℹ${NC} libdisplay-info not found - meson will build as subproject"
fi

if [ "$ALL_DEPS_OK" != true ]; then
    echo ""
    echo -e "${RED}✗${NC} Some required dependencies are missing. Please install them before continuing."
    echo -e "${YELLOW}ℹ${NC} For macOS, stubs are acceptable - ensure libinput-macos-stubs directory exists"
    exit 1
fi

echo ""
echo -e "${GREEN}✓${NC} All dependencies OK (required + compositor dependencies)"
echo ""

# Clone Weston if needed
if [ ! -d "$WESTON_DIR" ]; then
    echo -e "${YELLOW}ℹ${NC} Cloning Weston repository..."
    cd "$PROJECT_ROOT"
    git clone https://gitlab.freedesktop.org/wayland/weston.git
    echo -e "${GREEN}✓${NC} Weston cloned"
else
    echo -e "${GREEN}✓${NC} Weston repository exists"
fi

# Update Weston
echo -e "${YELLOW}ℹ${NC} Updating Weston..."
cd "$WESTON_DIR"
# Stash local changes before pulling to avoid merge conflicts
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo -e "${YELLOW}ℹ${NC} Stashing local changes..."
    git stash push -m "Wawona local changes preserved by build-weston-compositor.sh" >/dev/null 2>&1 || true
    HAD_STASH=true
else
    HAD_STASH=false
fi
git pull || true
# Reapply stashed changes if any
if [ "$HAD_STASH" = true ]; then
    echo -e "${YELLOW}ℹ${NC} Reapplying local changes..."
    git stash pop >/dev/null 2>&1 || {
        echo -e "${YELLOW}⚠${NC} Some local changes may have conflicts - check manually if needed"
        git stash list | head -1 || true
    }
fi
echo ""

# Apply meson.build patches if needed (make libinput optional for macOS, libdrm header-only)
echo -e "${YELLOW}ℹ${NC} Checking meson.build patches..."
MESON_BUILD="$WESTON_DIR/meson.build"
LIBWESTON_MESON="$WESTON_DIR/libweston/meson.build"
# Always re-patch to ensure correct configuration
if [ -f "$MESON_BUILD" ]; then
    echo -e "${YELLOW}ℹ${NC} Applying meson.build patches for macOS compatibility..."
    python3 << PYTHON_SCRIPT
import sys
import re

meson_build = "$MESON_BUILD"
with open(meson_build, 'r') as f:
    content = f.read()

# Always apply patches (idempotent - safe to run multiple times)
# Add has_any_backend check before libinput dependency (if not already present)
libinput_pattern = r'(dep_xkbcommon = dependency\([^)]+\))\n(dep_libinput = dependency\([^)]+\))'
backend_check = "has_any_backend = get_option('backend-drm') or get_option('backend-headless') or get_option('backend-wayland') or get_option('backend-x11')"
replacement = r'\1\n\n# Patched for macOS compositor build\n' + backend_check + r'\n\2'
content = re.sub(libinput_pattern, replacement, content)

# Make libinput optional - wayland backend doesn't require it
# Only drm backend actually requires libinput
# Replace any existing libinput dependency (handles both patched and unpatched versions)
if "required: get_option('backend-drm')" not in content:
    content = re.sub(
        r"dep_libinput = dependency\('libinput', version: '>= 1\.2\.0', required: [^)]+\)",
        r"dep_libinput = dependency('libinput', version: '>= 1.2.0', required: get_option('backend-drm'))",
        content,
        count=1
    )

# Fix HAVE_COMPOSE_AND_KANA check
content = re.sub(
    r'if dep_xkbcommon\.version\(\)\.version_compare\([^)]+\)\s*\n\s*if dep_libinput\.version\(\)',
    r"if dep_xkbcommon.version().version_compare('>= 1.8.0')\n\tif dep_libinput.found() and dep_libinput.version()",
    content
)

# Make libevdev optional - wayland backend doesn't require it
# Only drm backend actually requires libevdev
# Fix any existing libevdev dependency line (handles both patched and unpatched versions)
if "required: get_option('backend-drm')" not in content:
    # Match the dependency line and replace it
    content = re.sub(
        r"dep_libevdev = dependency\('libevdev', required: [^)]+\)",
        r"dep_libevdev = dependency('libevdev', required: get_option('backend-drm'))",
        content,
        count=1
    )

# Fix libdrm handling for macOS - make it optional and header-only
# Make libdrm optional - only required for drm backend
# Fix any existing libdrm dependency line (handles both patched and unpatched versions)
if "required: get_option('backend-drm')" not in content:
    # Match the dependency line - be careful with parentheses
    libdrm_pattern = r"dep_libdrm = dependency\('libdrm', version: '>= 2\.4\.108', required: [^)]+\)"
    content = re.sub(
        libdrm_pattern,
        r"dep_libdrm = dependency('libdrm', version: '>= 2.4.108', required: get_option('backend-drm'))",
        content,
        count=1
    )

# Replace the condition to always use header-only on macOS (even when wayland backend is enabled)
old_libdrm_condition = "if host_machine.system() == 'darwin' and not has_any_backend"
new_libdrm_condition = "if host_machine.system() == 'darwin'"
if old_libdrm_condition in content:
    content = content.replace(
        old_libdrm_condition,
        new_libdrm_condition + "  # Patched for macOS compositor: always use header-only libdrm"
    )

# Fix backend-default check - skip error when no backends enabled
backend_error_pattern = r"(if not get_option\('backend-' \+ backend_default\))\s*\n\s*(error\([^)]+\))\s*\n\s*(endif)"
backend_error_replacement = r'\1\n\tif has_any_backend\n\t\t\2\n\tendif\n\3'
content = re.sub(backend_error_pattern, backend_error_replacement, content)

with open(meson_build, 'w') as f:
    f.write(content)

print("Patched meson.build")
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Patched meson.build"
    else
        echo -e "${YELLOW}⚠${NC} Python patching failed, continuing anyway..."
    fi
else
    echo -e "${GREEN}✓${NC} meson.build already patched"
fi

# Also patch libweston/meson.build to use header-only libdrm and fix libinput includes (always re-patch)
if [ -f "$LIBWESTON_MESON" ]; then
    echo -e "${YELLOW}ℹ${NC} Patching libweston/meson.build for header-only libdrm and libinput includes..."
    python3 << PYTHON_SCRIPT
import sys
import re
import os

meson_build = "$LIBWESTON_MESON"
project_root = "$PROJECT_ROOT"
with open(meson_build, 'r') as f:
    content = f.read()

# Always apply patches (idempotent)
# Replace dep_libdrm in deps_libweston with dep_libdrm_headers (header-only)
# This prevents linking against libdrm library on macOS
deps_pattern = r'(deps_libweston = \[)\s*\n\s*(dep_wayland_server,\s*\n\s*dep_pixman,\s*\n\s*dep_libm,\s*\n\s*dep_libdl,\s*\n\s*)dep_libdrm,'
deps_replacement = r'\1\n\t\2dep_libdrm_headers,  # Patched for macOS compositor: use header-only libdrm'
content = re.sub(deps_pattern, deps_replacement, content)

# Fix libinput include directories - add src directory if libinput is built locally
# Check if libinput headers are in src/ directory (common for local builds)
libinput_src_header = os.path.join(project_root, "libinput", "src", "libinput.h")
if os.path.exists(libinput_src_header):
    # Find all instances of include_directories: common_inc, and add libinput src directory
    # Pattern: match include_directories: common_inc, (with optional trailing comment)
    # Replace with include_directories: common_inc + [include_directories('../../libinput/src')],
    # Only patch if not already patched (check for the libinput/src include)
    if "include_directories('../../libinput/src')" not in content:
        # Replace all instances of include_directories: common_inc, (with optional comment on same line)
        # Use regex to handle comments on same line
        import re
        pattern = r'(\tinclude_directories: common_inc,)(\s*#.*)?\n'
        replacement = r'\1 + [include_directories(\'../../libinput/src\')],\n\t# Patched for macOS: add libinput src directory\n'
        content = re.sub(pattern, replacement, content)

with open(meson_build, 'w') as f:
    f.write(content)

print("Patched libweston/meson.build")
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Patched libweston/meson.build"
    else
        echo -e "${YELLOW}⚠${NC} Python patching failed for libweston/meson.build, continuing anyway..."
    fi
else
    echo -e "${GREEN}✓${NC} libweston/meson.build already patched"
fi

# Patch source files that need linux/input.h compatibility
echo -e "${YELLOW}ℹ${NC} Patching source files for macOS compatibility..."
FILES_TO_PATCH=(
    "frontend/main.c"
    "kiosk-shell/kiosk-shell.c"
    "libweston/backend-wayland/wayland.c"
    "shared/client-buffer-util.c"
    "desktop-shell/shell.c"
)

# Find and patch all files that include linux/input.h
echo -e "${YELLOW}ℹ${NC} Finding files that need linux/input.h compatibility..."
LINUX_INPUT_FILES=$(find "$WESTON_DIR" -name "*.c" -type f -exec grep -l "#include.*linux/input.h" {} \; 2>/dev/null | grep -v "linux-input-compat.h" || true)

# Add explicit files to patch list
for file_path in "${FILES_TO_PATCH[@]}"; do
    FILE="$WESTON_DIR/$file_path"
    if [ -f "$FILE" ]; then
        # Fix #ifdef HAVE_LIBINPUT to #if HAVE_LIBINPUT (checks value, not just definition)
        if grep -q "#ifdef HAVE_LIBINPUT" "$FILE" 2>/dev/null; then
            sed -i '' 's/#ifdef HAVE_LIBINPUT/#if HAVE_LIBINPUT/g' "$FILE"
        fi
        # Replace linux/input.h with compatibility header on macOS
        if grep -q "#include.*linux/input.h" "$FILE" 2>/dev/null && ! grep -q "linux-input-compat.h" "$FILE" 2>/dev/null; then
            python3 << PYTHON_SCRIPT
import re

file_path = "$FILE"
with open(file_path, 'r') as f:
    content = f.read()

        # Replace linux/input.h include with conditional
        if '#include <linux/input.h>' in content:
            # Use regex to handle both quoted and angle bracket includes
            import re
            # Match #include <linux/input.h> or #include "linux/input.h"
            pattern = r'#include\s+[<"]linux/input\.h[>"]'
            replacement = '''#ifdef __APPLE__
#include "linux-input-compat.h"
#else
#include <linux/input.h>
#endif'''
            content = re.sub(pattern, replacement, content)
        # Replace linux/dma-buf.h include with conditional (macOS compatibility)
        if '#include <linux/dma-buf.h>' in content:
            content = content.replace(
                '#include <linux/dma-buf.h>',
                '''#ifdef __APPLE__
// macOS compatibility: dma-buf is Linux-specific, provide minimal stub
// This file is only used for dmabuf buffer handling which may not work on macOS
#else
#include <linux/dma-buf.h>
#endif'''
            )
        # Replace linux/udmabuf.h include with conditional (macOS compatibility)
        if '#include <linux/udmabuf.h>' in content:
            content = content.replace(
                '#include <linux/udmabuf.h>',
                '''#ifdef __APPLE__
// macOS compatibility: udmabuf is Linux-specific
#else
#include <linux/udmabuf.h>
#endif'''
            )
        if '#include <linux/input.h>' in content or '#include <linux/dma-buf.h>' in content or '#include <linux/udmabuf.h>' in content:
            with open(file_path, 'w') as f:
                f.write(content)
            print(f"Patched {file_path}")
PYTHON_SCRIPT
        fi
    fi
done

# Also patch any other files found that include linux/input.h
for FILE in $LINUX_INPUT_FILES; do
    if [ -f "$FILE" ] && ! grep -q "linux-input-compat.h" "$FILE" 2>/dev/null; then
        python3 << PYTHON_SCRIPT
import re

file_path = "$FILE"
with open(file_path, 'r') as f:
    content = f.read()

# Replace linux/input.h include with conditional
if re.search(r'#include\s+[<"]linux/input\.h[>"]', content):
    # Match #include <linux/input.h> or #include "linux/input.h"
    pattern = r'#include\s+[<"]linux/input\.h[>"]'
    replacement = '''#ifdef __APPLE__
#include "linux-input-compat.h"
#else
#include <linux/input.h>
#endif'''
    content = re.sub(pattern, replacement, content)
    
    with open(file_path, 'w') as f:
        f.write(content)
    print(f"Patched {file_path}")
PYTHON_SCRIPT
    fi
done

# Fix configure_input_device usage in main.c
MAIN_C="$WESTON_DIR/frontend/main.c"
if [ -f "$MAIN_C" ] && grep -q "config.configure_device = configure_input_device;" "$MAIN_C" 2>/dev/null && ! grep -q "#if HAVE_LIBINPUT" "$MAIN_C" 2>/dev/null | grep -A2 "configure_device"; then
    sed -i '' 's/config\.configure_device = configure_input_device;/#if HAVE_LIBINPUT\n\tconfig.configure_device = configure_input_device;\n#else\n\tconfig.configure_device = NULL;\n#endif/' "$MAIN_C"
fi

# Fix CLOCK_MONOTONIC_COARSE compatibility (not available on macOS)
BACKEND_H="$WESTON_DIR/libweston/backend.h"
if [ -f "$BACKEND_H" ] && grep -q "CLOCK_MONOTONIC_COARSE" "$BACKEND_H" 2>/dev/null && ! grep -q "#ifdef __APPLE__" "$BACKEND_H" 2>/dev/null | grep -A2 "CLOCK_MONOTONIC_COARSE"; then
    # Add compatibility definition for CLOCK_MONOTONIC_COARSE on macOS
    python3 << PYTHON_SCRIPT
import re

file_path = "$BACKEND_H"
with open(file_path, 'r') as f:
    content = f.read()

# Add CLOCK_MONOTONIC_COARSE definition before WESTON_PRESENTATION_CLOCKS_SOFTWARE
if 'WESTON_PRESENTATION_CLOCKS_SOFTWARE' in content and 'CLOCK_MONOTONIC_COARSE' in content:
    # Add compatibility definition before the macro
    pattern = r'(#define WESTON_PRESENTATION_CLOCKS_SOFTWARE)'
    replacement = r'''#ifdef __APPLE__
#ifndef CLOCK_MONOTONIC_COARSE
#define CLOCK_MONOTONIC_COARSE CLOCK_MONOTONIC  // macOS compatibility: use CLOCK_MONOTONIC as fallback
#endif
#endif
\1'''
    content = re.sub(pattern, replacement, content, count=1)
    
    with open(file_path, 'w') as f:
        f.write(content)
    print(f"Patched {file_path} for CLOCK_MONOTONIC_COARSE compatibility")
PYTHON_SCRIPT
fi

echo -e "${GREEN}✓${NC} Source files patched"
echo ""

# Add wayland-protocols build directory to PKG_CONFIG_PATH if it exists
if [ -d "$PROJECT_ROOT/wayland-protocols/build" ] && [ -f "$PROJECT_ROOT/wayland-protocols/build/wayland-protocols.pc" ]; then
    export PKG_CONFIG_PATH="$PROJECT_ROOT/wayland-protocols/build:$PKG_CONFIG_PATH"
fi

# Link libdisplay-info headers from subproject to stubs directory for include path
if [ -d "$WESTON_DIR/subprojects/display-info/include/libdisplay-info" ] && [ ! -e "$PROJECT_ROOT/libinput-macos-stubs/libdisplay-info" ]; then
    ln -sf "$WESTON_DIR/subprojects/display-info/include/libdisplay-info" "$PROJECT_ROOT/dependencies/libinput-macos-stubs/libdisplay-info"
    echo -e "${GREEN}✓${NC} Linked libdisplay-info headers from subproject"
fi

# Add macOS stubs to PKG_CONFIG_PATH as fallback for missing dependencies
# This allows meson to find stubs for libevdev, libdrm, hwdata, libdisplay-info, etc.
# We add stubs AFTER checking for real libraries, so real ones take precedence
STUBS_DIR="$PROJECT_ROOT/dependencies/libinput-macos-stubs"
if [ -d "$STUBS_DIR" ]; then
    # Ensure all stub .pc files exist (create from -stub.pc if needed)
    STUB_PC_FILES=(
        "libevdev-stub.pc:libevdev.pc"
        "libdrm-stub.pc:libdrm.pc"
        "hwdata-stub.pc:hwdata.pc"
        "libdisplay-info.pc:libdisplay-info.pc"  # Already created above
    )
    
    for stub_pair in "${STUB_PC_FILES[@]}"; do
        stub_file="${stub_pair%%:*}"
        target_file="${stub_pair##*:}"
        if [ -f "$STUBS_DIR/$stub_file" ] && [ ! -f "$STUBS_DIR/$target_file" ]; then
            cp "$STUBS_DIR/$stub_file" "$STUBS_DIR/$target_file"
        fi
    done
    
    # Add stubs directory to PKG_CONFIG_PATH (at the end, so real libs take precedence)
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$STUBS_DIR"
    echo -e "${GREEN}✓${NC} Added macOS stubs directory to PKG_CONFIG_PATH (fallback)"
fi

# Create build directory
mkdir -p "$WESTON_BUILD_DIR"
cd "$WESTON_BUILD_DIR"

# Configure Weston build for macOS compositor
echo -e "${YELLOW}ℹ${NC} Configuring Weston compositor build..."
echo -e "${YELLOW}ℹ${NC} Install prefix: ${INSTALL_PREFIX}"

MESON_OPTS=(
    "--prefix=$INSTALL_PREFIX"
    "--buildtype=release"
    "-Dwarning_level=3"
    "-Dwerror=true"  # Treat warnings as errors
    # macOS-specific: Disable weak linking for EGL libraries
    "-Dc_link_args=-Wl,-no_weak_imports -Wl,-weak_reference_mismatches,non-weak"
    # Enable wayland backend (nested compositor - runs within Wawona)
    "-Dbackend-wayland=true"
    # Set default backend to wayland (since we're disabling drm)
    "-Dbackend-default=wayland"
    # Disable Linux-specific backends
    "-Dbackend-drm=false"
    "-Dbackend-x11=false"
    "-Dbackend-vnc=false"
    "-Dbackend-rdp=false"
    "-Dbackend-pipewire=false"
    "-Dbackend-headless=false"  # Can enable if needed for headless testing
    # Enable shells (desktop shell for full compositor experience)
    # Note: shell-desktop may require libinput, but we'll try to build anyway
    "-Dshell-desktop=$HAS_LIBINPUT"  # Only enable if libinput is available
    "-Dshell-kiosk=true"
    "-Dshell-ivi=false"  # IVI shell not needed for desktop use
    "-Dshell-lua=false"  # Lua shell not needed
    "-Ddeprecated-shell-fullscreen=false"  # Deprecated, use shell-kiosk instead
    # Disable Linux-specific features
    "-Dxwayland=false"
    "-Dsystemd=false"
    "-Dremoting=false"
    "-Dpipewire=false"
    "-Dtests=false"
    # Enable renderers
    # Note: wayland-egl is required for GL renderer with wayland backend
    "-Drenderer-gl=$HAS_WAYLAND_EGL"
    "-Drenderer-vulkan=$HAS_VULKAN"
    # Enable clients and tools
    "-Ddemo-clients=true"
    "-Dsimple-clients=damage,egl,im,shm,touch"
    "-Dtools=calibrator,debug,terminal,touch-calibrator"
)

if [ "$HAS_EGL" = true ] && [ "$HAS_WAYLAND_EGL" = true ]; then
    echo -e "${GREEN}✓${NC} GL renderer enabled"
else
    echo -e "${YELLOW}⚠${NC} GL renderer disabled (wayland-egl required for wayland backend)"
fi

if [ "$HAS_VULKAN" = true ]; then
    echo -e "${GREEN}✓${NC} Vulkan renderer enabled"
else
    echo -e "${YELLOW}⚠${NC} Vulkan renderer disabled"
fi

# Run meson setup
if [ ! -f "build.ninja" ]; then
    meson setup . .. "${MESON_OPTS[@]}"
else
    meson configure . "${MESON_OPTS[@]}"
fi

echo -e "${GREEN}✓${NC} Configuration complete"
echo ""

# Build
echo -e "${YELLOW}ℹ${NC} Building Weston compositor..."
CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")
ninja -j$CORES
echo -e "${GREEN}✓${NC} Build complete"
echo ""

# Install
echo -e "${YELLOW}ℹ${NC} Installing Weston compositor..."
ninja install
echo -e "${GREEN}✓${NC} Installation complete"
echo ""

# Fix runtime library paths for libinput
# libinput is built locally and needs to be accessible at runtime
if [ -f "$PROJECT_ROOT/dependencies/libinput/build-macos/liblibinput.dylib" ]; then
    echo -e "${YELLOW}ℹ${NC} Fixing libinput library paths..."
    
    # Copy libinput library to install directory if not already there
    LIBINPUT_INSTALL_LIB="$INSTALL_PREFIX/lib"
    if [ ! -f "$LIBINPUT_INSTALL_LIB/liblibinput.dylib" ]; then
        cp "$PROJECT_ROOT/libinput/build-macos/liblibinput.dylib" "$LIBINPUT_INSTALL_LIB/"
        echo -e "${GREEN}✓${NC} Copied libinput library to install directory"
    fi
    
    # Create versioned symlinks (liblibinput.10.dylib is what binaries expect)
    if [ ! -f "$LIBINPUT_INSTALL_LIB/liblibinput.10.dylib" ]; then
        ln -sf "liblibinput.dylib" "$LIBINPUT_INSTALL_LIB/liblibinput.10.dylib"
    fi
    # Also create versioned symlink based on actual version
    LIBINPUT_VERSION=$(pkg-config --modversion libinput 2>/dev/null | cut -d. -f1-2 || echo "1.29")
    if [ ! -f "$LIBINPUT_INSTALL_LIB/liblibinput.$LIBINPUT_VERSION.dylib" ]; then
        ln -sf "liblibinput.dylib" "$LIBINPUT_INSTALL_LIB/liblibinput.$LIBINPUT_VERSION.dylib"
    fi
    
    # Update install names in binaries to use @rpath
    find "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/lib" -type f \( -perm +111 -o -name "*.dylib" \) -exec sh -c '
        file "{}" 2>/dev/null | grep -q "Mach-O" || exit 0
        # Change absolute paths to @rpath for liblibinput
        install_name_tool -change "$PROJECT_ROOT/dependencies/libinput/build-macos/liblibinput.10.dylib" "@rpath/liblibinput.10.dylib" "{}" 2>/dev/null || true
        install_name_tool -change "$PROJECT_ROOT/dependencies/libinput/build-macos/liblibinput.dylib" "@rpath/liblibinput.dylib" "{}" 2>/dev/null || true
    ' \;
    
    # Update install names and rpaths in installed binaries and libraries
    # Change @rpath/liblibinput.10.dylib to point to the copied library
    find "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/lib" -type f \( -perm +111 -o -name "*.dylib" \) -exec sh -c '
        file "{}" 2>/dev/null | grep -q "Mach-O" || exit 0
        # Add rpath to find libinput in install directory
        install_name_tool -add_rpath "@loader_path/../lib" "{}" 2>/dev/null || true
        install_name_tool -add_rpath "@executable_path/../lib" "{}" 2>/dev/null || true
        # Change absolute paths to @rpath
        install_name_tool -change "$PROJECT_ROOT/dependencies/libinput/build-macos/liblibinput.10.dylib" "@rpath/liblibinput.10.dylib" "{}" 2>/dev/null || true
        install_name_tool -change "$PROJECT_ROOT/dependencies/libinput/build-macos/liblibinput.dylib" "@rpath/liblibinput.dylib" "{}" 2>/dev/null || true
    ' \;
    echo -e "${GREEN}✓${NC} Updated rpath and install names in installed binaries and libraries"
fi
echo ""

# Verify installation
WESTON_BIN="$INSTALL_PREFIX/bin/weston"
if [ -f "$WESTON_BIN" ]; then
    BINARY_SIZE=$(du -h "$WESTON_BIN" | cut -f1)
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓${NC} Weston compositor built successfully!"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}ℹ${NC} Binary: $WESTON_BIN ($BINARY_SIZE)"
    echo -e "${YELLOW}ℹ${NC} Install prefix: $INSTALL_PREFIX"
    echo ""
    echo -e "${YELLOW}ℹ${NC} To run Weston nested within Wawona:"
    echo -e "${GREEN}  ${NC}1. Start Wawona compositor: ${GREEN}make compositor${NC}"
    echo -e "${GREEN}  ${NC}2. Run Weston: ${GREEN}$WESTON_BIN${NC}"
    echo ""
else
    echo -e "${RED}✗${NC} Weston binary not found at $WESTON_BIN"
    exit 1
fi

