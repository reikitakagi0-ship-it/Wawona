#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EGL Comprehensive Test for macOS"
echo "Testing KosmicKrisp + Zink EGL Implementation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Set up library paths
export DYLD_LIBRARY_PATH="kosmickrisp/build/src/egl:kosmickrisp/build/src/mesa/glapi/es2api:kosmickrisp/build/src/gallium/targets/dri:$DYLD_LIBRARY_PATH"

# Set up DRI driver search path
export LIBGL_DRIVERS_PATH="kosmickrisp/build/src/gallium/targets/dri"

# Force Zink driver
export MESA_LOADER_DRIVER_OVERRIDE=zink

# Disable software rendering
export LIBGL_ALWAYS_SOFTWARE=0

# Enable debug output
export EGL_LOG_LEVEL=debug
export MESA_DEBUG=1

echo "Environment:"
echo "  DYLD_LIBRARY_PATH: $DYLD_LIBRARY_PATH"
echo "  LIBGL_DRIVERS_PATH: $LIBGL_DRIVERS_PATH"
echo "  MESA_LOADER_DRIVER_OVERRIDE: $MESA_LOADER_DRIVER_OVERRIDE"
echo ""

# Check if libraries exist
echo "Checking libraries:"
[ -f "kosmickrisp/build/src/egl/libEGL.1.dylib" ] && echo "  ✓ libEGL.1.dylib found" || echo "  ✗ libEGL.1.dylib NOT FOUND"
[ -f "kosmickrisp/build/src/mesa/glapi/es2api/libGLESv2.2.dylib" ] && echo "  ✓ libGLESv2.2.dylib found" || echo "  ✗ libGLESv2.2.dylib NOT FOUND"
[ -f "kosmickrisp/build/src/gallium/targets/dri/libgallium-26.0.0-devel.dylib" ] && echo "  ✓ libgallium DRI driver found" || echo "  ✗ libgallium DRI driver NOT FOUND"
echo ""

# Run test
echo "Running EGL test..."
./test-egl 2>&1
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ All tests passed! EGL is working correctly."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✗ Tests failed. Check output above for details."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

exit $EXIT_CODE
