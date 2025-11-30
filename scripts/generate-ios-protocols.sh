#!/bin/bash
set -e

SCANNER=$(which wayland-scanner)
PROTOCOLS_DIR="dependencies/wayland-protocols"
OUT_DIR="src/protocols"

echo "Generating Wayland protocols..."

generate() {
    local xml=$1
    local name=$2
    
    echo "  Generating $name..."
    $SCANNER private-code "$xml" "$OUT_DIR/$name.c"
    $SCANNER server-header "$xml" "$OUT_DIR/$name.h"
}

# Core protocols
generate "$PROTOCOLS_DIR/stable/xdg-shell/xdg-shell.xml" "xdg-shell-protocol"
generate "$PROTOCOLS_DIR/stable/presentation-time/presentation-time.xml" "presentation-time-protocol"
generate "$PROTOCOLS_DIR/stable/viewporter/viewporter.xml" "viewporter-protocol"

# Unstable/Staging protocols
generate "$PROTOCOLS_DIR/unstable/primary-selection/primary-selection-unstable-v1.xml" "primary-selection-protocol"
generate "$PROTOCOLS_DIR/staging/xdg-activation/xdg-activation-v1.xml" "xdg-activation-protocol"
generate "$PROTOCOLS_DIR/staging/fractional-scale/fractional-scale-v1.xml" "fractional-scale-protocol"
generate "$PROTOCOLS_DIR/staging/cursor-shape/cursor-shape-v1.xml" "cursor-shape-protocol"
generate "$PROTOCOLS_DIR/unstable/text-input/text-input-unstable-v3.xml" "text-input-v3-protocol"
generate "$PROTOCOLS_DIR/unstable/text-input/text-input-unstable-v1.xml" "text-input-v1-protocol"
generate "$PROTOCOLS_DIR/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml" "xdg-decoration-protocol"
generate "$PROTOCOLS_DIR/staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml" "xdg-toplevel-icon-protocol"
generate "$PROTOCOLS_DIR/staging/color-management/color-management-v1.xml" "color-management-v1-protocol"

echo "Done."
