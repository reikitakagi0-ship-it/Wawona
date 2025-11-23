#!/bin/bash
# Build Wayland debugging tools (wayland-info, wayland-debug)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBUG_DIR="$PROJECT_ROOT/test-clients/debug"
BUILD_DIR="$DEBUG_DIR/build"
INSTALL_DIR="$DEBUG_DIR/bin"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔨 Building Wayland Debugging Tools${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check dependencies
if ! pkg-config --exists wayland-client; then
    echo -e "${RED}✗${NC} wayland-client not found"
    exit 1
fi

mkdir -p "$DEBUG_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

WAYLAND_CFLAGS=$(pkg-config --cflags wayland-client)
WAYLAND_LIBS=$(pkg-config --libs wayland-client)
CFLAGS="$WAYLAND_CFLAGS -Wall -Wextra -Werror -std=c11"
LIBS="$WAYLAND_LIBS"

# Build wayland-info
echo -e "${YELLOW}ℹ${NC} Building wayland-info..."
cat > "$BUILD_DIR/wayland-info.c" << 'EOFINFOSRC'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

struct wl_display *display = NULL;

static void registry_global(void *data, struct wl_registry *registry,
                           uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)registry;
    printf("Global: name=%u, interface=%s, version=%u\n", name, interface, version);
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                  uint32_t name) {
    (void)data;
    (void)registry;
    printf("Global removed: name=%u\n", name);
}

static const struct wl_registry_listener registry_listener = {
    registry_global,
    registry_global_remove
};

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    const char *display_name = getenv("WAYLAND_DISPLAY");
    if (!display_name) {
        display_name = "wayland-0";
    }

    printf("Connecting to Wayland display: %s\n", display_name);
    display = wl_display_connect(display_name);
    if (!display) {
        fprintf(stderr, "Failed to connect to Wayland display\n");
        return 1;
    }

    printf("\n=== Wayland Globals ===\n");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    printf("\n=== Display Information ===\n");
    printf("Display: %p\n", display);
    
    // Get formats if wl_shm is available
    wl_display_roundtrip(display);

    wl_registry_destroy(registry);
    wl_display_disconnect(display);

    return 0;
}
EOFINFOSRC

clang $CFLAGS -o "$INSTALL_DIR/wayland-info" "$BUILD_DIR/wayland-info.c" $LIBS
echo -e "${GREEN}✓${NC} Built wayland-info"

# Build wayland-debug (simplified version)
echo -e "${YELLOW}ℹ${NC} Building wayland-debug..."
cat > "$BUILD_DIR/wayland-debug.c" << 'EOFDEBUGSRC'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

struct wl_display *display = NULL;

static void registry_global(void *data, struct wl_registry *registry,
                           uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)registry;
    fprintf(stderr, "[DEBUG] Global: name=%u, interface=%s, version=%u\n", 
            name, interface, version);
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                  uint32_t name) {
    (void)data;
    (void)registry;
    fprintf(stderr, "[DEBUG] Global removed: name=%u\n", name);
}

static const struct wl_registry_listener registry_listener = {
    registry_global,
    registry_global_remove
};

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <wayland-client-command> [args...]\n", argv[0]);
        fprintf(stderr, "Example: %s weston-simple-shm\n", argv[0]);
        return 1;
    }

    const char *display_name = getenv("WAYLAND_DISPLAY");
    if (!display_name) {
        display_name = "wayland-0";
    }

    fprintf(stderr, "[DEBUG] Connecting to Wayland display: %s\n", display_name);
    display = wl_display_connect(display_name);
    if (!display) {
        fprintf(stderr, "[DEBUG] Failed to connect to Wayland display\n");
        return 1;
    }

    fprintf(stderr, "[DEBUG] Connected. Listing globals...\n");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    fprintf(stderr, "[DEBUG] Executing: %s\n", argv[1]);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);

    // Execute the client
    execvp(argv[1], &argv[1]);
    perror("execvp");
    return 1;
}
EOFDEBUGSRC

clang $CFLAGS -o "$INSTALL_DIR/wayland-debug" "$BUILD_DIR/wayland-debug.c" $LIBS
echo -e "${GREEN}✓${NC} Built wayland-debug"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} Debugging tools built!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} Tools installed to: ${INSTALL_DIR}"
echo -e "${YELLOW}ℹ${NC} Usage: ${INSTALL_DIR}/wayland-info"
echo -e "${YELLOW}ℹ${NC} Usage: ${INSTALL_DIR}/wayland-debug <client>"
echo ""

