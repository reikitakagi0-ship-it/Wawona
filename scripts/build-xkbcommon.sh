#!/bin/bash
# Build xkbcommon from source for macOS
# xkbcommon is required for keyboard handling in Wayland compositors

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XKBCOMMON_DIR="$PROJECT_ROOT/xkbcommon"
XKBCOMMON_BUILD_DIR="$XKBCOMMON_DIR/build"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔨 Building xkbcommon for macOS${NC}"
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

# Check for optional dependencies
HAS_XCB=false
if pkg-config --exists xcb; then
    HAS_XCB=true
    echo -e "${GREEN}✓${NC} libxcb found (optional, for X11 backend)"
else
    echo -e "${YELLOW}⚠${NC} libxcb not found (X11 backend will be disabled)"
fi

# Check for wayland (required for Wayland backend)
if ! pkg-config --exists wayland-client; then
    echo -e "${RED}✗${NC} wayland-client not found. Install wayland first."
    exit 1
fi

# Check for xkeyboard-config (required for keyboard layouts)
if ! pkg-config --exists xkeyboard-config; then
    echo -e "${YELLOW}⚠${NC} xkeyboard-config not found"
    echo -e "${YELLOW}ℹ${NC} Installing xkeyboard-config..."
    if command -v brew &> /dev/null; then
        brew install xkeyboardconfig || {
            echo -e "${RED}✗${NC} Failed to install xkeyboard-config"
            echo -e "${YELLOW}ℹ${NC} Install manually: brew install xkeyboardconfig"
            exit 1
        }
    else
        echo -e "${RED}✗${NC} xkeyboard-config required but Homebrew not found"
        exit 1
    fi
fi

# Check for bison (required, version >= 3.6)
if ! command -v bison &> /dev/null || [ "$(bison --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | awk -F. '{print $1*100+$2}')" -lt 306 ]; then
    echo -e "${YELLOW}⚠${NC} bison >= 3.6 not found"
    echo -e "${YELLOW}ℹ${NC} Installing bison..."
    if command -v brew &> /dev/null; then
        brew install bison || {
            echo -e "${RED}✗${NC} Failed to install bison"
            echo -e "${YELLOW}ℹ${NC} Install manually: brew install bison"
            exit 1
        }
        # Add Homebrew bison to PATH (it's usually in /opt/homebrew/opt/bison/bin)
        if [ -d "/opt/homebrew/opt/bison/bin" ]; then
            export PATH="/opt/homebrew/opt/bison/bin:$PATH"
        fi
    else
        echo -e "${RED}✗${NC} bison >= 3.6 required but Homebrew not found"
        exit 1
    fi
fi

echo -e "${GREEN}✓${NC} Dependencies OK"
echo ""

# Clone xkbcommon if needed
if [ ! -d "$XKBCOMMON_DIR" ]; then
    echo -e "${YELLOW}ℹ${NC} Cloning xkbcommon repository..."
    cd "$PROJECT_ROOT"
    git clone https://github.com/xkbcommon/libxkbcommon.git xkbcommon
    echo -e "${GREEN}✓${NC} xkbcommon cloned"
else
    echo -e "${GREEN}✓${NC} xkbcommon repository exists"
fi

# Update xkbcommon
echo -e "${YELLOW}ℹ${NC} Updating xkbcommon..."
cd "$XKBCOMMON_DIR"
git pull || true
echo ""

# Create build directory
mkdir -p "$XKBCOMMON_BUILD_DIR"
cd "$XKBCOMMON_BUILD_DIR"

# Configure xkbcommon build
echo -e "${YELLOW}ℹ${NC} Configuring xkbcommon build..."

# Minimal options - xkbcommon will auto-detect backends
# Note: We don't use -Werror here because xkbcommon has compatibility code
# that conflicts with macOS's built-in functions (like strndup)
MESON_OPTS=(
    "--prefix=$INSTALL_PREFIX"
    "--buildtype=release"
    "-Denable-wayland=false"
)

# Run meson setup
if [ ! -f "build.ninja" ]; then
    meson setup . .. "${MESON_OPTS[@]}"
else
    meson configure . "${MESON_OPTS[@]}"
fi

echo -e "${GREEN}✓${NC} Configuration complete"
echo ""

# Build
echo -e "${YELLOW}ℹ${NC} Building xkbcommon..."
ninja -j$(sysctl -n hw.ncpu)
echo -e "${GREEN}✓${NC} Build complete"
echo ""

# Install
echo -e "${YELLOW}ℹ${NC} Installing xkbcommon..."
echo -e "${YELLOW}⚠${NC} This requires sudo privileges..."
if sudo ninja install; then
    echo -e "${GREEN}✓${NC} Installation complete"
else
    echo -e "${RED}✗${NC} Installation failed (may need sudo password)"
    echo -e "${YELLOW}ℹ${NC} You can install manually: cd $XKBCOMMON_BUILD_DIR && sudo ninja install"
    exit 1
fi
echo ""

# Verify installation
echo -e "${YELLOW}ℹ${NC} Verifying installation..."
if pkg-config --exists xkbcommon; then
    VERSION=$(pkg-config --modversion xkbcommon)
    echo -e "${GREEN}✓${NC} xkbcommon installed: version ${VERSION}"
else
    echo -e "${RED}✗${NC} xkbcommon not found after installation"
    exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} xkbcommon installed successfully!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} Installed to: ${INSTALL_PREFIX}"
echo -e "${YELLOW}ℹ${NC} You can now build Weston clients: make test-clients"
echo ""

