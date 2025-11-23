#!/bin/bash
# Colima client script for running Weston in Docker containers
# Uses Colima with VirtioFS for Unix domain socket support
# Runs Weston nested compositor in NixOS container, connected to host compositor

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/colima-client"

# Source common variables
if ! source "$MODULES_DIR/common.sh"; then
    echo "Failed to initialize common settings" >&2
    exit 1
fi

# Source module functions
source "$MODULES_DIR/waypipe-setup.sh"
source "$MODULES_DIR/docker-setup.sh"
source "$MODULES_DIR/container-setup.sh"

# Check compositor socket exists
check_compositor_socket() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} Colima Client Setup"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "${IOS_SIMULATOR_MODE:-0}" = "1" ]; then
        echo -e "${YELLOW}ℹ${NC} Using iOS Simulator Wawona compositor"
        echo -e "${YELLOW}ℹ${NC} Socket path: ${GREEN}$SOCKET_PATH${NC}"
    else
        echo -e "${YELLOW}ℹ${NC} Checking compositor socket: ${GREEN}$SOCKET_PATH${NC}"
    fi
    
    if [ ! -S "$SOCKET_PATH" ] && [ ! -e "$SOCKET_PATH" ]; then
        echo -e "${RED}✗${NC} Compositor socket not found: ${RED}$SOCKET_PATH${NC}"
        echo ""
        if [ "${IOS_SIMULATOR_MODE:-0}" = "1" ]; then
            echo -e "${YELLOW}ℹ${NC} Start iOS compositor first: ${GREEN}make ios-compositor${NC}"
        else
            echo -e "${YELLOW}ℹ${NC} Start the compositor first: ${GREEN}make compositor${NC}"
        fi
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Compositor socket found"
    
    if [ "${IOS_SIMULATOR_MODE:-0}" != "1" ] && [ "$COCOMA_XDG_RUNTIME_DIR" != "$XDG_RUNTIME_DIR" ]; then
        echo -e "${YELLOW}ℹ${NC} Using Colima-compatible path: ${GREEN}$COCOMA_XDG_RUNTIME_DIR${NC}"
    fi
    echo ""
}

# Generate container command for waypipe server + weston
generate_container_waypipe_weston_command() {
    cat << 'CONTAINER_WAYPIPE_WESTON_EOF'
waypipe --socket "\$WAYPIPE_SOCKET" --display "\$WAYPIPE_DISPLAY" server -- sh -c \"
    export XDG_RUNTIME_DIR=/run/user/1000
    export WAYLAND_DISPLAY=\\\"\$WAYPIPE_DISPLAY\\\"
    export PATH=\\\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\$PATH\\\"
    
    # Check if Weston is already installed
    if command -v weston >/dev/null 2>&1; then
        echo "✅ Weston already installed, skipping package installation"
    else
        echo "📦 Installing Weston and dependencies..."
        if command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
            echo "   Using Nix package manager..."
            if [ ! -d "/root/.nix-defexpr/channels" ] || [ ! -L "/root/.nix-defexpr/channels/nixpkgs" ]; then
                echo "   Setting up nixpkgs channel..."
                mkdir -p /root/.nix-defexpr/channels
                nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                nix-channel --update nixpkgs 2>/dev/null || true
            fi
            INSTALL_OUTPUT=\$(nix-env -iA nixpkgs.weston nixpkgs.dbus nixpkgs.xkeyboard_config 2>&1)
            INSTALL_EXIT=\$?
            if [ \$INSTALL_EXIT -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already installed"; then
                echo "✅ Weston installed via nix-env"
            else
                echo "⚠ Direct nix install failed, trying to find weston in nix store..."
                WESTON_BIN=\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                if [ -n "\$WESTON_BIN" ]; then
                    export PATH="\$(dirname \$WESTON_BIN):\$PATH"
                    echo "✅ Weston found in nix store at: \$WESTON_BIN"
                else
                    echo "❌ Failed to install or find Weston"
                    exit 1
                fi
            fi
            if ! command -v weston >/dev/null 2>&1; then
                WESTON_BIN=\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                if [ -n "\$WESTON_BIN" ]; then
                    export PATH="\$(dirname \$WESTON_BIN):\$PATH"
                else
                    echo "❌ Weston not found after installation"
                    exit 1
                fi
            fi
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y weston wayland-protocols-devel dbus-x11 xkeyboard-config 2>/dev/null || \
            dnf install -y weston dbus-x11 xkeyboard-config 2>/dev/null || {
                echo "❌ Failed to install Weston"
                exit 1
            }
        elif command -v apk >/dev/null 2>&1; then
            rm -f /var/cache/apk/*.lock /var/lib/apk/lock.* /var/lib/apk/lock 2>/dev/null || true
            sleep 1
            apk update && apk add --no-cache weston weston-terminal dbus xkeyboard-config || {
                echo "❌ Failed to install Weston"
                exit 1
            }
        else
            echo "❌ Unsupported package manager"
            exit 1
        fi
        echo "✅ Weston installed"
    fi
    echo ""
    echo "🔍 Verifying Wayland socket (waypipe proxy)..."
    sleep 3
    SOCKET_FOUND=false
    ACTUAL_SOCKET=""
    EXPECTED_SOCKET="\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY"
    # First check for the expected socket (waypipe-server)
    if [ -S "\$EXPECTED_SOCKET" ]; then
        SOCKET_FOUND=true
        ACTUAL_SOCKET="\$EXPECTED_SOCKET"
        echo "✅ Waypipe compositor socket found at expected location: \$ACTUAL_SOCKET"
    else
        echo "   Searching for waypipe compositor socket..."
        # Prefer waypipe-* sockets over wayland-* (waypipe server creates waypipe-server)
        for sock in \$(ls -1 "\$XDG_RUNTIME_DIR"/waypipe-* "\$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v waypipe.sock\$); do
            if [ -n "\$sock" ] && [ -S "\$sock" ] 2>/dev/null; then
                SOCKET_NAME=\$(basename "\$sock")
                # Skip wayland-0 if it's not the waypipe server socket (might be from previous run)
                if [ "\$SOCKET_NAME" = "wayland-0" ] && [ -S "\$XDG_RUNTIME_DIR/waypipe-server" ]; then
                    continue
                fi
                SOCKET_FOUND=true
                ACTUAL_SOCKET="\$sock"
                echo "✅ Found waypipe compositor socket: \$ACTUAL_SOCKET"
                export WAYLAND_DISPLAY="\$SOCKET_NAME"
                echo "   Updated WAYLAND_DISPLAY to: \$WAYLAND_DISPLAY"
                break
            fi
        done
        # Fallback: if waypipe-server exists, use it
        if [ "\$SOCKET_FOUND" = false ] && [ -S "\$XDG_RUNTIME_DIR/waypipe-server" ]; then
            SOCKET_FOUND=true
            ACTUAL_SOCKET="\$XDG_RUNTIME_DIR/waypipe-server"
            export WAYLAND_DISPLAY="waypipe-server"
            echo "✅ Found waypipe compositor socket: \$ACTUAL_SOCKET"
            echo "   Updated WAYLAND_DISPLAY to: \$WAYLAND_DISPLAY"
        fi
    fi
    if [ "\$SOCKET_FOUND" = false ]; then
        echo "❌ Waypipe compositor socket not found in \$XDG_RUNTIME_DIR"
        ls -la "\$XDG_RUNTIME_DIR/" 2>/dev/null || echo "   Directory not accessible"
        exit 1
    fi
    echo "   Using socket: \$ACTUAL_SOCKET"
    echo "   WAYLAND_DISPLAY=\$WAYLAND_DISPLAY"
    echo "   Verifying socket is ready..."
    # Wait for waypipe server to fully initialize and bind to socket
    # The socket exists, but waypipe server needs time to start listening
    sleep 4
    # Check if socket exists - waypipe server creates it when ready
    # If the socket exists, waypipe server is running and ready
    if [ ! -S "\$ACTUAL_SOCKET" ]; then
        echo "❌ Socket not found: \$ACTUAL_SOCKET"
        echo "   Directory contents:"
        ls -la "\$XDG_RUNTIME_DIR/" 2>/dev/null || echo "   Directory not accessible"
        exit 1
    fi
    # Socket exists - waypipe server is ready
    # Try optional socat verification (non-blocking)
    if command -v socat >/dev/null 2>&1; then
        if socat -u OPEN:/dev/null UNIX-CONNECT:"\$ACTUAL_SOCKET" </dev/null 2>/dev/null; then
            echo "   Socket verified with socat"
        else
            echo "   Socket exists, socat verification skipped (socket may still be initializing)"
        fi
    else
        echo "   Socket exists, assuming ready (socat not available)"
    fi
    echo "   Socket is ready"
    echo ""
    echo "🚀 Starting Weston compositor (via waypipe proxy)..."
    echo "   Backend: wayland (nested)"
    echo "   Parent socket: \$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY (waypipe proxy)"
    echo ""
    if ! command -v weston >/dev/null 2>&1; then
        WESTON_BIN=\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
        if [ -n "\$WESTON_BIN" ]; then
            export PATH="\$(dirname \$WESTON_BIN):\$PATH"
        else
            echo "❌ Weston binary not found"
            exit 1
        fi
    fi
    export LD_LIBRARY_PATH="/nix/var/nix/profiles/default/lib:/root/.nix-profile/lib:\$LD_LIBRARY_PATH"
    echo "   Starting Weston with wayland backend..."
    if ! command -v weston >/dev/null 2>&1; then
        echo "❌ Weston command not found in PATH"
        exit 1
    fi
    # CRITICAL: Create/fix XDG_RUNTIME_DIR permissions BEFORE anything else
    # Must be 0700 and owned by current user (UID 0 in container)
    if [ -d "\$XDG_RUNTIME_DIR" ]; then
        # Try to fix permissions - if it fails, remove and recreate
        if ! chmod 0700 "\$XDG_RUNTIME_DIR" 2>/dev/null; then
            rm -rf "\$XDG_RUNTIME_DIR"/* 2>/dev/null || true
            rmdir "\$XDG_RUNTIME_DIR" 2>/dev/null || true
        fi
    fi
    # Create directory with correct permissions from the start
    mkdir -p "\$XDG_RUNTIME_DIR" 2>/dev/null || true
    chmod 0700 "\$XDG_RUNTIME_DIR" 2>/dev/null || true
    chown root:root "\$XDG_RUNTIME_DIR" 2>/dev/null || true
    
    # Set up fontconfig to avoid errors
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf
    if [ ! -f "\$FONTCONFIG_FILE" ]; then
        mkdir -p /etc/fonts
        cat > "\$FONTCONFIG_FILE" << '\''FONTCONFIG_EOF'\''
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <dir>/usr/share/fonts</dir>
    <dir>/nix/store/*/share/fonts</dir>
    <cachedir>/tmp/fontconfig-cache</cachedir>
    <include ignore_missing="yes">conf.d</include>
</fontconfig>
FONTCONFIG_EOF
        mkdir -p /tmp/fontconfig-cache
    fi
    
    # Suppress cursor theme warnings (harmless)
    export XCURSOR_THEME=default
    export XCURSOR_PATH=/usr/share/icons:/nix/store/*/share/icons
    
    echo "   Using weston: \$(command -v weston)"
    echo "   WAYLAND_DISPLAY=\$WAYLAND_DISPLAY"
    echo "   XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR"
    echo "   Socket path: \$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY"
    
    # Suppress harmless warnings while keeping important errors visible
    weston --backend=wayland --socket=weston-0 2>&1 | grep -v "could not load cursor" | grep -v "Fontconfig error" | grep -v "XDG_RUNTIME_DIR.*is not configured correctly" || true
" &
WAYPIPE_SERVER_PID=\$!
sleep 2
wait \$WAYPIPE_SERVER_PID || {
    WESTON_EXIT_CODE=\$?
    echo ""
    echo "⚠ Weston exited with code \$WESTON_EXIT_CODE"
    echo "   This may be normal if Weston was stopped or crashed"
    echo "   Check logs above for details"
    exit \$WESTON_EXIT_CODE
}
CONTAINER_WAYPIPE_WESTON_EOF
}

# Run container with waypipe server and weston
run_container_waypipe_weston() {
    local TTY_FLAG=$(get_tty_flag)
    
    docker exec $TTY_FLAG \
        -e "XDG_RUNTIME_DIR=/run/user/1000" \
        -e "HOME=/root" \
        -e "WAYPIPE_TCP_PORT=${WAYPIPE_TCP_PORT:-9999}" \
        "$CONTAINER_NAME" \
        sh -c "
        export XDG_RUNTIME_DIR=/run/user/1000
        export PATH=\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\$PATH\"
        set -e
        if ! command -v waypipe >/dev/null 2>&1; then
            echo \"📦 Installing waypipe...\"
            nix-env -iA nixpkgs.waypipe 2>/dev/null || {
                if [ ! -d \"/root/.nix-defexpr/channels\" ] || [ ! -L \"/root/.nix-defexpr/channels/nixpkgs\" ]; then
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                nix-env -iA nixpkgs.waypipe 2>/dev/null || {
                    echo \"❌ Failed to install waypipe\"
                    exit 1
                }
            }
        fi
        echo \"🚀 Starting waypipe server in container...\"
        WAYPIPE_DISPLAY=\"waypipe-server\"
        # Use TCP connection instead of Unix socket (Docker bind mounts don't support Unix sockets on macOS)
        # Connect to host's socat TCP proxy via host.docker.internal
        WAYPIPE_TCP_PORT=\${WAYPIPE_TCP_PORT:-9999}
        echo \"   Connecting to waypipe client via TCP (host.docker.internal:\$WAYPIPE_TCP_PORT)...\"
        # Install socat if needed (required for TCP proxy)
        if ! command -v socat >/dev/null 2>&1; then
            echo \"   Installing socat for TCP proxy...\"
            if command -v nix-env >/dev/null 2>&1; then
                nix-env -iA nixpkgs.socat 2>/dev/null || {
                    echo \"⚠ Socat install failed, trying alternative...\"
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                    nix-env -iA nixpkgs.socat 2>/dev/null || {
                        echo \"❌ Failed to install socat\"
                        exit 1
                    }
                }
            elif command -v apk >/dev/null 2>&1; then
                apk add --no-cache socat || {
                    echo \"❌ Failed to install socat\"
                    exit 1
                }
            else
                echo \"❌ Socat not available and cannot install\"
                exit 1
            fi
            echo \"✅ Socat installed\"
        fi
        # Use socat to proxy TCP to Unix socket for waypipe server
        # waypipe server expects Unix socket, so we create a local socket and proxy TCP to it
        WAYPIPE_LOCAL_SOCK=\"/tmp/waypipe-container.sock\"
        rm -f \"\$WAYPIPE_LOCAL_SOCK\"
        # Start socat proxy before waypipe server
        # Connect to host's socat TCP proxy and create local Unix socket for waypipe
        socat UNIX-LISTEN:\"\$WAYPIPE_LOCAL_SOCK\",fork,reuseaddr,unlink-early TCP:host.docker.internal:\$WAYPIPE_TCP_PORT >/tmp/socat-container.log 2>&1 &
        SOCAT_CONTAINER_PID=\$!
        # Wait for socat to create the socket and establish TCP connection
        sleep 4
        # Verify socket exists before starting waypipe
        if [ ! -S \"\$WAYPIPE_LOCAL_SOCK\" ]; then
            echo \"❌ Socat failed to create socket: \$WAYPIPE_LOCAL_SOCK\"
            echo \"   Checking TCP connection to host...\"
            nc -zv host.docker.internal \$WAYPIPE_TCP_PORT 2>&1 || echo \"   TCP connection test failed\"
            cat /tmp/socat-container.log 2>/dev/null | tail -20
            exit 1
        fi
        echo \"   Socket proxy ready: \$WAYPIPE_LOCAL_SOCK\"
        # Test TCP connection is working
        if command -v nc >/dev/null 2>&1; then
            if nc -zv host.docker.internal \$WAYPIPE_TCP_PORT 2>&1 | grep -q succeeded; then
                echo \"   TCP connection to host verified\"
            else
                echo \"   ⚠ TCP connection test inconclusive, continuing...\"
            fi
        fi
        # Install Mesa Vulkan drivers for DMA-BUF support (required for video + dmabuf)
        echo \"📦 Installing Mesa Vulkan drivers for DMA-BUF support...\"
        if command -v nix-env >/dev/null 2>&1; then
            # Install Mesa with Vulkan support - need both drivers and loader
            nix-env -iA nixpkgs.mesa.drivers nixpkgs.vulkan-loader nixpkgs.vulkan-tools nixpkgs.mesa 2>/dev/null || {
                echo \"⚠ Mesa Vulkan install failed, trying alternative...\"
                if [ ! -d \"/root/.nix-defexpr/channels\" ] || [ ! -L \"/root/.nix-defexpr/channels/nixpkgs\" ]; then
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                nix-env -iA nixpkgs.mesa.drivers nixpkgs.vulkan-loader nixpkgs.vulkan-tools nixpkgs.mesa 2>/dev/null || {
                    echo \"⚠ Mesa Vulkan drivers not available via nix, waypipe will use GBM fallback\"
                }
            }
            # Ensure Mesa libraries are in library path
            MESA_LIB=\$(find /nix/store -name 'libvulkan.so*' -type f 2>/dev/null | head -1)
            if [ -n \"\$MESA_LIB\" ]; then
                MESA_LIB_DIR=\$(dirname \"\$MESA_LIB\")
                export LD_LIBRARY_PATH=\"\$MESA_LIB_DIR:\$LD_LIBRARY_PATH\"
            fi
        fi
        # Set up Vulkan ICD loader configuration
        # Prefer software renderer (llvmpipe/swrast) for containers without GPU
        # First, find all available Vulkan ICD files
        VULKAN_ICD_DIR=\$(find /nix/store -type d -name 'icd.d' -path '*/vulkan/icd.d' 2>/dev/null | head -1)
        if [ -n \"\$VULKAN_ICD_DIR\" ]; then
            # Build colon-separated list of ICD JSON files (Vulkan loader doesn't expand globs)
            VK_ICD_LIST=\"\"
            for icd in \$VULKAN_ICD_DIR/*.json; do
                if [ -f \"\$icd\" ]; then
                    if [ -z \"\$VK_ICD_LIST\" ]; then
                        VK_ICD_LIST=\"\$icd\"
                    else
                        VK_ICD_LIST=\"\$VK_ICD_LIST:\$icd\"
                    fi
                fi
            done
            if [ -n \"\$VK_ICD_LIST\" ]; then
                export VK_ICD_FILENAMES=\$VK_ICD_LIST
                echo \"✅ Found Vulkan ICD directory: \$VULKAN_ICD_DIR\"
                echo \"   Configured VK_ICD_FILENAMES with \$(echo \$VK_ICD_LIST | tr ':' '\\n' | wc -l) ICD(s)\"
            else
                echo \"⚠ No Vulkan ICD JSON files found in \$VULKAN_ICD_DIR\"
            fi
        else
            echo \"⚠ Vulkan ICD directory not found, waypipe will use GBM fallback\"
        fi
        export VK_LAYER_PATH=/nix/store/*/share/vulkan/explicit_layer.d
        # Ensure Mesa software rendering is enabled
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
        # Ensure Vulkan loader can find Mesa libraries - add all Mesa lib directories
        for mesa_lib_dir in \$(find /nix/store -type d -name 'lib' -path '*/mesa*/lib' 2>/dev/null); do
            export LD_LIBRARY_PATH=\"\$mesa_lib_dir:\$LD_LIBRARY_PATH\"
        done
        # Also find and add Vulkan driver libraries
        MESA_VULKAN_LIB=\$(find /nix/store -name 'libvulkan_intel.so*' -o -name 'libvulkan_radeon.so*' -o -name 'libvulkan_swrast.so*' -o -name 'libvulkan_lvp.so*' 2>/dev/null | head -1)
        if [ -n \"\$MESA_VULKAN_LIB\" ]; then
            MESA_VULKAN_LIB_DIR=\$(dirname \"\$MESA_VULKAN_LIB\")
            export LD_LIBRARY_PATH=\"\$MESA_VULKAN_LIB_DIR:\$LD_LIBRARY_PATH\"
            echo \"✅ Found Mesa Vulkan library directory: \$MESA_VULKAN_LIB_DIR\"
        fi
        waypipe --socket \"\$WAYPIPE_LOCAL_SOCK\" --display \"\$WAYPIPE_DISPLAY\" server -- sh -c \"
        export XDG_RUNTIME_DIR=/run/user/1000
        export WAYLAND_DISPLAY=\\\"\\\$WAYPIPE_DISPLAY\\\"
        export PATH=\\\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\\\$PATH\\\"
        # Pass through Vulkan environment variables
        export VK_ICD_FILENAMES=\\\$VK_ICD_FILENAMES
        export VK_LAYER_PATH=\\\$VK_LAYER_PATH
        # Ensure Mesa software rendering is enabled for Vulkan
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
        
        if command -v weston >/dev/null 2>&1; then
            echo \\\"✅ Weston already installed, skipping package installation\\\"
        else
            echo \\\"📦 Installing Weston and dependencies...\\\"
            if command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
                echo \\\"   Using Nix package manager...\\\"
                if [ ! -d \\\"/root/.nix-defexpr/channels\\\" ] || [ ! -L \\\"/root/.nix-defexpr/channels/nixpkgs\\\" ]; then
                    echo \\\"   Setting up nixpkgs channel...\\\"
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                INSTALL_OUTPUT=\\\$(nix-env -iA nixpkgs.weston nixpkgs.dbus nixpkgs.xkeyboard_config 2>&1)
                INSTALL_EXIT=\\\$?
                if [ \\\$INSTALL_EXIT -eq 0 ] || echo \\\"\\\$INSTALL_OUTPUT\\\" | grep -q \\\"already installed\\\"; then
                    echo \\\"✅ Weston installed via nix-env\\\"
                else
                    echo \\\"⚠ Direct nix install failed, trying to find weston in nix store...\\\"
                    WESTON_BIN=\\\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WESTON_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WESTON_BIN):\\\$PATH\\\"
                        echo \\\"✅ Weston found in nix store at: \\\$WESTON_BIN\\\"
                    else
                        echo \\\"❌ Failed to install or find Weston\\\"
                        exit 1
                    fi
                fi
                if ! command -v weston >/dev/null 2>&1; then
                    WESTON_BIN=\\\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WESTON_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WESTON_BIN):\\\$PATH\\\"
                    else
                        echo \\\"❌ Weston not found after installation\\\"
                        exit 1
                    fi
                fi
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y weston wayland-protocols-devel dbus-x11 xkeyboard-config 2>/dev/null || dnf install -y weston dbus-x11 xkeyboard-config 2>/dev/null || {
                    echo \\\"❌ Failed to install Weston\\\"
                    exit 1
                }
            elif command -v apk >/dev/null 2>&1; then
                rm -f /var/cache/apk/*.lock /var/lib/apk/lock.* /var/lib/apk/lock 2>/dev/null || true
                sleep 1
                apk update && apk add --no-cache weston weston-terminal dbus xkeyboard-config || {
                    echo \\\"❌ Failed to install Weston\\\"
                    exit 1
                }
            else
                echo \\\"❌ Unsupported package manager\\\"
                exit 1
            fi
            echo \\\"✅ Weston installed\\\"
        fi
        echo \\\"\\\"
        echo \\\"🔍 Verifying Wayland socket (waypipe proxy)...\\\"
        sleep 3
        SOCKET_FOUND=false
        ACTUAL_SOCKET=\\\"\\\"
        EXPECTED_SOCKET=\\\"\\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
        if [ -S \\\"\\\$EXPECTED_SOCKET\\\" ]; then
            SOCKET_FOUND=true
            ACTUAL_SOCKET=\\\"\\\$EXPECTED_SOCKET\\\"
            echo \\\"✅ Waypipe compositor socket found at expected location: \\\$ACTUAL_SOCKET\\\"
        else
            echo \\\"   Searching for waypipe compositor socket...\\\"
            for sock in \\\$(ls -1 \\\"\\\$XDG_RUNTIME_DIR\\\"/waypipe-* \\\"\\\$XDG_RUNTIME_DIR\\\"/wayland-* 2>/dev/null | grep -v waypipe.sock\\\$); do
                if [ -n \\\"\\\$sock\\\" ] && [ -S \\\"\\\$sock\\\" ] 2>/dev/null; then
                    SOCKET_NAME=\\\$(basename \\\"\\\$sock\\\")
                    if [ \\\"\\\$SOCKET_NAME\\\" = \\\"wayland-0\\\" ] && [ -S \\\"\\\$XDG_RUNTIME_DIR/waypipe-server\\\" ]; then
                        continue
                    fi
                    SOCKET_FOUND=true
                    ACTUAL_SOCKET=\\\"\\\$sock\\\"
                    echo \\\"✅ Found waypipe compositor socket: \\\$ACTUAL_SOCKET\\\"
                    export WAYLAND_DISPLAY=\\\"\\\$SOCKET_NAME\\\"
                    echo \\\"   Updated WAYLAND_DISPLAY to: \\\$WAYLAND_DISPLAY\\\"
                    break
                fi
            done
            if [ \\\"\\\$SOCKET_FOUND\\\" = false ] && [ -S \\\"\\\$XDG_RUNTIME_DIR/waypipe-server\\\" ]; then
                SOCKET_FOUND=true
                ACTUAL_SOCKET=\\\"\\\$XDG_RUNTIME_DIR/waypipe-server\\\"
                export WAYLAND_DISPLAY=\\\"waypipe-server\\\"
                echo \\\"✅ Found waypipe compositor socket: \\\$ACTUAL_SOCKET\\\"
                echo \\\"   Updated WAYLAND_DISPLAY to: \\\$WAYLAND_DISPLAY\\\"
            fi
        fi
        if [ \\\"\\\$SOCKET_FOUND\\\" = false ]; then
            echo \\\"❌ Waypipe compositor socket not found in \\\$XDG_RUNTIME_DIR\\\"
            ls -la \\\"\\\$XDG_RUNTIME_DIR/\\\" 2>/dev/null || echo \\\"   Directory not accessible\\\"
            exit 1
        fi
        echo \\\"   Using socket: \\\$ACTUAL_SOCKET\\\"
        echo \\\"   WAYLAND_DISPLAY=\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   Verifying socket is ready...\\\"
        sleep 4
        if [ ! -S \\\"\\\$ACTUAL_SOCKET\\\" ]; then
            echo \\\"❌ Socket not found: \\\$ACTUAL_SOCKET\\\"
            echo \\\"   Directory contents:\\\"
            ls -la \\\"\\\$XDG_RUNTIME_DIR/\\\" 2>/dev/null || echo \\\"   Directory not accessible\\\"
            exit 1
        fi
        if command -v socat >/dev/null 2>&1; then
            if socat -u OPEN:/dev/null UNIX-CONNECT:\\\"\\\$ACTUAL_SOCKET\\\" </dev/null 2>/dev/null; then
                echo \\\"   Socket verified with socat\\\"
            else
                echo \\\"   Socket exists, socat verification skipped (socket may still be initializing)\\\"
            fi
        else
            echo \\\"   Socket exists, assuming ready (socat not available)\\\"
        fi
        echo \\\"   Socket is ready\\\"
        echo \\\"\\\"
        echo \\\"🚀 Starting Weston compositor (via waypipe proxy)...\\\"
        echo \\\"   Backend: wayland (nested)\\\"
        echo \\\"   Parent socket: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY (waypipe proxy)\\\"
        echo \\\"\\\"
        if ! command -v weston >/dev/null 2>&1; then
            WESTON_BIN=\\\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
            if [ -n \\\"\\\$WESTON_BIN\\\" ]; then
                export PATH=\\\"\\\$(dirname \\\$WESTON_BIN):\\\$PATH\\\"
            else
                echo \\\"❌ Weston binary not found\\\"
                exit 1
            fi
        fi
        export LD_LIBRARY_PATH=\\\"/nix/var/nix/profiles/default/lib:/root/.nix-profile/lib:\\\$LD_LIBRARY_PATH\\\"
        
        # Configure Mesa for EGL platform extension support
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export MESA_GL_VERSION_OVERRIDE=3.3
        export MESA_GLSL_VERSION_OVERRIDE=330
        export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
        export EGL_PLATFORM=wayland
        
        # Find and set up Mesa EGL libraries for platform extension support
        MESA_EGL=\\\$(find /nix/store -name 'libEGL.so*' -type f 2>/dev/null | head -1)
        MESA_GL=\\\$(find /nix/store -name 'libGL.so*' -type f 2>/dev/null | head -1)
        if [ -n \\\"\\\$MESA_EGL\\\" ]; then
            MESA_EGL_DIR=\\\$(dirname \\\"\\\$MESA_EGL\\\")
            export LD_LIBRARY_PATH=\\\"\\\$MESA_EGL_DIR:\\\$LD_LIBRARY_PATH\\\"
        fi
        if [ -n \\\"\\\$MESA_GL\\\" ]; then
            MESA_GL_DIR=\\\$(dirname \\\"\\\$MESA_GL\\\")
            export LD_LIBRARY_PATH=\\\"\\\$MESA_GL_DIR:\\\$LD_LIBRARY_PATH\\\"
        fi
        
        echo \\\"   Starting Weston with wayland backend...\\\"
        if ! command -v weston >/dev/null 2>&1; then
            echo \\\"❌ Weston command not found in PATH\\\"
            exit 1
        fi
        echo \\\"   Using weston: \\\$(command -v weston)\\\"
        echo \\\"   WAYLAND_DISPLAY=\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   XDG_RUNTIME_DIR=\\\$XDG_RUNTIME_DIR\\\"
        echo \\\"   Socket path: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   EGL_PLATFORM=wayland\\\"
        weston --backend=wayland --socket=weston-0
        \" &
        WAYPIPE_SERVER_PID=\$!
        sleep 2
        wait \$WAYPIPE_SERVER_PID || {
            WESTON_EXIT_CODE=\$?
            echo \\\"\\\"
            echo \\\"⚠ Weston exited with code \\\$WESTON_EXIT_CODE\\\"
            echo \\\"   This may be normal if Weston was stopped or crashed\\\"
            echo \\\"   Check logs above for details\\\"
            exit \\\$WESTON_EXIT_CODE
        }
        "
}

# Create and run new container
create_and_run_container() {
    local TTY_FLAG=$(get_tty_flag)
    
    ensure_runtime_directories
    
    # CRITICAL: Ensure host directory has correct permissions BEFORE bind mounting
    # Docker bind mounts inherit permissions from host directory
    if [ -d "$COCOMA_XDG_RUNTIME_DIR" ]; then
        chmod 0700 "$COCOMA_XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
    
    # Use tmpfs mount for /run/user/1000 to ensure correct permissions (0700)
    # This avoids permission issues with bind mounts inheriting host permissions
    # We'll still bind mount the waypipe socket separately if needed
    docker run --name "$CONTAINER_NAME" $TTY_FLAG \
        --mount "type=tmpfs,target=/run/user/1000,tmpfs-mode=0700" \
        --mount "type=bind,source=$COCOMA_XDG_RUNTIME_DIR,target=/host-wayland-runtime,readonly" \
        -e "XDG_RUNTIME_DIR=/run/user/1000" \
        -e "HOME=/root" \
        -e "WAYPIPE_TCP_PORT=${WAYPIPE_TCP_PORT:-9999}" \
        "$CONTAINER_IMAGE" \
        sh -c "
        export XDG_RUNTIME_DIR=/run/user/1000
        export PATH=\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\$PATH\"
        set -e
        if ! command -v waypipe >/dev/null 2>&1; then
            echo \"📦 Installing waypipe...\"
            nix-env -iA nixpkgs.waypipe 2>/dev/null || {
                if [ ! -d \"/root/.nix-defexpr/channels\" ] || [ ! -L \"/root/.nix-defexpr/channels/nixpkgs\" ]; then
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                nix-env -iA nixpkgs.waypipe 2>/dev/null || {
                    echo \"❌ Failed to install waypipe\"
                    exit 1
                }
            }
        fi
        echo \"🚀 Starting waypipe server in container...\"
        WAYPIPE_DISPLAY=\"waypipe-server\"
        # Use TCP connection instead of Unix socket (Docker bind mounts don't support Unix sockets on macOS)
        # Connect to host's socat TCP proxy via host.docker.internal
        WAYPIPE_TCP_PORT=\${WAYPIPE_TCP_PORT:-9999}
        echo \"   Connecting to waypipe client via TCP (host.docker.internal:\$WAYPIPE_TCP_PORT)...\"
        # Install socat if needed (required for TCP proxy)
        if ! command -v socat >/dev/null 2>&1; then
            echo \"   Installing socat for TCP proxy...\"
            if command -v nix-env >/dev/null 2>&1; then
                nix-env -iA nixpkgs.socat 2>/dev/null || {
                    echo \"⚠ Socat install failed, trying alternative...\"
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                    nix-env -iA nixpkgs.socat 2>/dev/null || {
                        echo \"❌ Failed to install socat\"
                        exit 1
                    }
                }
            elif command -v apk >/dev/null 2>&1; then
                apk add --no-cache socat || {
                    echo \"❌ Failed to install socat\"
                    exit 1
                }
            else
                echo \"❌ Socat not available and cannot install\"
                exit 1
            fi
            echo \"✅ Socat installed\"
        fi
        # Use socat to proxy TCP to Unix socket for waypipe server
        # waypipe server expects Unix socket, so we create a local socket and proxy TCP to it
        WAYPIPE_LOCAL_SOCK=\"/tmp/waypipe-container.sock\"
        rm -f \"\$WAYPIPE_LOCAL_SOCK\"
        # Start socat proxy before waypipe server
        # Connect to host's socat TCP proxy and create local Unix socket for waypipe
        socat UNIX-LISTEN:\"\$WAYPIPE_LOCAL_SOCK\",fork,reuseaddr,unlink-early TCP:host.docker.internal:\$WAYPIPE_TCP_PORT >/tmp/socat-container.log 2>&1 &
        SOCAT_CONTAINER_PID=\$!
        # Wait for socat to create the socket and establish TCP connection
        sleep 4
        # Verify socket exists before starting waypipe
        if [ ! -S \"\$WAYPIPE_LOCAL_SOCK\" ]; then
            echo \"❌ Socat failed to create socket: \$WAYPIPE_LOCAL_SOCK\"
            echo \"   Checking TCP connection to host...\"
            nc -zv host.docker.internal \$WAYPIPE_TCP_PORT 2>&1 || echo \"   TCP connection test failed\"
            cat /tmp/socat-container.log 2>/dev/null | tail -20
            exit 1
        fi
        echo \"   Socket proxy ready: \$WAYPIPE_LOCAL_SOCK\"
        # Test TCP connection is working
        if command -v nc >/dev/null 2>&1; then
            if nc -zv host.docker.internal \$WAYPIPE_TCP_PORT 2>&1 | grep -q succeeded; then
                echo \"   TCP connection to host verified\"
            else
                echo \"   ⚠ TCP connection test inconclusive, continuing...\"
            fi
        fi
        # Install Mesa Vulkan drivers for DMA-BUF support (required for video + dmabuf)
        echo \"📦 Installing Mesa Vulkan drivers for DMA-BUF support...\"
        if command -v nix-env >/dev/null 2>&1; then
            # Install Mesa with Vulkan support - need both drivers and loader
            nix-env -iA nixpkgs.mesa.drivers nixpkgs.vulkan-loader nixpkgs.vulkan-tools nixpkgs.mesa 2>/dev/null || {
                echo \"⚠ Mesa Vulkan install failed, trying alternative...\"
                if [ ! -d \"/root/.nix-defexpr/channels\" ] || [ ! -L \"/root/.nix-defexpr/channels/nixpkgs\" ]; then
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                nix-env -iA nixpkgs.mesa.drivers nixpkgs.vulkan-loader nixpkgs.vulkan-tools nixpkgs.mesa 2>/dev/null || {
                    echo \"⚠ Mesa Vulkan drivers not available via nix, waypipe will use GBM fallback\"
                }
            }
            # Ensure Mesa libraries are in library path
            MESA_LIB=\$(find /nix/store -name 'libvulkan.so*' -type f 2>/dev/null | head -1)
            if [ -n \"\$MESA_LIB\" ]; then
                MESA_LIB_DIR=\$(dirname \"\$MESA_LIB\")
                export LD_LIBRARY_PATH=\"\$MESA_LIB_DIR:\$LD_LIBRARY_PATH\"
            fi
        fi
        # Set up Vulkan ICD loader configuration
        # Prefer software renderer (llvmpipe/swrast) for containers without GPU
        # First, find all available Vulkan ICD files
        VULKAN_ICD_DIR=\$(find /nix/store -type d -name 'icd.d' -path '*/vulkan/icd.d' 2>/dev/null | head -1)
        if [ -n \"\$VULKAN_ICD_DIR\" ]; then
            # Build colon-separated list of ICD JSON files (Vulkan loader doesn't expand globs)
            VK_ICD_LIST=\"\"
            for icd in \$VULKAN_ICD_DIR/*.json; do
                if [ -f \"\$icd\" ]; then
                    if [ -z \"\$VK_ICD_LIST\" ]; then
                        VK_ICD_LIST=\"\$icd\"
                    else
                        VK_ICD_LIST=\"\$VK_ICD_LIST:\$icd\"
                    fi
                fi
            done
            if [ -n \"\$VK_ICD_LIST\" ]; then
                export VK_ICD_FILENAMES=\$VK_ICD_LIST
                echo \"✅ Found Vulkan ICD directory: \$VULKAN_ICD_DIR\"
                echo \"   Configured VK_ICD_FILENAMES with \$(echo \$VK_ICD_LIST | tr ':' '\\n' | wc -l) ICD(s)\"
            else
                echo \"⚠ No Vulkan ICD JSON files found in \$VULKAN_ICD_DIR\"
            fi
        else
            echo \"⚠ Vulkan ICD directory not found, waypipe will use GBM fallback\"
        fi
        export VK_LAYER_PATH=/nix/store/*/share/vulkan/explicit_layer.d
        # Ensure Mesa software rendering is enabled
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
        # Ensure Vulkan loader can find Mesa libraries - add all Mesa lib directories
        for mesa_lib_dir in \$(find /nix/store -type d -name 'lib' -path '*/mesa*/lib' 2>/dev/null); do
            export LD_LIBRARY_PATH=\"\$mesa_lib_dir:\$LD_LIBRARY_PATH\"
        done
        # Also find and add Vulkan driver libraries
        MESA_VULKAN_LIB=\$(find /nix/store -name 'libvulkan_intel.so*' -o -name 'libvulkan_radeon.so*' -o -name 'libvulkan_swrast.so*' -o -name 'libvulkan_lvp.so*' 2>/dev/null | head -1)
        if [ -n \"\$MESA_VULKAN_LIB\" ]; then
            MESA_VULKAN_LIB_DIR=\$(dirname \"\$MESA_VULKAN_LIB\")
            export LD_LIBRARY_PATH=\"\$MESA_VULKAN_LIB_DIR:\$LD_LIBRARY_PATH\"
            echo \"✅ Found Mesa Vulkan library directory: \$MESA_VULKAN_LIB_DIR\"
        fi
        waypipe --socket \"\$WAYPIPE_LOCAL_SOCK\" --display \"\$WAYPIPE_DISPLAY\" server -- sh -c \"
        export XDG_RUNTIME_DIR=/run/user/1000
        export WAYLAND_DISPLAY=\\\"\\\$WAYPIPE_DISPLAY\\\"
        export PATH=\\\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\\\$PATH\\\"
        # Pass through Vulkan environment variables
        export VK_ICD_FILENAMES=\\\$VK_ICD_FILENAMES
        export VK_LAYER_PATH=\\\$VK_LAYER_PATH
        # Ensure Mesa software rendering is enabled for Vulkan
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
        
        if command -v weston >/dev/null 2>&1; then
            echo \\\"✅ Weston already installed, skipping package installation\\\"
        else
            echo \\\"📦 Installing Weston and dependencies...\\\"
            if command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
                echo \\\"   Using Nix package manager...\\\"
                if [ ! -d \\\"/root/.nix-defexpr/channels\\\" ] || [ ! -L \\\"/root/.nix-defexpr/channels/nixpkgs\\\" ]; then
                    echo \\\"   Setting up nixpkgs channel...\\\"
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                INSTALL_OUTPUT=\\\$(nix-env -iA nixpkgs.weston nixpkgs.dbus nixpkgs.xkeyboard_config 2>&1)
                INSTALL_EXIT=\\\$?
                if [ \\\$INSTALL_EXIT -eq 0 ] || echo \\\"\\\$INSTALL_OUTPUT\\\" | grep -q \\\"already installed\\\"; then
                    echo \\\"✅ Weston installed via nix-env\\\"
                else
                    echo \\\"⚠ Direct nix install failed, trying to find weston in nix store...\\\"
                    WESTON_BIN=\\\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WESTON_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WESTON_BIN):\\\$PATH\\\"
                        echo \\\"✅ Weston found in nix store at: \\\$WESTON_BIN\\\"
                    else
                        echo \\\"❌ Failed to install or find Weston\\\"
                        exit 1
                    fi
                fi
                if ! command -v weston >/dev/null 2>&1; then
                    WESTON_BIN=\\\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WESTON_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WESTON_BIN):\\\$PATH\\\"
                    else
                        echo \\\"❌ Weston not found after installation\\\"
                        exit 1
                    fi
                fi
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y weston wayland-protocols-devel dbus-x11 xkeyboard-config 2>/dev/null || dnf install -y weston dbus-x11 xkeyboard-config 2>/dev/null || {
                    echo \\\"❌ Failed to install Weston\\\"
                    exit 1
                }
            elif command -v apk >/dev/null 2>&1; then
                rm -f /var/cache/apk/*.lock /var/lib/apk/lock.* /var/lib/apk/lock 2>/dev/null || true
                sleep 1
                apk update && apk add --no-cache weston weston-terminal dbus xkeyboard-config || {
                    echo \\\"❌ Failed to install Weston\\\"
                    exit 1
                }
            else
                echo \\\"❌ Unsupported package manager\\\"
                exit 1
            fi
            echo \\\"✅ Weston installed\\\"
        fi
        echo \\\"\\\"
        echo \\\"🔍 Verifying Wayland socket (waypipe proxy)...\\\"
        sleep 3
        SOCKET_FOUND=false
        ACTUAL_SOCKET=\\\"\\\"
        EXPECTED_SOCKET=\\\"\\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
        if [ -S \\\"\\\$EXPECTED_SOCKET\\\" ]; then
            SOCKET_FOUND=true
            ACTUAL_SOCKET=\\\"\\\$EXPECTED_SOCKET\\\"
            echo \\\"✅ Waypipe compositor socket found at expected location: \\\$ACTUAL_SOCKET\\\"
        else
            echo \\\"   Searching for waypipe compositor socket...\\\"
            for sock in \\\$(ls -1 \\\"\\\$XDG_RUNTIME_DIR\\\"/waypipe-* \\\"\\\$XDG_RUNTIME_DIR\\\"/wayland-* 2>/dev/null | grep -v waypipe.sock\\\$); do
                if [ -n \\\"\\\$sock\\\" ] && [ -S \\\"\\\$sock\\\" ] 2>/dev/null; then
                    SOCKET_NAME=\\\$(basename \\\"\\\$sock\\\")
                    if [ \\\"\\\$SOCKET_NAME\\\" = \\\"wayland-0\\\" ] && [ -S \\\"\\\$XDG_RUNTIME_DIR/waypipe-server\\\" ]; then
                        continue
                    fi
                    SOCKET_FOUND=true
                    ACTUAL_SOCKET=\\\"\\\$sock\\\"
                    echo \\\"✅ Found waypipe compositor socket: \\\$ACTUAL_SOCKET\\\"
                    export WAYLAND_DISPLAY=\\\"\\\$SOCKET_NAME\\\"
                    echo \\\"   Updated WAYLAND_DISPLAY to: \\\$WAYLAND_DISPLAY\\\"
                    break
                fi
            done
            if [ \\\"\\\$SOCKET_FOUND\\\" = false ] && [ -S \\\"\\\$XDG_RUNTIME_DIR/waypipe-server\\\" ]; then
                SOCKET_FOUND=true
                ACTUAL_SOCKET=\\\"\\\$XDG_RUNTIME_DIR/waypipe-server\\\"
                export WAYLAND_DISPLAY=\\\"waypipe-server\\\"
                echo \\\"✅ Found waypipe compositor socket: \\\$ACTUAL_SOCKET\\\"
                echo \\\"   Updated WAYLAND_DISPLAY to: \\\$WAYLAND_DISPLAY\\\"
            fi
        fi
        if [ \\\"\\\$SOCKET_FOUND\\\" = false ]; then
            echo \\\"❌ Waypipe compositor socket not found in \\\$XDG_RUNTIME_DIR\\\"
            ls -la \\\"\\\$XDG_RUNTIME_DIR/\\\" 2>/dev/null || echo \\\"   Directory not accessible\\\"
            exit 1
        fi
        echo \\\"   Using socket: \\\$ACTUAL_SOCKET\\\"
        echo \\\"   WAYLAND_DISPLAY=\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   Verifying socket is ready...\\\"
        sleep 4
        if [ ! -S \\\"\\\$ACTUAL_SOCKET\\\" ]; then
            echo \\\"❌ Socket not found: \\\$ACTUAL_SOCKET\\\"
            echo \\\"   Directory contents:\\\"
            ls -la \\\"\\\$XDG_RUNTIME_DIR/\\\" 2>/dev/null || echo \\\"   Directory not accessible\\\"
            exit 1
        fi
        if command -v socat >/dev/null 2>&1; then
            if socat -u OPEN:/dev/null UNIX-CONNECT:\\\"\\\$ACTUAL_SOCKET\\\" </dev/null 2>/dev/null; then
                echo \\\"   Socket verified with socat\\\"
            else
                echo \\\"   Socket exists, socat verification skipped (socket may still be initializing)\\\"
            fi
        else
            echo \\\"   Socket exists, assuming ready (socat not available)\\\"
        fi
        echo \\\"   Socket is ready\\\"
        echo \\\"\\\"
        echo \\\"🚀 Starting Weston compositor (via waypipe proxy)...\\\"
        echo \\\"   Backend: wayland (nested)\\\"
        echo \\\"   Parent socket: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY (waypipe proxy)\\\"
        echo \\\"\\\"
        if ! command -v weston >/dev/null 2>&1; then
            WESTON_BIN=\\\$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
            if [ -n \\\"\\\$WESTON_BIN\\\" ]; then
                export PATH=\\\"\\\$(dirname \\\$WESTON_BIN):\\\$PATH\\\"
            else
                echo \\\"❌ Weston binary not found\\\"
                exit 1
            fi
        fi
        export LD_LIBRARY_PATH=\\\"/nix/var/nix/profiles/default/lib:/root/.nix-profile/lib:\\\$LD_LIBRARY_PATH\\\"
        
        # Configure Mesa for EGL platform extension support
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export MESA_GL_VERSION_OVERRIDE=3.3
        export MESA_GLSL_VERSION_OVERRIDE=330
        export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
        export EGL_PLATFORM=wayland
        
        # Find and set up Mesa EGL libraries for platform extension support
        MESA_EGL=\\\$(find /nix/store -name 'libEGL.so*' -type f 2>/dev/null | head -1)
        MESA_GL=\\\$(find /nix/store -name 'libGL.so*' -type f 2>/dev/null | head -1)
        if [ -n \\\"\\\$MESA_EGL\\\" ]; then
            MESA_EGL_DIR=\\\$(dirname \\\"\\\$MESA_EGL\\\")
            export LD_LIBRARY_PATH=\\\"\\\$MESA_EGL_DIR:\\\$LD_LIBRARY_PATH\\\"
        fi
        if [ -n \\\"\\\$MESA_GL\\\" ]; then
            MESA_GL_DIR=\\\$(dirname \\\"\\\$MESA_GL\\\")
            export LD_LIBRARY_PATH=\\\"\\\$MESA_GL_DIR:\\\$LD_LIBRARY_PATH\\\"
        fi
        
        echo \\\"   Starting Weston with wayland backend...\\\"
        if ! command -v weston >/dev/null 2>&1; then
            echo \\\"❌ Weston command not found in PATH\\\"
            exit 1
        fi
        echo \\\"   Using weston: \\\$(command -v weston)\\\"
        echo \\\"   WAYLAND_DISPLAY=\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   XDG_RUNTIME_DIR=\\\$XDG_RUNTIME_DIR\\\"
        echo \\\"   Socket path: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   EGL_PLATFORM=wayland\\\"
        weston --backend=wayland --socket=weston-0
        \" &
        WAYPIPE_SERVER_PID=\$!
        sleep 2
        wait \$WAYPIPE_SERVER_PID || {
            WESTON_EXIT_CODE=\$?
            echo \\\"\\\"
            echo \\\"⚠ Weston exited with code \\\$WESTON_EXIT_CODE\\\"
            echo \\\"   This may be normal if Weston was stopped or crashed\\\"
            echo \\\"   Check logs above for details\\\"
            exit \\\$WESTON_EXIT_CODE
        }
        "
}

# Main execution
main() {
    # Initialize waypipe client
    init_waypipe
    
    # Check compositor socket
    check_compositor_socket
    
    # Initialize Docker/Colima
    init_docker
    
    # Ensure container image exists
    ensure_container_image
    
    # Container management
    CONTAINER_EXISTS=false
    if check_container_exists; then
        CONTAINER_EXISTS=true
        stop_container_if_running
        
        if ! remove_container_if_needed; then
            CONTAINER_EXISTS=false
        else
            start_existing_container
        fi
    fi
    
    # Display container info
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} Starting Weston Container"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}ℹ${NC}  Container: ${GREEN}$CONTAINER_NAME${NC}"
    echo -e "${YELLOW}ℹ${NC}  Image: ${GREEN}$CONTAINER_IMAGE${NC}"
    echo -e "${YELLOW}ℹ${NC}  Wayland socket: ${GREEN}$SOCKET_PATH${NC} -> ${GREEN}/run/user/1000/waypipe-server${NC}"
    echo ""
    
    # Set up cleanup on script exit (after container finishes)
    trap cleanup_waypipe EXIT
    
    # Run container (temporarily disable set -e to handle errors gracefully)
    set +e
    CONTAINER_EXIT_CODE=0
    if [ "$CONTAINER_EXISTS" = true ]; then
        run_container_waypipe_weston
        CONTAINER_EXIT_CODE=$?
    else
        create_and_run_container
        CONTAINER_EXIT_CODE=$?
    fi
    set -e
    
    # Handle container exit
    if [ $CONTAINER_EXIT_CODE -ne 0 ]; then
        echo ""
        echo -e "${RED}✗${NC} Container exited with code $CONTAINER_EXIT_CODE"
        echo -e "${YELLOW}ℹ${NC} This may indicate Weston crashed or encountered an error"
        echo -e "${YELLOW}ℹ${NC} Check the logs above for details"
        echo ""
        echo -e "${YELLOW}ℹ${NC} Waypipe client is still running (PID: $WAYPIPE_CLIENT_PID)"
        echo -e "${YELLOW}ℹ${NC} To stop everything: Press Ctrl+C"
        # Keep script running so waypipe client stays alive
        # Wait for waypipe client to exit or user interrupt (Ctrl+C)
        while kill -0 $WAYPIPE_CLIENT_PID 2>/dev/null; do
            sleep 1
        done
    fi
    
    # Container finished - cleanup will happen via EXIT trap
}

# Run main function
main
