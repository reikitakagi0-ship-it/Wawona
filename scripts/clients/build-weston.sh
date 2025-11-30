#!/bin/bash
# Build Weston demo clients for macOS
# Weston provides essential test clients for compositor development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WESTON_DIR="$PROJECT_ROOT/weston"
WESTON_BUILD_DIR="$WESTON_DIR/build"
WESTON_INSTALL_DIR="$PROJECT_ROOT/test-clients/weston"
INSTALL_PREFIX="$PROJECT_ROOT/test-clients/weston"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔨 Building Weston Demo Clients${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
    echo -e "${RED}✗${NC} Wayland libraries not found. Install wayland first."
    exit 1
fi

# Check for EGL (optional but recommended)
HAS_EGL=false
if pkg-config --exists egl; then
    HAS_EGL=true
    echo -e "${GREEN}✓${NC} EGL found"
else
    echo -e "${YELLOW}⚠${NC} EGL not found (some clients will be skipped)"
fi

# Check for pixman
if ! pkg-config --exists pixman-1; then
    echo -e "${RED}✗${NC} pixman not found. Install with: brew install pixman"
    exit 1
fi

# Check for xkbcommon (required by Weston)
if ! pkg-config --exists xkbcommon; then
    echo -e "${YELLOW}⚠${NC} xkbcommon not found. Weston build will be skipped."
    echo -e "${YELLOW}ℹ${NC} Install with: make xkbcommon"
    echo -e "${YELLOW}ℹ${NC} Minimal clients and debug tools will still be built."
    exit 0
fi

    # Add wayland-protocols build directory to PKG_CONFIG_PATH if it exists
    if [ -d "$PROJECT_ROOT/wayland-protocols/build" ] && [ -f "$PROJECT_ROOT/wayland-protocols/build/wayland-protocols.pc" ]; then
        export PKG_CONFIG_PATH="$PROJECT_ROOT/wayland-protocols/build:$PKG_CONFIG_PATH"
        echo -e "${GREEN}✓${NC} wayland-protocols found (local build)"
    fi
    
    # Pre-build libdisplay-info subproject so its pkg-config file is available
    # This allows Meson to find it during configuration instead of rebuilding
    DISPLAY_INFO_DIR="$WESTON_DIR/subprojects/display-info"
    DISPLAY_INFO_BUILD_DIR="$WESTON_DIR/subprojects/display-info/build"
    
    if [ -d "$DISPLAY_INFO_DIR" ]; then
        # Build display-info subproject if not already built
        if [ ! -f "$DISPLAY_INFO_BUILD_DIR/meson-private/libdisplay-info.pc" ]; then
            echo -e "${YELLOW}ℹ${NC} Pre-building libdisplay-info subproject..."
            mkdir -p "$DISPLAY_INFO_BUILD_DIR"
            cd "$DISPLAY_INFO_BUILD_DIR"
            
            # Configure display-info
            meson setup . .. \
                --prefix="$INSTALL_PREFIX" \
                --buildtype=release \
                -Dwerror=true 2>&1 | grep -E "(Project|Found|Run-time|ERROR)" || true
            
            # Build display-info
            ninja 2>&1 | grep -E "(Linking|ERROR)" || true
            
            cd "$PROJECT_ROOT"
        fi
        
        # Patch libdisplay-info.pc to point to build directory instead of install prefix
        DISPLAY_INFO_PC="$DISPLAY_INFO_BUILD_DIR/meson-private/libdisplay-info.pc"
        if [ -f "$DISPLAY_INFO_PC" ]; then
            # Update the pkg-config file to point to the build directory
            if ! grep -q "^prefix=$DISPLAY_INFO_BUILD_DIR$" "$DISPLAY_INFO_PC" 2>/dev/null; then
                sed -i '' "s|^prefix=.*|prefix=$DISPLAY_INFO_BUILD_DIR|" "$DISPLAY_INFO_PC"
                sed -i '' "s|^includedir=.*|includedir=$DISPLAY_INFO_DIR/include|" "$DISPLAY_INFO_PC"
                sed -i '' "s|^libdir=.*|libdir=\${prefix}|" "$DISPLAY_INFO_PC"
                echo -e "${GREEN}✓${NC} Patched libdisplay-info.pc to point to build directory"
            fi
        fi
        
        # Add display-info pkg-config directory to PKG_CONFIG_PATH
        if [ -f "$DISPLAY_INFO_BUILD_DIR/meson-private/libdisplay-info.pc" ]; then
            export PKG_CONFIG_PATH="$DISPLAY_INFO_BUILD_DIR/meson-private:$PKG_CONFIG_PATH"
            echo -e "${GREEN}✓${NC} libdisplay-info pkg-config found"
        fi
    fi
    
    # Also check Weston build directory (from previous builds)
    WESTON_BUILD_DIR="$WESTON_DIR/build"
    if [ -d "$WESTON_BUILD_DIR/meson-private" ] && [ -f "$WESTON_BUILD_DIR/meson-private/libdisplay-info.pc" ]; then
        # Patch Weston's copy too if needed
        WESTON_DISPLAY_INFO_PC="$WESTON_BUILD_DIR/meson-private/libdisplay-info.pc"
        if [ -f "$WESTON_DISPLAY_INFO_PC" ] && [ -d "$DISPLAY_INFO_BUILD_DIR" ]; then
            if ! grep -q "^prefix=$DISPLAY_INFO_BUILD_DIR$" "$WESTON_DISPLAY_INFO_PC" 2>/dev/null; then
                sed -i '' "s|^prefix=.*|prefix=$DISPLAY_INFO_BUILD_DIR|" "$WESTON_DISPLAY_INFO_PC"
                sed -i '' "s|^includedir=.*|includedir=$DISPLAY_INFO_DIR/include|" "$WESTON_DISPLAY_INFO_PC"
                sed -i '' "s|^libdir=.*|libdir=\${prefix}|" "$WESTON_DISPLAY_INFO_PC"
            fi
        fi
        export PKG_CONFIG_PATH="$WESTON_BUILD_DIR/meson-private:$PKG_CONFIG_PATH"
        echo -e "${GREEN}✓${NC} libdisplay-info found (from Weston build)"
    fi

# CRITICAL: Check for real EGL FIRST before adding stubs to PKG_CONFIG_PATH
# This ensures we use the real EGL library from /opt/homebrew/lib, not stubs
# pkg-config searches PKG_CONFIG_PATH in order, so real EGL must come first
REAL_EGL_FOUND=false
if pkg-config --exists egl glesv2 wayland-egl 2>/dev/null; then
    REAL_EGL_FOUND=true
    EGL_PKG_CONFIG_DIR=$(pkg-config --variable=prefix egl 2>/dev/null || echo "")
    if [ -n "$EGL_PKG_CONFIG_DIR" ] && [ -d "$EGL_PKG_CONFIG_DIR/lib/pkgconfig" ]; then
        # Add real EGL pkg-config directory FIRST to PKG_CONFIG_PATH
        export PKG_CONFIG_PATH="$EGL_PKG_CONFIG_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"
        echo -e "${GREEN}✓${NC} Real EGL found - prioritizing in PKG_CONFIG_PATH: $EGL_PKG_CONFIG_DIR/lib/pkgconfig"
    fi
fi

# Add macOS stub pkg-config files to PKG_CONFIG_PATH
# These provide compatibility for Linux-specific dependencies
# BUT: Only add EGL/GLES stubs if real EGL was NOT found
STUB_PKG_CONFIG_DIR="$PROJECT_ROOT/libinput-macos-stubs"
if [ -d "$STUB_PKG_CONFIG_DIR" ]; then
    # Create pkg-config files so Meson can find the stubs
    # (pkg-config matches by filename, not by Name: field)
    STUB_PC_FILES=(
        "libudev-stub.pc:libudev.pc"
        "libevdev-stub.pc:libevdev.pc"
        "libdrm-stub.pc:libdrm.pc"
        "gbm-stub.pc:gbm.pc"
        "hwdata-stub.pc:hwdata.pc"
    )
    
    # Only add EGL/GLES stubs if real EGL was NOT found
    if [ "$REAL_EGL_FOUND" = false ]; then
        STUB_PC_FILES+=(
            "egl-stub.pc:egl.pc"
            "glesv2-stub.pc:glesv2.pc"
            "wayland-egl-stub.pc:wayland-egl.pc"
        )
        echo -e "${YELLOW}⚠${NC} Real EGL not found - will use stubs (clients will compile but fail at runtime)"
    fi
    
    for stub_pair in "${STUB_PC_FILES[@]}"; do
        stub_file="${stub_pair%%:*}"
        target_file="${stub_pair##*:}"
        if [ -f "$STUB_PKG_CONFIG_DIR/$stub_file" ] && [ ! -f "$STUB_PKG_CONFIG_DIR/$target_file" ]; then
            cp "$STUB_PKG_CONFIG_DIR/$stub_file" "$STUB_PKG_CONFIG_DIR/$target_file"
        fi
    done
    
    # Add stubs to PKG_CONFIG_PATH AFTER real EGL (so real EGL is found first)
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$STUB_PKG_CONFIG_DIR"
    
    # Report which stubs are available
    if [ -f "$STUB_PKG_CONFIG_DIR/libudev.pc" ]; then
        echo -e "${GREEN}✓${NC} libudev stub found (macOS compatibility)"
    fi
    if [ -f "$STUB_PKG_CONFIG_DIR/libevdev.pc" ]; then
        echo -e "${GREEN}✓${NC} libevdev stub found (macOS compatibility)"
    fi
    if [ -f "$STUB_PKG_CONFIG_DIR/libdrm.pc" ]; then
        echo -e "${GREEN}✓${NC} libdrm stub found (macOS compatibility)"
    fi
    if [ -f "$STUB_PKG_CONFIG_DIR/gbm.pc" ]; then
        echo -e "${GREEN}✓${NC} gbm stub found (macOS compatibility)"
    fi
    if [ -f "$STUB_PKG_CONFIG_DIR/hwdata.pc" ]; then
        echo -e "${GREEN}✓${NC} hwdata stub found (macOS compatibility)"
    fi
    if [ -f "$STUB_PKG_CONFIG_DIR/egl.pc" ]; then
        echo -e "${GREEN}✓${NC} egl stub found (macOS compatibility - clients will compile but fail at runtime)"
    fi
    if [ -f "$STUB_PKG_CONFIG_DIR/glesv2.pc" ]; then
        echo -e "${GREEN}✓${NC} glesv2 stub found (macOS compatibility - clients will compile but fail at runtime)"
    fi
    if [ -f "$STUB_PKG_CONFIG_DIR/wayland-egl.pc" ]; then
        echo -e "${GREEN}✓${NC} wayland-egl stub found (macOS compatibility - clients will compile but fail at runtime)"
    fi
fi

# Check for libinput (required by Weston compositor, but not for clients)
# We'll build only clients, so libinput is optional
# Add libinput build directory to PKG_CONFIG_PATH if it exists
LIBINPUT_PKG_CONFIG_DIRS=(
    "$PROJECT_ROOT/libinput/build-macos/meson-private"
    "$PROJECT_ROOT/libinput/build-macos"
    "/opt/homebrew/lib/pkgconfig"
    "/usr/local/lib/pkgconfig"
)

# Patch libinput.pc to point to build directory if it exists
LIBINPUT_PC="$PROJECT_ROOT/libinput/build-macos/meson-private/libinput.pc"
if [ -f "$LIBINPUT_PC" ]; then
    # Update the pkg-config file to point to the build directory
    LIBINPUT_BUILD_DIR="$PROJECT_ROOT/libinput/build-macos"
    # libinput headers are in the source directory, not build directory
    LIBINPUT_INCLUDE_DIR="$PROJECT_ROOT/libinput"
    
    # Use sed to update paths (works on macOS)
    if ! grep -q "^prefix=$LIBINPUT_BUILD_DIR$" "$LIBINPUT_PC" 2>/dev/null; then
        sed -i '' "s|^prefix=.*|prefix=$LIBINPUT_BUILD_DIR|" "$LIBINPUT_PC"
        sed -i '' "s|^includedir=.*|includedir=$LIBINPUT_INCLUDE_DIR|" "$LIBINPUT_PC"
        sed -i '' "s|^libdir=.*|libdir=\${prefix}|" "$LIBINPUT_PC"
        echo -e "${GREEN}✓${NC} Patched libinput.pc to point to build directory"
    fi
    
    # Ensure libinput.dylib symlink exists (Meson creates liblibinput.dylib)
    if [ ! -e "$LIBINPUT_BUILD_DIR/libinput.dylib" ] && [ -f "$LIBINPUT_BUILD_DIR/liblibinput.dylib" ]; then
        ln -sf liblibinput.dylib "$LIBINPUT_BUILD_DIR/libinput.dylib"
        echo -e "${GREEN}✓${NC} Created libinput.dylib symlink"
    fi
fi

for dir in "${LIBINPUT_PKG_CONFIG_DIRS[@]}"; do
    if [ -d "$dir" ] && ([ -f "$dir/libinput.pc" ] || [ -f "$dir/../libinput.pc" ]); then
        export PKG_CONFIG_PATH="$dir:$PKG_CONFIG_PATH"
        break
    fi
done

# Also check if libinput is installed system-wide
HAS_LIBINPUT=false
if pkg-config --exists libinput 2>/dev/null; then
    HAS_LIBINPUT=true
    LIBINPUT_VERSION=$(pkg-config --modversion libinput 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓${NC} libinput found (macOS port)"
    echo -e "${GREEN}  ${NC} Version: $LIBINPUT_VERSION"
else
    echo -e "${YELLOW}⚠${NC} libinput not found - will build clients only (not compositor)"
    echo -e "${YELLOW}  ${NC} Searched in: ${LIBINPUT_PKG_CONFIG_DIRS[*]}"
fi

# Check for EGL (already checked above, but verify again with updated PKG_CONFIG_PATH)
HAS_EGL=false
if pkg-config --exists egl glesv2 wayland-egl 2>/dev/null; then
    HAS_EGL=true
    EGL_VERSION=$(pkg-config --modversion egl 2>/dev/null || echo "unknown")
    EGL_PKG_CONFIG_DIR=$(pkg-config --variable=prefix egl 2>/dev/null || echo "")
    echo -e "${GREEN}✓${NC} EGL found"
    echo -e "${GREEN}  ${NC} Version: $EGL_VERSION"
    if [ -n "$EGL_PKG_CONFIG_DIR" ]; then
        echo -e "${GREEN}  ${NC} Location: $EGL_PKG_CONFIG_DIR"
        # Verify we're using real EGL, not stubs
        if [ "$EGL_PKG_CONFIG_DIR" = "$STUB_PKG_CONFIG_DIR" ]; then
            echo -e "${YELLOW}⚠${NC} WARNING: Using EGL stubs instead of real EGL!"
        else
            echo -e "${GREEN}  ${NC} Using real EGL library (not stubs)"
        fi
    fi
else
    echo -e "${YELLOW}⚠${NC} EGL not found - will use stubs (clients will compile but fail at runtime)"
    echo -e "${YELLOW}  ${NC} Note: EGL stubs allow compilation but clients will fail at runtime"
fi

echo -e "${GREEN}✓${NC} Dependencies OK"
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
git pull || true
echo ""

# Patch meson.build to make libinput/libevdev optional for clients-only builds
echo -e "${YELLOW}ℹ${NC} Patching meson.build for clients-only build..."
MESON_BUILD="$WESTON_DIR/meson.build"
LIBWESTON_MESON="$WESTON_DIR/libweston/meson.build"

if ! grep -q "# Patched for clients-only" "$MESON_BUILD" 2>/dev/null; then
    # Create a Python script to patch the meson.build file
    python3 << PYTHON_SCRIPT
import sys
import re

meson_build = "$MESON_BUILD"
with open(meson_build, 'r') as f:
    content = f.read()

# Check if already patched
if "# Patched for clients-only" in content:
    print("Already patched")
    sys.exit(0)

# Add has_any_backend check before libinput dependency
libinput_pattern = r'(dep_xkbcommon = dependency\([^)]+\))\n(dep_libinput = dependency\([^)]+\))'
# In Meson, just use regular single quotes - no escaping needed for option names
backend_check = "has_any_backend = get_option('backend-drm') or get_option('backend-headless') or get_option('backend-wayland') or get_option('backend-x11')"
replacement = r'\1\n\n# Patched for clients-only build\n' + backend_check + r'\n\2'
content = re.sub(libinput_pattern, replacement, content)

# Make libinput optional
content = re.sub(
    r'dep_libinput = dependency\([^)]+\)',
    r"dep_libinput = dependency('libinput', version: '>= 1.2.0', required: has_any_backend)",
    content,
    count=1
)

# Fix HAVE_COMPOSE_AND_KANA check
content = re.sub(
    r'if dep_xkbcommon\.version\(\)\.version_compare\([^)]+\)\s*\n\s*if dep_libinput\.version\(\)',
    r"if dep_xkbcommon.version().version_compare('>= 1.8.0')\n\tif dep_libinput.found() and dep_libinput.version()",
    content
)

# Make libevdev optional
content = re.sub(
    r'dep_libevdev = dependency\([^)]+\)',
    r"dep_libevdev = dependency('libevdev', required: has_any_backend)",
    content,
    count=1
)

# Fix backend-default check - skip error when no backends enabled
# The pattern is: if not get_option('backend-' + backend_default) ... error(...) ... endif
# Wrap the error check in a conditional
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
        echo -e "${YELLOW}⚠${NC} Python patching failed, trying sed fallback..."
        # Fallback to sed (may not work perfectly but better than nothing)
        sed -i.bak \
            -e 's/dep_libinput = dependency/dep_libinput = dependency/g' \
            "$MESON_BUILD"
    fi
else
    echo -e "${GREEN}✓${NC} Already patched"
fi

# Patch display-info subproject to handle missing hwdata on macOS
DISPLAY_INFO_MESON="$WESTON_DIR/subprojects/display-info/meson.build"
if [ -f "$DISPLAY_INFO_MESON" ] && ! grep -q "# Patched for macOS" "$DISPLAY_INFO_MESON" 2>/dev/null; then
    python3 << PYTHON_SCRIPT
import re

meson_build = "$DISPLAY_INFO_MESON"
with open(meson_build, 'r') as f:
    content = f.read()

# Replace the else branch that tries to access /usr/share/hwdata/pnp.ids
if "pnp_ids = files('/usr/share/hwdata/pnp.ids')" in content:
    content = content.replace(
        """else
	pnp_ids = files('/usr/share/hwdata/pnp.ids')
endif""",
        """else
	# Patched for macOS - create empty pnp.ids stub
	pnp_ids_stub = custom_target(
		'pnp-ids-empty',
		command: ['sh', '-c', 'touch @OUTPUT@'],
		output: 'pnp.ids',
	)
	pnp_ids_file = pnp_ids_stub
endif"""
    )
    # Also update the reference from pnp_ids to pnp_ids_file
    content = content.replace('pnp_ids = files(hwdata_dir / \'pnp.ids\')', "pnp_ids_file = hwdata_dir / 'pnp.ids'")
    content = content.replace('command: [ gen_search_table, pnp_ids,', 'command: [ gen_search_table, pnp_ids_file,')
    
    with open(meson_build, 'w') as f:
        f.write(content)
    print("Patched display-info meson.build")
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Patched display-info meson.build"
    fi
fi

# Patch libweston/meson.build to make libinput-backend conditional
if [ -f "$LIBWESTON_MESON" ] && ! grep -q "# Patched for clients-only" "$LIBWESTON_MESON" 2>/dev/null; then
    python3 << PYTHON_SCRIPT
import sys
import re

meson_build = "$LIBWESTON_MESON"
with open(meson_build, 'r') as f:
    content = f.read()

# Check if already patched
if "# Patched for clients-only" in content:
    print("Already patched")
    sys.exit(0)

# Add conditional around libinput-backend
libinput_backend_pattern = r'(lib_libinput_backend = static_library\()'
# In Meson, just use regular single quotes - no escaping needed for option names
backend_check = "has_any_backend = get_option('backend-drm') or get_option('backend-headless') or get_option('backend-wayland') or get_option('backend-x11')"
replacement = '# Patched for clients-only build\n' + backend_check + '\nif has_any_backend and dep_libinput.found()\n' + r'\1'
content = re.sub(libinput_backend_pattern, replacement, content)

# Close the conditional after dep_libinput_backend
dep_pattern = r'(dep_libinput_backend = declare_dependency\([^)]+\))\n(endif)'
dep_replacement = r'\1\nendif\n\2'
content = re.sub(dep_pattern, dep_replacement, content)

# If no endif found, add one
if 'dep_libinput_backend = declare_dependency' in content and content.find('if has_any_backend') >= 0:
    # Count if statements vs endif statements after the first if
    if_pos = content.find('if has_any_backend')
    if if_pos >= 0:
        after_if = content[if_pos:]
        if_count = after_if.count('if has_any_backend')
        endif_count = after_if.count('endif')
        if if_count > endif_count:
            content = re.sub(
                r'(dep_libinput_backend = declare_dependency\([^)]+\))\n',
                r'\1\nendif\n',
                content,
                count=1
            )

with open(meson_build, 'w') as f:
    f.write(content)

print("Patched libweston/meson.build")
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Patched libweston/meson.build"
    fi
fi

# Patch client files to use macOS compatibility headers
echo -e "${YELLOW}ℹ${NC} Patching client files for macOS compatibility..."
CLIENT_FILES=(
    "clients/simple-shm.c"
    "clients/clickdot.c"
    "clients/cliptest.c"
    "clients/transformed.c"
    "clients/terminal.c"
    "clients/tablet.c"
    "clients/subsurfaces.c"
    "clients/stacking.c"
    "clients/simple-vulkan.c"
    "clients/simple-egl.c"
    "clients/simple-dmabuf-v4l.c"
    "clients/scaler.c"
    "clients/resizor.c"
    "clients/keyboard.c"
    "clients/ivi-shell-user-interface.c"
    "clients/image.c"
    "clients/fullscreen.c"
    "clients/flower.c"
    "clients/editor.c"
    "clients/desktop-shell.c"
    "clients/content_protection.c"
    "clients/constraints.c"
)

for client_file in "${CLIENT_FILES[@]}"; do
    CLIENT_PATH="$WESTON_DIR/$client_file"
    if [ -f "$CLIENT_PATH" ] && ! grep -q "linux-input-compat.h" "$CLIENT_PATH" 2>/dev/null; then
        python3 << PYTHON_SCRIPT
import re

client_path = "$CLIENT_PATH"
with open(client_path, 'r') as f:
    content = f.read()

# Replace linux/input.h include with conditional
if '#include <linux/input.h>' in content:
    content = content.replace(
        '#include <linux/input.h>',
        '''#ifdef __APPLE__
#include "linux-input-compat.h"
#else
#include <linux/input.h>
#endif'''
    )
    with open(client_path, 'w') as f:
        f.write(content)
    print(f"Patched {client_path}")
PYTHON_SCRIPT
    fi
done

# Patch terminal.c for pty.h compatibility
TERMINAL_PATH="$WESTON_DIR/clients/terminal.c"
if [ -f "$TERMINAL_PATH" ] && ! grep -q "util.h" "$TERMINAL_PATH" 2>/dev/null; then
    python3 << PYTHON_SCRIPT
import re

terminal_path = "$TERMINAL_PATH"
with open(terminal_path, 'r') as f:
    content = f.read()

# Replace pty.h include with conditional
if '#include <pty.h>' in content:
    content = content.replace(
        '#include <pty.h>',
        '''#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif'''
    )
    with open(terminal_path, 'w') as f:
        f.write(content)
    print(f"Patched {terminal_path}")
PYTHON_SCRIPT
fi

echo -e "${GREEN}✓${NC} Client files patched"
echo ""

# Create build directory
mkdir -p "$WESTON_BUILD_DIR"
cd "$WESTON_BUILD_DIR"

# Configure Weston build
echo -e "${YELLOW}ℹ${NC} Configuring Weston build..."
echo -e "${YELLOW}ℹ${NC} Install prefix: ${INSTALL_PREFIX}"

# Check for Vulkan support (KosmicKrisp)
HAS_VULKAN=false
if pkg-config --exists vulkan 2>/dev/null && which glslangValidator >/dev/null 2>&1; then
    # Check if KosmicKrisp is actually installed
    if [ -f "/opt/homebrew/lib/libvulkan_kosmickrisp.dylib" ] || \
       [ -f "/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json" ] || \
       [ -f "/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.x86_64.json" ]; then
        HAS_VULKAN=true
        echo -e "${GREEN}✓${NC} Vulkan support found (KosmicKrisp)"
    fi
fi

# Configure Weston to build only clients (not compositor)
# This avoids libinput/libudev dependencies
# Strict compiler flags: treat all warnings as errors, make implicit declarations errors
# Use Meson's warning_level=3 (maximum) and werror=true (treat warnings as errors)
# Note: -Werror is applied via Meson's werror option, not c_args, to avoid breaking compiler detection
STRICT_C_FLAGS=(
    "-Wstrict-prototypes"        # Require function prototypes
    "-Wmissing-prototypes"       # Warn about missing prototypes
    "-Wimplicit-function-declaration"  # Error on implicit function declarations
    "-Werror=implicit-function-declaration"  # Make implicit declarations errors
    "-Wmissing-declarations"     # Warn about missing declarations
    "-Wundef"                    # Warn about undefined macros
    "-Wstrict-aliasing=2"        # Strict aliasing rules
    "-Wformat=2"                 # Strict format string checking
    "-Wformat-security"          # Warn about format string security issues
    "-Wno-format-nonliteral"    # Suppress format-nonliteral (common in logging code, intentional)
    "-Winit-self"                # Warn about uninitialized variables
    "-Wuninitialized"            # Warn about uninitialized variables
    "-Wredundant-decls"          # Warn about redundant declarations
    "-Wno-shadow"                # Suppress shadow warnings (too many in Weston code)
    "-Wno-visibility"            # Suppress visibility warnings (needed for macOS)
    "-Wno-gnu-pointer-arith"     # Suppress GNU pointer arithmetic warnings (legitimate in Weston code)
    # Note: Some flags disabled for compatibility with existing Weston/Wayland code:
    # -Wdeclaration-after-statement: Too strict, requires C99 style (Weston uses C89 style in places)
    # -Wcast-qual: Too strict, catches legitimate const casts in Weston code
    # -Wcast-align: Too strict, catches legitimate container_of-style macros in Wayland/Weston
    # -Wconversion/-Wsign-conversion: Too strict, catches many legitimate conversions in Weston code
    # -Wpointer-arith: Catches GNU void pointer arithmetic (legitimate, suppressed with -Wno-gnu-pointer-arith)
    # -Wlogical-op and -Wwrite-strings: Not supported by Apple clang
)

STRICT_CPP_FLAGS=(
    "-Wno-gnu-zero-variadic-macro-arguments"  # Suppress GNU extension warnings (needed for edid-decode)
    "-Wno-variadic-macro-arguments-omitted"   # Suppress variadic macro warnings
    "-Wno-deprecated-declarations"           # Suppress deprecation warnings (needed for edid-decode)
)

# Join array elements with spaces for Meson
C_ARGS_STR=$(IFS=' '; echo "${STRICT_C_FLAGS[*]}")
CPP_ARGS_STR=$(IFS=' '; echo "${STRICT_CPP_FLAGS[*]}")

MESON_OPTS=(
    "--prefix=$INSTALL_PREFIX"
    "--buildtype=release"
    "-Dwarning_level=3"          # Maximum warning level (equivalent to -Wall -Wextra)
    "-Dwerror=true"               # Treat all warnings as errors
    "-Dc_args=$C_ARGS_STR"
    "-Dcpp_args=$CPP_ARGS_STR"
    # macOS-specific: Disable weak linking for EGL libraries
    # EGL libraries from KosmicKrisp don't export weak symbols, so we need normal linking
    "-Dc_link_args=-Wl,-no_weak_imports -Wl,-weak_reference_mismatches,non-weak"  # Disable weak imports and treat weak refs as non-weak
    # Disable all backends (they require libinput/libudev)
    "-Dbackend-drm=false"
    "-Dbackend-headless=false"
    "-Dbackend-pipewire=false"
    "-Dbackend-rdp=false"
    "-Dbackend-vnc=false"
    "-Dbackend-wayland=false"
    "-Dbackend-x11=false"
    # Disable compositor features that need libinput
    "-Dshell-desktop=false"
    "-Dshell-kiosk=false"
    "-Dshell-ivi=false"
    "-Dshell-lua=false"
    "-Dxwayland=false"
    "-Dsystemd=false"
    "-Dremoting=false"
    "-Dpipewire=false"
    "-Dtests=false"
    # Enable Vulkan renderer if KosmicKrisp is available
    "-Drenderer-vulkan=$HAS_VULKAN"
    # Enable clients (exclude dmabuf-feedback/egl which require Linux-specific deps)
    "-Ddemo-clients=true"
    "-Dsimple-clients=damage,egl,im,shm,touch"
    "-Dtools=calibrator,debug,terminal,touch-calibrator"
)

# macOS-specific: Disable systemd, logind, etc.
# Enable only what we need for demo clients

# Always enable renderer-gl if EGL stubs are available (allows compilation)
# Note: Clients will compile but fail at runtime if using stubs
if [ "$HAS_EGL" = true ]; then
    MESON_OPTS+=("-Drenderer-gl=true")
    echo -e "${GREEN}✓${NC} EGL renderer enabled (real EGL)"
else
    # Enable renderer-gl even with stubs to allow compilation
    # Clients will fail at runtime when trying to use EGL functions
    MESON_OPTS+=("-Drenderer-gl=true")
    echo -e "${YELLOW}⚠${NC} EGL renderer enabled with stubs (clients will compile but fail at runtime)"
fi

if [ "$HAS_VULKAN" = true ]; then
    echo -e "${GREEN}✓${NC} Vulkan renderer enabled (KosmicKrisp)"
else
    echo -e "${YELLOW}⚠${NC} Vulkan not available - Vulkan clients will be skipped"
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
echo -e "${YELLOW}ℹ${NC} Building Weston..."
ninja -j$(sysctl -n hw.ncpu)
echo -e "${GREEN}✓${NC} Build complete"
echo ""

# Install demo clients only
echo -e "${YELLOW}ℹ${NC} Installing demo clients..."
mkdir -p "$INSTALL_PREFIX/bin"

# Copy demo client binaries
DEMO_CLIENTS=(
    "weston-simple-shm"
    "weston-simple-egl"
    "weston-transformed"
    "weston-subsurfaces"
    "weston-simple-damage"
    "weston-simple-touch"
    "weston-eventdemo"
    "weston-keyboard"
    "weston-dnd"
    "weston-cliptest"
    "weston-image"
    "weston-editor"
)

for client in "${DEMO_CLIENTS[@]}"; do
    if [ -f "clients/$client" ]; then
        cp "clients/$client" "$INSTALL_PREFIX/bin/"
        echo -e "${GREEN}✓${NC} Installed $client"
    elif [ -f "$client" ]; then
        cp "$client" "$INSTALL_PREFIX/bin/"
        echo -e "${GREEN}✓${NC} Installed $client"
    else
        echo -e "${YELLOW}⚠${NC} $client not found (may require EGL or other deps)"
    fi
done

# Create symlinks for easy access
mkdir -p "$PROJECT_ROOT/test-clients/bin"
for client in "${DEMO_CLIENTS[@]}"; do
    if [ -f "$INSTALL_PREFIX/bin/$client" ]; then
        ln -sf "$INSTALL_PREFIX/bin/$client" "$PROJECT_ROOT/test-clients/bin/$client"
    fi
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} Weston demo clients installed!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} Clients installed to: ${INSTALL_PREFIX}/bin"
echo -e "${YELLOW}ℹ${NC} Run with: export WAYLAND_DISPLAY=wayland-0 && ${INSTALL_PREFIX}/bin/weston-simple-shm"
echo ""

