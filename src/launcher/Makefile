# macOS Wayland Launcher Makefile
# Handles Wayland client application launching

CC = clang
OBJC = clang
CFLAGS = -Wall -Wextra -O2 -fobjc-arc
OBJCFLAGS = -Wall -Wextra -O2 -fobjc-arc

# Platform detection
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    PLATFORM_CFLAGS = -DMACOS -DWAWONA_PLATFORM_MACOS -framework Cocoa -framework Foundation -framework CoreFoundation
endif

# Include paths
INCLUDES = -I../../shared -I../../.. -I../../../dependencies/wayland/src -I../../../dependencies/wayland/build/src -I/usr/local/include

# Source files - using unified cross-platform launcher
SOURCES = ../../shared/wayland_client_launcher.m
HEADERS = ../../shared/wayland_client_launcher.h

# Object files
OBJECTS = $(SOURCES:.m=.o)

# Library name
LIBRARY = libwawona_launcher.a

# Default target
all: $(LIBRARY)

# Compile object files
%.o: %.m $(HEADERS)
	$(OBJC) $(OBJCFLAGS) $(PLATFORM_CFLAGS) $(INCLUDES) -c $< -o $@

# Special rule for shared directory source
../../shared/%.o: ../../shared/%.m ../../shared/%.h
	$(OBJC) $(OBJCFLAGS) $(PLATFORM_CFLAGS) $(INCLUDES) -c $< -o $@

# Create static library
$(LIBRARY): $(OBJECTS)
	ar rcs $@ $^

# Install (optional)
install: $(LIBRARY)
	install -d $(PREFIX)/lib
	install -m 644 $(LIBRARY) $(PREFIX)/lib/
	install -d $(PREFIX)/include/wawona/launcher
	install -m 644 $(HEADERS) $(PREFIX)/include/wawona/launcher/

# Clean
clean:
	rm -f $(OBJECTS) $(LIBRARY)

# Dependencies
depend:
	$(OBJC) -MM $(OBJCFLAGS) $(PLATFORM_CFLAGS) $(INCLUDES) $(SOURCES) > .depend

-include .depend

.PHONY: all install clean depend