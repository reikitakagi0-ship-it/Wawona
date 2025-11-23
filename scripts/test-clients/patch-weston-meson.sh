#!/bin/bash
# Patch Weston's meson.build to make libinput/libevdev/libudev optional
# This allows building clients without the compositor

set -e

WESTON_DIR="$1"
if [ -z "$WESTON_DIR" ]; then
    echo "Usage: $0 <weston-dir>"
    exit 1
fi

MESON_BUILD="$WESTON_DIR/meson.build"
LIBWESTON_MESON="$WESTON_DIR/libweston/meson.build"

if [ ! -f "$MESON_BUILD" ]; then
    echo "Error: $MESON_BUILD not found"
    exit 1
fi

echo "Patching Weston meson.build files for clients-only build..."

# Check if already patched
if grep -q "# Patched for clients-only build" "$MESON_BUILD"; then
    echo "Already patched, skipping..."
    exit 0
fi

# Make libinput optional in main meson.build
sed -i.bak \
    -e 's/^dep_libinput = dependency(.*libinput.*)$/# Patched for clients-only build\n# Make libinput optional\nhas_libinput_backend = false\nforeach b : [ '\''drm'\'', '\''headless'\'', '\''wayland'\'', '\''x11'\'' ]\n\tif get_option('\''backend-'\'' + b)\n\t\thas_libinput_backend = true\n\t\tbreak\n\tendif\nendforeach\nif has_libinput_backend\n\tdep_libinput = dependency('\''libinput'\'', version: '\''>= 1.2.0'\'')\nelse\n\tdep_libinput = dependency('\''libinput'\'', version: '\''>= 1.2.0'\'', required: false)\nendif/' \
    "$MESON_BUILD"

# Make libevdev optional
sed -i.bak \
    -e 's/^dep_libevdev = dependency(.*libevdev.*)$/if has_libinput_backend\n\tdep_libevdev = dependency('\''libevdev'\'')\nelse\n\tdep_libevdev = dependency('\''libevdev'\'', required: false)\nendif/' \
    "$MESON_BUILD"

# Fix the HAVE_COMPOSE_AND_KANA check to handle optional libinput
sed -i.bak \
    -e 's/^if dep_xkbcommon.version().version_compare(.*)$/if dep_libinput.found() and dep_xkbcommon.version().version_compare(.*)/' \
    "$MESON_BUILD"

# Make libinput-backend conditional in libweston/meson.build
if [ -f "$LIBWESTON_MESON" ]; then
    # Check if libinput-backend section exists and make it conditional
    if grep -q "lib_libinput_backend = static_library" "$LIBWESTON_MESON"; then
        # Replace the unconditional libinput-backend build with conditional
        sed -i.bak \
            -e '/^lib_libinput_backend = static_library/,/^dep_libinput_backend = declare_dependency/ {
                /^lib_libinput_backend = static_library/i\
# Only build libinput-backend if a backend that needs it is enabled\
has_libinput_backend = false\
foreach b : [ '\''drm'\'', '\''headless'\'', '\''wayland'\'', '\''x11'\'' ]\
\tif get_option('\''backend-'\'' + b)\
\t\thas_libinput_backend = true\
\t\tbreak\
\tendif\
endforeach\
if has_libinput_backend
                /^dep_libinput_backend = declare_dependency/a\
endif
            }' \
            "$LIBWESTON_MESON"
    fi
fi

# Fix backend-default check to handle no backends
sed -i.bak \
    -e '/^if not get_option(.*backend-default.*)$/,/^endif$/ {
        /^if not get_option(.*backend-default.*)$/a\
\t# Allow no backends when building clients only\
\tif backend_default == '\''auto'\'' and not has_libinput_backend\
\t\tbackend_default = '\''headless'\''\
\t\tconfig_h.set_quoted('\''WESTON_NATIVE_BACKEND'\'', '\''headless'\'')\
\t\tmessage('\''No backends enabled, using headless as default (clients-only build)'\')\
\t\t# Skip backend check for clients-only build\
\telse
        /^endif$/i\
\tendif
    }' \
    "$MESON_BUILD"

echo "Patched successfully!"

