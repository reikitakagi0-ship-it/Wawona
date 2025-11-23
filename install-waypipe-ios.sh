#!/bin/bash

# install-waypipe-ios.sh
# Cross-compiles Waypipe for iOS Simulator

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYPIPE_DIR="${ROOT_DIR}/waypipe"
INSTALL_DIR="${ROOT_DIR}/ios-install"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Create install directory
mkdir -p "${INSTALL_DIR}/bin"

# Source cargo env and ensure rustup-managed Rust is used (not Homebrew Rust)
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Prioritize rustup-managed Rust over Homebrew Rust (Homebrew Rust lacks iOS targets)
export PATH="$HOME/.cargo/bin:$PATH"

# Check if rustup is installed
if ! command -v rustup >/dev/null 2>&1; then
    echo "Error: rustup not found. Install Rust via rustup: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo "Note: Homebrew Rust doesn't include iOS Simulator targets"
    exit 1
fi

# Verify we're using rustup-managed cargo
if [ -f "$HOME/.cargo/bin/cargo" ]; then
    CARGO_CMD="$HOME/.cargo/bin/cargo"
    echo "Using rustup-managed cargo: $CARGO_CMD"
else
    echo "Error: rustup-managed cargo not found at ~/.cargo/bin/cargo"
    exit 1
fi

# Install iOS Simulator target if not already installed
echo "Installing Rust target for iOS Simulator..."
rustup target add aarch64-apple-ios-sim || {
    echo "Error: Failed to install aarch64-apple-ios-sim target"
    echo "Make sure rustup is installed and configured correctly"
    exit 1
}

# Verify target std library is available
echo "Verifying iOS Simulator target std library..."
RUSTC_CMD="$HOME/.cargo/bin/rustc"
if [ ! -f "$RUSTC_CMD" ]; then
    RUSTC_CMD="rustc"
fi
RUST_SYSROOT=$($RUSTC_CMD --print sysroot 2>/dev/null || echo "")
if [ -z "$RUST_SYSROOT" ] || [ ! -d "$RUST_SYSROOT/lib/rustlib/aarch64-apple-ios-sim/lib" ]; then
    echo "Error: iOS Simulator std library not found"
    echo "Rust sysroot: $RUST_SYSROOT"
    echo "Try: rustup component add rust-std --target aarch64-apple-ios-sim"
    exit 1
fi
echo "iOS Simulator std library found at: $RUST_SYSROOT/lib/rustlib/aarch64-apple-ios-sim/lib"

# Clone Waypipe if not exists
if [ ! -d "${WAYPIPE_DIR}" ]; then
    echo "Cloning Waypipe..."
    git clone https://gitlab.freedesktop.org/mstoeckl/waypipe.git "${WAYPIPE_DIR}"
fi

cd "${WAYPIPE_DIR}"

# Set PKG_CONFIG_PATH
export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"

# Set Cargo environment variables for cross-compilation
# Treat warnings as errors (matching Wawona's build requirements)
export CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS="-C link-arg=-isysroot -C link-arg=${SDK_PATH} -C link-arg=-mios-simulator-version-min=15.0 -L ${INSTALL_DIR}/lib -D warnings"
export RUSTFLAGS="-D warnings"
export CC="xcrun -sdk iphonesimulator clang"
export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
export PKG_CONFIG_ALLOW_CROSS=1

# Build
echo "Building Waypipe for iOS Simulator..."
# We disable gbmfallback because GBM is not available on iOS
# We enable lz4 and zstd which we just installed
# Video feature requires ffmpeg, which is not yet ported. Disabling for now.
# Use rustup run to ensure we use rustup-managed toolchain
rustup run stable cargo build \
    --target aarch64-apple-ios-sim \
    --release \
    --no-default-features \
    --features "dmabuf lz4 zstd" || {
    echo "Error: Waypipe build failed"
    echo "If you see 'can't find crate for core/std', the iOS Simulator std library may be missing"
    echo "Try: rustup component add rust-std --target aarch64-apple-ios-sim"
    exit 1
}


# Install
echo "Installing Waypipe..."
cp target/aarch64-apple-ios-sim/release/waypipe "${INSTALL_DIR}/bin/"

echo "Success! Waypipe installed to ${INSTALL_DIR}/bin/waypipe"
