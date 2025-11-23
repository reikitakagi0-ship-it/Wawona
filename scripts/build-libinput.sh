#!/bin/bash
# Build libinput from source for macOS
# Attempts to build libinput with macOS compatibility stubs

set -e

# Use the macOS compatibility build script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/build-libinput-macos.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔨 Building libinput for macOS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}⚠${NC}  libinput is Linux-specific and depends on:"
echo -e "   - Linux kernel evdev interface"
echo -e "   - udev (Linux device management)"
echo -e "   - libevdev (Linux input device library)"
echo -e ""
echo -e "${YELLOW}ℹ${NC}  This build will attempt macOS compatibility but may have limitations."
echo ""

# Detect install prefix
if [[ "$(uname -m)" == "arm64" ]] && [ -d "/opt/homebrew" ]; then
    INSTALL_PREFIX="/opt/homebrew"
else
    INSTALL_PREFIX="/usr/local"
fi

echo -e "${YELLOW}ℹ${NC} Install prefix: ${INSTALL_PREFIX}"
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

if ! command -v pkg-config &> /dev/null; then
    echo -e "${RED}✗${NC} pkg-config not found. Install with: brew install pkg-config"
    exit 1
fi

# Check for required dependencies
MISSING_DEPS=()

# Check for libevdev (Linux-specific, may not be available)
if ! pkg-config --exists libevdev; then
    echo -e "${YELLOW}⚠${NC} libevdev not found (Linux-specific)"
    MISSING_DEPS+=("libevdev")
fi

# Check for udev (Linux-specific, definitely not available)
if ! pkg-config --exists libudev; then
    echo -e "${YELLOW}⚠${NC} libudev not found (Linux-specific, required)"
    MISSING_DEPS+=("libudev")
fi

# Check for mtdev (multi-touch protocol)
if ! pkg-config --exists mtdev; then
    echo -e "${YELLOW}⚠${NC} mtdev not found"
    MISSING_DEPS+=("mtdev")
fi

# Check for systemd (Linux-specific)
if ! pkg-config --exists systemd; then
    echo -e "${YELLOW}⚠${NC} systemd not found (Linux-specific)"
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}✗${NC} Missing required dependencies: ${MISSING_DEPS[*]}"
    echo -e "${YELLOW}ℹ${NC} libinput requires Linux-specific libraries:"
    echo -e "   - libevdev (Linux evdev interface)"
    echo -e "   - libudev (Linux device management)"
    echo -e "   - mtdev (multi-touch protocol)"
    echo ""
    echo -e "${YELLOW}ℹ${NC} These cannot be ported to macOS as they depend on Linux kernel interfaces."
    echo -e "${YELLOW}ℹ${NC} Weston will be skipped on macOS (libinput is required)."
    echo -e "${YELLOW}ℹ${NC} Minimal clients and debug tools will still work."
    exit 0
fi

echo -e "${GREEN}✓${NC} Dependencies OK"
echo ""

# Clone libinput if needed
if [ ! -d "$LIBINPUT_DIR" ]; then
    echo -e "${YELLOW}ℹ${NC} Cloning libinput repository..."
    cd "$PROJECT_ROOT"
    git clone https://gitlab.freedesktop.org/libinput/libinput.git
    echo -e "${GREEN}✓${NC} libinput cloned"
else
    echo -e "${GREEN}✓${NC} libinput repository exists"
fi

# Update libinput
echo -e "${YELLOW}ℹ${NC} Updating libinput..."
cd "$LIBINPUT_DIR"
git pull || true
echo ""

# Create build directory
mkdir -p "$LIBINPUT_BUILD_DIR"
cd "$LIBINPUT_BUILD_DIR"

# Configure libinput build
echo -e "${YELLOW}ℹ${NC} Configuring libinput build..."

MESON_OPTS=(
    "--prefix=$INSTALL_PREFIX"
    "--buildtype=release"
    "-Ddocumentation=false"
    "-Dtests=false"
    "-Ddebug-gui=false"
)

# Run meson setup
if [ ! -f "build.ninja" ]; then
    meson setup . .. "${MESON_OPTS[@]}" || {
        echo -e "${RED}✗${NC} libinput configuration failed"
        echo -e "${YELLOW}ℹ${NC} libinput requires Linux kernel interfaces and cannot run on macOS."
        exit 0
    }
else
    meson configure . "${MESON_OPTS[@]}" || {
        echo -e "${RED}✗${NC} libinput configuration failed"
        exit 0
    }
fi

echo -e "${GREEN}✓${NC} Configuration complete"
echo ""

# Build
echo -e "${YELLOW}ℹ${NC} Building libinput..."
ninja -j$(sysctl -n hw.ncpu) || {
    echo -e "${RED}✗${NC} libinput build failed"
    echo -e "${YELLOW}ℹ${NC} libinput requires Linux kernel interfaces and cannot build on macOS."
    exit 0
}
echo -e "${GREEN}✓${NC} Build complete"
echo ""

# Install
echo -e "${YELLOW}ℹ${NC} Installing libinput..."
echo -e "${YELLOW}⚠${NC} This requires sudo privileges..."
if sudo ninja install; then
    echo -e "${GREEN}✓${NC} Installation complete"
else
    echo -e "${RED}✗${NC} Installation failed (may need sudo password)"
    echo -e "${YELLOW}ℹ${NC} You can install manually: cd $LIBINPUT_BUILD_DIR && sudo ninja install"
    exit 1
fi
echo ""

# Verify installation
echo -e "${YELLOW}ℹ${NC} Verifying installation..."
if pkg-config --exists libinput; then
    VERSION=$(pkg-config --modversion libinput)
    echo -e "${GREEN}✓${NC} libinput installed: version ${VERSION}"
else
    echo -e "${RED}✗${NC} libinput not found after installation"
    exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} libinput installed successfully!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} Installed to: ${INSTALL_PREFIX}"
echo -e "${YELLOW}ℹ${NC} You can now build Weston clients: make test-clients"
echo ""

