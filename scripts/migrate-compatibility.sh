#!/bin/bash
# migrate-compatibility.sh
# Migrates compatibility code from dependencies to compat/ directory

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Migrating compatibility code..."

# Wayland
if [ -f "dependencies/wayland/src/ios_compat.h" ]; then
    echo "Migrating Wayland ios_compat.h..."
    cp dependencies/wayland/src/ios_compat.h compat/ios/headers/wayland/ios_compat.h
    # Update references in wayland source
    find dependencies/wayland/src -type f -name "*.c" -exec sed -i.bak 's|"ios_compat.h"|"../../../../compat/ios/headers/wayland/ios_compat.h"|g' {} \;
fi

# KosmicKrisp
if [ -f "dependencies/kosmickrisp/src/util/ios_compat.h" ]; then
    echo "Migrating KosmicKrisp ios_compat.h..."
    cp dependencies/kosmickrisp/src/util/ios_compat.h compat/ios/headers/kosmickrisp/ios_compat.h
    cp dependencies/kosmickrisp/src/util/ios_sys_headers.h compat/ios/headers/kosmickrisp/ios_sys_headers.h
    # Update references
    find dependencies/kosmickrisp/src/util -type f -name "*.c" -exec sed -i.bak 's|"util/ios_compat.h"|"../../../../../compat/ios/headers/kosmickrisp/ios_compat.h"|g' {} \;
fi

# System headers
echo "Migrating system headers..."
find dependencies/kosmickrisp/src/util/sys -name "*.h" -exec cp {} compat/ios/sys/ \; 2>/dev/null || true

# Pixman
if [ -f "dependencies/pixman/pixman/ios_compat.h" ]; then
    echo "Migrating Pixman ios_compat.h..."
    cp dependencies/pixman/pixman/ios_compat.h compat/ios/headers/pixman/ios_compat.h
fi

echo "Migration complete!"
echo ""
echo "Next steps:"
echo "1. Update build systems to reference compat/ paths"
echo "2. Test builds"
echo "3. Remove old compatibility files from dependencies/"

