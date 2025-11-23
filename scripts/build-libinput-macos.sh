#!/bin/bash
# Build libinput compatibility layer for macOS
# Creates minimal stubs for Linux-specific dependencies and builds libinput

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBINPUT_DIR="$PROJECT_ROOT/libinput"
LIBINPUT_BUILD_DIR="$LIBINPUT_DIR/build"
STUBS_DIR="$PROJECT_ROOT/libinput-macos-stubs"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔨 Building libinput macOS Compatibility Layer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}⚠${NC}  This creates macOS compatibility stubs for Linux-specific libraries"
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
if ! command -v meson &> /dev/null; then
    echo -e "${RED}✗${NC} meson not found"
    exit 1
fi

if ! command -v ninja &> /dev/null; then
    echo -e "${RED}✗${NC} ninja not found"
    exit 1
fi

# Create macOS compatibility stubs
echo -e "${YELLOW}ℹ${NC} Creating macOS compatibility stubs..."

mkdir -p "$STUBS_DIR"
cd "$STUBS_DIR"

# Create libevdev stub
cat > libevdev-stub.pc << 'EOF'
prefix=/opt/homebrew
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libevdev
Description: Linux input device library (macOS stub)
Version: 1.13.0
Libs: -L${libdir} -levdev-stub
Cflags: -I${includedir}
EOF

# Create libudev stub
cat > libudev-stub.pc << 'EOF'
prefix=/opt/homebrew
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libudev
Description: udev library (macOS stub)
Version: 251
Libs: -L${libdir} -ludev-stub
Cflags: -I${includedir}
EOF

# Create mtdev stub
cat > mtdev-stub.pc << 'EOF'
prefix=/opt/homebrew
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: mtdev
Description: Multi-touch protocol library (macOS stub)
Version: 1.1.6
Libs: -L${libdir} -lmtdev-stub
Cflags: -I${includedir}
EOF

echo -e "${GREEN}✓${NC} Stub pkg-config files created"
echo ""

# Build stub libraries
echo -e "${YELLOW}ℹ${NC} Building stub libraries..."

# Simple stub library source
cat > evdev-stub.c << 'EOFSTUB'
#include <stdint.h>
#include <stddef.h>

// Minimal libevdev stub for macOS
// These functions are stubs that return safe defaults

struct input_event {
    uint64_t time;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

struct libevdev {
    int dummy;
};

struct libevdev* libevdev_new(void) { return NULL; }
void libevdev_free(struct libevdev *dev) { (void)dev; }
int libevdev_set_fd(struct libevdev *dev, int fd) { (void)dev; (void)fd; return 0; }
int libevdev_get_fd(const struct libevdev *dev) { (void)dev; return -1; }
int libevdev_next_event(struct libevdev *dev, unsigned int flags, struct input_event *ev) { (void)dev; (void)flags; (void)ev; return -1; }
const char* libevdev_get_name(const struct libevdev *dev) { (void)dev; return "macOS Input Device"; }
int libevdev_has_event_type(const struct libevdev *dev, unsigned int type) { (void)dev; (void)type; return 0; }
int libevdev_has_event_code(const struct libevdev *dev, unsigned int type, unsigned int code) { (void)dev; (void)type; (void)code; return 0; }
EOFSTUB

cat > udev-stub.c << 'EOFSTUB'
#include <stdint.h>
#include <stddef.h>

// Minimal libudev stub for macOS
struct udev {
    int dummy;
};

struct udev* udev_new(void) { return NULL; }
void udev_unref(struct udev *udev) { (void)udev; }
struct udev_device* udev_device_new_from_syspath(struct udev *udev, const char *syspath) { (void)udev; (void)syspath; return NULL; }
void udev_device_unref(struct udev_device *device) { (void)device; }
const char* udev_device_get_devnode(struct udev_device *device) { (void)device; return NULL; }
EOFSTUB

cat > mtdev-stub.c << 'EOFSTUB'
#include <stdint.h>
#include <stddef.h>

// Minimal mtdev stub for macOS
struct input_event {
    uint64_t time;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

struct mtdev {
    int dummy;
};

struct mtdev* mtdev_open(const char *path, int flags) { (void)path; (void)flags; return NULL; }
void mtdev_close(struct mtdev *mtdev) { (void)mtdev; }
int mtdev_get(struct mtdev *mtdev, struct input_event *ev, int maxev) { (void)mtdev; (void)ev; (void)maxev; return 0; }
EOFSTUB

# Compile stub libraries (suppress warnings)
clang -shared -fPIC -Wno-visibility -o libevdev-stub.dylib evdev-stub.c -install_name @rpath/libevdev-stub.dylib || {
    echo -e "${RED}✗${NC} Failed to build libevdev stub"
    exit 1
}

clang -shared -fPIC -Wno-visibility -o libudev-stub.dylib udev-stub.c -install_name @rpath/libudev-stub.dylib || {
    echo -e "${RED}✗${NC} Failed to build libudev stub"
    exit 1
}

clang -shared -fPIC -Wno-visibility -o libmtdev-stub.dylib mtdev-stub.c -install_name @rpath/libmtdev-stub.dylib || {
    echo -e "${RED}✗${NC} Failed to build mtdev stub"
    exit 1
}

echo -e "${GREEN}✓${NC} Stub libraries built"
echo ""

# Install stubs
echo -e "${YELLOW}ℹ${NC} Installing stub libraries..."
echo -e "${YELLOW}⚠${NC} This requires sudo privileges..."
if sudo mkdir -p "$INSTALL_PREFIX/lib/pkgconfig" && \
   sudo cp *.pc "$INSTALL_PREFIX/lib/pkgconfig/" && \
   sudo cp *.dylib "$INSTALL_PREFIX/lib/"; then
    echo -e "${GREEN}✓${NC} Stubs installed"
else
    echo -e "${RED}✗${NC} Failed to install stubs (may need sudo password)"
    echo -e "${YELLOW}ℹ${NC} You can install manually:"
    echo -e "   sudo mkdir -p $INSTALL_PREFIX/lib/pkgconfig"
    echo -e "   sudo cp $STUBS_DIR/*.pc $INSTALL_PREFIX/lib/pkgconfig/"
    echo -e "   sudo cp $STUBS_DIR/*.dylib $INSTALL_PREFIX/lib/"
    exit 1
fi

# Add to PKG_CONFIG_PATH
export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

echo ""

# Now try to build libinput
echo -e "${YELLOW}ℹ${NC} Attempting to build libinput with macOS stubs..."
echo -e "${YELLOW}⚠${NC}  This may fail - libinput is deeply Linux-specific"
echo ""

cd "$PROJECT_ROOT"

# Clone libinput if needed
if [ ! -d "$LIBINPUT_DIR" ]; then
    echo -e "${YELLOW}ℹ${NC} Cloning libinput repository..."
    git clone https://gitlab.freedesktop.org/libinput/libinput.git
fi

cd "$LIBINPUT_DIR"
git pull || true

mkdir -p "$LIBINPUT_BUILD_DIR"
cd "$LIBINPUT_BUILD_DIR"

MESON_OPTS=(
    "--prefix=$INSTALL_PREFIX"
    "--buildtype=release"
    "-Ddocumentation=false"
    "-Dtests=false"
    "-Ddebug-gui=false"
)

if [ ! -f "build.ninja" ]; then
    PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
    meson setup . .. "${MESON_OPTS[@]}" || {
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}✗${NC} libinput cannot be built on macOS"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}ℹ${NC} libinput requires Linux kernel interfaces that don't exist on macOS:"
        echo -e "   - /dev/input/event* devices (evdev)"
        echo -e "   - udev device management"
        echo -e "   - Linux input subsystem"
        echo ""
        echo -e "${YELLOW}ℹ${NC} Weston will not work on macOS without libinput."
        echo -e "${YELLOW}ℹ${NC} Minimal clients and debug tools will still work."
        echo ""
        exit 0
    }
fi

PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
ninja -j$(sysctl -n hw.ncpu) || {
    echo -e "${RED}✗${NC} libinput build failed"
    exit 0
}

echo -e "${GREEN}✓${NC} libinput built successfully!"
echo ""

# Install
echo -e "${YELLOW}ℹ${NC} Installing libinput..."
sudo PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" ninja install || {
    echo -e "${RED}✗${NC} Installation failed"
    exit 1
}

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} libinput installed!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

