#!/bin/bash

# build-host-mesa-tools.sh
# Builds mesa_clc and other tools for the host (macOS)

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOSMICKRISP_DIR="${ROOT_DIR}/kosmickrisp"
HOST_INSTALL_DIR="${ROOT_DIR}/host-install"

# Create install directory
mkdir -p "${HOST_INSTALL_DIR}"

cd "${KOSMICKRISP_DIR}"

# Configure for host
echo "Configuring Mesa for host..."
rm -rf build-host

# We need to enable tools that provide mesa_clc
# mesa_clc is built if we enable a driver that needs it, or if we explicitly ask for it?
# Actually, mesa_clc is built as a tool if needed.
# We can enable 'intel-clc' or similar to force it, or just rely on dependency.
# But we want to install it.
# We'll enable 'intel' tools which might include it, or just build the target directly.

# We need LLVM for mesa_clc
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/llvm/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"



meson setup build-host \
    --prefix "${HOST_INSTALL_DIR}" \
    -Dplatforms=macos \
    -Dgallium-drivers=llvmpipe \
    -Dvulkan-drivers=swrast \
    -Dllvm=enabled \
    -Dglx=disabled \
    -Dmesa-clc=enabled \
    -Dinstall-mesa-clc=true \
    -Dbuild-tests=false



# Build mesa_clc
echo "Building mesa_clc..."
meson compile -C build-host


# Install (we can just copy it)
echo "Installing mesa_clc..."
cp build-host/src/compiler/clc/mesa_clc "${HOST_INSTALL_DIR}/bin/"

# Also vtn_bindgen2 might be needed
echo "Building vtn_bindgen2..."
meson compile -C build-host src/compiler/spirv/vtn_bindgen2
cp build-host/src/compiler/spirv/vtn_bindgen2 "${HOST_INSTALL_DIR}/bin/"

echo "Success! Host tools installed to ${HOST_INSTALL_DIR}/bin"
