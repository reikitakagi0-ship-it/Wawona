# macOS Rendering Backend Makefile
# Handles rendering for macOS Wayland compositor

CC = clang
OBJC = clang
CFLAGS = -Wall -Wextra -O2 -fobjc-arc
OBJCFLAGS = -Wall -Wextra -O2 -fobjc-arc

# Platform detection
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    PLATFORM_CFLAGS = -DMACOS -framework Cocoa -framework Metal -framework MetalKit -framework CoreGraphics -framework QuartzCore
endif

# Include paths
INCLUDES = -I../../shared -I../../.. -I/usr/local/include

# Source files
SOURCES = rendering_backend.m surface_renderer.m metal_renderer.m metal_waypipe.m metal_dmabuf.m
HEADERS = rendering_backend.h surface_renderer.h metal_renderer.h metal_waypipe.h metal_dmabuf.h

# Object files
OBJECTS = $(SOURCES:.m=.o)

# Library name
LIBRARY = libwawona_rendering.a

# Default target
all: $(LIBRARY)

# Compile object files
%.o: %.m $(HEADERS)
	$(OBJC) $(OBJCFLAGS) $(PLATFORM_CFLAGS) $(INCLUDES) -c $< -o $@

# Create static library
$(LIBRARY): $(OBJECTS)
	ar rcs $@ $^

# Install (optional)
install: $(LIBRARY)
	install -d $(PREFIX)/lib
	install -m 644 $(LIBRARY) $(PREFIX)/lib/
	install -d $(PREFIX)/include/wawona/rendering
	install -m 644 $(HEADERS) $(PREFIX)/include/wawona/rendering/

# Clean
clean:
	rm -f $(OBJECTS) $(LIBRARY)

# Dependencies
depend:
	$(OBJC) -MM $(OBJCFLAGS) $(PLATFORM_CFLAGS) $(INCLUDES) $(SOURCES) > .depend

-include .depend

.PHONY: all install clean depend