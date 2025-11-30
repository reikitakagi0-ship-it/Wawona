#!/bin/bash
# create-all-patches.sh
# Creates patches for all modified dependencies

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Creating patches for all dependencies..."

# Wayland
if [ -d "dependencies/wayland" ]; then
    echo "Creating Wayland patches..."
    cd dependencies/wayland
    if git status --porcelain | grep -q .; then
        ../../scripts/create-patch.sh wayland ios-compat-$(date +%Y%m%d)
    fi
    cd "$ROOT_DIR"
fi

# KosmicKrisp
if [ -d "dependencies/kosmickrisp" ]; then
    echo "Creating KosmicKrisp patches..."
    cd dependencies/kosmickrisp
    if git status --porcelain | grep -q .; then
        ../../scripts/create-patch.sh kosmickrisp ios-compat-$(date +%Y%m%d)
    fi
    cd "$ROOT_DIR"
fi

# Pixman
if [ -d "dependencies/pixman" ]; then
    echo "Creating Pixman patches..."
    cd dependencies/pixman
    if git status --porcelain | grep -q .; then
        ../../scripts/create-patch.sh pixman ios-compat-$(date +%Y%m%d)
    fi
    cd "$ROOT_DIR"
fi

echo "Patches created in patches/ directory"
