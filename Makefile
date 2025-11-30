# Wawona Compositor Makefile
# Simplified targets for common operations

.PHONY: help compositor stop-compositor clean-compositor \
        deps-macos ios-compositor ios-compositor-fast clean-ios-compositor \
        clean macos-compositor

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
ROOT_DIR := $(shell pwd)

# Binaries
COMPOSITOR_BIN := $(BUILD_DIR)/Wawona
IOS_COMPOSITOR_BIN := $(BUILD_DIR)/build-ios/Wawona.app/Wawona

help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🔨 Wawona Compositor Makefile$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make macos-compositor$(NC)  - Build and run Wawona for macOS (includes deps)"
	@echo "  $(YELLOW)make ios-compositor$(NC)    - Build and run Wawona for iOS Simulator (includes deps)"
	@echo "  $(YELLOW)make ios-compositor-fast$(NC) - Rebuild iOS compositor only (skips deps if already built)"
	@echo "  $(YELLOW)make clean$(NC)             - Clean all build artifacts"
	@echo ""

# --- Shared Dependency Logic ---

# Build all dependencies for a specific platform
# Usage: make build-deps PLATFORM=macos
build-deps:
	@echo "$(BLUE)▶$(NC) Building dependencies for $(PLATFORM)"
	@./scripts/install-epoll-shim.sh --platform $(PLATFORM)
	@./scripts/install-libffi.sh --platform $(PLATFORM)
	@./scripts/install-expat.sh --platform $(PLATFORM)
	@./scripts/install-libxml2.sh --platform $(PLATFORM)
	@./scripts/install-wayland.sh --platform $(PLATFORM)
	@./scripts/install-wayland-protocols.sh --platform $(PLATFORM)
	@./scripts/install-pixman.sh --platform $(PLATFORM)
	@./scripts/install-xkbcommon.sh --platform $(PLATFORM)
	@# Build KosmicKrisp (Vulkan)
	@./scripts/install-kosmickrisp.sh --platform $(PLATFORM)
	@# Build Waypipe
	@./scripts/install-ffmpeg.sh --platform $(PLATFORM)
	@./scripts/install-lz4.sh --platform $(PLATFORM)
	@./scripts/install-zstd.sh --platform $(PLATFORM)
	@./scripts/install-waypipe.sh --platform $(PLATFORM)
	@echo "$(GREEN)✓$(NC) $(PLATFORM) dependencies built"

# --- macOS Targets ---

# Build and run macOS compositor (full stack)
macos-compositor:
	@$(MAKE) build-deps PLATFORM=macos
	@echo "$(BLUE)▶$(NC) Building macOS Compositor"
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake .. && make -j$(shell sysctl -n hw.ncpu)
	@echo "$(GREEN)✓$(NC) Build complete"
	@echo "$(BLUE)▶$(NC) Running Compositor"
	@$(COMPOSITOR_BIN) 2>&1 | tee $(BUILD_DIR)/macos-run.log

# Alias for backward compatibility
compositor: macos-compositor

# --- iOS Targets ---

# Check if iOS dependencies are already built
# Returns 0 if deps exist, 1 if they need to be built
check-ios-deps:
	@if [ -d "$(BUILD_DIR)/ios-install/lib" ] && [ -f "$(BUILD_DIR)/ios-install/lib/libwayland-server.a" ] && [ -f "$(BUILD_DIR)/ios-install/lib/libvulkan_kosmickrisp.a" ]; then \
		echo "$(GREEN)✓$(NC) iOS dependencies already built"; \
		exit 0; \
	else \
		echo "$(YELLOW)ℹ$(NC) iOS dependencies not found, will build them"; \
		exit 1; \
	fi

# Build iOS dependencies (if not already built)
build-ios-deps:
	@echo "$(BLUE)▶$(NC) Building iOS Dependencies"
	@# Ensure build tools are available (cmake, pkg-config)
	@./scripts/install-host-cmake.sh
	@./scripts/install-host-pkg-config.sh
	@# Build all dependencies for iOS platform
	@echo "$(BLUE)▶$(NC) Building dependencies for ios"
	@./scripts/install-epoll-shim.sh --platform ios
	@./scripts/install-libffi.sh --platform ios
	@./scripts/install-expat.sh --platform ios
	@./scripts/install-libxml2.sh --platform ios
	@./scripts/install-wayland.sh --platform ios
	@./scripts/install-wayland-protocols.sh --platform ios
	@./scripts/install-pixman.sh --platform ios
	@./scripts/install-xkbcommon.sh --platform ios
	@# Build KosmicKrisp (Vulkan)
	@./scripts/install-kosmickrisp.sh --platform ios
	@# Build Waypipe dependencies
	@./scripts/install-ffmpeg.sh --platform ios
	@./scripts/install-lz4.sh --platform ios
	@./scripts/install-zstd.sh --platform ios
	@./scripts/install-waypipe.sh --platform ios
	@echo "$(GREEN)✓$(NC) ios dependencies built"

# Build and launch iOS compositor (shared logic)
build-launch-ios:
	@# Build Wawona iOS
	@./scripts/generate-cross-ios.sh # Ensure cross file is up to date
	@mkdir -p $(BUILD_DIR)/build-ios
	@cd $(BUILD_DIR)/build-ios && export PATH="$(ROOT_DIR)/build/ios-bootstrap/bin:$$PATH" && cmake -DCMAKE_TOOLCHAIN_FILE=../../dependencies/wayland/toolchain-ios.cmake -DCMAKE_SYSTEM_NAME=iOS -G "Unix Makefiles" ../.. && make -j$(shell sysctl -n hw.ncpu)
	@echo "$(GREEN)✓$(NC) iOS Build Complete"
	@echo "$(BLUE)▶$(NC) Launching in Simulator..."
	@# Simple launch logic - use xcrun simctl
	@DEVICE_ID=$$(xcrun simctl list devices available | grep "Booted" | grep -v "Watch" | head -1 | grep -oE "[0-9A-F-]{36}"); \
	if [ -z "$$DEVICE_ID" ]; then \
		DEVICE_ID=$$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -oE "[0-9A-F-]{36}"); \
		xcrun simctl boot $$DEVICE_ID || true; \
	fi; \
	open -a Simulator; \
	xcrun simctl install $$DEVICE_ID $(BUILD_DIR)/build-ios/Wawona.app; \
	xcrun simctl launch --console-pty $$DEVICE_ID com.aspauldingcode.Wawona 2>&1 | tee $(BUILD_DIR)/ios-run.log

# Build all iOS dependencies and the compositor
ios-compositor:
	@echo "$(BLUE)▶$(NC) Building iOS Compositor and Dependencies"
	@$(MAKE) build-ios-deps || true
	@$(MAKE) build-launch-ios

# Fast rebuild: skip dependencies if already built
ios-compositor-fast:
	@echo "$(BLUE)▶$(NC) Fast rebuild iOS Compositor (skipping deps if already built)"
	@$(MAKE) check-ios-deps || $(MAKE) build-ios-deps
	@$(MAKE) build-launch-ios

# Helper to test connection information
test-ios-connection:
	@./scripts/test-ios-connection.sh

# Run Weston in Colima connected to iOS
ios-colima-client:
	@./scripts/ios-colima-client.sh || true

# Run Weston in Colima connected to macOS compositor
colima-client:
	@./scripts/colima-client.sh || true

# --- Clean ---

clean:
	@echo "$(YELLOW)ℹ$(NC) Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "$(GREEN)✓$(NC) Cleaned"
