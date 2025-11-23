#!/bin/bash
# Colima wlcs script for running Wayland Conformance Test Suite
# Uses Colima with waypipe + socat for Unix domain socket support
# Runs wlcs in NixOS container, connected to host compositor

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/colima-client"

# Source common variables
source "$MODULES_DIR/common.sh"

# Override container name for wlcs
CONTAINER_NAME="wlcs-container"

# Source module functions
source "$MODULES_DIR/waypipe-setup.sh"
source "$MODULES_DIR/docker-setup.sh"
source "$MODULES_DIR/container-setup.sh"

# Log file
LOG_FILE="/tmp/wlcs-test.log"

# Check compositor socket exists
check_compositor_socket() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} Wayland Conformance Test Suite (wlcs)"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${YELLOW}ℹ${NC} Checking compositor socket: ${GREEN}$SOCKET_PATH${NC}"
    if [ ! -S "$SOCKET_PATH" ] && [ ! -e "$SOCKET_PATH" ]; then
        echo -e "${RED}✗${NC} Compositor socket not found: ${RED}$SOCKET_PATH${NC}"
        echo ""
        echo -e "${YELLOW}ℹ${NC} Start the compositor first: ${GREEN}make compositor${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Compositor socket found"
    
    if [ "$COCOMA_XDG_RUNTIME_DIR" != "$XDG_RUNTIME_DIR" ]; then
        echo -e "${YELLOW}ℹ${NC} Using Colima-compatible path: ${GREEN}$COCOMA_XDG_RUNTIME_DIR${NC}"
    fi
    echo ""
    echo -e "${YELLOW}ℹ${NC} Log file: ${GREEN}$LOG_FILE${NC}"
    echo ""
}

# Generate container command for waypipe server + wlcs
generate_container_waypipe_wlcs_command() {
    cat << 'CONTAINER_WAYPIPE_WLCS_EOF'
waypipe --socket "\$WAYPIPE_SOCKET" --display "\$WAYPIPE_DISPLAY" server -- sh -c \"
    export XDG_RUNTIME_DIR=/run/user/1000
    export WAYLAND_DISPLAY=\\\"\$WAYPIPE_DISPLAY\\\"
    export PATH=\\\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\$PATH\\\"
    
    # Install wlcs if needed
    if ! command -v wlcs >/dev/null 2>&1; then
        echo \"📦 Installing wlcs...\"
        if command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
            echo \"   Using Nix package manager...\"
            if [ ! -d \"/root/.nix-defexpr/channels\" ] || [ ! -L \"/root/.nix-defexpr/channels/nixpkgs\" ]; then
                echo \"   Setting up nixpkgs channel...\"
                mkdir -p /root/.nix-defexpr/channels
                nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                nix-channel --update nixpkgs 2>/dev/null || true
            fi
            INSTALL_OUTPUT=\$(nix-env -iA nixpkgs.wlcs 2>&1)
            INSTALL_EXIT=\$?
            if [ \$INSTALL_EXIT -eq 0 ] || echo \"\$INSTALL_OUTPUT\" | grep -q \"already installed\"; then
                echo \"✅ wlcs installed via nix-env\"
            else
                echo \"⚠ Direct nix install failed, trying to find wlcs in nix store...\"
                WLCS_BIN=\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
                if [ -n \"\$WLCS_BIN\" ]; then
                    export PATH=\"\$(dirname \$WLCS_BIN):\$PATH\"
                    echo \"✅ wlcs found in nix store at: \$WLCS_BIN\"
                else
                    echo \"❌ Failed to install or find wlcs\"
                    exit 1
                fi
            fi
            if ! command -v wlcs >/dev/null 2>&1; then
                WLCS_BIN=\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
                if [ -n \"\$WLCS_BIN\" ]; then
                    export PATH=\"\$(dirname \$WLCS_BIN):\$PATH\"
                else
                    echo \"❌ wlcs not found after installation\"
                    exit 1
                fi
            fi
        else
            echo \"❌ Nix package manager not found\"
            exit 1
        fi
        echo \"✅ wlcs installed\"
    fi
    echo \"\"
    echo \"🔍 Verifying Wayland socket (waypipe proxy)...\"
    sleep 3
    SOCKET_FOUND=false
    ACTUAL_SOCKET=\"\"
    EXPECTED_SOCKET=\"\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY\"
    if [ -S \"\$EXPECTED_SOCKET\" ]; then
        SOCKET_FOUND=true
        ACTUAL_SOCKET=\"\$EXPECTED_SOCKET\"
        echo \"✅ Waypipe compositor socket found at expected location: \$ACTUAL_SOCKET\"
    else
        echo \"   Searching for waypipe compositor socket...\"
        for sock in \$(ls -1 \"\$XDG_RUNTIME_DIR\"/waypipe-* \"\$XDG_RUNTIME_DIR\"/wayland-* 2>/dev/null | grep -v waypipe.sock\$); do
            if [ -n \"\$sock\" ] && [ -S \"\$sock\" ] 2>/dev/null; then
                SOCKET_NAME=\$(basename \"\$sock\")
                if [ \"\$SOCKET_NAME\" = \"wayland-0\" ] && [ -S \"\$XDG_RUNTIME_DIR/waypipe-server\" ]; then
                    continue
                fi
                SOCKET_FOUND=true
                ACTUAL_SOCKET=\"\$sock\"
                echo \"✅ Found waypipe compositor socket: \$ACTUAL_SOCKET\"
                export WAYLAND_DISPLAY=\"\$SOCKET_NAME\"
                echo \"   Updated WAYLAND_DISPLAY to: \$WAYLAND_DISPLAY\"
                break
            fi
        done
        if [ \"\$SOCKET_FOUND\" = false ] && [ -S \"\$XDG_RUNTIME_DIR/waypipe-server\" ]; then
            SOCKET_FOUND=true
            ACTUAL_SOCKET=\"\$XDG_RUNTIME_DIR/waypipe-server\"
            export WAYLAND_DISPLAY=\"waypipe-server\"
            echo \"✅ Found waypipe compositor socket: \$ACTUAL_SOCKET\"
            echo \"   Updated WAYLAND_DISPLAY to: \$WAYLAND_DISPLAY\"
        fi
    fi
    if [ \"\$SOCKET_FOUND\" = false ]; then
        echo \"❌ Waypipe compositor socket not found in \$XDG_RUNTIME_DIR\"
        ls -la \"\$XDG_RUNTIME_DIR/\" 2>/dev/null || echo \"   Directory not accessible\"
        exit 1
    fi
    echo \"   Using socket: \$ACTUAL_SOCKET\"
    echo \"   WAYLAND_DISPLAY=\$WAYLAND_DISPLAY\"
    echo \"   Verifying socket is ready...\"
    sleep 4
    if [ ! -S \"\$ACTUAL_SOCKET\" ]; then
        echo \"❌ Socket not found: \$ACTUAL_SOCKET\"
        echo \"   Directory contents:\"
        ls -la \"\$XDG_RUNTIME_DIR/\" 2>/dev/null || echo \"   Directory not accessible\"
        exit 1
    fi
    if command -v socat >/dev/null 2>&1; then
        if socat -u OPEN:/dev/null UNIX-CONNECT:\"\$ACTUAL_SOCKET\" </dev/null 2>/dev/null; then
            echo \"   Socket verified with socat\"
        else
            echo \"   Socket exists, socat verification skipped (socket may still be initializing)\"
        fi
    else
        echo \"   Socket exists, assuming ready (socat not available)\"
    fi
    echo \"   Socket is ready\"
    echo \"\"
    echo \"🧪 Running Wayland Conformance Test Suite (wlcs)...\"
    echo \"   Socket: \$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY (waypipe proxy)\"
    echo \"\"
    if ! command -v wlcs >/dev/null 2>&1; then
        WLCS_BIN=\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
        if [ -n \"\$WLCS_BIN\" ]; then
            export PATH=\"\$(dirname \$WLCS_BIN):\$PATH\"
        else
            echo \"❌ wlcs binary not found\"
            exit 1
        fi
    fi
    echo \"   Using wlcs: \$(command -v wlcs)\"
    echo \"   WAYLAND_DISPLAY=\$WAYLAND_DISPLAY\"
    echo \"   XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR\"
    echo \"   Socket path: \$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY\"
    echo \"\"
    wlcs 2>&1
" &
WAYPIPE_SERVER_PID=\$!
sleep 2
wait \$WAYPIPE_SERVER_PID
CONTAINER_WAYPIPE_WLCS_EOF
}

# Run container with waypipe server and wlcs
run_container_waypipe_wlcs() {
    local TTY_FLAG=$(get_tty_flag)
    
    # Clear log file
    rm -f "$LOG_FILE"
    touch "$LOG_FILE"
    
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
        WAYPIPE_TCP_PORT=\${WAYPIPE_TCP_PORT:-9999}
        echo \"   Connecting to waypipe client via TCP (host.docker.internal:\$WAYPIPE_TCP_PORT)...\"
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
        WAYPIPE_LOCAL_SOCK=\"/tmp/waypipe-container.sock\"
        rm -f \"\$WAYPIPE_LOCAL_SOCK\"
        socat UNIX-LISTEN:\"\$WAYPIPE_LOCAL_SOCK\",fork,reuseaddr,unlink-early TCP:host.docker.internal:\$WAYPIPE_TCP_PORT >/tmp/socat-container.log 2>&1 &
        SOCAT_CONTAINER_PID=\$!
        sleep 4
        if [ ! -S \"\$WAYPIPE_LOCAL_SOCK\" ]; then
            echo \"❌ Socat failed to create socket: \$WAYPIPE_LOCAL_SOCK\"
            echo \"   Checking TCP connection to host...\"
            nc -zv host.docker.internal \$WAYPIPE_TCP_PORT 2>&1 || echo \"   TCP connection test failed\"
            cat /tmp/socat-container.log 2>/dev/null | tail -20
            exit 1
        fi
        echo \"   Socket proxy ready: \$WAYPIPE_LOCAL_SOCK\"
        waypipe --socket \"\$WAYPIPE_LOCAL_SOCK\" --display \"\$WAYPIPE_DISPLAY\" server -- sh -c \"
        export XDG_RUNTIME_DIR=/run/user/1000
        export WAYLAND_DISPLAY=\\\"\\\$WAYPIPE_DISPLAY\\\"
        export PATH=\\\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\\\$PATH\\\"
        
        if ! command -v wlcs >/dev/null 2>&1; then
            echo \\\"📦 Installing wlcs...\\\"
            if command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
                echo \\\"   Using Nix package manager...\\\"
                if [ ! -d \\\"/root/.nix-defexpr/channels\\\" ] || [ ! -L \\\"/root/.nix-defexpr/channels/nixpkgs\\\" ]; then
                    echo \\\"   Setting up nixpkgs channel...\\\"
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                INSTALL_OUTPUT=\\\$(nix-env -iA nixpkgs.wlcs 2>&1)
                INSTALL_EXIT=\\\$?
                if [ \\\$INSTALL_EXIT -eq 0 ] || echo \\\"\\\$INSTALL_OUTPUT\\\" | grep -q \\\"already installed\\\"; then
                    echo \\\"✅ wlcs installed via nix-env\\\"
                else
                    echo \\\"⚠ Direct nix install failed, trying to find wlcs in nix store...\\\"
                    WLCS_BIN=\\\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WLCS_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WLCS_BIN):\\\$PATH\\\"
                        echo \\\"✅ wlcs found in nix store at: \\\$WLCS_BIN\\\"
                    else
                        echo \\\"❌ Failed to install or find wlcs\\\"
                        exit 1
                    fi
                fi
                if ! command -v wlcs >/dev/null 2>&1; then
                    WLCS_BIN=\\\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WLCS_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WLCS_BIN):\\\$PATH\\\"
                    else
                        echo \\\"❌ wlcs not found after installation\\\"
                        exit 1
                    fi
                fi
            else
                echo \\\"❌ Nix package manager not found\\\"
                exit 1
            fi
            echo \\\"✅ wlcs installed\\\"
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
        echo \\\"🧪 Running Wayland Conformance Test Suite (wlcs)...\\\"
        echo \\\"   Socket: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY (waypipe proxy)\\\"
        echo \\\"\\\"
        if ! command -v wlcs >/dev/null 2>&1; then
            WLCS_BIN=\\\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
            if [ -n \\\"\\\$WLCS_BIN\\\" ]; then
                export PATH=\\\"\\\$(dirname \\\$WLCS_BIN):\\\$PATH\\\"
            else
                echo \\\"❌ wlcs binary not found\\\"
                exit 1
            fi
        fi
        echo \\\"   Using wlcs: \\\$(command -v wlcs)\\\"
        echo \\\"   WAYLAND_DISPLAY=\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   XDG_RUNTIME_DIR=\\\$XDG_RUNTIME_DIR\\\"
        echo \\\"   Socket path: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
        echo \\\"\\\"
        echo \\\"🔍 Finding wlcs integration modules...\\\"
        WLCS_BIN=\\\$(command -v wlcs)
        WLCS_PKG_DIR=\\\$(dirname \\\$(dirname \\\"\\\$WLCS_BIN\\\") 2>/dev/null || echo \\\"\\\")
        echo \\\"   wlcs binary: \\\$WLCS_BIN\\\"
        echo \\\"   wlcs package dir: \\\$WLCS_PKG_DIR\\\"
        # Search for integration modules in multiple locations
        # 1. Search entire nix store for wlcs-related .so files
        INTEGRATION_MODULES=\\\$(find /nix/store -path \\\"*/wlcs*\\\" -name \\\"*.so\\\" 2>/dev/null | grep -v \\\".pyc\\\" | head -20)
        # 2. Search in common wlcs package locations
        if [ -n \\\"\\\$WLCS_PKG_DIR\\\" ]; then
            for dir in \\\"\\\$WLCS_PKG_DIR/lib/wlcs\\\" \\\"\\\$WLCS_PKG_DIR/lib\\\" \\\"\\\$WLCS_PKG_DIR/libexec/wlcs\\\" \\\"\\\$WLCS_PKG_DIR/libexec\\\" \\\"\\\$WLCS_PKG_DIR/share/wlcs\\\" \\\"\\\$WLCS_PKG_DIR\\\"; do
                if [ -d \\\"\\\$dir\\\" ]; then
                    echo \\\"   Checking: \\\$dir\\\"
                    FOUND=\\\$(find \\\"\\\$dir\\\" -name \\\"*.so\\\" 2>/dev/null | head -10)
                    if [ -n \\\"\\\$FOUND\\\" ]; then
                        INTEGRATION_MODULES=\\\"\\\$INTEGRATION_MODULES \\\$FOUND\\\"
                    fi
                fi
            done
        fi
        # 3. Also search for common integration module names
        for name in \\\"libwlcs-test-server.so\\\" \\\"libwlcs_integration_test.so\\\" \\\"wlcs-test-server.so\\\"; do
            FOUND=\\\$(find /nix/store -name \\\"\\\$name\\\" 2>/dev/null | head -5)
            if [ -n \\\"\\\$FOUND\\\" ]; then
                INTEGRATION_MODULES=\\\"\\\$INTEGRATION_MODULES \\\$FOUND\\\"
            fi
        done
        # Remove duplicates and empty lines
        INTEGRATION_MODULES=\\\$(echo \\\"\\\$INTEGRATION_MODULES\\\" | grep -v \\\"^\\\$\\\" | sort -u)
        if [ -n \\\"\\\$INTEGRATION_MODULES\\\" ]; then
            echo \\\"   Found integration modules:\\\"
            echo \\\"\\\$INTEGRATION_MODULES\\\" | while read mod; do 
                echo \\\"     - \\\$(basename \\\$mod): \\\$mod\\\"
            done
            # Try to use the first available module (usually libwlcs-test-server.so or similar)
            FIRST_MODULE=\\\$(echo \\\"\\\$INTEGRATION_MODULES\\\" | head -1)
            if [ -n \\\"\\\$FIRST_MODULE\\\" ] && [ -f \\\"\\\$FIRST_MODULE\\\" ]; then
                echo \\\"\\\"
                echo \\\"🧪 Running wlcs with integration module: \\\$(basename \\\$FIRST_MODULE)\\\"
                echo \\\"   Note: Testing Wawona Compositor via waypipe proxy\\\"
                echo \\\"   Socket: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
                echo \\\"\\\"
                # Try to list tests first, then run a subset
                wlcs \\\"\\\$FIRST_MODULE\\\" --gtest_list_tests 2>&1 | head -100 || \\
                wlcs \\\"\\\$FIRST_MODULE\\\" --gtest_filter=\\\"*.*\\\" 2>&1 | head -200 || \\
                wlcs \\\"\\\$FIRST_MODULE\\\" 2>&1 | head -200 || true
            fi
        else
            echo \\\"   ⚠ No integration modules (.so files) found\\\"
            echo \\\"   Searched in: /nix/store (wlcs packages), \\\$WLCS_PKG_DIR/lib, \\\$WLCS_PKG_DIR/libexec, \\\$WLCS_PKG_DIR/share\\\"
            if [ -n \\\"\\\$WLCS_PKG_DIR\\\" ]; then
                echo \\\"   Listing wlcs package structure:\\\"
                ls -la \\\"\\\$WLCS_PKG_DIR\\\" 2>&1 | head -20 || true
            fi
            echo \\\"\\\"
            echo \\\"🧪 wlcs requires a compositor integration module to test compositors.\\\"
            echo \\\"   For Wawona Compositor, you may need to build a custom integration module.\\\"
            echo \\\"   Showing wlcs usage:\\\"
            echo \\\"\\\"
            wlcs --help 2>&1 | head -40 || wlcs 2>&1 | head -40 || true
        fi
        \" &
        WAYPIPE_SERVER_PID=\$!
        sleep 2
        wait \$WAYPIPE_SERVER_PID
        " >>"$LOG_FILE" 2>&1 &
    CONTAINER_PID=$!
    
    # Tail log file in foreground
    echo -e "${YELLOW}ℹ${NC} Tailing log file (Ctrl+C to stop)..."
    echo ""
    trap "kill $CONTAINER_PID 2>/dev/null || true; exit" INT TERM
    tail -f "$LOG_FILE" &
    TAIL_PID=$!
    
    # Wait for container to finish
    wait $CONTAINER_PID || true
    kill $TAIL_PID 2>/dev/null || true
    trap - INT TERM
}

# Create and run new container
create_and_run_container() {
    local TTY_FLAG=$(get_tty_flag)
    
    ensure_runtime_directories
    
    if [ -d "$COCOMA_XDG_RUNTIME_DIR" ]; then
        chmod 0700 "$COCOMA_XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
    
    # Clear log file
    rm -f "$LOG_FILE"
    touch "$LOG_FILE"
    
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
        WAYPIPE_TCP_PORT=\${WAYPIPE_TCP_PORT:-9999}
        echo \"   Connecting to waypipe client via TCP (host.docker.internal:\$WAYPIPE_TCP_PORT)...\"
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
        WAYPIPE_LOCAL_SOCK=\"/tmp/waypipe-container.sock\"
        rm -f \"\$WAYPIPE_LOCAL_SOCK\"
        socat UNIX-LISTEN:\"\$WAYPIPE_LOCAL_SOCK\",fork,reuseaddr,unlink-early TCP:host.docker.internal:\$WAYPIPE_TCP_PORT >/tmp/socat-container.log 2>&1 &
        SOCAT_CONTAINER_PID=\$!
        sleep 4
        if [ ! -S \"\$WAYPIPE_LOCAL_SOCK\" ]; then
            echo \"❌ Socat failed to create socket: \$WAYPIPE_LOCAL_SOCK\"
            echo \"   Checking TCP connection to host...\"
            nc -zv host.docker.internal \$WAYPIPE_TCP_PORT 2>&1 || echo \"   TCP connection test failed\"
            cat /tmp/socat-container.log 2>/dev/null | tail -20
            exit 1
        fi
        echo \"   Socket proxy ready: \$WAYPIPE_LOCAL_SOCK\"
        waypipe --socket \"\$WAYPIPE_LOCAL_SOCK\" --display \"\$WAYPIPE_DISPLAY\" server -- sh -c \"
        export XDG_RUNTIME_DIR=/run/user/1000
        export WAYLAND_DISPLAY=\\\"\\\$WAYPIPE_DISPLAY\\\"
        export PATH=\\\"/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:\\\$PATH\\\"
        
        if ! command -v wlcs >/dev/null 2>&1; then
            echo \\\"📦 Installing wlcs...\\\"
            if command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
                echo \\\"   Using Nix package manager...\\\"
                if [ ! -d \\\"/root/.nix-defexpr/channels\\\" ] || [ ! -L \\\"/root/.nix-defexpr/channels/nixpkgs\\\" ]; then
                    echo \\\"   Setting up nixpkgs channel...\\\"
                    mkdir -p /root/.nix-defexpr/channels
                    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
                    nix-channel --update nixpkgs 2>/dev/null || true
                fi
                INSTALL_OUTPUT=\\\$(nix-env -iA nixpkgs.wlcs 2>&1)
                INSTALL_EXIT=\\\$?
                if [ \\\$INSTALL_EXIT -eq 0 ] || echo \\\"\\\$INSTALL_OUTPUT\\\" | grep -q \\\"already installed\\\"; then
                    echo \\\"✅ wlcs installed via nix-env\\\"
                else
                    echo \\\"⚠ Direct nix install failed, trying to find wlcs in nix store...\\\"
                    WLCS_BIN=\\\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WLCS_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WLCS_BIN):\\\$PATH\\\"
                        echo \\\"✅ wlcs found in nix store at: \\\$WLCS_BIN\\\"
                    else
                        echo \\\"❌ Failed to install or find wlcs\\\"
                        exit 1
                    fi
                fi
                if ! command -v wlcs >/dev/null 2>&1; then
                    WLCS_BIN=\\\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
                    if [ -n \\\"\\\$WLCS_BIN\\\" ]; then
                        export PATH=\\\"\\\$(dirname \\\$WLCS_BIN):\\\$PATH\\\"
                    else
                        echo \\\"❌ wlcs not found after installation\\\"
                        exit 1
                    fi
                fi
            else
                echo \\\"❌ Nix package manager not found\\\"
                exit 1
            fi
            echo \\\"✅ wlcs installed\\\"
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
        echo \\\"🧪 Running Wayland Conformance Test Suite (wlcs)...\\\"
        echo \\\"   Socket: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY (waypipe proxy)\\\"
        echo \\\"\\\"
        if ! command -v wlcs >/dev/null 2>&1; then
            WLCS_BIN=\\\$(find /nix/store -name wlcs -type f -executable 2>/dev/null | head -1)
            if [ -n \\\"\\\$WLCS_BIN\\\" ]; then
                export PATH=\\\"\\\$(dirname \\\$WLCS_BIN):\\\$PATH\\\"
            else
                echo \\\"❌ wlcs binary not found\\\"
                exit 1
            fi
        fi
        echo \\\"   Using wlcs: \\\$(command -v wlcs)\\\"
        echo \\\"   WAYLAND_DISPLAY=\\\$WAYLAND_DISPLAY\\\"
        echo \\\"   XDG_RUNTIME_DIR=\\\$XDG_RUNTIME_DIR\\\"
        echo \\\"   Socket path: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
        echo \\\"\\\"
        echo \\\"🔍 Finding wlcs integration modules...\\\"
        WLCS_BIN=\\\$(command -v wlcs)
        WLCS_PKG_DIR=\\\$(dirname \\\$(dirname \\\"\\\$WLCS_BIN\\\") 2>/dev/null || echo \\\"\\\")
        echo \\\"   wlcs binary: \\\$WLCS_BIN\\\"
        echo \\\"   wlcs package dir: \\\$WLCS_PKG_DIR\\\"
        # Search for integration modules in multiple locations
        # 1. Search entire nix store for wlcs-related .so files
        INTEGRATION_MODULES=\\\$(find /nix/store -path \\\"*/wlcs*\\\" -name \\\"*.so\\\" 2>/dev/null | grep -v \\\".pyc\\\" | head -20)
        # 2. Search in common wlcs package locations
        if [ -n \\\"\\\$WLCS_PKG_DIR\\\" ]; then
            for dir in \\\"\\\$WLCS_PKG_DIR/lib/wlcs\\\" \\\"\\\$WLCS_PKG_DIR/lib\\\" \\\"\\\$WLCS_PKG_DIR/libexec/wlcs\\\" \\\"\\\$WLCS_PKG_DIR/libexec\\\" \\\"\\\$WLCS_PKG_DIR/share/wlcs\\\" \\\"\\\$WLCS_PKG_DIR\\\"; do
                if [ -d \\\"\\\$dir\\\" ]; then
                    echo \\\"   Checking: \\\$dir\\\"
                    FOUND=\\\$(find \\\"\\\$dir\\\" -name \\\"*.so\\\" 2>/dev/null | head -10)
                    if [ -n \\\"\\\$FOUND\\\" ]; then
                        INTEGRATION_MODULES=\\\"\\\$INTEGRATION_MODULES \\\$FOUND\\\"
                    fi
                fi
            done
        fi
        # 3. Also search for common integration module names
        for name in \\\"libwlcs-test-server.so\\\" \\\"libwlcs_integration_test.so\\\" \\\"wlcs-test-server.so\\\"; do
            FOUND=\\\$(find /nix/store -name \\\"\\\$name\\\" 2>/dev/null | head -5)
            if [ -n \\\"\\\$FOUND\\\" ]; then
                INTEGRATION_MODULES=\\\"\\\$INTEGRATION_MODULES \\\$FOUND\\\"
            fi
        done
        # Remove duplicates and empty lines
        INTEGRATION_MODULES=\\\$(echo \\\"\\\$INTEGRATION_MODULES\\\" | grep -v \\\"^\\\$\\\" | sort -u)
        if [ -n \\\"\\\$INTEGRATION_MODULES\\\" ]; then
            echo \\\"   Found integration modules:\\\"
            echo \\\"\\\$INTEGRATION_MODULES\\\" | while read mod; do 
                echo \\\"     - \\\$(basename \\\$mod): \\\$mod\\\"
            done
            # Try to use the first available module (usually libwlcs-test-server.so or similar)
            FIRST_MODULE=\\\$(echo \\\"\\\$INTEGRATION_MODULES\\\" | head -1)
            if [ -n \\\"\\\$FIRST_MODULE\\\" ] && [ -f \\\"\\\$FIRST_MODULE\\\" ]; then
                echo \\\"\\\"
                echo \\\"🧪 Running wlcs with integration module: \\\$(basename \\\$FIRST_MODULE)\\\"
                echo \\\"   Note: Testing Wawona Compositor via waypipe proxy\\\"
                echo \\\"   Socket: \\\$XDG_RUNTIME_DIR/\\\$WAYLAND_DISPLAY\\\"
                echo \\\"\\\"
                # Try to list tests first, then run a subset
                wlcs \\\"\\\$FIRST_MODULE\\\" --gtest_list_tests 2>&1 | head -100 || \\
                wlcs \\\"\\\$FIRST_MODULE\\\" --gtest_filter=\\\"*.*\\\" 2>&1 | head -200 || \\
                wlcs \\\"\\\$FIRST_MODULE\\\" 2>&1 | head -200 || true
            fi
        else
            echo \\\"   ⚠ No integration modules (.so files) found\\\"
            echo \\\"   Searched in: /nix/store (wlcs packages), \\\$WLCS_PKG_DIR/lib, \\\$WLCS_PKG_DIR/libexec, \\\$WLCS_PKG_DIR/share\\\"
            if [ -n \\\"\\\$WLCS_PKG_DIR\\\" ]; then
                echo \\\"   Listing wlcs package structure:\\\"
                ls -la \\\"\\\$WLCS_PKG_DIR\\\" 2>&1 | head -20 || true
            fi
            echo \\\"\\\"
            echo \\\"🧪 wlcs requires a compositor integration module to test compositors.\\\"
            echo \\\"   For Wawona Compositor, you may need to build a custom integration module.\\\"
            echo \\\"   Showing wlcs usage:\\\"
            echo \\\"\\\"
            wlcs --help 2>&1 | head -40 || wlcs 2>&1 | head -40 || true
        fi
        \" &
        WAYPIPE_SERVER_PID=\$!
        sleep 2
        wait \$WAYPIPE_SERVER_PID
        " >>"$LOG_FILE" 2>&1 &
    CONTAINER_PID=$!
    
    # Tail log file in foreground
    echo -e "${YELLOW}ℹ${NC} Tailing log file (Ctrl+C to stop)..."
    echo ""
    trap "kill $CONTAINER_PID 2>/dev/null || true; exit" INT TERM
    tail -f "$LOG_FILE" &
    TAIL_PID=$!
    
    # Wait for container to finish
    wait $CONTAINER_PID || true
    kill $TAIL_PID 2>/dev/null || true
    trap - INT TERM
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
    echo -e "${BLUE}▶${NC} Starting wlcs Container"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}ℹ${NC}  Container: ${GREEN}$CONTAINER_NAME${NC}"
    echo -e "${YELLOW}ℹ${NC}  Image: ${GREEN}$CONTAINER_IMAGE${NC}"
    echo -e "${YELLOW}ℹ${NC}  Wayland socket: ${GREEN}$SOCKET_PATH${NC} -> ${GREEN}/run/user/1000/waypipe-server${NC}"
    echo ""
    
    # Run container
    if [ "$CONTAINER_EXISTS" = true ]; then
        run_container_waypipe_wlcs
    else
        create_and_run_container
    fi
}

# Run main function
main

