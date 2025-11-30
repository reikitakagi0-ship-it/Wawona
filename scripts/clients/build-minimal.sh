#!/bin/bash
# Build minimal Wayland test clients
# These are lightweight clients for basic protocol testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MINIMAL_DIR="$PROJECT_ROOT/test-clients/minimal"
BUILD_DIR="$MINIMAL_DIR/build"
INSTALL_DIR="$MINIMAL_DIR/bin"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔨 Building Minimal Wayland Test Clients${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check dependencies
echo -e "${YELLOW}ℹ${NC} Checking dependencies..."

if ! pkg-config --exists wayland-client; then
    echo -e "${RED}✗${NC} wayland-client not found"
    exit 1
fi

if ! pkg-config --exists pixman-1; then
    echo -e "${RED}✗${NC} pixman not found"
    exit 1
fi

echo -e "${GREEN}✓${NC} Dependencies OK"
echo ""

# Create directories
mkdir -p "$MINIMAL_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

# Get compiler flags
WAYLAND_CFLAGS=$(pkg-config --cflags wayland-client)
WAYLAND_LIBS=$(pkg-config --libs wayland-client)
PIXMAN_CFLAGS=$(pkg-config --cflags pixman-1)
PIXMAN_LIBS=$(pkg-config --libs pixman-1)

CFLAGS="$WAYLAND_CFLAGS $PIXMAN_CFLAGS -Wall -Wextra -Werror -std=c11"
LIBS="$WAYLAND_LIBS $PIXMAN_LIBS"

# Build simple-shm client
echo -e "${YELLOW}ℹ${NC} Building simple-shm..."
cat > "$BUILD_DIR/simple-shm.c" << 'EOFSHMSRC'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <fcntl.h>
#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <pixman.h>

struct wl_display *display = NULL;
struct wl_compositor *compositor = NULL;
struct wl_surface *surface = NULL;
struct wl_shm *shm = NULL;
struct wl_buffer *buffer = NULL;

static void shm_format(void *data, struct wl_shm *wl_shm, uint32_t format) {
    (void)data;
    (void)wl_shm;
    (void)format;
    // Accept all formats
}

static const struct wl_shm_listener shm_listener = {
    shm_format
};

static void registry_global(void *data, struct wl_registry *registry,
                           uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, "wl_compositor") == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, "wl_shm") == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
        wl_shm_add_listener(shm, &shm_listener, NULL);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                  uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
    // Ignore
}

static const struct wl_registry_listener registry_listener = {
    registry_global,
    registry_global_remove
};

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "Failed to connect to Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor || !shm) {
        fprintf(stderr, "Compositor or SHM not available\n");
        return 1;
    }

    surface = wl_compositor_create_surface(compositor);
    if (!surface) {
        fprintf(stderr, "Failed to create surface\n");
        return 1;
    }

    // Create a simple 256x256 buffer
    int width = 256;
    int height = 256;
    int stride = width * 4;
    int size = stride * height;

    char shm_name[256];
    snprintf(shm_name, sizeof(shm_name), "/wayland-test-%d", getpid());
    int fd = shm_open(shm_name, O_CREAT | O_RDWR | O_TRUNC, 0600);
    if (fd < 0) {
        fprintf(stderr, "Failed to create shared memory\n");
        return 1;
    }
    shm_unlink(shm_name); // Unlink immediately, fd remains valid
    ftruncate(fd, size);

    uint32_t *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        fprintf(stderr, "Failed to mmap\n");
        return 1;
    }

    // Fill with a gradient
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            uint32_t r = (x * 255) / width;
            uint32_t g = (y * 255) / height;
            uint32_t b = 128;
            data[y * width + x] = (0xFF << 24) | (r << 16) | (g << 8) | b;
        }
    }

    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
                                       WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);

    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_commit(surface);

    printf("Created surface with %dx%d buffer\n", width, height);
    printf("Press Enter to exit...\n");
    getchar();

    wl_buffer_destroy(buffer);
    wl_surface_destroy(surface);
    wl_compositor_destroy(compositor);
    wl_shm_destroy(shm);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);

    return 0;
}
EOFSHMSRC

clang $CFLAGS -o "$INSTALL_DIR/simple-shm" "$BUILD_DIR/simple-shm.c" $LIBS
echo -e "${GREEN}✓${NC} Built simple-shm"

# Build simple-damage client
echo -e "${YELLOW}ℹ${NC} Building simple-damage..."
cat > "$BUILD_DIR/simple-damage.c" << 'EOFDAMAGESRC'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <fcntl.h>
#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <pixman.h>

struct wl_display *display = NULL;
struct wl_compositor *compositor = NULL;
struct wl_surface *surface = NULL;
struct wl_shm *shm = NULL;
struct wl_buffer *buffer = NULL;

static void shm_format(void *data, struct wl_shm *wl_shm, uint32_t format) {
    (void)data;
    (void)wl_shm;
    (void)format;
}

static const struct wl_shm_listener shm_listener = {
    shm_format
};

static void registry_global(void *data, struct wl_registry *registry,
                           uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, "wl_compositor") == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, "wl_shm") == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
        wl_shm_add_listener(shm, &shm_listener, NULL);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                  uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    registry_global,
    registry_global_remove
};

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "Failed to connect to Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor || !shm) {
        fprintf(stderr, "Compositor or SHM not available\n");
        return 1;
    }

    surface = wl_compositor_create_surface(compositor);
    if (!surface) {
        fprintf(stderr, "Failed to create surface\n");
        return 1;
    }

    int width = 256;
    int height = 256;
    int stride = width * 4;
    int size = stride * height;

    char shm_name[256];
    snprintf(shm_name, sizeof(shm_name), "/wayland-damage-test-%d", getpid());
    int fd = shm_open(shm_name, O_CREAT | O_RDWR | O_TRUNC, 0600);
    if (fd < 0) {
        fprintf(stderr, "Failed to create shared memory\n");
        return 1;
    }
    shm_unlink(shm_name); // Unlink immediately, fd remains valid
    ftruncate(fd, size);

    uint32_t *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        fprintf(stderr, "Failed to mmap\n");
        return 1;
    }

    // Fill with pattern
    memset(data, 0xFF, size);
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            if ((x + y) % 32 < 16) {
                data[y * width + x] = 0xFFFF0000; // Red
            } else {
                data[y * width + x] = 0xFF0000FF; // Blue
            }
        }
    }

    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
                                       WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);

    wl_surface_attach(surface, buffer, 0, 0);
    
    // Add damage region (full surface)
    wl_surface_damage(surface, 0, 0, width, height);
    wl_surface_commit(surface);

    printf("Created surface with damage region\n");
    printf("Press Enter to exit...\n");
    getchar();

    wl_buffer_destroy(buffer);
    wl_surface_destroy(surface);
    wl_compositor_destroy(compositor);
    wl_shm_destroy(shm);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);

    return 0;
}
EOFDAMAGESRC

clang $CFLAGS -o "$INSTALL_DIR/simple-damage" "$BUILD_DIR/simple-damage.c" $LIBS
echo -e "${GREEN}✓${NC} Built simple-damage"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓${NC} Minimal test clients built!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}ℹ${NC} Clients installed to: ${INSTALL_DIR}"
echo ""

