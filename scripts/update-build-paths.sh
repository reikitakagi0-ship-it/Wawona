#!/bin/bash
# update-build-paths.sh
# Updates build systems to reference new compat/ paths

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Updating build systems to use compat/ paths..."

# Wayland meson.build
if [ -f "dependencies/wayland/src/meson.build" ]; then
    echo "Updating Wayland meson.build..."
    sed -i.bak 's|"ios_compat.h"|"../../../../compat/ios/headers/wayland/ios_compat.h"|g' \
        dependencies/wayland/src/meson.build
    sed -i.bak 's|include_directories.*ios_compat|include_directories("../../../../compat/ios/headers/wayland")|g' \
        dependencies/wayland/src/meson.build
fi

# KosmicKrisp meson.build
if [ -f "dependencies/kosmickrisp/meson.build" ]; then
    echo "Updating KosmicKrisp meson.build..."
    sed -i.bak 's|"util/ios_compat.h"|"../../../../compat/ios/headers/kosmickrisp/ios_compat.h"|g' \
        dependencies/kosmickrisp/meson.build
    sed -i.bak 's|include_directories.*src/util|include_directories("../../../../compat/ios/headers/kosmickrisp")|g' \
        dependencies/kosmickrisp/meson.build
    sed -i.bak 's|include_directories.*sys|include_directories("../../../../compat/ios/sys")|g' \
        dependencies/kosmickrisp/meson.build
fi

# Pixman meson.build
if [ -f "dependencies/pixman/pixman/meson.build" ]; then
    echo "Updating Pixman meson.build..."
    sed -i.bak 's|"pixman/ios_compat.h"|"../../../../compat/ios/headers/pixman/ios_compat.h"|g' \
        dependencies/pixman/pixman/meson.build
fi

echo "Build system paths updated!"
echo ""
echo "Note: You may need to manually verify and adjust paths in:"
echo "- dependencies/wayland/src/meson.build"
echo "- dependencies/kosmickrisp/meson.build"
echo "- dependencies/pixman/pixman/meson.build"

