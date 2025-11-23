#!/bin/bash
# Test script for xkbcommon and libinput dependencies
# Can be run locally to verify builds

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🧪 Testing Dependencies${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Detect install prefix
if [[ "$(uname -m)" == "arm64" ]] && [ -d "/opt/homebrew" ]; then
    INSTALL_PREFIX="/opt/homebrew"
else
    INSTALL_PREFIX="/usr/local"
fi

echo -e "${YELLOW}ℹ${NC} Install prefix: ${INSTALL_PREFIX}"
echo ""

# Test xkbcommon
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Testing xkbcommon${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if pkg-config --exists xkbcommon; then
    VERSION=$(pkg-config --modversion xkbcommon)
    echo -e "${GREEN}✅${NC} xkbcommon found: version ${VERSION}"
    
    # Check library
    if [ -f "$INSTALL_PREFIX/lib/libxkbcommon.dylib" ] || [ -f "$INSTALL_PREFIX/lib/libxkbcommon.a" ]; then
        echo -e "${GREEN}✅${NC} xkbcommon library found"
    else
        echo -e "${RED}❌${NC} xkbcommon library not found"
        exit 1
    fi
    
    # Test API
    echo -e "${YELLOW}ℹ${NC} Testing xkbcommon API..."
    cat > /tmp/test_xkbcommon.c << 'EOF'
#include <xkbcommon/xkbcommon.h>
#include <stdio.h>

int main() {
    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!ctx) {
        fprintf(stderr, "Failed to create xkb_context\n");
        return 1;
    }
    
    printf("✅ xkb_context created successfully\n");
    
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(
        ctx, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
    
    if (keymap) {
        printf("✅ xkb_keymap loaded successfully\n");
        xkb_keymap_unref(keymap);
    } else {
        printf("⚠️ xkb_keymap loading failed (may need xkeyboard-config)\n");
    }
    
    xkb_context_unref(ctx);
    return 0;
}
EOF
    
    if ! PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
        clang -o /tmp/test_xkbcommon /tmp/test_xkbcommon.c \
        $(pkg-config --cflags --libs xkbcommon) 2>&1 | grep -v "warning:" | grep -v "^$"; then
        # Check if compilation actually succeeded despite warnings
        if [ ! -f /tmp/test_xkbcommon ]; then
            echo -e "${RED}❌${NC} Failed to compile xkbcommon test"
            PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
            clang -o /tmp/test_xkbcommon /tmp/test_xkbcommon.c \
                $(pkg-config --cflags --libs xkbcommon) 2>&1 || true
            exit 1
        fi
    fi
    
    DYLD_LIBRARY_PATH="$INSTALL_PREFIX/lib:$DYLD_LIBRARY_PATH" \
    /tmp/test_xkbcommon || {
        echo -e "${RED}❌${NC} xkbcommon test failed"
        exit 1
    }
    
    echo -e "${GREEN}✅${NC} xkbcommon API test passed"
    echo ""
else
    echo -e "${RED}❌${NC} xkbcommon not found"
    echo -e "${YELLOW}ℹ${NC} Build with: make xkbcommon"
    exit 1
fi

# Test libinput
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Testing libinput${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

LIBINPUT_BUILD_DIR="$PROJECT_ROOT/libinput/build-macos"

if [ -f "$LIBINPUT_BUILD_DIR/libinput.10.dylib" ]; then
    echo -e "${GREEN}✅${NC} libinput.10.dylib found"
    ls -lh "$LIBINPUT_BUILD_DIR/libinput.10.dylib"
    echo ""
    
    # Check symbols
    echo -e "${YELLOW}ℹ${NC} Checking libinput symbols..."
    
    if nm -gU "$LIBINPUT_BUILD_DIR/libinput.10.dylib" | grep -q "libinput_macos_create_context"; then
        echo -e "${GREEN}✅${NC} libinput_macos_create_context symbol found"
    else
        echo -e "${RED}❌${NC} libinput_macos_create_context symbol not found"
        exit 1
    fi
    
    if nm -gU "$LIBINPUT_BUILD_DIR/libinput.10.dylib" | grep -q "libevdev_new"; then
        echo -e "${GREEN}✅${NC} libevdev wrapper symbols found"
    else
        echo -e "${YELLOW}⚠${NC} libevdev wrapper symbols not found"
    fi
    
    echo ""
    
    # Test API
    echo -e "${YELLOW}ℹ${NC} Testing libinput API..."
    cat > /tmp/test_libinput.c << 'EOF'
#include <libinput.h>
#include <stdio.h>

// Forward declaration for macOS-specific API
struct libinput *libinput_macos_create_context(
    const struct libinput_interface *interface,
    void *user_data);

int main() {
    // Test macOS-specific API
    struct libinput_interface interface = {
        .open_restricted = NULL,
        .close_restricted = NULL
    };
    
    struct libinput *li = libinput_macos_create_context(&interface, NULL);
    if (!li) {
        fprintf(stderr, "Failed to create libinput context\n");
        return 1;
    }
    
    printf("✅ libinput context created successfully\n");
    
    // Test udev API compatibility
    struct libinput *li2 = libinput_udev_create_context(&interface, NULL, NULL);
    if (li2) {
        printf("✅ libinput_udev_create_context works\n");
        libinput_unref(li2);
    } else {
        printf("⚠️ libinput_udev_create_context returned NULL (may be expected)\n");
    }
    
    libinput_unref(li);
    return 0;
}
EOF
    
    cd "$LIBINPUT_BUILD_DIR"
    
    if ! clang -o /tmp/test_libinput /tmp/test_libinput.c \
        -I../include \
        -I../src \
        -L. \
        -Wl,-rpath,@loader_path \
        libinput.10.dylib 2>&1 | grep -v "warning:" | grep -v "^$"; then
        # Check if compilation actually succeeded despite warnings
        if [ ! -f /tmp/test_libinput ]; then
            echo -e "${RED}❌${NC} Failed to compile libinput test"
            clang -o /tmp/test_libinput /tmp/test_libinput.c \
                -I../include \
                -I../src \
                -L. \
                -Wl,-rpath,@loader_path \
                libinput.10.dylib 2>&1 || true
            exit 1
        fi
    fi
    
    DYLD_LIBRARY_PATH=".:$DYLD_LIBRARY_PATH" \
    /tmp/test_libinput || {
        echo -e "${RED}❌${NC} libinput test failed"
        exit 1
    }
    
    echo -e "${GREEN}✅${NC} libinput API test passed"
    echo ""
    
    # Check tools
    echo -e "${YELLOW}ℹ${NC} Checking libinput tools..."
    TOOLS=(
        "libinput"
        "libinput-list-devices"
        "libinput-debug-events"
        "libinput-quirks"
    )
    
    for tool in "${TOOLS[@]}"; do
        if [ -f "$LIBINPUT_BUILD_DIR/$tool" ]; then
            echo -e "${GREEN}✅${NC} $tool built successfully"
        else
            echo -e "${YELLOW}⚠${NC} $tool not found (may be expected)"
        fi
    done
    
else
    echo -e "${RED}❌${NC} libinput.10.dylib not found"
    echo -e "${YELLOW}ℹ${NC} Build with: cd libinput/build-macos && meson setup . .. && ninja"
    exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅${NC} All dependency tests passed!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Cleanup
rm -f /tmp/test_xkbcommon.c /tmp/test_xkbcommon
rm -f /tmp/test_libinput.c /tmp/test_libinput

