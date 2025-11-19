# Wawona Compositor Makefile
# Simplified targets for common operations

.PHONY: help compositor client tartvm-client external-client container-client colima-client clean-remote-socket wayland test uninstall logs clean-compositor clean-client clean-wayland kosmickrisp clone-kosmickrisp build-kosmickrisp install-kosmickrisp clean-kosmickrisp

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

# Binaries
COMPOSITOR_BIN := $(BUILD_DIR)/Wawona
TEST_CLIENT_BIN := macos_wlclient_color_test

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

help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🔨 Wawona Compositor Makefile$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make compositor$(NC)      - Clean, build, and run compositor"
	@echo "  $(YELLOW)make client$(NC)           - Clean, build, and run client"
	@echo "  $(YELLOW)make tartvm-client$(NC)    - Start Fedora VM with shared directory for Wayland"
	@echo "  $(YELLOW)make external-client$(NC) - Connect external client via waypipe (auto-cleans remote socket)"
	@echo "  $(YELLOW)make container-client$(NC) - Run Weston in macOS Containerization.framework container"
	@echo "    $(RED)⚠$(NC)  $(YELLOW)Note:$(NC) Does NOT support Unix domain sockets (connection will fail)"
	@echo "    $(YELLOW)ℹ$(NC)  Use $(GREEN)make colima-client$(NC) for Unix socket support"
	@echo "  $(YELLOW)make colima-client$(NC) - Run Weston in Colima/Docker container (supports Unix sockets)"
	@echo "  $(YELLOW)make clean-remote-socket$(NC) - Clean stale Wayland sockets on remote machine"
	@echo "  $(YELLOW)make external-client EXTERNAL_CLIENT_HOST=host$(NC) - Connect NixOS client via SSH"
	@echo "  $(YELLOW)make test-clients$(NC)    - Test various Wayland clients (foot, GTK, Qt apps)"
	@echo "  $(YELLOW)make test-compositors$(NC) - Test nested compositors (Weston, Sway, GNOME, KDE)"
	@echo "  $(YELLOW)make wayland$(NC)          - Clean, build, and install Wayland"
	@echo "  $(YELLOW)make waypipe$(NC)         - Clean, build, and install Rust waypipe (for Wayland forwarding)"
	@echo "  $(YELLOW)make kosmickrisp$(NC)     - Clone, build, and install KosmicKrisp Vulkan driver for macOS"
	@echo "  $(YELLOW)make test$(NC)            - Clean all, build all, install wayland, run both"
	@echo "  $(YELLOW)make uninstall$(NC)       - Uninstall Wayland"
	@echo "  $(YELLOW)make logs$(NC)            - Open/view all log files"
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
	@echo "$(YELLOW)ℹ$(NC) Press Ctrl+C to stop"
	@echo "$(YELLOW)ℹ$(NC) Runtime log: /tmp/compositor-run.log"
	@echo ""
	@rm -f /tmp/compositor-run.log
	@export WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-0}"; \
	export XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/tmp/wayland-runtime}"; \
	XDG_RUNTIME_DIR=$$(echo "$$XDG_RUNTIME_DIR" | sed "s#//#/#g"); \
	bash -c '\
		mkdir -p "$$XDG_RUNTIME_DIR"; \
		chmod 0700 "$$XDG_RUNTIME_DIR"; \
		rm -f "$$XDG_RUNTIME_DIR/$$WAYLAND_DISPLAY"; \
		$(COMPOSITOR_BIN) 2>&1 | grep -v "failed to read client connection (pid 0)" | tee /tmp/compositor-run.log'

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
	WAYLAND_DISPLAY="$$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$$XDG_RUNTIME_DIR" waypipe ssh $$EXTERNAL_USER@$$EXTERNAL_HOST foot'

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

# Waypipe: clean, build, install (for Wayland forwarding over SSH)
waypipe: clean-waypipe build-waypipe install-waypipe

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

# KosmicKrisp: clone, build, install Vulkan driver for macOS
kosmickrisp: clean-kosmickrisp clone-kosmickrisp build-kosmickrisp install-kosmickrisp

clone-kosmickrisp:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Cloning KosmicKrisp Driver"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ -d "kosmickrisp" ]; then \
		echo "$(GREEN)✓$(NC) KosmicKrisp directory already exists"; \
		echo "$(YELLOW)ℹ$(NC) Updating repository..."; \
		cd kosmickrisp && git pull 2>&1 | grep -E "(Already up to date|Updating|error)" || true; \
	else \
		echo "$(YELLOW)ℹ$(NC) Cloning Mesa repository (KosmicKrisp driver merged in Mesa 26.0)..."; \
		echo "$(YELLOW)ℹ$(NC) KosmicKrisp is a Vulkan-to-Metal driver for macOS (merged October 2025)"; \
		git clone --depth 1 --branch main https://gitlab.freedesktop.org/mesa/mesa.git kosmickrisp 2>&1 | tee kosmickrisp-clone.log || { \
			echo "$(RED)✗$(NC) Failed to clone Mesa repository"; \
			echo "$(YELLOW)ℹ$(NC) Please check KOSMICKRISP.md for alternative repository URLs"; \
			echo "$(YELLOW)ℹ$(NC) You may need to manually clone the repository"; \
			cat kosmickrisp-clone.log 2>/dev/null || true; \
			exit 1; \
		}; \
		echo "$(GREEN)✓$(NC) Cloned Mesa repository"; \
		echo "$(YELLOW)ℹ$(NC) KosmicKrisp driver provides Vulkan 1.3 conformance on Apple hardware"; \
	fi

build-kosmickrisp: clone-kosmickrisp
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Building KosmicKrisp Driver"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -d "kosmickrisp" ]; then \
		echo "$(RED)✗$(NC) KosmicKrisp directory not found"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Checking build dependencies..."
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
	@if [ ! -d "kosmickrisp/build" ]; then \
		echo "$(YELLOW)ℹ$(NC) Configuring Mesa with KosmicKrisp driver (Mesa 26.0+)..."; \
		cd kosmickrisp && \
		LLVM_CONFIG=/opt/homebrew/opt/llvm/bin/llvm-config \
		PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig:$$PKG_CONFIG_PATH \
		meson setup build \
			--prefix=/opt/homebrew \
			-Dplatforms=macos \
			-Dvulkan-drivers=kosmickrisp \
			-Dgallium-drivers= \
			-Dvulkan-layers='[]' \
			-Dtools='[]' \
			2>&1 | tee ../kosmickrisp-build.log || { \
			echo "$(RED)✗$(NC) Meson configuration failed - see kosmickrisp-build.log"; \
			echo "$(YELLOW)ℹ$(NC) Note: KosmicKrisp requires Mesa 26.0+ (merged October 2025)"; \
			exit 1; \
		}; \
		echo "$(GREEN)✓$(NC) Meson configuration complete"; \
	else \
		echo "$(GREEN)✓$(NC) Build directory already exists"; \
	fi
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Building KosmicKrisp driver..."
	@cd kosmickrisp && \
		ninja -C build 2>&1 | tee -a ../kosmickrisp-build.log || { \
			echo "$(RED)✗$(NC) Build failed - see kosmickrisp-build.log"; \
			exit 1; \
		}
	@echo "$(GREEN)✓$(NC) Build complete"

install-kosmickrisp: build-kosmickrisp
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)▶$(NC) Installing KosmicKrisp Driver"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@if [ ! -d "kosmickrisp/build" ]; then \
		echo "$(RED)✗$(NC) Build directory not found - run $(YELLOW)make build-kosmickrisp$(NC) first"; \
		exit 1; \
	fi
	@echo "$(YELLOW)ℹ$(NC) Installing to /opt/homebrew..."
	@cd kosmickrisp && \
		sudo ninja -C build install 2>&1 | tee -a ../kosmickrisp-install.log || { \
			echo "$(RED)✗$(NC) Installation failed - see kosmickrisp-install.log"; \
			echo "$(YELLOW)ℹ$(NC) You may need to run with sudo or adjust permissions"; \
			exit 1; \
		}
	@echo "$(GREEN)✓$(NC) KosmicKrisp driver installed"
	@echo ""
	@echo "$(YELLOW)ℹ$(NC) Verifying installation..."
	@ICD_FOUND=0; \
	if [ -f "/opt/homebrew/share/vulkan/icd.d/kosmickrisp_icd.json" ]; then \
		echo "$(GREEN)✓$(NC) KosmicKrisp Vulkan ICD found: kosmickrisp_icd.json"; \
		ICD_FOUND=1; \
	fi; \
	if [ -f "/opt/homebrew/lib/libvulkan_kosmickrisp.dylib" ] || [ -f "/opt/homebrew/lib/libvulkan_kosmickrisp.so" ]; then \
		echo "$(GREEN)✓$(NC) KosmicKrisp Vulkan driver library found"; \
		ICD_FOUND=1; \
	fi; \
	# Check for panfrost-based driver (if KosmicKrisp uses panfrost backend) \
	if [ -f "/opt/homebrew/share/vulkan/icd.d/panfrost_icd.json" ]; then \
		echo "$(GREEN)✓$(NC) Panfrost Vulkan ICD found (may be KosmicKrisp backend)"; \
		ICD_FOUND=1; \
	fi; \
	if [ $$ICD_FOUND -eq 0 ]; then \
		echo "$(YELLOW)⚠$(NC) Vulkan ICD not found in expected location"; \
		echo "$(YELLOW)ℹ$(NC) Checking /opt/homebrew/share/vulkan/icd.d/..."; \
		ls -la /opt/homebrew/share/vulkan/icd.d/ 2>/dev/null || echo "$(YELLOW)ℹ$(NC) ICD directory does not exist"; \
		echo "$(YELLOW)ℹ$(NC) Check /opt/homebrew/lib/ for driver libraries..."; \
		ls -la /opt/homebrew/lib/libvulkan*.dylib 2>/dev/null | head -5 || true; \
	fi
	@echo ""
	@echo "$(GREEN)✓$(NC) Installation complete!"
	@echo "$(YELLOW)ℹ$(NC) You can now use Vulkan with waypipe dmabuf and video features"

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

# Test clients
test-clients: build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🧪 Testing Wayland Clients$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/test-clients.sh

# Test compositors
test-compositors: build-compositor
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🧪 Testing Nested Compositors$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@bash scripts/test-compositors.sh
	@echo "$(GREEN)✓$(NC) Logs opened"
