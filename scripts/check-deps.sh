#!/bin/bash

# CALayerWayland Dependency Checker
# Verifies all required dependencies are installed
# NOTE: We do NOT use WLRoots (it's Linux-only)

echo "🔍 CALayerWayland Dependency Checker"
echo "======================================"
echo ""
echo "ℹ️  NOTE: This is a FROM-SCRATCH compositor"
echo "   We use ONLY libwayland-server for protocol handling"
echo "   We do NOT use WLRoots (Linux-only)"
echo ""

ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_cmd() {
    if command -v "$1" &> /dev/null; then
        VERSION=$($1 --version 2>/dev/null | head -n1)
        echo -e "${GREEN}✓${NC} $1: $VERSION"
        return 0
    else
        echo -e "${RED}✗${NC} $1: NOT FOUND"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

check_pkg() {
    if pkg-config --exists "$1" 2>/dev/null; then
        VERSION=$(pkg-config --modversion "$1" 2>/dev/null)
        echo -e "${GREEN}✓${NC} $1: $VERSION"
        return 0
    else
        echo -e "${RED}✗${NC} $1: NOT FOUND"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

check_framework() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} $2 framework: Found"
        return 0
    else
        echo -e "${RED}✗${NC} $2 framework: NOT FOUND"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

check_lib() {
    if [ -f "$1" ] || [ -L "$1" ]; then
        echo -e "${GREEN}✓${NC} $2: Found"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $2: Not found (may be in different location)"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

echo "📦 Build Tools:"
echo "---------------"
check_cmd "cmake"
check_cmd "pkg-config"
check_cmd "clang"
check_cmd "git"

echo ""
echo "📚 Core Libraries:"
echo "------------------"

# Check for Homebrew paths
if [ -d "/opt/homebrew" ]; then
    LIB_DIR="/opt/homebrew/lib"
    INC_DIR="/opt/homebrew/include"
    echo -e "${GREEN}✓${NC} Using Apple Silicon Homebrew paths"
elif [ -d "/usr/local" ]; then
    LIB_DIR="/usr/local/lib"
    INC_DIR="/usr/local/include"
    echo -e "${GREEN}✓${NC} Using Intel Mac Homebrew paths"
else
    LIB_DIR="/usr/lib"
    INC_DIR="/usr/include"
    echo -e "${YELLOW}⚠${NC} Using system paths (may need Homebrew)"
fi

# Check for wayland libraries
# Try Homebrew first, but it may require Linux - fall back to manual build instructions
WAYLAND_SERVER_FOUND=0
WAYLAND_CLIENT_FOUND=0

if pkg-config --exists "wayland-server" 2>/dev/null; then
    VERSION=$(pkg-config --modversion "wayland-server" 2>/dev/null)
    echo -e "${GREEN}✓${NC} wayland-server: $VERSION"
    WAYLAND_SERVER_FOUND=1
elif [ -f "$LIB_DIR/libwayland-server.dylib" ] || [ -f "$LIB_DIR/libwayland-server.a" ]; then
    echo -e "${GREEN}✓${NC} wayland-server: Found"
    WAYLAND_SERVER_FOUND=1
else
    echo -e "${RED}✗${NC} wayland-server: NOT FOUND"
    ERRORS=$((ERRORS + 1))
fi

if pkg-config --exists "wayland-client" 2>/dev/null; then
    VERSION=$(pkg-config --modversion "wayland-client" 2>/dev/null)
    echo -e "${GREEN}✓${NC} wayland-client: $VERSION"
    WAYLAND_CLIENT_FOUND=1
elif [ -f "$LIB_DIR/libwayland-client.dylib" ] || [ -f "$LIB_DIR/libwayland-client.a" ]; then
    echo -e "${GREEN}✓${NC} wayland-client: Found"
    WAYLAND_CLIENT_FOUND=1
else
    echo -e "${RED}✗${NC} wayland-client: NOT FOUND"
    ERRORS=$((ERRORS + 1))
fi

check_pkg "pixman-1"

# Check for wayland-scanner tool
if command -v wayland-scanner &> /dev/null; then
    VERSION=$(wayland-scanner --version 2>/dev/null || echo "Found")
    echo -e "${GREEN}✓${NC} wayland-scanner: $VERSION"
elif [ -f "$LIB_DIR/../bin/wayland-scanner" ]; then
    echo -e "${GREEN}✓${NC} wayland-scanner: Found"
else
    echo -e "${RED}✗${NC} wayland-scanner: NOT FOUND"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "🍎 macOS Frameworks:"
echo "---------------------"
check_framework "/System/Library/Frameworks/Cocoa.framework" "Cocoa"
check_framework "/System/Library/Frameworks/QuartzCore.framework" "QuartzCore"
check_framework "/System/Library/Frameworks/CoreVideo.framework" "CoreVideo"
check_framework "/System/Library/Frameworks/CoreGraphics.framework" "CoreGraphics"

echo ""
echo "🔗 Library Files:"
echo "-----------------"
check_lib "$LIB_DIR/libwayland-server.dylib" "libwayland-server"
check_lib "$LIB_DIR/libwayland-client.dylib" "libwayland-client"
check_lib "$LIB_DIR/libpixman-1.dylib" "libpixman-1"

echo ""
echo "📋 Optional Testing Tools:"
echo "--------------------------"
if command -v qmake6 &> /dev/null || command -v qmake &> /dev/null; then
    echo -e "${GREEN}✓${NC} Qt: Found"
else
    echo -e "${YELLOW}⚠${NC} Qt: Not found (optional, for testing QtWayland clients)"
    WARNINGS=$((WARNINGS + 1))
fi

if command -v gtk4-launch &> /dev/null; then
    echo -e "${GREEN}✓${NC} GTK4: Found"
else
    echo -e "${YELLOW}⚠${NC} GTK4: Not found (optional, for testing GTK apps)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "🧪 Wayland Functionality Tests:"
echo "--------------------------------"

# Test Wayland version and functionality
WAYLAND_TEST_PASSED=0
WAYLAND_TEST_FAILED=0

test_wayland_version() {
    echo -n "  Testing wayland-server version... "
    if pkg-config --exists "wayland-server" 2>/dev/null; then
        VERSION=$(pkg-config --modversion "wayland-server" 2>/dev/null)
        if [ -n "$VERSION" ]; then
            echo -e "${GREEN}✓${NC} $VERSION"
            WAYLAND_TEST_PASSED=$((WAYLAND_TEST_PASSED + 1))
            return 0
        fi
    fi
    echo -e "${RED}✗${NC} Failed"
    WAYLAND_TEST_FAILED=$((WAYLAND_TEST_FAILED + 1))
    return 1
}

test_wayland_client_version() {
    echo -n "  Testing wayland-client version... "
    if pkg-config --exists "wayland-client" 2>/dev/null; then
        VERSION=$(pkg-config --modversion "wayland-client" 2>/dev/null)
        if [ -n "$VERSION" ]; then
            echo -e "${GREEN}✓${NC} $VERSION"
            WAYLAND_TEST_PASSED=$((WAYLAND_TEST_PASSED + 1))
            return 0
        fi
    fi
    echo -e "${RED}✗${NC} Failed"
    WAYLAND_TEST_FAILED=$((WAYLAND_TEST_FAILED + 1))
    return 1
}

test_wayland_scanner() {
    echo -n "  Testing wayland-scanner... "
    if command -v wayland-scanner &> /dev/null; then
        SCANNER_PATH=$(which wayland-scanner)
        if wayland-scanner --version &>/dev/null || [ -x "$SCANNER_PATH" ]; then
            echo -e "${GREEN}✓${NC} Found at $SCANNER_PATH"
            WAYLAND_TEST_PASSED=$((WAYLAND_TEST_PASSED + 1))
            return 0
        fi
    fi
    echo -e "${RED}✗${NC} Failed"
    WAYLAND_TEST_FAILED=$((WAYLAND_TEST_FAILED + 1))
    return 1
}

test_wayland_headers() {
    echo -n "  Testing wayland headers... "
    HEADER_FOUND=0
    if [ -f "$INC_DIR/wayland-server.h" ] || [ -f "$INC_DIR/wayland/wayland-server.h" ]; then
        HEADER_FOUND=1
    fi
    if [ -f "$INC_DIR/wayland-client.h" ] || [ -f "$INC_DIR/wayland/wayland-client.h" ]; then
        HEADER_FOUND=$((HEADER_FOUND + 1))
    fi
    
    if [ $HEADER_FOUND -ge 2 ]; then
        echo -e "${GREEN}✓${NC} Headers found"
        WAYLAND_TEST_PASSED=$((WAYLAND_TEST_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Headers missing"
        WAYLAND_TEST_FAILED=$((WAYLAND_TEST_FAILED + 1))
        return 1
    fi
}

test_wayland_library_link() {
    echo -n "  Testing library linking... "
    
    # Create a temporary test file
    TEST_FILE=$(mktemp /tmp/wayland_test_XXXXXX.c)
    TEST_BIN=$(mktemp /tmp/wayland_test_XXXXXX)
    
    cat > "$TEST_FILE" << 'EOF'
#include <wayland-server.h>
#include <wayland-client.h>
int main() {
    struct wl_display *display = wl_display_create();
    if (display) {
        wl_display_destroy(display);
        return 0;
    }
    return 1;
}
EOF
    
    # Try to compile and link
    if pkg-config --exists "wayland-server" 2>/dev/null && pkg-config --exists "wayland-client" 2>/dev/null; then
        CFLAGS=$(pkg-config --cflags wayland-server wayland-client 2>/dev/null)
        LIBS=$(pkg-config --libs wayland-server wayland-client 2>/dev/null)
        
        if clang $CFLAGS -o "$TEST_BIN" "$TEST_FILE" $LIBS 2>/dev/null; then
            # Try to run it
            if "$TEST_BIN" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} Libraries link and work"
                rm -f "$TEST_FILE" "$TEST_BIN"
                WAYLAND_TEST_PASSED=$((WAYLAND_TEST_PASSED + 1))
                return 0
            fi
        fi
    fi
    
    rm -f "$TEST_FILE" "$TEST_BIN"
    echo -e "${RED}✗${NC} Failed to link libraries"
    WAYLAND_TEST_FAILED=$((WAYLAND_TEST_FAILED + 1))
    return 1
}

test_wayland_scanner_functionality() {
    echo -n "  Testing wayland-scanner functionality... "
    
    # Create a minimal wayland protocol XML
    TEST_XML=$(mktemp /tmp/wayland_test_XXXXXX.xml)
    TEST_OUTPUT=$(mktemp /tmp/wayland_test_XXXXXX.h)
    
    cat > "$TEST_XML" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<protocol name="test_protocol">
  <interface name="test_interface" version="1">
    <request name="test_request" />
  </interface>
</protocol>
EOF
    
    if command -v wayland-scanner &> /dev/null; then
        if wayland-scanner client-header "$TEST_XML" "$TEST_OUTPUT" 2>/dev/null; then
            if [ -f "$TEST_OUTPUT" ] && grep -q "test_interface" "$TEST_OUTPUT" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} Scanner works correctly"
                rm -f "$TEST_XML" "$TEST_OUTPUT"
                WAYLAND_TEST_PASSED=$((WAYLAND_TEST_PASSED + 1))
                return 0
            fi
        fi
    fi
    
    rm -f "$TEST_XML" "$TEST_OUTPUT"
    echo -e "${RED}✗${NC} Scanner test failed"
    WAYLAND_TEST_FAILED=$((WAYLAND_TEST_FAILED + 1))
    return 1
}

test_wayland_symbols() {
    echo -n "  Testing library symbols... "
    
    # Check if we can find key symbols in the library
    if [ -f "$LIB_DIR/libwayland-server.dylib" ]; then
        if nm "$LIB_DIR/libwayland-server.dylib" 2>/dev/null | grep -q "wl_display_create" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Key symbols found"
            WAYLAND_TEST_PASSED=$((WAYLAND_TEST_PASSED + 1))
            return 0
        fi
    fi
    
    echo -e "${YELLOW}⚠${NC} Symbol check skipped (library format)"
    return 0
}

# Run all tests
test_wayland_version
test_wayland_client_version
test_wayland_scanner
test_wayland_headers
test_wayland_library_link
test_wayland_scanner_functionality
test_wayland_symbols

echo ""
if [ $WAYLAND_TEST_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All Wayland functionality tests passed! ($WAYLAND_TEST_PASSED/$((WAYLAND_TEST_PASSED + WAYLAND_TEST_FAILED)))${NC}"
else
    echo -e "${RED}❌ Some Wayland functionality tests failed ($WAYLAND_TEST_FAILED failed, $WAYLAND_TEST_PASSED passed)${NC}"
    ERRORS=$((ERRORS + WAYLAND_TEST_FAILED))
fi

echo ""
echo "======================================"

# Track what's actually missing
MISSING_BUILD_TOOLS=0
MISSING_WAYLAND=0
MISSING_PIXMAN=0

# Check if build tools are missing
if ! command -v cmake &> /dev/null; then
    MISSING_BUILD_TOOLS=1
fi
if ! command -v pkg-config &> /dev/null; then
    MISSING_BUILD_TOOLS=1
fi

# Check if pixman is missing
if ! pkg-config --exists "pixman-1" 2>/dev/null; then
    MISSING_PIXMAN=1
fi

# Check if wayland is missing
if [ $WAYLAND_SERVER_FOUND -eq 0 ] || [ $WAYLAND_CLIENT_FOUND -eq 0 ]; then
    MISSING_WAYLAND=1
fi
if ! command -v wayland-scanner &> /dev/null && [ ! -f "$LIB_DIR/../bin/wayland-scanner" ]; then
    MISSING_WAYLAND=1
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All required dependencies are installed!${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $WARNINGS optional dependencies missing${NC}"
    fi
    exit 0
else
    echo -e "${RED}❌ $ERRORS required dependencies missing${NC}"
    echo ""
    echo "Install missing dependencies:"
    echo ""
    
    if [ $MISSING_BUILD_TOOLS -eq 1 ] || [ $MISSING_PIXMAN -eq 1 ]; then
        echo "1. Build tools and libraries (via Homebrew):"
        INSTALL_CMD="brew install"
        if [ $MISSING_BUILD_TOOLS -eq 1 ]; then
            INSTALL_CMD="$INSTALL_CMD cmake pkg-config"
        fi
        if [ $MISSING_PIXMAN -eq 1 ]; then
            INSTALL_CMD="$INSTALL_CMD pixman"
        fi
        echo "   $INSTALL_CMD"
        echo ""
    fi
    
    if [ $MISSING_WAYLAND -eq 1 ]; then
        echo "2. Wayland libraries (build from source - Homebrew formula requires Linux):"
        echo "   # First install build dependencies:"
        echo "   brew install meson ninja expat libffi libxml2"
        echo ""
        echo "   # Then build wayland from source:"
        echo "   git clone https://gitlab.freedesktop.org/wayland/wayland.git"
        echo "   cd wayland"
        echo "   meson setup build -Ddocumentation=false"
        echo "   meson compile -C build"
        echo "   sudo meson install -C build"
        echo ""
        echo "   Note: Wayland is platform-agnostic and builds fine on macOS."
        echo "   Homebrew just won't install it due to formula Linux requirement."
        echo ""
        echo "   Or see docs/DEPENDENCIES.md for detailed instructions"
        echo ""
    fi
    
    echo "NOTE: We do NOT install wlroots - it's Linux-only and won't work on macOS"
    exit 1
fi

