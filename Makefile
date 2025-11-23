# Wawona Compositor Makefile
# Simplified targets for common operations

.PHONY: help compositor stop-compositor client tartvm-client external-client container-client colima-client colima-client-ios colima-weston-simple-egl colima-wlcs clean-remote-socket wayland xkbcommon libinput weston build-weston-compositor run-weston-compositor clean-weston test uninstall logs clean-compositor clean-client clean-wayland kosmickrisp clean-kosmickrisp test-clients test-wayland-info test-wayland-debug test-simple-shm test-simple-damage test-weston-simple-shm test-weston-simple-egl test-weston-transformed test-weston-subsurfaces test-weston-simple-damage test-weston-simple-touch test-weston-eventdemo test-weston-keyboard test-weston-dnd test-weston-cliptest test-weston-image test-weston-editor debug-compositor-lldb debug-compositor-dyld debug-weston-simple-egl-lldb debug-weston-simple-egl-dyld debug-kosmickrisp-lldb debug-kosmickrisp-dyld debug-full ios-compositor ios-wayland ios-waypipe ios-kosmickrisp ios-build-compositor ios-install-compositor ios-run-compositor clean-ios-compositor

# Default target
.DEFAULT_GOAL := help

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m # No Color

# Directories
BUILD_DIR := build
WAYLAND_DIR := wayland
WAYLAND_BUILD_DIR := $(WAYLAND_DIR)/build
IOS_BUILD_DIR := build-ios
IOS_INSTALL_DIR := ios-install

# Binaries
COMPOSITOR_BIN := $(BUILD_DIR)/Wawona
IOS_COMPOSITOR_BIN := $(IOS_BUILD_DIR)/Wawona.app/Wawona
TEST_CLIENT_BIN := macos_wlclient_color_test

# iOS Settings
IOS_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
IOS_BUNDLE_ID := com.aspauldingcode.Wawona
IOS_DEVICE_ID := $(shell xcrun simctl list devices available | grep "DebugPhone" | grep -oE '[0-9A-F-]{36}' || echo "")

# Environment
XDG_RUNTIME_DIR ?= $(shell echo $${TMPDIR:-/tmp}/wayland-runtime)
WAYLAND_DISPLAY ?= wayland-0
WAYLAND_DEBUG ?= 1

# Tart VM settings
# Note: Tart uses VirtioFS for directory sharing
# Default tag is "com.apple.virtio-fs.automount" if no tag specified
# Custom tag format: --dir="path:tag=customtag"
TART_VM_NAME := fedora
TART_SHARED_DIR := /tmp/tart-wayland-shared
TART_VM_MOUNT := /opt/wlshared
TART_MOUNT_TAG := wlshared

# External client settings
# Set EXTERNAL_CLIENT_HOST to your NixOS machine hostname/IP
# Example: make external-client EXTERNAL_CLIENT_HOST=10.0.0.109
# Or: EXTERNAL_CLIENT_HOST=my-nixos-box make external-client
EXTERNAL_CLIENT_HOST ?=10.0.0.109
EXTERNAL_CLIENT_USER ?= $(shell whoami)

# Container client settings
CONTAINER_IMAGE ?= alpine
CONTAINER_NAME ?= weston-container
CONTAINER_RUNTIME_DIR ?= /tmp/container-wayland-runtime

# Detect Wayland install prefix
WAYLAND_PREFIX := $(shell if [ -d "/opt/homebrew/lib/pkgconfig" ] && pkg-config --exists wayland-server 2>/dev/null && pkg-config --variable=prefix wayland-server 2>/dev/null | grep -q "/opt/homebrew"; then echo "/opt/homebrew"; elif [ -d "/usr/local/lib/pkgconfig" ] && pkg-config --exists wayland-server 2>/dev/null && pkg-config --variable=prefix wayland-server 2>/dev/null | grep -q "/usr/local"; then echo "/usr/local"; else echo ""; fi)

# KosmicKrisp installation paths (override when running make to avoid sudo)
KOSMICKRISP_PREFIX ?= /opt/homebrew
KOSMICKRISP_DESTDIR ?=
KOSMICKRISP_PREFIX_FULL := $(KOSMICKRISP_DESTDIR)$(KOSMICKRISP_PREFIX)
KOSMICKRISP_LIB := $(KOSMICKRISP_PREFIX_FULL)/lib
KOSMICKRISP_INCLUDE := $(KOSMICKRISP_PREFIX_FULL)/include
KOSMICKRISP_PKGCONFIG := $(KOSMICKRISP_PREFIX_FULL)/lib/pkgconfig
KOSMICKRISP_ICD := $(KOSMICKRISP_PREFIX_FULL)/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
KOSMICKRISP_DRI := $(KOSMICKRISP_LIB)/dri

help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🔨 Wawona Compositor Makefile$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make compositor$(NC)      - Clean, build, and run compositor (background)"
	@echo "  $(YELLOW)make stop-compositor$(NC) - Stop running compositor"
	@echo "  $(YELLOW)make client$(NC)           - Clean, build, and run client"
	@echo "  $(YELLOW)make tartvm-client$(NC)    - Start Fedora VM with shared directory for Wayland"
	@echo "  $(YELLOW)make external-client$(NC) - Connect external client via waypipe (auto-cleans remote socket)"
	@echo "  $(YELLOW)make container-client$(NC) - Run Weston in macOS Containerization.framework container"
	@echo "    $(RED)⚠$(NC)  $(YELLOW)Note:$(NC) Does NOT support Unix domain sockets (connection will fail)"
	@echo "    $(YELLOW)ℹ$(NC)  Use $(GREEN)make colima-client$(NC) for Unix socket support"
	@echo "  $(YELLOW)make colima-client$(NC) - Run Weston in Colima/Docker container (supports Unix sockets)"
	@echo "  $(YELLOW)make colima-wlcs$(NC)   - Run Wayland Conformance Test Suite (wlcs) via Colima"
	@echo "  $(YELLOW)make clean-remote-socket$(NC) - Clean stale Wayland sockets on remote machine"
	@echo "  $(YELLOW)make external-client EXTERNAL_CLIENT_HOST=host$(NC) - Connect NixOS client via SSH"
	@echo "  $(YELLOW)make test-clients$(NC)    - Clean, build, and run all Wayland test clients"
	@echo "  $(YELLOW)make test-<client>$(NC)   - Run individual test client interactively"
	@echo "    $(YELLOW)ℹ$(NC)  Press Ctrl+C (SIGTERM) to exit the test client"
	@echo "    $(YELLOW)ℹ$(NC)  Available clients:"
	@echo "      • test-wayland-info, test-wayland-debug"
	@echo "      • test-simple-shm, test-simple-damage"
	@echo "      • test-weston-simple-shm, test-weston-simple-egl"
	@echo "      • test-weston-transformed, test-weston-subsurfaces"
	@echo "      • test-weston-simple-damage, test-weston-simple-touch"
	@echo "      • test-weston-eventdemo, test-weston-keyboard"
	@echo "      • test-weston-dnd, test-weston-cliptest"
	@echo "      • test-weston-image, test-weston-editor"
	@echo "  $(YELLOW)make test-compositors$(NC) - Test nested compositors (Weston, Sway, GNOME, KDE)"
	@echo "  $(YELLOW)make wayland$(NC)          - Clean, build, and install Wayland"
	@echo "  $(YELLOW)make xkbcommon$(NC)        - Build and install xkbcommon (keyboard handling)"
	@echo "  $(YELLOW)make libinput$(NC)         - Build and install libinput (Linux-specific, may not work on macOS)"
	@echo "  $(YELLOW)make weston$(NC)           - Build Weston compositor for macOS (nested Wayland backend)"
	@echo "  $(YELLOW)make waypipe$(NC)         - Clean, build, and install Rust waypipe for macOS and iOS"
	@echo "    $(YELLOW)ℹ$(NC)  Builds waypipe with dmabuf, video (macOS), lz4, zstd features"
	@echo "    $(YELLOW)ℹ$(NC)  Requires KosmicKrisp Vulkan driver (use $(GREEN)make kosmickrisp$(NC))"
	@echo "    $(YELLOW)ℹ$(NC)  macOS binary: /opt/homebrew/bin/waypipe"
	@echo "    $(YELLOW)ℹ$(NC)  iOS binary: ios-install/bin/waypipe"
	@echo "  $(YELLOW)make kosmickrisp$(NC)     - Build and install KosmicKrisp Vulkan driver + EGL (Zink) for macOS and iOS"
	@echo "    $(YELLOW)ℹ$(NC)  Enables EGL/OpenGL ES support via KosmicKrisp+Zink"
	@echo "    $(YELLOW)ℹ$(NC)  Required for EGL test clients (weston-simple-egl, etc.)"
	@echo "    $(YELLOW)ℹ$(NC)  Required for waypipe dmabuf/video features"
	@echo "    $(YELLOW)ℹ$(NC)  macOS: Installs to /opt/homebrew/lib/"
	@echo "    $(YELLOW)ℹ$(NC)  iOS: Installs to ios-install/lib/"
	@echo "  $(YELLOW)make ios-compositor$(NC)  - Build and run Wawona on iOS Simulator"
	@echo "    $(YELLOW)ℹ$(NC)  Builds all dependencies (Wayland, Waypipe, KosmicKrisp) for iOS"
	@echo "    $(YELLOW)ℹ$(NC)  Compiles Wawona for iOS Simulator and launches it"
	@echo "    $(YELLOW)ℹ$(NC)  Requires iOS SDK and Xcode command-line tools"
	@echo "  $(YELLOW)make ios-wayland$(NC)    - Build Wayland libraries for iOS Simulator"
	@echo "  $(YELLOW)make ios-waypipe$(NC)     - Build Waypipe for iOS Simulator (requires ios-wayland, ios-kosmickrisp)"
	@echo "  $(YELLOW)make ios-kosmickrisp$(NC) - Build KosmicKrisp Vulkan driver for iOS Simulator (requires ios-wayland)"
	@echo "  $(YELLOW)make colima-client-ios$(NC) - Connect to iOS Simulator Wawona compositor via waypipe"
	@echo "    $(YELLOW)ℹ$(NC)  Runs Weston in Docker container, connects to iOS Simulator Wayland socket"
	@echo "  $(YELLOW)make test$(NC)            - Clean all, build all, install wayland, run both"
	@echo "  $(YELLOW)make uninstall$(NC)       - Uninstall Wayland"
	@echo "  $(YELLOW)make logs$(NC)            - Open/view all log files"
	@echo ""
	@echo "$(GREEN)Common Workflows:$(NC)"
	@echo ""
	@echo "  $(YELLOW)1. First-time setup (macOS):$(NC)"
	@echo "     $(GREEN)make wayland$(NC)        # Install Wayland for macOS"
	@echo "     $(GREEN)make kosmickrisp$(NC)     # Install Vulkan+EGL support for macOS and iOS"
	@echo "     $(GREEN)make waypipe$(NC)         # Install Waypipe for macOS and iOS (requires kosmickrisp)"
	@echo ""
	@echo "  $(YELLOW)2. Run compositor (macOS):$(NC)"
	@echo "     $(GREEN)make compositor$(NC)     # Build and run compositor"
	@echo "     # Or: $(GREEN)make run-compositor$(NC) in another terminal"
	@echo ""
	@echo "  $(YELLOW)3. Test clients (macOS):$(NC)"
	@echo "     $(GREEN)make test-clients$(NC)   # Run all tests"
	@echo "     $(GREEN)make test-weston-simple-egl$(NC)  # Run single test interactively"
	@echo ""
	@echo "  $(YELLOW)4. iOS Simulator setup:$(NC)"
	@echo "     $(GREEN)make ios-compositor$(NC)  # Build and run Wawona on iOS Simulator"
	@echo "     # This builds all iOS dependencies (Wayland, Waypipe, KosmicKrisp)"
	@echo "     # Or build individually:"
	@echo "     $(GREEN)make ios-wayland$(NC)     # Build Wayland for iOS"
	@echo "     $(GREEN)make ios-kosmickrisp$(NC) # Build KosmicKrisp for iOS"
	@echo "     $(GREEN)make ios-waypipe$(NC)    # Build Waypipe for iOS"
	@echo ""
	@echo "  $(YELLOW)5. Connect to iOS Simulator:$(NC)"
	@echo "     $(GREEN)make colima-client-ios$(NC)  # Run Weston in Docker, connect to iOS Simulator"
	@echo ""
	@echo "  $(YELLOW)6. Prerequisites for EGL clients:$(NC)"
	@echo "     • Run $(GREEN)make kosmickrisp$(NC) to install EGL support"
	@echo "     • Compositor will auto-detect and use EGL if available"
	@echo ""
	@echo "$(GREEN)Platform-specific targets:$(NC)"
	@echo ""
	@echo "  $(YELLOW)macOS only:$(NC)"
	@echo "     $(GREEN)make kosmickrisp-macos$(NC)  # Build KosmicKrisp for macOS only"
	@echo ""
	@echo "  $(YELLOW)iOS only:$(NC)"
	@echo "     $(GREEN)make ios-wayland$(NC)       # Build Wayland for iOS only"
	@echo "     $(GREEN)make ios-waypipe$(NC)       # Build Waypipe for iOS only"
	@echo "     $(GREEN)make ios-kosmickrisp$(NC)   # Build KosmicKrisp for iOS only"
	@echo ""

# Clean compositor build
clean-compositor:
	@if [ -d "$(BUILD_DIR)" ]; then \
		rm -rf $(BUILD_DIR); \
		echo "$(GREEN)✓$(NC) Compositor cleaned"; \
	fi

# Clean client build
clean-client:
	@if [ -f "$(TEST_CLIENT_BIN)" ]; then \
		rm -f $(TEST_CLIENT_BIN); \
		echo "$(GREEN)✓$(NC) Client cleaned"; \
	fi
	@make -f Makefile.test_client clean 2>/dev/null || true

# Clean wayland build
clean-wayland:
	@if [ -d "$(WAYLAND_BUILD_DIR)" ]; then \
		rm -rf $(WAYLAND_BUILD_DIR); \
		echo "$(GREEN)✓$(NC) Wayland build cleaned"; \
	fi

# Build compositor
build-compositor:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(YELLOW)ℹ$(NC) Build output redirected to compositor-build.log"
	@MISSING_DEPS=0; \
	if ! command -v cmake >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) cmake not found"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) cmake: $$(cmake --version | head -n1)"; \
	fi; \
	if ! command -v pkg-config >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) pkg-config not found"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) pkg-config: $$(pkg-config --version)"; \
	fi; \
	if ! pkg-config --exists wayland-server 2>/dev/null; then \
		echo "$(RED)✗$(NC) wayland-server not found"; \
		echo "   Run ./install-wayland.sh to install Wayland"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) wayland-server: $$(pkg-config --modversion wayland-server)"; \
	fi; \
	if ! pkg-config --exists pixman-1 2>/dev/null; then \
		echo "$(RED)✗$(NC) pixman-1 not found"; \
		echo "   Install with: brew install pixman"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) pixman-1: $$(pkg-config --modversion pixman-1)"; \
	fi; \
	echo "$(YELLOW)ℹ$(NC) Checking for KosmicKrisp Vulkan driver (REQUIRED)..."; \
	if [ -f "/opt/homebrew/lib/libvulkan_kosmickrisp.dylib" ] && [ -f "/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json" ]; then \
		echo "$(GREEN)✓$(NC) KosmicKrisp Vulkan driver found"; \
	else \
		echo "$(RED)✗$(NC) KosmicKrisp Vulkan driver not found!"; \
		echo "$(RED)✗$(NC) Required files:"; \
		echo "   - /opt/homebrew/lib/libvulkan_kosmickrisp.dylib"; \
		echo "   - /opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"; \
		echo "$(YELLOW)ℹ$(NC) Install KosmicKrisp driver: $(GREEN)make kosmickrisp$(NC)"; \
		MISSING_DEPS=1; \
	fi; \
	if [ $$MISSING_DEPS -eq 1 ]; then \
		echo "$(RED)✗$(NC) Missing required dependencies"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✓$(NC) All dependencies found"
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Configuring CMake"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake .. || (echo "$(RED)✗$(NC) CMake configuration failed"; exit 1)
	@echo "$(GREEN)✓$(NC) CMake configuration complete"
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@rm -f compositor-build.log
	@cd $(BUILD_DIR) && \
		if [ -f "build.ninja" ]; then \
			if command -v ninja >/dev/null 2>&1; then \
				echo "$(YELLOW)ℹ$(NC) Using Ninja build system"; \
				ninja 2>&1 | tee ../compositor-build.log || (cat ../compositor-build.log && echo "$(RED)✗$(NC) Build failed" && exit 1); \
			else \
				echo "$(RED)✗$(NC) Ninja build files found but ninja command not available"; \
				echo "   Install ninja: brew install ninja"; \
				exit 1; \
			fi; \
		elif [ -f "Makefile" ]; then \
			echo "$(YELLOW)ℹ$(NC) Using Make build system"; \
			CORES=$$(sysctl -n hw.ncpu 2>/dev/null || echo "4"); \
			echo "$(YELLOW)ℹ$(NC) Building with $$CORES parallel jobs..."; \
			make -j$$CORES 2>&1 | tee ../compositor-build.log || (cat ../compositor-build.log && echo "$(RED)✗$(NC) Build failed" && exit 1); \
		else \
			echo "$(RED)✗$(NC) No build files found"; \
			exit 1; \
		fi
	@if [ ! -f "$(COMPOSITOR_BIN)" ]; then \
		echo "$(RED)✗$(NC) Binary not found: $(COMPOSITOR_BIN)"; \
		exit 1; \
	fi
	@BINARY_SIZE=$$(du -h $(COMPOSITOR_BIN) | cut -f1); \
	echo "$(GREEN)✓$(NC) Build complete"; \
	echo "$(GREEN)✓$(NC) Binary created: $(COMPOSITOR_BIN) ($$BINARY_SIZE)"

# Build client
build-client:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Color Test Client"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(YELLOW)ℹ$(NC) Build output redirected to client-build.log"
	@rm -f client-build.log
	@make -f Makefile.test_client macos_wlclient_color_test > client-build.log 2>&1 || (cat client-build.log && exit 1)
	@if [ ! -f "macos_wlclient_color_test" ]; then \
		echo "$(RED)✗$(NC) Build failed - see client-build.log"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓$(NC) Color test client built"

# Build input test client
build-input-client:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Input Test Client"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(YELLOW)ℹ$(NC) Build output redirected to input-client-build.log"
	@rm -f input-client-build.log
	@make -f Makefile.test_client macos_wlclient_input_test > input-client-build.log 2>&1 || (cat input-client-build.log && exit 1)
	@if [ ! -f "macos_wlclient_input_test" ]; then \
		echo "$(RED)✗$(NC) Build failed - see input-client-build.log"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓$(NC) Input test client built"

# Input test client: clean, build, run
input-client: clean-client build-input-client
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Running Input Test Client"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "macos_wlclient_input_test" ]; then \
		echo "$(RED)✗$(NC) Input test client not built"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Runtime log: /tmp/input-client-run.log"
	@rm -f /tmp/input-client-run.log
	@WAYLAND_DISPLAY="$(WAYLAND_DISPLAY)" \
	 XDG_RUNTIME_DIR="$(XDG_RUNTIME_DIR)" \
	 WAYLAND_DEBUG="$(WAYLAND_DEBUG)" \
	 bash -c '\
		if [ ! -S "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY" ]; then \
			echo "$(YELLOW)⚠$(NC) Compositor socket not found at $$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY"; \
			echo "   Run compositor first: $(YELLOW)make compositor$(NC)"; \
			echo ""; \
		fi; \
		echo "$(GREEN)✓$(NC) Starting input test client (WAYLAND_DEBUG=$${WAYLAND_DEBUG:-0})..."; \
		echo ""; \
		./macos_wlclient_input_test > /tmp/input-client-run.log 2>&1 & \
		INPUT_CLIENT_PID=$$!; \
		sleep 0.5; \
		tail -f /tmp/input-client-run.log; \
		wait $$INPUT_CLIENT_PID'

# Compositor: clean, build, run
compositor: clean-compositor build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Running Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "$(COMPOSITOR_BIN)" ]; then \
		echo "$(RED)✗$(NC) Compositor not built"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Checking for existing compositor processes..."
	@KILLED=0; \
	for PID in $$(pgrep -f "Wawona" 2>/dev/null || true); do \
		if [ -n "$$PID" ] && kill -9 $$PID 2>/dev/null; then \
			echo "$(YELLOW)⚠$(NC) Killed compositor process $$PID"; \
			KILLED=$$((KILLED + 1)); \
		fi; \
	done; \
	if [ $$KILLED -gt 0 ]; then \
		echo "$(YELLOW)⚠$(NC) Killed $$KILLED existing compositor process(es)"; \
		sleep 0.5; \
		for PID in $$(pgrep -f "Wawona" 2>/dev/null || true); do \
			if [ -n "$$PID" ]; then \
				kill -9 $$PID 2>/dev/null && echo "$(YELLOW)⚠$(NC) Force killed remaining process $$PID"; \
			fi; \
		done; \
		pkill -9 -f "Wawona" 2>/dev/null || true; \
		sleep 0.3; \
	else \
		echo "$(GREEN)✓$(NC) No existing compositor found"; \
	fi
	@sleep 0.2
	@echo "$(YELLOW)ℹ$(NC) Cleaning up stale Wayland sockets..."
	@CLEANED=0; \
	SOCKET_DIRS="$(TART_SHARED_DIR) $${XDG_RUNTIME_DIR:-$${TMPDIR:-/tmp}/wayland-runtime} /tmp"; \
	for DIR in $$SOCKET_DIRS; do \
		if [ -d "$$DIR" ]; then \
			for SOCKET in "$$DIR"/wayland-*; do \
				if [ -e "$$SOCKET" ] && [ -S "$$SOCKET" ] 2>/dev/null; then \
					echo "$(YELLOW)⚠$(NC) Removing stale socket: $$SOCKET"; \
					rm -f "$$SOCKET" && CLEANED=$$((CLEANED + 1)); \
				fi; \
			done 2>/dev/null || true; \
		fi; \
	done; \
	if [ $$CLEANED -eq 0 ]; then \
		echo "$(GREEN)✓$(NC) No stale sockets found"; \
	else \
		echo "$(GREEN)✓$(NC) Cleaned up $$CLEANED stale socket(s)"; \
	fi
	@sleep 0.2
	@echo "$(GREEN)✓$(NC) Starting compositor..."
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Environment Variables$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━$(NC)"
	@export WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-0}"; \
	export XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"; \
	XDG_RUNTIME_DIR=$$(echo "$$XDG_RUNTIME_DIR" | sed "s#//#/#g"); \
	echo "$(YELLOW)ℹ$(NC) WAYLAND_DISPLAY=$(GREEN)$$WAYLAND_DISPLAY$(NC)"; \
	echo "$(YELLOW)ℹ$(NC) XDG_RUNTIME_DIR=$(GREEN)$$XDG_RUNTIME_DIR$(NC)"; \
	echo "$(YELLOW)ℹ$(NC) Socket will be at: $(GREEN)$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY$(NC)"; \
	echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(YELLOW)ℹ$(NC) Compositor will run in background"
	@echo "$(YELLOW)ℹ$(NC) Runtime log: /tmp/compositor-run.log"
	@echo "$(YELLOW)ℹ$(NC) To stop: $(GREEN)make stop-compositor$(NC) or $(GREEN)pkill -f Wawona$(NC)"
	@echo ""
	@rm -f /tmp/compositor-run.log
	@export WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-0}"; \
	export XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"; \
	XDG_RUNTIME_DIR=$$(echo "$$XDG_RUNTIME_DIR" | sed "s#//#/#g"); \
	bash -c '\
		mkdir -p "$$XDG_RUNTIME_DIR"; \
		chmod 0700 "$$XDG_RUNTIME_DIR"; \
		rm -f "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY"; \
		$(COMPOSITOR_BIN) >/tmp/compositor-run.log 2>&1 & \
		COMPOSITOR_PID=$$!; \
		echo "$(GREEN)✓$(NC) Compositor started (PID: $$COMPOSITOR_PID)"; \
		sleep 0.5; \
		if kill -0 $$COMPOSITOR_PID 2>/dev/null; then \
			echo "$(GREEN)✓$(NC) Compositor is running"; \
			echo "$(YELLOW)ℹ$(NC) Socket: $(GREEN)$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY$(NC)"; \
			echo "$(YELLOW)ℹ$(NC) Log: $(GREEN)/tmp/compositor-run.log$(NC)"; \
			echo ""; \
		else \
			echo "$(RED)✗$(NC) Compositor failed to start"; \
			if [ -f /tmp/compositor-run.log ]; then \
				echo "$(YELLOW)ℹ$(NC) Last log entries:"; \
				tail -20 /tmp/compositor-run.log; \
			fi; \
			exit 1; \
		fi'

# Debug target: rebuild compositor and run under lldb with stdout/stderr attached
debug-compositor: clean-compositor build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Debugging Compositor (lldb)$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "$(COMPOSITOR_BIN)" ]; then \
		echo "$(RED)✗$(NC) Compositor binary not found"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Press Ctrl+C to stop (will auto-sample process on exit)"
	@echo "$(YELLOW)ℹ$(NC) Sample log: /tmp/compositor-debug-sample.log"
	@echo ""
	@WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-0}" \
	 XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}" \
	 SAMPLE_LOG=/tmp/compositor-debug-sample.log \
	 bash -c '\
		cleanup() { \
			echo ""; \
			echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
			echo "▶ Sampling Compositor Process"; \
			echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
			PID=$$(pgrep -f "Wawona" | head -n 1); \
			if [ -n "$$PID" ]; then \
				if command -v sample >/dev/null 2>&1; then \
					echo "ℹ Sampling process $$PID for 5 seconds..."; \
					sample $$PID 5 -file $$SAMPLE_LOG >/dev/null 2>&1; \
					echo "✓ Sample captured at $$SAMPLE_LOG"; \
				else \
					echo "⚠ macOS sample tool not found, skipping"; \
				fi; \
			else \
				echo "⚠ Compositor process not found (may have exited)"; \
			fi; \
		}; \
		trap cleanup EXIT INT TERM; \
		mkdir -p "$$XDG_RUNTIME_DIR"; \
		chmod 0700 "$$XDG_RUNTIME_DIR"; \
		rm -f "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY"; \
		echo "$(YELLOW)ℹ$(NC) Launching under lldb (WAYLAND_DISPLAY=$$WAYLAND_DISPLAY)"; \
		lldb --one-line "run" -- $(COMPOSITOR_BIN)'

debug-compositor-batch: clean-compositor build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Debugging Compositor (lldb batch)$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "$(COMPOSITOR_BIN)" ]; then \
		echo "$(RED)✗$(NC) Compositor binary not found"; \
		exit 1; \
	fi
	@LOG_FILE=/tmp/compositor-debug.log; \
	echo "$(YELLOW)ℹ$(NC) Capturing lldb output to $$LOG_FILE"; \
	WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-0}" \
	 XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}" \
	 bash -c '\
		mkdir -p "$$XDG_RUNTIME_DIR"; \
		chmod 0700 "$$XDG_RUNTIME_DIR"; \
		rm -f "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY"; \
		lldb --batch \
			-o "run" \
			-k "thread backtrace all" \
			-k "register read" \
			-k "memory read --size 8 --count 16 $$sp" \
			-k "quit" \
			-- $(COMPOSITOR_BIN)' | tee $$LOG_FILE; \
	echo "$(GREEN)✓$(NC) Batch debug log written to $$LOG_FILE"

sample-compositor:
	@PID=$$(pgrep -f "Wawona" | head -n 1); \
	if [ -z "$$PID" ]; then \
		echo "$(RED)✗$(NC) Wawona is not running"; \
		exit 1; \
	fi; \
	if ! command -v sample >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) macOS 'sample' tool not found"; \
		exit 1; \
	fi; \
	OUT=/tmp/compositor-sample.log; \
	echo "$(YELLOW)ℹ$(NC) Sampling process $$PID for 10 seconds -> $$OUT"; \
	sample $$PID 10 -file $$OUT >/dev/null; \
	echo "$(GREEN)✓$(NC) Sample captured at $$OUT"

# Client: clean, build, run
client: clean-client build-client
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Running Client"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "$(TEST_CLIENT_BIN)" ]; then \
		echo "$(RED)✗$(NC) Client not built"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Runtime log: /tmp/client-run.log"
	@rm -f /tmp/client-run.log
	@WAYLAND_DISPLAY="$(WAYLAND_DISPLAY)" \
	 XDG_RUNTIME_DIR="$(XDG_RUNTIME_DIR)" \
	 WAYLAND_DEBUG="$(WAYLAND_DEBUG)" \
	 bash -c '\
		if [ ! -S "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY" ]; then \
			echo "$(YELLOW)⚠$(NC) Compositor socket not found at $$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY"; \
			echo "   Run compositor first: $(YELLOW)make compositor$(NC)"; \
			echo ""; \
		fi; \
		echo "$(GREEN)✓$(NC) Starting color test client (WAYLAND_DEBUG=$${WAYLAND_DEBUG:-0})..."; \
		echo ""; \
		./$(TEST_CLIENT_BIN) 2>&1 | tee /tmp/client-run.log'

# Tart VM client: start Fedora VM, setup SSH keys, forward Wayland socket, run foot
tartvm-client:
	@bash -c '\
	set -e; \
	mkdir -p "$(TART_SHARED_DIR)"; \
	SOCKET_NAME="$${WAYLAND_DISPLAY:-wayland-0}"; \
	SHARED_SOCKET="$(TART_SHARED_DIR)/$$SOCKET_NAME"; \
	DEFAULT_RUNTIME="$${XDG_RUNTIME_DIR:-$${TMPDIR:-/tmp}/wayland-runtime}"; \
	DEFAULT_RUNTIME=$$(echo "$$DEFAULT_RUNTIME" | sed 's#//#/#g'); \
	DEFAULT_SOCKET="$$DEFAULT_RUNTIME/$$SOCKET_NAME"; \
	DEFAULT_SOCKET=$$(echo "$$DEFAULT_SOCKET" | sed 's#//#/#g'); \
	if [ -S "$$SHARED_SOCKET" ]; then \
		SOCKET_PATH="$$SHARED_SOCKET"; \
		USE_SHARED="yes"; \
	elif [ -S "$$DEFAULT_SOCKET" ]; then \
		SOCKET_PATH="$$DEFAULT_SOCKET"; \
		USE_SHARED="no"; \
		echo -e "$(YELLOW)ℹ$(NC) Socket not in shared dir. Restart compositor with:"; \
		echo "   $(YELLOW)XDG_RUNTIME_DIR=$(TART_SHARED_DIR) make compositor$(NC)"; \
	else \
		echo -e "$(RED)✗$(NC) Wayland socket not found"; \
		echo "   Run: $(YELLOW)make compositor$(NC) first"; \
		exit 1; \
	fi; \
	echo -e "$(GREEN)✓$(NC) Wayland socket: $$SOCKET_PATH"; \
	echo -e "$(YELLOW)ℹ$(NC) USE_SHARED=$$USE_SHARED"; \
	VM_STATUS=$$(tart list 2>/dev/null | grep -E "^[^ ]+ +$(TART_VM_NAME)" | awk "{print \$$NF}" || echo "stopped"); \
	VM_PID=""; \
	if [ "$$VM_STATUS" = "running" ]; then \
		VM_IP=$$(tart ip "$(TART_VM_NAME)" 2>/dev/null); \
		if [ -n "$$VM_IP" ]; then \
			echo -e "$(GREEN)✓$(NC) VM already running: $$VM_IP"; \
		else \
			echo -e "$(YELLOW)ℹ$(NC) VM running but no IP, stopping..."; \
			tart stop "$(TART_VM_NAME)" 2>/dev/null || true; \
			sleep 2; \
			VM_STATUS="stopped"; \
		fi; \
	fi; \
	if [ "$$VM_STATUS" != "running" ]; then \
		echo -e "$(YELLOW)ℹ$(NC) Starting VM..."; \
		mkdir -p "$(TART_SHARED_DIR)"; \
		if [ ! -d "$(TART_SHARED_DIR)" ]; then \
			echo -e "$(RED)✗$(NC) Failed to create shared directory: $(TART_SHARED_DIR)"; \
			exit 1; \
		fi; \
		if [ -S "$$SOCKET_PATH" ]; then \
			echo -e "$(YELLOW)ℹ$(NC) Note: Socket exists but Unix sockets cannot be copied"; \
			echo -e "$(YELLOW)ℹ$(NC) Compositor should create socket in $(TART_SHARED_DIR) for VM access"; \
		fi; \
		tart run "$(TART_VM_NAME)" --dir "$(TART_SHARED_DIR):tag=$(TART_MOUNT_TAG)" > /tmp/tart-vm.log 2>&1 & \
		VM_PID=$$!; \
		echo $$VM_PID > /tmp/tart-vm.pid; \
		sleep 5; \
		for i in $$(seq 1 30); do \
			VM_STATUS=$$(tart list 2>/dev/null | grep -E "^[^ ]+ +$(TART_VM_NAME)" | awk "{print \$$NF}" || echo "stopped"); \
			if [ "$$VM_STATUS" = "running" ]; then \
				VM_IP=$$(tart ip "$(TART_VM_NAME)" 2>/dev/null); \
				if [ -n "$$VM_IP" ]; then \
					echo -e "$(GREEN)✓$(NC) VM started: $$VM_IP"; \
					break; \
				fi; \
			fi; \
			if [ $$i -eq 30 ]; then \
				echo -e "$(RED)✗$(NC) Failed to get VM IP after 30 seconds"; \
				echo "   Check logs: $(YELLOW)cat /tmp/tart-vm.log$(NC)"; \
				kill $$VM_PID 2>/dev/null || true; \
				tart stop "$(TART_VM_NAME)" 2>/dev/null || true; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
	fi; \
	echo -e "$(YELLOW)ℹ$(NC) Waiting for SSH..."; \
	for i in $$(seq 1 20); do \
		if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			admin@$$VM_IP "echo ready" >/dev/null 2>&1; then \
			break; \
		fi; \
		if [ $$i -eq 20 ]; then \
			echo -e "$(RED)✗$(NC) SSH not ready after 20 seconds"; \
			if [ -n "$$VM_PID" ]; then kill $$VM_PID 2>/dev/null || true; fi; \
			exit 1; \
		fi; \
		sleep 1; \
	done; \
	echo -e "$(YELLOW)ℹ$(NC) Setting up SSH keys..."; \
	if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o PasswordAuthentication=no -o BatchMode=yes \
		admin@$$VM_IP "echo test" >/dev/null 2>&1; then \
		echo -e "$(GREEN)✓$(NC) SSH keys already configured"; \
	else \
		ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			admin@$$VM_IP || { \
			echo -e "$(RED)✗$(NC) ssh-copy-id failed (enter password for admin)"; \
			if [ -n "$$VM_PID" ]; then kill $$VM_PID 2>/dev/null || true; fi; \
			exit 1; \
		}; \
		echo -e "$(GREEN)✓$(NC) SSH key copied"; \
	fi; \
	echo -e "$(YELLOW)ℹ$(NC) Checking VM dependencies..."; \
	if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		admin@$$VM_IP "command -v foot >/dev/null 2>&1" 2>/dev/null; then \
		echo -e "$(YELLOW)ℹ$(NC) Installing foot on VM..."; \
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			admin@$$VM_IP "sudo dnf install -y foot" || { \
			echo -e "$(RED)✗$(NC) Failed to install foot on VM"; \
			if [ -n "$$VM_PID" ]; then kill $$VM_PID 2>/dev/null || true; fi; \
			exit 1; \
		}; \
		echo -e "$(GREEN)✓$(NC) foot installed"; \
	else \
		echo -e "$(GREEN)✓$(NC) foot already installed"; \
	fi; \
	if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		admin@$$VM_IP "command -v waypipe >/dev/null 2>&1" 2>/dev/null; then \
		echo -e "$(YELLOW)ℹ$(NC) Installing waypipe on VM..."; \
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			admin@$$VM_IP "sudo dnf install -y waypipe" || { \
			echo -e "$(RED)✗$(NC) Failed to install waypipe on VM"; \
			if [ -n "$$VM_PID" ]; then kill $$VM_PID 2>/dev/null || true; fi; \
			exit 1; \
		}; \
		echo -e "$(GREEN)✓$(NC) waypipe installed"; \
	else \
		echo -e "$(GREEN)✓$(NC) waypipe already installed"; \
	fi; \
	if command -v waypipe >/dev/null 2>&1; then \
		echo -e "$(GREEN)✓$(NC) Using waypipe for Wayland forwarding..."; \
		export PATH="$${INSTALL_PREFIX:-/opt/homebrew}/bin:/usr/local/bin:$$PATH"; \
		WAYLAND_DISPLAY="$$SOCKET_NAME" XDG_RUNTIME_DIR="$$(dirname "$$SOCKET_PATH")" \
		waypipe ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$$VM_IP foot -e pfetch || { \
			echo -e "$(RED)✗$(NC) Failed to run foot via waypipe"; \
			if [ -n "$$VM_PID" ]; then kill $$VM_PID 2>/dev/null || true; fi; \
			exit 1; \
		}; \
	else \
		echo -e "$(YELLOW)ℹ$(NC) waypipe not found on macOS host"; \
		echo -e "$(YELLOW)ℹ$(NC) Note: waypipe macOS port is in progress (see waypipe/ directory)"; \
		echo -e "$(YELLOW)ℹ$(NC) Using SSH socket forwarding as fallback..."; \
		SOCKET_PATH=$$(echo "$$SOCKET_PATH" | sed 's#//#/#g'); \
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			-o StreamLocalBindUnlink=yes \
			-R /tmp/wayland-0:"$$SOCKET_PATH" \
			admin@$$VM_IP \
			"export XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=wayland-0; sleep 2; if [ ! -S /tmp/wayland-0 ]; then echo Error: Socket not found; exit 1; fi; echo Socket found, starting foot...; foot -e pfetch" || { \
			echo ""; \
			echo -e "$(RED)✗$(NC) Failed to run foot"; \
			echo "   Build waypipe: $(YELLOW)make waypipe$(NC) (macOS port in progress)"; \
			if [ -n "$$VM_PID" ]; then kill $$VM_PID 2>/dev/null || true; fi; \
			exit 1; \
		}; \
	fi; \
	if [ -n "$$VM_PID" ]; then \
		echo -e "$(YELLOW)ℹ$(NC) Stopping VM..."; \
		kill $$VM_PID 2>/dev/null || true; \
		tart stop "$(TART_VM_NAME)" 2>/dev/null || true; \
	fi'

# External client: connect to external Linux machine via waypipe
external-client:
	@bash -c '\
	set -e; \
	export WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-0}"; \
	export XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"; \
	XDG_RUNTIME_DIR=$$(echo "$$XDG_RUNTIME_DIR" | sed "s#//#/#g"); \
	SOCKET_PATH="$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY"; \
	echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo -e "$(BLUE)▶$(NC) Connecting External Client"; \
	echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo ""; \
	echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo -e "$(BLUE)▶$(NC) Environment Variables$(NC)"; \
	echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo -e "$(YELLOW)ℹ$(NC) WAYLAND_DISPLAY=$(GREEN)$$WAYLAND_DISPLAY$(NC)"; \
	echo -e "$(YELLOW)ℹ$(NC) XDG_RUNTIME_DIR=$(GREEN)$$XDG_RUNTIME_DIR$(NC)"; \
	echo -e "$(YELLOW)ℹ$(NC) Compositor socket: $(GREEN)$$SOCKET_PATH$(NC)"; \
	if [ ! -S "$$SOCKET_PATH" ]; then \
		echo -e "$(YELLOW)⚠$(NC) Socket not found - waypipe will attempt to connect anyway"; \
		echo ""; \
	fi; \
	echo ""; \
	if [ -z "$(EXTERNAL_CLIENT_HOST)" ]; then \
		echo -e "$(RED)✗$(NC) EXTERNAL_CLIENT_HOST not set"; \
		echo "   Usage: $(YELLOW)make external-client EXTERNAL_CLIENT_HOST=10.0.0.109$(NC)"; \
		echo "   Or: $(YELLOW)EXTERNAL_CLIENT_HOST=my-nixos-box make external-client$(NC)"; \
		exit 1; \
	fi; \
	EXTERNAL_HOST="$(EXTERNAL_CLIENT_HOST)"; \
	EXTERNAL_USER="$${EXTERNAL_CLIENT_USER:-alex}"; \
	echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo -e "$(BLUE)▶$(NC) Connection Details$(NC)"; \
	echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo -e "$(YELLOW)ℹ$(NC) Remote host: $(GREEN)$$EXTERNAL_USER@$$EXTERNAL_HOST$(NC)"; \
	echo -e "$(YELLOW)ℹ$(NC) Command: $(GREEN)foot$(NC)"; \
	echo ""; \
	echo -e "$(YELLOW)ℹ$(NC) Cleaning remote socket before connecting..."; \
	ssh $$EXTERNAL_USER@$$EXTERNAL_HOST "rm -f /run/user/1000/wayland-* /tmp/wayland-* 2>/dev/null; echo \"✓ Cleaned remote sockets\"" 2>/dev/null || echo -e "$(YELLOW)⚠$(NC) Could not clean remote socket (continuing anyway)"; \
	echo ""; \
	echo -e "$(YELLOW)ℹ$(NC) Connecting..."; \
	echo ""; \
	echo -e "$(YELLOW)ℹ$(NC) Using compression: $(GREEN)lz4$(NC) (default)"; \
	echo -e "$(YELLOW)ℹ$(NC) For better compression, use: $(GREEN)waypipe -c zstd ssh ...$(NC)"; \
	echo ""; \
	WAYLAND_DISPLAY="$$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$$XDG_RUNTIME_DIR" waypipe -c lz4 ssh $$EXTERNAL_USER@$$EXTERNAL_HOST foot'

# Container client: Run Weston in macOS Containerization.framework container
# Uses Alpine Linux (lightweight) and shares Wayland socket directly (no waypipe)
# Automatically builds and installs container tool if not already installed
container-client:
	@echo "$(YELLOW)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(YELLOW)⚠$(NC)  $(RED)LIMITATION:$(NC) macOS Containerization.framework does NOT support"
	@echo "     Unix domain sockets across bind mounts."
	@echo ""
	@echo "     The socket file will be visible, but connections will fail"
	@echo "     with 'Connection refused'."
	@echo ""
	@echo "$(YELLOW)ℹ$(NC)  For working Unix socket support, use: $(GREEN)make colima-client$(NC)"
	@echo "$(YELLOW)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@$(shell pwd)/scripts/container-client.sh

colima-client:
	@$(shell pwd)/scripts/colima-client.sh

colima-client-ios:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Connecting to iOS Simulator Wawona Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@IOS_SIMULATOR_MODE=1 $(shell pwd)/scripts/colima-client.sh 2>&1 || { \
		echo ""; \
		echo "$(RED)✗$(NC) Failed to connect to iOS Simulator Wawona"; \
		echo ""; \
		echo "$(YELLOW)ℹ$(NC) Common issues:"; \
		echo "  1. Wawona is not running in iOS Simulator"; \
		echo "  2. Wayland socket not created yet"; \
		echo ""; \
		echo "$(YELLOW)ℹ$(NC) Try:"; \
		echo "  make ios-compositor"; \
		echo ""; \
		echo "$(YELLOW)ℹ$(NC) For detailed error, run:"; \
		echo "  IOS_SIMULATOR_MODE=1 bash scripts/colima-client.sh"; \
		echo ""; \
		exit 1; \
	}

colima-weston-simple-egl:
	@$(shell pwd)/scripts/colima-weston-simple-egl.sh

# Stop compositor
stop-compositor:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Stopping Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@KILLED=0; \
	for PID in $$(pgrep -f "Wawona" 2>/dev/null || true); do \
		if [ -n "$$PID" ] && kill -TERM $$PID 2>/dev/null; then \
			echo "$(YELLOW)⚠$(NC) Sent TERM to compositor process $$PID"; \
			KILLED=$$((KILLED + 1)); \
		fi; \
	done; \
	if [ $$KILLED -gt 0 ]; then \
		sleep 1; \
		for PID in $$(pgrep -f "Wawona" 2>/dev/null || true); do \
			if [ -n "$$PID" ] && kill -9 $$PID 2>/dev/null; then \
				echo "$(YELLOW)⚠$(NC) Force killed remaining process $$PID"; \
			fi; \
		done; \
		echo "$(GREEN)✓$(NC) Compositor stopped"; \
	else \
		echo "$(YELLOW)ℹ$(NC) No compositor process found"; \
	fi

# Wayland Conformance Test Suite (wlcs) via Colima
colima-wlcs:
	@$(shell pwd)/scripts/colima-wlcs.sh

# Clean remote Wayland sockets (on remote machine via SSH)
clean-remote-socket:
	@bash -c '\
	set -e; \
	EXTERNAL_HOST="$(EXTERNAL_CLIENT_HOST)"; \
	EXTERNAL_USER="$${EXTERNAL_CLIENT_USER:-alex}"; \
	REMOTE_SOCKET_PATH="/run/user/1000/wayland-0"; \
	if [ -z "$$EXTERNAL_HOST" ]; then \
		echo -e "$(YELLOW)ℹ$(NC) Usage: $(GREEN)make clean-remote-socket EXTERNAL_CLIENT_HOST=your-host$(NC)"; \
		echo -e "$(YELLOW)ℹ$(NC) Example: $(GREEN)make clean-remote-socket EXTERNAL_CLIENT_HOST=10.0.0.109$(NC)"; \
		echo ""; \
		exit 0; \
	fi; \
	echo -e "$(YELLOW)ℹ$(NC) Cleaning remote Wayland socket on $$EXTERNAL_USER@$$EXTERNAL_HOST..."; \
	echo -e "$(YELLOW)ℹ$(NC) Socket path: $(GREEN)$$REMOTE_SOCKET_PATH$(NC)"; \
	ssh $$EXTERNAL_USER@$$EXTERNAL_HOST "rm -f $$REMOTE_SOCKET_PATH /run/user/1000/wayland-* /tmp/wayland-* 2>/dev/null; echo \"✓ Cleaned remote sockets\"" || { \
		echo -e "$(YELLOW)⚠$(NC) Failed to clean remote socket (may not exist or SSH failed)"; \
		exit 0; \
	}; \
	echo -e "$(GREEN)✓$(NC) Remote socket cleanup complete"'

# Wayland: clean, build, install (preserves local changes in wayland/ directory)
wayland: clean-wayland
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Installing Wayland"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ -d "wayland" ]; then \
		echo "$(YELLOW)ℹ$(NC) Using existing wayland directory (local changes will be preserved)"; \
	fi
	@rm -f wayland-install.log
	@./install-wayland.sh < /dev/null 2>&1 | tee wayland-install.log

# xkbcommon: build and install (required for keyboard handling)
xkbcommon:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building xkbcommon"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/build-xkbcommon.sh

# libinput: build and install (Linux-specific, may not work on macOS)
libinput:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building libinput"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/build-libinput.sh

# Weston: build full compositor for macOS (nested Wayland backend)
weston: clean-weston build-weston-compositor run-weston-compositor

build-weston-compositor:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Weston Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/build-weston-compositor.sh

run-weston-compositor:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Running Weston Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "weston-install/bin/weston" ]; then \
		echo "$(RED)✗$(NC) Weston compositor not built. Build failed."; \
		exit 1; \
	fi
	@bash -c '\
		export WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-0}"; \
		export XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"; \
		XDG_RUNTIME_DIR=$$(echo "$$XDG_RUNTIME_DIR" | sed "s#//#/#g"); \
		rm -rf "$$XDG_RUNTIME_DIR"; \
		mkdir -p "$$XDG_RUNTIME_DIR"; \
		chmod 0700 "$$XDG_RUNTIME_DIR"; \
		if [ ! -S "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY" ]; then \
			echo "$(YELLOW)ℹ$(NC) Starting Wawona compositor..."; \
			WAYLAND_DISPLAY="$$WAYLAND_DISPLAY" \
			 XDG_RUNTIME_DIR="$$XDG_RUNTIME_DIR" \
			 $(COMPOSITOR_BIN) >/tmp/wawona-for-weston.log 2>&1 & \
			COMPOSITOR_PID=$$!; \
			sleep 3; \
			if ! kill -0 $$COMPOSITOR_PID 2>/dev/null; then \
				echo "$(RED)✗$(NC) Compositor failed to start. Check /tmp/wawona-for-weston.log"; \
				if [ -f /tmp/wawona-for-weston.log ]; then \
					tail -30 /tmp/wawona-for-weston.log; \
				fi; \
				exit 1; \
			fi; \
			for i in 1 2 3 4 5; do \
				if [ -S "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY" ]; then \
					break; \
				fi; \
				sleep 1; \
			done; \
			if [ ! -S "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY" ]; then \
				echo "$(RED)✗$(NC) Compositor socket not created after 8 seconds. Check /tmp/wawona-for-weston.log"; \
				if [ -f /tmp/wawona-for-weston.log ]; then \
					tail -30 /tmp/wawona-for-weston.log; \
				fi; \
				kill $$COMPOSITOR_PID 2>/dev/null || true; \
				exit 1; \
			fi; \
			chmod 0700 "$$XDG_RUNTIME_DIR"; \
			echo "$(GREEN)✓$(NC) Compositor started (PID: $$COMPOSITOR_PID)"; \
		fi; \
		echo "$(YELLOW)ℹ$(NC) Running Weston nested within Wawona..."; \
		echo "$(YELLOW)ℹ$(NC) Socket: $(GREEN)$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY$(NC)"; \
		echo "$(YELLOW)ℹ$(NC) To stop: Ctrl+C"; \
		echo ""; \
		trap "kill $$COMPOSITOR_PID 2>/dev/null || true" EXIT INT TERM; \
		WAYLAND_DISPLAY="$$WAYLAND_DISPLAY" \
		 XDG_RUNTIME_DIR="$$XDG_RUNTIME_DIR" \
		 WESTON_LOG_SCOPE="*" \
		 "weston-install/bin/weston" --backend=wayland --no-config --idle-time=0 --output-count=1 --width=1024 --height=768 2>&1; \
		EXIT_CODE=$$?; \
		echo ""; \
		if [ $$EXIT_CODE -eq 130 ]; then \
			echo "$(GREEN)✓$(NC) Weston stopped (Ctrl+C)"; \
		elif [ $$EXIT_CODE -eq 0 ]; then \
			echo "$(GREEN)✓$(NC) Weston exited normally"; \
		else \
			echo "$(YELLOW)⚠$(NC) Weston exited with code $$EXIT_CODE"; \
			echo "$(YELLOW)ℹ$(NC) This may indicate an initialization error. Check output above for details."; \
			echo "$(YELLOW)ℹ$(NC) The signalfd warnings are expected on macOS and harmless."; \
		fi; \
		kill $$COMPOSITOR_PID 2>/dev/null || true; \
	'

# Clean Weston build
clean-weston:
	@echo "$(YELLOW)ℹ$(NC) Cleaning Weston build..."
	@if [ -d "weston/build" ]; then \
		rm -rf weston/build; \
		echo "$(GREEN)✓$(NC) Cleaned Weston build directory"; \
	fi
	@if [ -d "weston-install" ]; then \
		rm -rf weston-install; \
		echo "$(GREEN)✓$(NC) Removed Weston install directory: weston-install"; \
	fi

# Waypipe: clean, build, install (for Wayland forwarding over SSH)
waypipe: clean-waypipe build-waypipe install-waypipe ios-waypipe
	@echo "$(GREEN)✓$(NC) Waypipe built for macOS and iOS"

build-waypipe:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Custom Waypipe"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -d "waypipe" ]; then \
		echo "$(RED)✗$(NC) waypipe directory not found"; \
		echo "   Run: $(YELLOW)git clone https://gitlab.freedesktop.org/mstoeckl/waypipe.git$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Checking dependencies..."
	@MISSING_DEPS=0; \
	if ! command -v cargo >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) cargo not found"; \
		echo "   Install Rust: $(YELLOW)curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh$(NC)"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) cargo: $$(cargo --version | head -n1)"; \
	fi; \
	if ! command -v bindgen >/dev/null 2>&1 && ! command -v ~/.cargo/bin/bindgen >/dev/null 2>&1; then \
		echo "$(YELLOW)ℹ$(NC) bindgen not found, installing..."; \
		cargo install bindgen-cli 2>&1 | grep -E "(Installing|Updating|Ignored)" || true; \
	fi; \
	if ! command -v pkg-config >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) pkg-config not found"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) pkg-config: $$(pkg-config --version)"; \
	fi; \
	if [ $$MISSING_DEPS -eq 1 ]; then \
		echo "$(RED)✗$(NC) Missing required dependencies"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Building Rust waypipe for macOS..."
	@if ! command -v cargo >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) cargo not found"; \
		echo "   Install Rust: $(YELLOW)curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Checking for KosmicKrisp Vulkan driver (REQUIRED)..."
	@HAS_KOSMICKRISP=0; \
	if [ -f "/opt/homebrew/lib/libvulkan_kosmickrisp.dylib" ] && [ -f "/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json" ]; then \
		echo "$(GREEN)✓$(NC) KosmicKrisp Vulkan driver found"; \
		HAS_KOSMICKRISP=1; \
	else \
		echo "$(RED)✗$(NC) KosmicKrisp Vulkan driver not found!"; \
		echo "$(RED)✗$(NC) Required files:"; \
		echo "   - /opt/homebrew/lib/libvulkan_kosmickrisp.dylib"; \
		echo "   - /opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"; \
		echo "$(YELLOW)ℹ$(NC) Install KosmicKrisp driver: $(GREEN)make kosmickrisp$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Checking for shader compiler (required for video feature)..."
	@HAS_SHADER_COMPILER=0; \
	if command -v glslc >/dev/null 2>&1 || command -v glslangValidator >/dev/null 2>&1; then \
		echo "$(GREEN)✓$(NC) Shader compiler found"; \
		HAS_SHADER_COMPILER=1; \
	elif [ -f "/opt/homebrew/bin/glslc" ] || [ -f "/opt/homebrew/bin/glslangValidator" ]; then \
		export PATH="/opt/homebrew/bin:$$PATH"; \
		echo "$(GREEN)✓$(NC) Found shader compiler in /opt/homebrew/bin"; \
		HAS_SHADER_COMPILER=1; \
	else \
		echo "$(RED)✗$(NC) glslc/glslangValidator not found!"; \
		echo "$(YELLOW)ℹ$(NC) Install with: $(GREEN)brew install glslang$(NC)"; \
		echo "$(RED)✗$(NC) Video feature requires shader compiler - build will fail"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Building with ALL features: dmabuf, video, lz4, zstd..."
	@FEATURES="dmabuf,video,lz4,zstd"; \
	cd waypipe && \
		export PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:$$PKG_CONFIG_PATH && \
		export PATH=$$HOME/.cargo/bin:/opt/homebrew/bin:$$PATH && \
		export RUSTFLAGS="-D warnings" && \
		export VK_ICD_FILENAMES=/opt/homebrew/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json && \
		if ! command -v bindgen >/dev/null 2>&1 && [ -f "$$HOME/.cargo/bin/bindgen" ]; then \
			export PATH="$$HOME/.cargo/bin:$$PATH"; \
		fi && \
		cargo build --release --no-default-features --features "$$FEATURES" 2>&1 | tee ../waypipe-build.log || { \
			echo "$(RED)✗$(NC) Build failed - see waypipe-build.log"; \
			exit 1; \
		}
	@if [ ! -f "waypipe/target/release/waypipe" ]; then \
		echo "$(RED)✗$(NC) Binary not found: waypipe/target/release/waypipe"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Verifying all features are enabled..."
	@WAYPIPE_VERSION=$$($(PWD)/waypipe/target/release/waypipe --version 2>&1); \
		if echo "$$WAYPIPE_VERSION" | grep -q "dmabuf: true" && \
		   echo "$$WAYPIPE_VERSION" | grep -q "video: true" && \
		   echo "$$WAYPIPE_VERSION" | grep -q "lz4: true" && \
		   echo "$$WAYPIPE_VERSION" | grep -q "zstd: true"; then \
			echo "$(GREEN)✓$(NC) All features enabled"; \
		else \
			echo "$(RED)✗$(NC) Not all features are enabled!"; \
			echo "$$WAYPIPE_VERSION"; \
			exit 1; \
		fi
	@BINARY_SIZE=$$(du -h waypipe/target/release/waypipe | cut -f1); \
		echo "$(GREEN)✓$(NC) Build complete"; \
		echo "$(GREEN)✓$(NC) Binary created: waypipe/target/release/waypipe ($$BINARY_SIZE)"

install-waypipe: build-waypipe
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Installing Waypipe Binary"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "waypipe/target/release/waypipe" ]; then \
		echo "$(RED)✗$(NC) waypipe binary not found - run $(YELLOW)make build-waypipe$(NC) first"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Installing to /opt/homebrew/bin/waypipe..."
	@cp waypipe/target/release/waypipe /opt/homebrew/bin/waypipe && \
		chmod +x /opt/homebrew/bin/waypipe && \
		echo "$(GREEN)✓$(NC) Installed waypipe to /opt/homebrew/bin/waypipe"
	@echo "$(YELLOW)ℹ$(NC) Signing binary for macOS..."
	@codesign --force --deep --sign - /opt/homebrew/bin/waypipe >/dev/null 2>&1 && \
		echo "$(GREEN)✓$(NC) Binary signed successfully" || \
		echo "$(YELLOW)⚠$(NC) Code signing failed (may need manual signing)"
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Verifying installation..."
	@if [ -f "/opt/homebrew/bin/waypipe" ] && [ -x "/opt/homebrew/bin/waypipe" ]; then \
		echo "$(GREEN)✓$(NC) waypipe binary installed at /opt/homebrew/bin/waypipe"; \
		BINARY_SIZE=$$(du -h /opt/homebrew/bin/waypipe | cut -f1); \
		echo "$(GREEN)✓$(NC) Binary size: $$BINARY_SIZE"; \
		echo ""; \
		echo "$(YELLOW)ℹ$(NC) Testing waypipe version..."; \
		if /opt/homebrew/bin/waypipe --version >/dev/null 2>&1; then \
			echo "$(GREEN)✓$(NC) waypipe is working:"; \
			/opt/homebrew/bin/waypipe --version | sed 's/^/  /'; \
			echo "$(GREEN)✓$(NC) Installation complete!"; \
		else \
			echo "$(YELLOW)⚠$(NC) waypipe binary exists but version check failed"; \
			echo "$(GREEN)✓$(NC) Installation complete (binary may need manual testing)"; \
		fi; \
	else \
		echo "$(RED)✗$(NC) Installation failed - binary not found"; \
		exit 1; \
	fi

clean-waypipe:
	@echo "$(YELLOW)ℹ$(NC) Cleaning waypipe build..."
	@if [ -d "waypipe/target" ]; then \
		cd waypipe && cargo clean 2>/dev/null || true; \
		echo "$(GREEN)✓$(NC) Cleaned waypipe Rust build artifacts"; \
	fi
	@if [ -d "waypipe/build" ]; then \
		cd waypipe && rm -rf build 2>/dev/null || true; \
		echo "$(GREEN)✓$(NC) Cleaned waypipe Meson build directory"; \
	fi
	@rm -f waypipe-build.log waypipe-install.log

# KosmicKrisp: clean, clone, build, and install Vulkan driver for macOS (with EGL support via Zink)
kosmickrisp: kosmickrisp-macos kosmickrisp-ios
	@echo "$(GREEN)✓$(NC) KosmicKrisp built for macOS and iOS"

kosmickrisp-macos:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building KosmicKrisp Vulkan Driver for macOS (with EGL support)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Step 1: Cleaning previous build..."
	@if [ -d "kosmickrisp/build" ]; then \
		echo "$(YELLOW)ℹ$(NC) Removing build directory..."; \
		cd kosmickrisp && \
		if rm -rf build 2>/dev/null; then \
			echo "$(GREEN)✓$(NC) Cleaned KosmicKrisp build directory"; \
		elif sudo rm -rf build 2>/dev/null; then \
			echo "$(GREEN)✓$(NC) Cleaned KosmicKrisp build directory (used sudo)"; \
		else \
			echo "$(YELLOW)⚠$(NC) Could not fully remove build directory (permission issues)"; \
			echo "$(YELLOW)ℹ$(NC) Meson will handle this with --wipe flag"; \
		fi; \
	fi
	@rm -f kosmickrisp-build.log kosmickrisp-install.log kosmickrisp-clone.log
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Step 2: Cloning/updating Mesa repository..."
	@if [ -d "kosmickrisp" ]; then \
		echo "$(GREEN)✓$(NC) KosmicKrisp directory already exists"; \
		echo "$(YELLOW)ℹ$(NC) Updating repository..."; \
		cd kosmickrisp && \
		if [ -n "$$(git status --porcelain)" ]; then \
			echo "$(YELLOW)ℹ$(NC) Stashing local changes..."; \
			git stash push -m "Wawona local changes preserved by make kosmickrisp" >/dev/null 2>&1 || true; \
			HAD_STASH=true; \
		else \
			HAD_STASH=false; \
		fi; \
		git pull 2>&1 | grep -E "(Already up to date|Updating|error)" || true; \
		if [ "$$HAD_STASH" = "true" ]; then \
			echo "$(YELLOW)ℹ$(NC) Reapplying local changes..."; \
			git stash pop >/dev/null 2>&1 || { \
				echo "$(YELLOW)⚠$(NC) Some local changes may have conflicts - check manually if needed"; \
				git stash list | head -1; \
			}; \
		fi; \
	else \
		echo "$(YELLOW)ℹ$(NC) Cloning Mesa repository (KosmicKrisp driver merged in Mesa 26.0)..."; \
		echo "$(YELLOW)ℹ$(NC) KosmicKrisp is a Vulkan-to-Metal driver for macOS (merged October 2025)"; \
		git clone --depth 1 --branch main https://gitlab.freedesktop.org/mesa/mesa.git kosmickrisp 2>&1 | tee kosmickrisp-clone.log || { \
			echo "$(RED)✗$(NC) Failed to clone Mesa repository"; \
			echo "$(YELLOW)ℹ$(NC) Please check KOSMICKRISP.md for alternative repository URLs"; \
			cat kosmickrisp-clone.log 2>/dev/null || true; \
			exit 1; \
		}; \
		echo "$(GREEN)✓$(NC) Cloned Mesa repository"; \
	fi
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Step 3: Checking build dependencies..."
	@MISSING_DEPS=0; \
	if ! command -v meson >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) meson not found"; \
		echo "   Install with: $(YELLOW)brew install meson$(NC)"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) meson: $$(meson --version | head -n1)"; \
	fi; \
	if ! command -v ninja >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) ninja not found"; \
		echo "   Install with: $(YELLOW)brew install ninja$(NC)"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) ninja: $$(ninja --version)"; \
	fi; \
	if ! brew list libclc >/dev/null 2>&1; then \
		echo "$(YELLOW)ℹ$(NC) Installing libclc..."; \
		brew install libclc >/dev/null 2>&1 || { \
			echo "$(RED)✗$(NC) Failed to install libclc"; \
			MISSING_DEPS=1; \
		}; \
	fi; \
	if ! python3 -c "import mako" >/dev/null 2>&1; then \
		echo "$(YELLOW)ℹ$(NC) Installing Python mako module..."; \
		python3 -m pip install --break-system-packages mako >/dev/null 2>&1 || { \
			echo "$(RED)✗$(NC) Failed to install mako"; \
			MISSING_DEPS=1; \
		}; \
	fi; \
	if ! python3 -c "import yaml" >/dev/null 2>&1; then \
		echo "$(YELLOW)ℹ$(NC) Installing Python PyYAML module..."; \
		python3 -m pip install --break-system-packages pyyaml >/dev/null 2>&1 || { \
			echo "$(RED)✗$(NC) Failed to install pyyaml"; \
			MISSING_DEPS=1; \
		}; \
	fi; \
	if ! python3 -c "import setuptools" >/dev/null 2>&1; then \
		echo "$(YELLOW)ℹ$(NC) Installing Python setuptools..."; \
		brew install python-setuptools >/dev/null 2>&1 || { \
			echo "$(RED)✗$(NC) Failed to install setuptools"; \
			MISSING_DEPS=1; \
		}; \
	fi; \
	if ! brew list llvm >/dev/null 2>&1; then \
		echo "$(YELLOW)ℹ$(NC) Installing LLVM (required for Mesa build)..."; \
		brew install llvm >/dev/null 2>&1 || { \
			echo "$(RED)✗$(NC) Failed to install LLVM"; \
			MISSING_DEPS=1; \
		}; \
	fi; \
	if ! brew list spirv-llvm-translator >/dev/null 2>&1; then \
		echo "$(YELLOW)ℹ$(NC) Installing SPIRV-LLVM-Translator (required for Mesa build)..."; \
		brew install spirv-llvm-translator >/dev/null 2>&1 || { \
			echo "$(RED)✗$(NC) Failed to install spirv-llvm-translator"; \
			MISSING_DEPS=1; \
		}; \
	fi; \
	if ! pkg-config --exists vulkan 2>/dev/null; then \
		echo "$(YELLOW)⚠$(NC) Vulkan headers not found via pkg-config (may be in Vulkan SDK)"; \
	fi; \
	if [ $$MISSING_DEPS -eq 1 ]; then \
		echo "$(RED)✗$(NC) Missing required dependencies"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Configuring KosmicKrisp build for macOS..."
	@echo "$(YELLOW)ℹ$(NC) Configuring Mesa with KosmicKrisp driver (Mesa 26.0+)..."; \
		cd kosmickrisp && \
	if [ -d "build" ] && [ ! -f "build/build.ninja" ]; then \
		echo "$(YELLOW)ℹ$(NC) Removing invalid build directory (may require sudo)..."; \
		rm -rf build 2>/dev/null || sudo rm -rf build 2>/dev/null || true; \
	fi; \
	PATH=/opt/homebrew/opt/bison/bin:$$PATH \
		LLVM_CONFIG=/opt/homebrew/opt/llvm/bin/llvm-config \
		PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:$$PKG_CONFIG_PATH \
		meson setup build \
		--prefix=$(KOSMICKRISP_PREFIX) \
		--wipe \
			-Dplatforms=macos,wayland \
			-Dvulkan-drivers=kosmickrisp \
		-Dgallium-drivers=zink \
		-Degl=enabled \
		-Dgles1=enabled \
		-Dgles2=enabled \
		-Dglx=disabled \
		-Dmoltenvk-dir=$$(brew --prefix molten-vk) \
			-Dvulkan-layers='[]' \
			-Dtools='[]' \
			2>&1 | tee ../kosmickrisp-build.log || { \
			echo "$(RED)✗$(NC) Meson configuration failed - see kosmickrisp-build.log"; \
			echo "$(YELLOW)ℹ$(NC) Note: KosmicKrisp requires Mesa 26.0+ (merged October 2025)"; \
			exit 1; \
		}; \
	echo "$(GREEN)✓$(NC) Meson configuration complete"
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Building KosmicKrisp driver..."
	@cd kosmickrisp && \
		PATH=/opt/homebrew/opt/bison/bin:$$PATH \
		LLVM_CONFIG=/opt/homebrew/opt/llvm/bin/llvm-config \
		PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:$$PKG_CONFIG_PATH \
		ninja -C build 2>&1 | tee -a ../kosmickrisp-build.log; \
	BUILD_EXIT=$${PIPESTATUS[0]}; \
	if [ $$BUILD_EXIT -ne 0 ]; then \
		echo "$(RED)✗$(NC) Build failed (exit code $$BUILD_EXIT) - see kosmickrisp-build.log"; \
			exit 1; \
	fi
	@echo "$(GREEN)✓$(NC) Build complete"
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Step 3b: Uninstalling previous installation..."
	@UNINSTALL_CMD=""; \
	if [ -z "$(KOSMICKRISP_DESTDIR)" ]; then \
		case "$(KOSMICKRISP_PREFIX)" in \
			/opt/homebrew|/usr/local|/usr) \
				UNINSTALL_CMD="sudo"; \
				;; \
		esac; \
	fi; \
	REMOVED=0; \
	echo "$(YELLOW)ℹ$(NC) Removing previously installed KosmicKrisp components..."; \
	for lib in libvulkan_kosmickrisp.dylib libEGL.dylib libEGL.1.dylib libGLESv1_CM.dylib libGLESv1_CM.1.dylib libGLESv2.dylib libGLESv2.2.dylib libgallium-26.0.0-devel.dylib; do \
		if [ -f "$(KOSMICKRISP_LIB)/$$lib" ]; then \
			$$UNINSTALL_CMD rm -f "$(KOSMICKRISP_LIB)/$$lib" 2>/dev/null && REMOVED=$$((REMOVED + 1)); \
		fi; \
	done; \
	for icd in kosmickrisp_mesa_icd.aarch64.json kosmickrisp_icd.json; do \
		if [ -f "$(KOSMICKRISP_PREFIX_FULL)/share/vulkan/icd.d/$$icd" ]; then \
			$$UNINSTALL_CMD rm -f "$(KOSMICKRISP_PREFIX_FULL)/share/vulkan/icd.d/$$icd" 2>/dev/null && REMOVED=$$((REMOVED + 1)); \
		fi; \
	done; \
	for pc in egl.pc glesv1_cm.pc glesv2.pc dri.pc; do \
		if [ -f "$(KOSMICKRISP_PKGCONFIG)/$$pc" ]; then \
			$$UNINSTALL_CMD rm -f "$(KOSMICKRISP_PKGCONFIG)/$$pc" 2>/dev/null && REMOVED=$$((REMOVED + 1)); \
		fi; \
	done; \
	if [ -d "$(KOSMICKRISP_DRI)" ]; then \
		$$UNINSTALL_CMD rm -rf "$(KOSMICKRISP_DRI)"/*.dylib 2>/dev/null && REMOVED=$$((REMOVED + 1)); \
	fi; \
	if [ -d "$(KOSMICKRISP_PREFIX_FULL)/share/drirc.d" ]; then \
		$$UNINSTALL_CMD rm -f "$(KOSMICKRISP_PREFIX_FULL)/share/drirc.d"/*.conf 2>/dev/null && REMOVED=$$((REMOVED + 1)); \
	fi; \
	if [ $$REMOVED -gt 0 ]; then \
		echo "$(GREEN)✓$(NC) Removed $$REMOVED previously installed component(s)"; \
	else \
		echo "$(GREEN)✓$(NC) No previous installation found (clean install)"; \
	fi
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Step 4: Installing KosmicKrisp driver..."
	@echo "$(YELLOW)ℹ$(NC) Installing to $(KOSMICKRISP_PREFIX_FULL)..."
	@cd kosmickrisp && \
		PATH=/opt/homebrew/opt/bison/bin:$$PATH \
		LLVM_CONFIG=/opt/homebrew/opt/llvm/bin/llvm-config \
		PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:$$PKG_CONFIG_PATH \
		INSTALL_CMD=""; \
		if [ -n "$(KOSMICKRISP_DESTDIR)" ]; then \
			INSTALL_CMD="meson install -C build --destdir \"$(KOSMICKRISP_DESTDIR)\""; \
		else \
			INSTALL_CMD="meson install -C build"; \
			case "$(KOSMICKRISP_PREFIX)" in \
				/opt/homebrew|/usr/local|/usr) \
					echo "$(YELLOW)ℹ$(NC) Installing to system directory - will use sudo"; \
					INSTALL_CMD="sudo $$INSTALL_CMD"; \
					;; \
			esac; \
		fi; \
		echo "$(YELLOW)ℹ$(NC) Running: $$INSTALL_CMD"; \
		$$INSTALL_CMD 2>&1 | tee -a ../kosmickrisp-install.log; \
		INSTALL_EXIT=$${PIPESTATUS[0]}; \
		if [ $$INSTALL_EXIT -ne 0 ]; then \
			echo "$(RED)✗$(NC) Installation failed (exit code $$INSTALL_EXIT) - see kosmickrisp-install.log"; \
			echo "$(YELLOW)ℹ$(NC) You may need to run with sudo or set KOSMICKRISP_DESTDIR to a writable location"; \
			echo "$(YELLOW)ℹ$(NC) Last 20 lines of install log:"; \
			tail -20 ../kosmickrisp-install.log | grep -E "(error|Error|ERROR|failed|Failed|FAILED|Installing)" || tail -20 ../kosmickrisp-install.log; \
			exit 1; \
		fi
	@echo "$(GREEN)✓$(NC) Meson installation completed"
	@echo "$(YELLOW)ℹ$(NC) Verifying installed files in $(KOSMICKRISP_PREFIX_FULL)..."
	@INSTALLED_COUNT=0; \
	for file in "$(KOSMICKRISP_LIB)/libvulkan_kosmickrisp.dylib" "$(KOSMICKRISP_LIB)/libEGL.dylib" "$(KOSMICKRISP_LIB)/libGLESv2.dylib"; do \
		if [ -f "$$file" ]; then \
			echo "$(GREEN)✓$(NC) Found: $$file"; \
			INSTALLED_COUNT=$$((INSTALLED_COUNT + 1)); \
		else \
			echo "$(YELLOW)⚠$(NC) Not found: $$file"; \
		fi; \
	done; \
	if [ $$INSTALLED_COUNT -eq 0 ]; then \
		echo "$(YELLOW)⚠$(NC) No expected libraries found in $(KOSMICKRISP_LIB)/"; \
		echo "$(YELLOW)ℹ$(NC) Checking what Meson actually installed..."; \
		if [ -z "$(KOSMICKRISP_DESTDIR)" ]; then \
			echo "$(YELLOW)ℹ$(NC) Checking $(KOSMICKRISP_PREFIX)/lib/ for recently installed files..."; \
			find "$(KOSMICKRISP_PREFIX)/lib" -name "*.dylib" -newer kosmickrisp/build/meson-private/install.dat 2>/dev/null | head -10 || \
			find "$(KOSMICKRISP_PREFIX)/lib" -name "*vulkan*" -o -name "*EGL*" -o -name "*GLES*" 2>/dev/null | head -10; \
		fi; \
		echo "$(YELLOW)ℹ$(NC) Checking build directory for built libraries..."; \
		find kosmickrisp/build -name "*.dylib" -type f 2>/dev/null | grep -E "(vulkan|EGL|GLES)" | head -5 || echo "No matching .dylib files found in build directory"; \
	fi
	@echo "$(GREEN)✓$(NC) KosmicKrisp driver installed"
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Step 4b: Ensuring Gallium library is accessible..."
	@GALLIUM_LIB=""; \
	if [ -f "$(KOSMICKRISP_DRI)/libgallium-26.0.0-devel.dylib" ]; then \
		GALLIUM_LIB="$(KOSMICKRISP_DRI)/libgallium-26.0.0-devel.dylib"; \
	elif [ -f "kosmickrisp/build/src/gallium/targets/dri/libgallium-26.0.0-devel.dylib" ]; then \
		GALLIUM_LIB="kosmickrisp/build/src/gallium/targets/dri/libgallium-26.0.0-devel.dylib"; \
	fi; \
	if [ -n "$$GALLIUM_LIB" ] && [ ! -f "$(KOSMICKRISP_LIB)/libgallium-26.0.0-devel.dylib" ]; then \
		echo "$(YELLOW)ℹ$(NC) Copying Gallium library to $(KOSMICKRISP_LIB)..."; \
		if [ -z "$(KOSMICKRISP_DESTDIR)" ]; then \
			case "$(KOSMICKRISP_PREFIX)" in \
				/opt/homebrew|/usr/local|/usr) \
					sudo cp "$$GALLIUM_LIB" "$(KOSMICKRISP_LIB)/libgallium-26.0.0-devel.dylib" 2>/dev/null || { \
						echo "$(YELLOW)⚠$(NC) Could not copy Gallium library - you may need to run: sudo cp $$GALLIUM_LIB $(KOSMICKRISP_LIB)/"; \
					}; \
					;; \
				*) \
					cp "$$GALLIUM_LIB" "$(KOSMICKRISP_LIB)/libgallium-26.0.0-devel.dylib" 2>/dev/null || true; \
					;; \
			esac; \
		else \
			cp "$$GALLIUM_LIB" "$(KOSMICKRISP_LIB)/libgallium-26.0.0-devel.dylib" 2>/dev/null || true; \
		fi; \
		if [ -f "$(KOSMICKRISP_LIB)/libgallium-26.0.0-devel.dylib" ]; then \
			echo "$(GREEN)✓$(NC) Gallium library installed"; \
		fi; \
	elif [ -f "$(KOSMICKRISP_LIB)/libgallium-26.0.0-devel.dylib" ]; then \
		echo "$(GREEN)✓$(NC) Gallium library already in place"; \
	else \
		echo "$(YELLOW)⚠$(NC) Gallium library not found - EGL/OpenGL ES may not work"; \
	fi
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Step 5: Verifying installation..."
	@VULKAN_OK=false; \
	EGL_OK=false; \
	GLES_OK=false; \
	echo ""; \
	echo "$(YELLOW)ℹ$(NC) Checking Vulkan driver..."; \
	if [ -f "$(KOSMICKRISP_LIB)/libvulkan_kosmickrisp.dylib" ]; then \
		echo "$(GREEN)✓$(NC) Vulkan driver library found: libvulkan_kosmickrisp.dylib"; \
		VULKAN_OK=true; \
	else \
		echo "$(RED)✗$(NC) Vulkan driver library NOT found: libvulkan_kosmickrisp.dylib"; \
	fi; \
	if [ -f "$(KOSMICKRISP_ICD)" ] || [ -f "$(KOSMICKRISP_PREFIX_FULL)/share/vulkan/icd.d/kosmickrisp_icd.json" ]; then \
		echo "$(GREEN)✓$(NC) Vulkan ICD file found"; \
		VULKAN_OK=true; \
	else \
		echo "$(RED)✗$(NC) Vulkan ICD file NOT found"; \
	fi; \
	echo ""; \
	echo "$(YELLOW)ℹ$(NC) Checking EGL library..."; \
	if [ -f "$(KOSMICKRISP_LIB)/libEGL.dylib" ]; then \
		echo "$(GREEN)✓$(NC) EGL library found: libEGL.dylib"; \
		EGL_OK=true; \
	else \
		echo "$(RED)✗$(NC) EGL library NOT found: libEGL.dylib"; \
	fi; \
	if PKG_CONFIG_PATH=$(KOSMICKRISP_PKGCONFIG):$$PKG_CONFIG_PATH pkg-config --exists egl 2>/dev/null; then \
		EGL_VERSION=$$(PKG_CONFIG_PATH=$(KOSMICKRISP_PKGCONFIG):$$PKG_CONFIG_PATH pkg-config --modversion egl 2>/dev/null || echo "unknown"); \
		echo "$(GREEN)✓$(NC) EGL pkg-config found (version: $$EGL_VERSION)"; \
		EGL_OK=true; \
	else \
		echo "$(YELLOW)⚠$(NC) EGL pkg-config not found (may need PKG_CONFIG_PATH set)"; \
	fi; \
	echo ""; \
	echo "$(YELLOW)ℹ$(NC) Checking Gallium driver library..."; \
	if [ -f "$(KOSMICKRISP_LIB)/libgallium-26.0.0-devel.dylib" ]; then \
		echo "$(GREEN)✓$(NC) Gallium driver library found: libgallium-26.0.0-devel.dylib"; \
		EGL_OK=true; \
		GLES_OK=true; \
	elif [ -f "$(KOSMICKRISP_DRI)/libgallium-26.0.0-devel.dylib" ]; then \
		echo "$(YELLOW)⚠$(NC) Gallium library found in DRI directory but not in lib directory"; \
		echo "$(YELLOW)ℹ$(NC) This may cause EGL/OpenGL ES to fail - library should be in $(KOSMICKRISP_LIB)/"; \
	else \
		echo "$(RED)✗$(NC) Gallium driver library NOT found: libgallium-26.0.0-devel.dylib"; \
		echo "$(YELLOW)ℹ$(NC) EGL/OpenGL ES will not work without this library"; \
	fi; \
	echo ""; \
	echo "$(YELLOW)ℹ$(NC) Checking OpenGL ES libraries..."; \
	if [ -f "$(KOSMICKRISP_LIB)/libGLESv2.dylib" ]; then \
		echo "$(GREEN)✓$(NC) OpenGL ES 2.0 library found: libGLESv2.dylib"; \
		GLES_OK=true; \
	else \
		echo "$(RED)✗$(NC) OpenGL ES 2.0 library NOT found: libGLESv2.dylib"; \
	fi; \
	if [ -f "$(KOSMICKRISP_LIB)/libGLESv1_CM.dylib" ]; then \
		echo "$(GREEN)✓$(NC) OpenGL ES 1.0 library found: libGLESv1_CM.dylib"; \
		GLES_OK=true; \
	else \
		echo "$(YELLOW)⚠$(NC) OpenGL ES 1.0 library not found (optional)"; \
	fi; \
	echo ""; \
	if [ "$$VULKAN_OK" = false ]; then \
		echo "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo "$(RED)✗$(NC) VERIFICATION FAILED: Vulkan driver not found"; \
		echo "$(YELLOW)ℹ$(NC) Check kosmickrisp-install.log for installation errors"; \
		exit 1; \
	fi; \
	if [ "$$EGL_OK" = false ]; then \
		echo "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo "$(RED)✗$(NC) VERIFICATION FAILED: EGL library not found"; \
		echo "$(YELLOW)ℹ$(NC) EGL may not have been built - check kosmickrisp-build.log"; \
		echo "$(YELLOW)ℹ$(NC) Ensure -Degl=enabled and -Dgallium-drivers=zink are set"; \
		exit 1; \
	fi; \
	if [ "$$GLES_OK" = false ]; then \
		echo "$(YELLOW)⚠$(NC) WARNING: OpenGL ES libraries not found (may be optional)"; \
	fi; \
	echo ""; \
	echo "$(YELLOW)ℹ$(NC) Step 6: Testing EGL functionality..."; \
	HAS_COMPREHENSIVE=false; \
	if [ -f "test-egl-comprehensive.c" ]; then \
		echo "$(YELLOW)ℹ$(NC) Building comprehensive EGL test tool..."; \
		PKG_CONFIG_PATH=$(KOSMICKRISP_PKGCONFIG):$$PKG_CONFIG_PATH \
		clang -o test-egl-comprehensive test-egl-comprehensive.c \
			-I$(KOSMICKRISP_INCLUDE) \
			-L$(KOSMICKRISP_LIB) \
			-lEGL -lGLESv2 \
			-framework Foundation -framework Metal -framework MetalKit \
			-std=c11 -Wall -Wextra -Werror 2>&1 | grep -E "(error|warning|test-egl)" || true; \
		if [ -f "test-egl-comprehensive" ]; then \
			HAS_COMPREHENSIVE=true; \
		fi; \
	fi; \
	if [ "$$HAS_COMPREHENSIVE" = true ]; then \
		echo "$(GREEN)✓$(NC) Comprehensive EGL test tool ready"; \
		echo "$(YELLOW)ℹ$(NC) Running comprehensive EGL test..."; \
		echo "$(YELLOW)  $(NC) Using macOS platform backend (EGL_PLATFORM=macos) for standalone test"; \
		DYLD_LIBRARY_PATH=$(KOSMICKRISP_LIB):/opt/homebrew/lib:$$DYLD_LIBRARY_PATH \
		LIBGL_DRIVERS_PATH=$(KOSMICKRISP_DRI) \
		MESA_LOADER_DRIVER_OVERRIDE=zink \
		VK_ICD_FILENAMES=$(KOSMICKRISP_ICD) \
		EGL_PLATFORM=macos \
		./test-egl-comprehensive 2>&1 | tee /tmp/egl-test.log; \
		EGL_TEST_EXIT=$${PIPESTATUS[0]}; \
		if [ $$EGL_TEST_EXIT -eq 0 ]; then \
			echo "$(GREEN)✓$(NC) Comprehensive EGL test passed!"; \
		else \
			echo "$(RED)✗$(NC) Comprehensive EGL test failed (exit code $$EGL_TEST_EXIT)"; \
			echo "$(YELLOW)ℹ$(NC) Check /tmp/egl-test.log for details"; \
			cat /tmp/egl-test.log | tail -30; \
		fi; \
		rm -f test-egl-comprehensive; \
	elif [ -f "test-egl-simple.c" ]; then \
		echo "$(YELLOW)ℹ$(NC) Building simple EGL test tool..."; \
		PKG_CONFIG_PATH=$(KOSMICKRISP_PKGCONFIG):$$PKG_CONFIG_PATH \
		gcc -o test-egl test-egl-simple.c \
			-I$(KOSMICKRISP_INCLUDE) \
			-L$(KOSMICKRISP_LIB) \
			-lEGL -lGLESv2 \
			2>&1 | grep -E "(error|warning|test-egl)" || true; \
		if [ -f "test-egl" ]; then \
			echo "$(GREEN)✓$(NC) EGL test tool ready"; \
			echo "$(YELLOW)ℹ$(NC) Running EGL functional test..."; \
			DYLD_LIBRARY_PATH=$(KOSMICKRISP_LIB):/opt/homebrew/lib:$$DYLD_LIBRARY_PATH \
			LIBGL_DRIVERS_PATH=$(KOSMICKRISP_DRI) \
			MESA_LOADER_DRIVER_OVERRIDE=zink \
			VK_ICD_FILENAMES=$(KOSMICKRISP_ICD) \
			EGL_PLATFORM=macos \
			./test-egl 2>&1 | tee /tmp/egl-test.log; \
			EGL_TEST_EXIT=$${PIPESTATUS[0]}; \
			if [ $$EGL_TEST_EXIT -eq 0 ]; then \
				echo "$(GREEN)✓$(NC) EGL functional test passed!"; \
			else \
				echo "$(RED)✗$(NC) EGL functional test failed (exit code $$EGL_TEST_EXIT)"; \
				echo "$(YELLOW)ℹ$(NC) Check /tmp/egl-test.log for details"; \
				echo "$(YELLOW)ℹ$(NC) Note: Driver loading may require additional configuration"; \
			fi; \
			rm -f test-egl; \
		fi; \
	else \
		echo "$(YELLOW)⚠$(NC) No EGL test files found (test-egl-comprehensive.c or test-egl-simple.c)"; \
	fi; \
	echo ""; \
	echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$(GREEN)✓$(NC) KosmicKrisp installation verified successfully!"; \
	echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$(YELLOW)ℹ$(NC) Installed components:"; \
	echo "   • Vulkan driver (KosmicKrisp)"; \
	echo "   • EGL library (with Zink - OpenGL ES → Vulkan)"; \
	echo "   • OpenGL ES libraries (GLESv1, GLESv2)"; \
	echo ""; \
	echo "$(YELLOW)ℹ$(NC) You can now use:"; \
	echo "   • Vulkan with waypipe dmabuf and video features"; \
	echo "   • EGL/OpenGL ES clients (weston-simple-egl, etc.)"

# Clean KosmicKrisp build (separate target for manual cleaning)
clean-kosmickrisp:
	@echo "$(YELLOW)ℹ$(NC) Cleaning KosmicKrisp build..."
	@if [ -d "kosmickrisp/build" ]; then \
		cd kosmickrisp && rm -rf build 2>/dev/null || true; \
		echo "$(GREEN)✓$(NC) Cleaned KosmicKrisp build directory"; \
	fi
	@rm -f kosmickrisp-build.log kosmickrisp-install.log kosmickrisp-clone.log

# Test: clean and uninstall wayland, rebuild and reinstall wayland, clean and build compositor and client, then run compositor
test:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Test: Full Clean, Rebuild, and Run"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Step 1: Clean and Uninstall Wayland"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@$(MAKE) clean-wayland
	@$(MAKE) uninstall || echo "$(YELLOW)⚠$(NC) Wayland not installed or already removed"
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Step 2: Build and Install Wayland"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@$(MAKE) wayland
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Step 3: Clean and Build Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@$(MAKE) clean-compositor
	@$(MAKE) build-compositor
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Step 4: Clean and Build Client"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@$(MAKE) clean-client
	@$(MAKE) build-client
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Step 5: Running Compositor"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -f "$(COMPOSITOR_BIN)" ]; then \
		echo "$(RED)✗$(NC) Compositor not built"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓$(NC) Starting compositor..."
	@echo "$(YELLOW)ℹ$(NC) Press Ctrl+C to stop"
	@echo "$(YELLOW)ℹ$(NC) Runtime log: /tmp/compositor-run.log"
	@echo ""
	@rm -f /tmp/compositor-run.log
	@$(COMPOSITOR_BIN) 2>&1 | grep -v "failed to read client connection (pid 0)" | tee /tmp/compositor-run.log

# Uninstall Wayland
uninstall:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Uninstalling Wayland"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ -z "$(WAYLAND_PREFIX)" ]; then \
		echo "$(YELLOW)⚠$(NC) Wayland install location not detected"; \
		echo "   Trying common locations..."; \
		for prefix in /opt/homebrew /usr/local; do \
			if [ -f "$$prefix/lib/libwayland-server.dylib" ] || [ -f "$$prefix/lib/libwayland-server.a" ]; then \
				WAYLAND_PREFIX=$$prefix; \
				break; \
			fi; \
		done; \
	fi; \
	if [ -z "$$WAYLAND_PREFIX" ]; then \
		echo "$(RED)✗$(NC) Wayland not found in standard locations"; \
		echo "   If installed elsewhere, uninstall manually"; \
		exit 1; \
	fi; \
	echo "$(YELLOW)ℹ$(NC) Uninstalling from: $$WAYLAND_PREFIX"; \
	echo ""; \
	if [ -d "$$WAYLAND_PREFIX/lib/pkgconfig" ]; then \
		rm -f $$WAYLAND_PREFIX/lib/pkgconfig/wayland-server.pc; \
		rm -f $$WAYLAND_PREFIX/lib/pkgconfig/wayland-client.pc; \
		rm -f $$WAYLAND_PREFIX/lib/pkgconfig/wayland-scanner.pc; \
		echo "$(GREEN)✓$(NC) Removed pkg-config files"; \
	fi; \
	if [ -d "$$WAYLAND_PREFIX/lib" ]; then \
		rm -f $$WAYLAND_PREFIX/lib/libwayland-server.*; \
		rm -f $$WAYLAND_PREFIX/lib/libwayland-client.*; \
		rm -f $$WAYLAND_PREFIX/lib/libwayland-cursor.*; \
		echo "$(GREEN)✓$(NC) Removed libraries"; \
	fi; \
	if [ -d "$$WAYLAND_PREFIX/include/wayland" ]; then \
		rm -rf $$WAYLAND_PREFIX/include/wayland; \
		echo "$(GREEN)✓$(NC) Removed headers"; \
	fi; \
	if [ -d "$$WAYLAND_PREFIX/bin" ]; then \
		rm -f $$WAYLAND_PREFIX/bin/wayland-scanner; \
		echo "$(GREEN)✓$(NC) Removed wayland-scanner"; \
	fi; \
	if [ -d "$$WAYLAND_PREFIX/share/wayland" ]; then \
		rm -rf $$WAYLAND_PREFIX/share/wayland; \
		echo "$(GREEN)✓$(NC) Removed share files"; \
	fi; \
	echo ""; \
	echo "$(GREEN)✓$(NC) Wayland uninstalled from $$WAYLAND_PREFIX"

# Open/view logs
logs:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)📋 Log Files$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(GREEN)Build logs (in project directory):$(NC)"
	@for log in wayland-install.log compositor-build.log client-build.log; do \
		if [ -f "$$log" ]; then \
			echo "  $(GREEN)✓$(NC) $$log ($(shell wc -l < $$log | tr -d ' ') lines)"; \
		else \
			echo "  $(YELLOW)⚠$(NC) $$log (not found)"; \
		fi; \
	done
	@echo ""
	@echo "$(GREEN)Runtime logs (in /tmp):$(NC)"
	@for log in /tmp/compositor-run.log /tmp/client-run.log /tmp/input-client-run.log; do \
		if [ -f "$$log" ]; then \
			echo "  $(GREEN)✓$(NC) $$log ($(shell wc -l < $$log | tr -d ' ') lines)"; \
		else \
			echo "  $(YELLOW)⚠$(NC) $$log (not found)"; \
		fi; \
	done
	@echo ""
	@echo "$(BLUE)Opening logs in TextEdit...$(NC)"
	@for log in wayland-install.log compositor-build.log client-build.log; do \
		if [ -f "$$log" ]; then \
			open -a TextEdit "$$log" 2>/dev/null || true; \
		fi; \
	done
	@for log in /tmp/compositor-run.log /tmp/client-run.log /tmp/input-client-run.log; do \
		if [ -f "$$log" ]; then \
			open -a TextEdit "$$log" 2>/dev/null || true; \
		fi; \
	done

# Test clients (clean, build, and run)
test-clients: build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🧹 Cleaning Test Clients${NC}"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ -d "test-clients" ]; then \
		rm -rf test-clients; \
		echo "$(GREEN)✓$(NC) Removed test-clients directory"; \
	fi
	@if [ -d "weston/build" ]; then \
		rm -rf weston/build; \
		echo "$(GREEN)✓$(NC) Removed weston build directory"; \
	fi
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🔨 Building All Wayland Test Clients${NC}"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/test-clients/build-all.sh
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🧪 Running Wayland Test Clients${NC}"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/test-clients/run-tests.sh
	@echo "$(GREEN)✓$(NC) Test clients completed"

# Individual test client targets (run interactively until SIGTERM)
# Usage: make test-weston-simple-egl (then press Ctrl+C to exit)

test-wayland-info: build-compositor
	@bash scripts/test-clients/run-single-test.sh wayland-info

test-wayland-debug: build-compositor
	@bash scripts/test-clients/run-single-test.sh wayland-debug

test-simple-shm: build-compositor
	@bash scripts/test-clients/run-single-test.sh simple-shm

test-simple-damage: build-compositor
	@bash scripts/test-clients/run-single-test.sh simple-damage

test-weston-simple-shm: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-simple-shm

test-weston-simple-egl: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-simple-egl

test-weston-transformed: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-transformed

test-weston-subsurfaces: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-subsurfaces

test-weston-simple-damage: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-simple-damage

test-weston-simple-touch: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-simple-touch

test-weston-eventdemo: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-eventdemo

test-weston-keyboard: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-keyboard

test-weston-dnd: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-dnd

test-weston-cliptest: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-cliptest

test-weston-image: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-image

test-weston-editor: build-compositor
	@bash scripts/test-clients/run-single-test.sh weston-editor

# Debug targets (include from Makefile.debug)
include Makefile.debug

# Test compositors
test-compositors: build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🧪 Testing Nested Compositors$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/test-compositors.sh
	@echo "$(GREEN)✓$(NC) Logs opened"

# iOS Compositor Build Targets

# Clean iOS compositor build
clean-ios-compositor:
	@echo "$(YELLOW)ℹ$(NC) Cleaning iOS compositor build..."
	@if [ -d "$(IOS_BUILD_DIR)" ]; then \
		rm -rf $(IOS_BUILD_DIR); \
		echo "$(GREEN)✓$(NC) iOS compositor cleaned"; \
	fi

# Build iOS dependencies: Wayland
ios-wayland:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Wayland for iOS"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@./install-epoll-shim-ios.sh
	@./install-libffi-ios.sh
	@./install-pixman-ios.sh
	@./install-wayland-ios.sh

# Build iOS dependencies: Waypipe
ios-waypipe: ios-wayland ios-kosmickrisp
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Waypipe for iOS"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@./install-lz4-ios.sh
	@./install-zstd-ios.sh
	@./install-waypipe-ios.sh

# Build iOS dependencies: KosmicKrisp
ios-kosmickrisp: ios-wayland
	@if [ -f "$(IOS_INSTALL_DIR)/lib/libvulkan_kosmickrisp.dylib" ]; then \
		echo "$(GREEN)✓$(NC) KosmicKrisp already built for iOS"; \
	else \
		echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo "$(BLUE)▶$(NC) Building KosmicKrisp for iOS"; \
		echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		./install-kosmickrisp-ios.sh; \
	fi

# Alias for backward compatibility - kosmickrisp now builds for both platforms
kosmickrisp-ios: ios-kosmickrisp

# Build iOS compositor
ios-build-compositor: ios-wayland ios-waypipe ios-kosmickrisp
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Wawona for iOS Simulator"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ -z "$(IOS_SDK)" ] || [ ! -d "$(IOS_SDK)" ]; then \
		echo "$(RED)✗$(NC) iOS Simulator SDK not found"; \
		echo "   Install Xcode and command-line tools"; \
		echo "   Run: xcode-select --install"; \
		exit 1; \
	fi; \
	if ! command -v xcrun >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) xcrun not found"; \
		echo "   Install Xcode command-line tools"; \
		echo "   Run: xcode-select --install"; \
		exit 1; \
	fi; \
	if ! xcrun simctl list devices >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) simctl not available"; \
		echo "   Install Xcode and command-line tools"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Using iOS SDK: $(IOS_SDK)"
	@echo "$(YELLOW)ℹ$(NC) Checking dependencies..."
	@MISSING_DEPS=0; \
	if ! command -v cmake >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) cmake not found"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) cmake: $$(cmake --version | head -n1)"; \
	fi; \
	if ! command -v pkg-config >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) pkg-config not found"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) pkg-config: $$(pkg-config --version)"; \
	fi; \
	if [ ! -d "$(IOS_INSTALL_DIR)" ] || [ ! -f "$(IOS_INSTALL_DIR)/lib/libwayland-server.dylib" ]; then \
		echo "$(RED)✗$(NC) Wayland not built for iOS"; \
		echo "   Run: $(YELLOW)make ios-wayland$(NC)"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) Wayland for iOS found"; \
	fi; \
	if [ ! -f "$(IOS_INSTALL_DIR)/lib/libpixman-1.a" ] && [ ! -f "$(IOS_INSTALL_DIR)/lib/libpixman-1.dylib" ]; then \
		echo "$(RED)✗$(NC) pixman not built for iOS"; \
		echo "   Run: $(YELLOW)make ios-wayland$(NC)"; \
		MISSING_DEPS=1; \
	else \
		echo "$(GREEN)✓$(NC) pixman for iOS found"; \
	fi; \
	if [ $$MISSING_DEPS -eq 1 ]; then \
		echo "$(RED)✗$(NC) Missing required dependencies"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Configuring CMake for iOS"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@mkdir -p $(IOS_BUILD_DIR)
	@cd $(IOS_BUILD_DIR) && \
		CMAKE_OSX_SYSROOT=$(IOS_SDK) \
		CMAKE_OSX_ARCHITECTURES=arm64 \
		CMAKE_SYSTEM_NAME=iOS \
		CMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
		cmake -DCMAKE_TOOLCHAIN_FILE="" \
			-DCMAKE_SYSTEM_NAME=iOS \
			-DCMAKE_OSX_SYSROOT=$(IOS_SDK) \
			-DCMAKE_OSX_ARCHITECTURES=arm64 \
			-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
			.. || (echo "$(RED)✗$(NC) CMake configuration failed"; exit 1)
	@echo "$(GREEN)✓$(NC) CMake configuration complete"
	@echo ""
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building Wawona for iOS"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@cd $(IOS_BUILD_DIR) && \
		if [ -f "build.ninja" ]; then \
			if command -v ninja >/dev/null 2>&1; then \
				echo "$(YELLOW)ℹ$(NC) Using Ninja build system"; \
				ninja || (echo "$(RED)✗$(NC) Build failed" && exit 1); \
			else \
				echo "$(RED)✗$(NC) Ninja build files found but ninja command not available"; \
				exit 1; \
			fi; \
		elif [ -f "Makefile" ]; then \
			echo "$(YELLOW)ℹ$(NC) Using Make build system"; \
			make || (echo "$(RED)✗$(NC) Build failed" && exit 1); \
		else \
			echo "$(RED)✗$(NC) No build files found"; \
			exit 1; \
		fi
	@if [ ! -f "$(IOS_COMPOSITOR_BIN)" ]; then \
		echo "$(RED)✗$(NC) Binary not found: $(IOS_COMPOSITOR_BIN)"; \
		exit 1; \
	fi
	@BINARY_SIZE=$$(du -h $(IOS_COMPOSITOR_BIN) | cut -f1); \
	echo "$(GREEN)✓$(NC) Build complete"; \
	echo "$(GREEN)✓$(NC) Binary created: $(IOS_COMPOSITOR_BIN) ($$BINARY_SIZE)"

# Create iOS app bundle
ios-install-compositor: ios-build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Creating iOS App Bundle"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@APP_BUNDLE="$(IOS_BUILD_DIR)/Wawona.app"; \
	mkdir -p "$$APP_BUNDLE"; \
	cp "$(IOS_COMPOSITOR_BIN)" "$$APP_BUNDLE/Wawona"; \
	if [ -f "$(IOS_BUILD_DIR)/Info.plist" ]; then \
		cp "$(IOS_BUILD_DIR)/Info.plist" "$$APP_BUNDLE/Info.plist"; \
	else \
		echo "$(YELLOW)⚠$(NC) Info.plist not found, creating minimal one"; \
		echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>Wawona</string><key>CFBundleIdentifier</key><string>$(IOS_BUNDLE_ID)</string><key>CFBundleName</key><string>Wawona</string><key>CFBundlePackageType</key><string>APPL</string><key>MinimumOSVersion</key><string>15.0</string></dict></plist>" > "$$APP_BUNDLE/Info.plist"; \
	fi; \
	echo "APPL????" > "$$APP_BUNDLE/PkgInfo"; \
	if [ -d "Settings.bundle" ]; then \
		echo "$(YELLOW)ℹ$(NC) Copying Settings.bundle to app..."; \
		cp -R "Settings.bundle" "$$APP_BUNDLE/Settings.bundle"; \
		echo "$(GREEN)✓$(NC) Settings.bundle installed"; \
	fi; \
	echo "$(GREEN)✓$(NC) App bundle created: $$APP_BUNDLE"; \
	echo "$(YELLOW)ℹ$(NC) Signing app bundle for Simulator..."; \
	codesign --force --deep --sign - "$$APP_BUNDLE" >/dev/null 2>&1 && \
		echo "$(GREEN)✓$(NC) App bundle signed" || \
		echo "$(YELLOW)⚠$(NC) Code signing failed (may need manual signing)"

# Run iOS compositor in Simulator
ios-run-compositor: ios-install-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Running Wawona in iOS Simulator with Debug Logging"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@APP_BUNDLE="$(IOS_BUILD_DIR)/Wawona.app"; \
	if [ ! -d "$$APP_BUNDLE" ]; then \
		echo "$(RED)✗$(NC) App bundle not found: $$APP_BUNDLE"; \
		echo "$(YELLOW)ℹ$(NC) Run: make ios-build-compositor"; \
		exit 1; \
	fi; \
	if ! command -v xcrun >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) xcrun not found"; \
		echo "   Install Xcode command-line tools"; \
		echo "   Run: xcode-select --install"; \
		exit 1; \
	fi; \
	if [ -z "$(IOS_SDK)" ] || [ ! -d "$(IOS_SDK)" ]; then \
		echo "$(RED)✗$(NC) iOS Simulator SDK not found"; \
		echo "   Install Xcode and command-line tools"; \
		echo "   Run: xcode-select --install"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✓$(NC) iOS SDK found: $(IOS_SDK)"; \
	if ! xcrun simctl list devices >/dev/null 2>&1; then \
		echo "$(RED)✗$(NC) simctl not available"; \
		echo "   Install Xcode and command-line tools"; \
		echo "   Run: xcode-select --install"; \
		exit 1; \
	fi; \
	echo "$(YELLOW)ℹ$(NC) Opening iOS Simulator..."; \
	open -a Simulator; \
	sleep 3; \
	DEVICE_ID=""; \
	if [ -n "$(IOS_DEVICE_ID)" ]; then \
		DEVICE_ID="$(IOS_DEVICE_ID)"; \
		echo "$(YELLOW)ℹ$(NC) Using device ID: $$DEVICE_ID"; \
	else \
		echo "$(YELLOW)ℹ$(NC) Finding 'DebugPhone' iOS Simulator device..."; \
		DEVICE_ID=$$(xcrun simctl list devices available | grep "DebugPhone" | grep -oE '[0-9A-F-]{36}' || echo ""); \
		if [ -z "$$DEVICE_ID" ]; then \
			echo "$(RED)✗$(NC) 'DebugPhone' iOS Simulator device not found"; \
			echo "   Create a device named 'DebugPhone' in Xcode: Window > Devices and Simulators"; \
			exit 1; \
		fi; \
		echo "$(YELLOW)ℹ$(NC) Found device: $$DEVICE_ID"; \
	fi; \
	DEVICE_STATE=$$(xcrun simctl list devices | grep "$$DEVICE_ID" | grep -oE '\(Booted\)|\(Shutdown\)|\(Creating\)' | tr -d '()' || echo "Shutdown"); \
	if [ "$$DEVICE_STATE" != "Booted" ]; then \
		echo "$(YELLOW)ℹ$(NC) Device state: $$DEVICE_STATE"; \
		echo "$(YELLOW)ℹ$(NC) Booting device $$DEVICE_ID..."; \
		xcrun simctl boot $$DEVICE_ID 2>&1 || true; \
		echo "$(YELLOW)ℹ$(NC) Waiting for device to boot (max 30s)..."; \
		TIMEOUT=30; \
		ELAPSED=0; \
		while [ $$ELAPSED -lt $$TIMEOUT ]; do \
			CURRENT_STATE=$$(xcrun simctl list devices | grep "$$DEVICE_ID" | grep -oE '\(Booted\)|\(Shutdown\)|\(Creating\)' | tr -d '()' || echo "Shutdown"); \
			if [ "$$CURRENT_STATE" = "Booted" ]; then \
				break; \
			fi; \
			sleep 1; \
			ELAPSED=$$((ELAPSED + 1)); \
		done; \
		FINAL_STATE=$$(xcrun simctl list devices | grep "$$DEVICE_ID" | grep -oE '\(Booted\)|\(Shutdown\)|\(Creating\)' | tr -d '()' || echo "Shutdown"); \
		if [ "$$FINAL_STATE" != "Booted" ]; then \
			echo "$(RED)✗$(NC) Device failed to boot (state: $$FINAL_STATE)"; \
			exit 1; \
		fi; \
		sleep 2; \
		echo "$(GREEN)✓$(NC) Device booted"; \
	else \
		echo "$(GREEN)✓$(NC) Device already booted"; \
	fi; \
	echo "$(YELLOW)ℹ$(NC) Uninstalling previous version (if exists)..."; \
	xcrun simctl uninstall $$DEVICE_ID $(IOS_BUNDLE_ID) 2>/dev/null || true; \
	echo "$(YELLOW)ℹ$(NC) Installing app to Simulator..."; \
	xcrun simctl install $$DEVICE_ID "$$APP_BUNDLE" || { \
		echo "$(RED)✗$(NC) Installation failed"; \
		echo "   Device state: $$(xcrun simctl list devices | grep "$$DEVICE_ID")"; \
		exit 1; \
	}; \
	echo "$(GREEN)✓$(NC) App installed"; \
	echo ""; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$(BLUE)▶$(NC) Launching app with iOS Simulator logging attached"; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$(YELLOW)ℹ$(NC) Logs will stream below. Press Ctrl+C to stop."; \
	echo ""; \
	xcrun simctl launch --console-pty $$DEVICE_ID $(IOS_BUNDLE_ID) 2>&1 | cat || { \
		echo ""; \
		echo "$(RED)✗$(NC) Launch failed"; \
		echo "$(YELLOW)ℹ$(NC) Check device state: $$(xcrun simctl list devices | grep "$$DEVICE_ID")"; \
		echo "$(YELLOW)ℹ$(NC) Check app logs: xcrun simctl spawn $$DEVICE_ID log stream --predicate 'processImagePath contains \"Wawona\"'"; \
		exit 1; \
	}; \
	echo ""; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "$(GREEN)✓$(NC) iOS Compositor running in Simulator with debug logging"; \
	echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"

# Full iOS compositor target: clean, build dependencies, build compositor, install, and run
# Automatically builds, installs, opens Simulator, and runs with debug logging
# Note: ios-run-compositor will block and stream logs until the app exits or Ctrl+C is pressed
ios-compositor: ios-run-compositor
