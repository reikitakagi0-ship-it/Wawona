#!/bin/bash
# Create stub pkg-config files for libudev and libevdev
# These satisfy Weston's dependency checks when building clients only

set -e

PKG_CONFIG_DIR="${PKG_CONFIG_PATH%%:*}"
if [ -z "$PKG_CONFIG_DIR" ] || [ "$PKG_CONFIG_DIR" = "$PKG_CONFIG_PATH" ]; then
    # Try common locations
    if [ -d "/opt/homebrew/lib/pkgconfig" ]; then
        PKG_CONFIG_DIR="/opt/homebrew/lib/pkgconfig"
    elif [ -d "/usr/local/lib/pkgconfig" ]; then
        PKG_CONFIG_DIR="/usr/local/lib/pkgconfig"
    else
        echo "Error: Could not determine pkg-config directory"
        echo "Set PKG_CONFIG_PATH or install to /opt/homebrew/lib/pkgconfig"
        exit 1
    fi
fi

echo "Creating stub pkg-config files in $PKG_CONFIG_DIR..."

# Create libudev stub
cat > "$PKG_CONFIG_DIR/libudev.pc" << 'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libudev
Description: Library to access udev device information (stub for macOS)
Version: 136
Libs: -L${libdir} -ludev
Cflags: -I${includedir}
EOF

# Create libevdev stub  
cat > "$PKG_CONFIG_DIR/libevdev.pc" << 'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: libevdev
Description: Wrapper library for evdev devices (stub for macOS)
Version: 1.0
Libs: -L${libdir} -levdev
Cflags: -I${includedir}
EOF

echo "✓ Created stub pkg-config files"
echo "  - $PKG_CONFIG_DIR/libudev.pc"
echo "  - $PKG_CONFIG_DIR/libevdev.pc"
echo ""
echo "Note: These are stub files for dependency checking only."
echo "      Actual libraries are not required for building clients."

