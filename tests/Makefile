# Makefile for test clients
CC = clang
CFLAGS = -Wall -Wextra -std=c11 -D_GNU_SOURCE
LDFLAGS = -lwayland-client -lm

# Paths
WAYLAND_ROOT = ../dependencies/wayland
WAYLAND_BUILD = $(WAYLAND_ROOT)/build
WESTON_SRC = ../dependencies/weston
LIBINPUT_STUBS = ../dependencies/libinput-macos-stubs
KOSMICKRISP_INC = ../dependencies/kosmickrisp/include
PROTOCOLS_DIR = ../dependencies/wayland-protocols
SRC_PROTOCOLS_DIR = ../src/protocols

# Pkg-config path
export PKG_CONFIG_PATH := $(abspath ../build/macos-install/lib/pkgconfig):$(abspath ../build/macos-install/libdata/pkgconfig):$(PKG_CONFIG_PATH)
export PATH := $(abspath ../build/macos-install/bin):$(PATH)

# Include paths
INCLUDES = -I../src \
           -I.. \
           -I../src/protocols \
           -I$(WESTON_SRC) \
           -I$(WESTON_SRC)/include \
           -I$(LIBINPUT_STUBS) \
           -I$(WAYLAND_ROOT)/src \
           -I$(WAYLAND_ROOT)/cursor \
           -I$(WAYLAND_ROOT)/egl \
           -I$(KOSMICKRISP_INC) \
           -I.

# Library paths
LIB_DIRS = -L$(WAYLAND_BUILD)/src \
           -L$(WAYLAND_BUILD)/cursor \
           -L$(WAYLAND_BUILD)/egl

# Protocols
XDG_SHELL_XML = $(PROTOCOLS_DIR)/stable/xdg-shell/xdg-shell.xml
VIEWPORTER_XML = $(PROTOCOLS_DIR)/stable/viewporter/viewporter.xml
FRACTIONAL_SCALE_XML = $(PROTOCOLS_DIR)/staging/fractional-scale/fractional-scale-v1.xml
TEARING_CONTROL_XML = $(PROTOCOLS_DIR)/staging/tearing-control/tearing-control-v1.xml
COLOR_MANAGEMENT_XML = $(SRC_PROTOCOLS_DIR)/color-management-v1.xml
SINGLE_PIXEL_BUFFER_XML = $(PROTOCOLS_DIR)/staging/single-pixel-buffer/single-pixel-buffer-v1.xml
POINTER_CONSTRAINTS_XML = $(PROTOCOLS_DIR)/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml
RELATIVE_POINTER_XML = $(PROTOCOLS_DIR)/unstable/relative-pointer/relative-pointer-unstable-v1.xml
TABLET_XML = $(PROTOCOLS_DIR)/unstable/tablet/tablet-unstable-v2.xml
TEXT_CURSOR_POSITION_XML = $(WESTON_SRC)/protocol/text-cursor-position.xml

# Generated files
GEN_SRCS = $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c \
           $(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/viewporter-protocol.c \
           $(SRC_PROTOCOLS_DIR)/viewporter-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/fractional-scale-v1-protocol.c \
           $(SRC_PROTOCOLS_DIR)/fractional-scale-v1-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/tearing-control-v1-protocol.c \
           $(SRC_PROTOCOLS_DIR)/tearing-control-v1-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/color-management-v1-protocol.c \
           $(SRC_PROTOCOLS_DIR)/color-management-v1-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/single-pixel-buffer-v1-protocol.c \
           $(SRC_PROTOCOLS_DIR)/single-pixel-buffer-v1-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/pointer-constraints-unstable-v1-protocol.c \
           $(SRC_PROTOCOLS_DIR)/pointer-constraints-unstable-v1-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/relative-pointer-unstable-v1-protocol.c \
           $(SRC_PROTOCOLS_DIR)/relative-pointer-unstable-v1-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/tablet-unstable-v2-protocol.c \
           $(SRC_PROTOCOLS_DIR)/tablet-unstable-v2-client-protocol.h \
           $(SRC_PROTOCOLS_DIR)/text-cursor-position-protocol.c \
           $(SRC_PROTOCOLS_DIR)/text-cursor-position-client-protocol.h

# Targets
all: macos_wlclient_color_test weston-simple-shm weston-simple-egl test_glxgears weston-terminal

# Pkg-config
PKG_DEPS = cairo pango pangocairo glib-2.0 xkbcommon wayland-client wayland-cursor wayland-egl egl glesv2 pixman-1 libpng epoll-shim
PKG_CFLAGS := $(shell pkg-config --cflags $(PKG_DEPS))
PKG_LIBS := $(shell pkg-config --libs $(PKG_DEPS))

# Terminal sources
SHARED_SRCS = $(WESTON_SRC)/shared/cairo-util.c \
              $(WESTON_SRC)/shared/image-loader.c \
              $(WESTON_SRC)/shared/os-compatibility.c \
              $(WESTON_SRC)/shared/config-parser.c \
              $(WESTON_SRC)/shared/option-parser.c \
              $(WESTON_SRC)/shared/file-util.c \
              $(WESTON_SRC)/shared/matrix.c \
              $(WESTON_SRC)/shared/frame.c

TERMINAL_SRCS = $(WESTON_SRC)/clients/terminal.c \
                $(WESTON_SRC)/clients/window.c \
                $(SHARED_SRCS) \
                $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c \
                $(SRC_PROTOCOLS_DIR)/viewporter-protocol.c \
                $(SRC_PROTOCOLS_DIR)/tearing-control-v1-protocol.c \
                $(SRC_PROTOCOLS_DIR)/fractional-scale-v1-protocol.c \
                $(SRC_PROTOCOLS_DIR)/color-management-v1-protocol.c \
                $(SRC_PROTOCOLS_DIR)/single-pixel-buffer-v1-protocol.c \
                $(SRC_PROTOCOLS_DIR)/pointer-constraints-unstable-v1-protocol.c \
                $(SRC_PROTOCOLS_DIR)/relative-pointer-unstable-v1-protocol.c \
                $(SRC_PROTOCOLS_DIR)/tablet-unstable-v2-protocol.c \
                $(SRC_PROTOCOLS_DIR)/text-cursor-position-protocol.c

weston-terminal: $(TERMINAL_SRCS) \
                 $(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/viewporter-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/fractional-scale-v1-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/tearing-control-v1-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/color-management-v1-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/single-pixel-buffer-v1-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/pointer-constraints-unstable-v1-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/relative-pointer-unstable-v1-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/tablet-unstable-v2-client-protocol.h \
                 $(SRC_PROTOCOLS_DIR)/text-cursor-position-client-protocol.h
	$(CC) $(CFLAGS) -DDATADIR='"/usr/local/share"' $(INCLUDES) $(PKG_CFLAGS) $(LIB_DIRS) -o $@ \
		$(TERMINAL_SRCS) \
		$(LDFLAGS) $(PKG_LIBS) -ljpeg

$(SRC_PROTOCOLS_DIR)/%-protocol.c:
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/%-client-protocol.h:
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c: $(XDG_SHELL_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h: $(XDG_SHELL_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/viewporter-protocol.c: $(VIEWPORTER_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/viewporter-client-protocol.h: $(VIEWPORTER_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/fractional-scale-v1-protocol.c: $(FRACTIONAL_SCALE_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/fractional-scale-v1-client-protocol.h: $(FRACTIONAL_SCALE_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/tearing-control-v1-protocol.c: $(TEARING_CONTROL_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/tearing-control-v1-client-protocol.h: $(TEARING_CONTROL_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/color-management-v1-protocol.c: $(COLOR_MANAGEMENT_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/color-management-v1-client-protocol.h: $(COLOR_MANAGEMENT_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/single-pixel-buffer-v1-protocol.c: $(SINGLE_PIXEL_BUFFER_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/single-pixel-buffer-v1-client-protocol.h: $(SINGLE_PIXEL_BUFFER_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/pointer-constraints-unstable-v1-protocol.c: $(POINTER_CONSTRAINTS_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/pointer-constraints-unstable-v1-client-protocol.h: $(POINTER_CONSTRAINTS_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/relative-pointer-unstable-v1-protocol.c: $(RELATIVE_POINTER_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/relative-pointer-unstable-v1-client-protocol.h: $(RELATIVE_POINTER_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/tablet-unstable-v2-protocol.c: $(TABLET_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/tablet-unstable-v2-client-protocol.h: $(TABLET_XML)
	wayland-scanner client-header $< $@

$(SRC_PROTOCOLS_DIR)/text-cursor-position-protocol.c: $(TEXT_CURSOR_POSITION_XML)
	wayland-scanner private-code $< $@

$(SRC_PROTOCOLS_DIR)/text-cursor-position-client-protocol.h: $(TEXT_CURSOR_POSITION_XML)
	wayland-scanner client-header $< $@

# Client targets
macos_wlclient_test: test_client.c $(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c ../src/logging.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LIB_DIRS) -o $@ \
		test_client.c $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c ../src/logging.c $(LDFLAGS)

macos_wlclient_color_test: test_color_client.c $(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c $(SRC_PROTOCOLS_DIR)/color-management-v1-client-protocol.h $(SRC_PROTOCOLS_DIR)/color-management-v1-protocol.c ../src/logging.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LIB_DIRS) -o $@ \
		test_color_client.c $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c $(SRC_PROTOCOLS_DIR)/color-management-v1-protocol.c ../src/logging.c $(LDFLAGS)

weston-simple-shm: $(WESTON_SRC)/clients/simple-shm.c simple_client_helpers.c $(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LIB_DIRS) -o $@ \
		$(WESTON_SRC)/clients/simple-shm.c \
		simple_client_helpers.c \
		$(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c \
		$(LDFLAGS)

weston-simple-egl: $(WESTON_SRC)/clients/simple-egl.c simple_client_helpers.c $(WESTON_SRC)/shared/matrix.c $(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c $(SRC_PROTOCOLS_DIR)/viewporter-client-protocol.h $(SRC_PROTOCOLS_DIR)/viewporter-protocol.c $(SRC_PROTOCOLS_DIR)/fractional-scale-v1-client-protocol.h $(SRC_PROTOCOLS_DIR)/fractional-scale-v1-protocol.c $(SRC_PROTOCOLS_DIR)/tearing-control-v1-client-protocol.h $(SRC_PROTOCOLS_DIR)/tearing-control-v1-protocol.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LIB_DIRS) -o $@ \
		$(WESTON_SRC)/clients/simple-egl.c \
		simple_client_helpers.c \
		$(WESTON_SRC)/shared/matrix.c \
		$(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c \
		$(SRC_PROTOCOLS_DIR)/viewporter-protocol.c \
		$(SRC_PROTOCOLS_DIR)/fractional-scale-v1-protocol.c \
		$(SRC_PROTOCOLS_DIR)/tearing-control-v1-protocol.c \
		$(LDFLAGS) -lwayland-egl -lwayland-cursor -lEGL -lGLESv2

test_glxgears: test_glxgears.c $(SRC_PROTOCOLS_DIR)/xdg-shell-client-protocol.h $(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c
	$(CC) $(CFLAGS) $(INCLUDES) $(LIB_DIRS) -o $@ \
		test_glxgears.c \
		$(SRC_PROTOCOLS_DIR)/xdg-shell-protocol.c \
		$(LDFLAGS) -lwayland-egl -lwayland-cursor -lEGL -lGLESv2

clean:
	rm -f macos_wlclient_test macos_wlclient_color_test weston-simple-shm weston-simple-egl test_glxgears weston-terminal
	rm -f $(GEN_SRCS)
	rm -f test_xdg-shell-client-protocol.* test_color-management-v1-client-protocol.*

.PHONY: clean all
