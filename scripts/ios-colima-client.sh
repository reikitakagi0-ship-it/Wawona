#!/bin/bash
# iOS Colima client script for running Weston in Docker containers
# Uses Colima with TCP connection to iOS Simulator Wawona compositor
# Runs Weston nested compositor in NixOS container, connected to iOS compositor via TCP

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$SCRIPT_DIR/colima-client"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

IOS_UNIX_SOCKET=""
IOS_XDG_RUNTIME_DIR=""

find_ios_unix_socket() {
    echo -e "${YELLOW}ℹ${NC} Detecting iOS Simulator Wayland socket..."
    RESULT=$("$PROJECT_ROOT/scripts/ios-simulator-socket.sh" 2>/dev/null || echo "")
    if [ -z "$RESULT" ]; then
        echo -e "${RED}✗${NC} Could not locate iOS Simulator Wayland socket"
        echo -e "${YELLOW}ℹ${NC} Ensure Wawona is installed and simulator is booted"
        exit 1
    fi
    IOS_UNIX_SOCKET=$(echo "$RESULT" | cut -d '|' -f1)
    IOS_XDG_RUNTIME_DIR=$(echo "$RESULT" | cut -d '|' -f2)
    if [ -z "$IOS_UNIX_SOCKET" ] || [ -z "$IOS_XDG_RUNTIME_DIR" ]; then
        echo -e "${RED}✗${NC} Invalid socket detection output: $RESULT"
        exit 1
    fi
    if [ ! -S "$IOS_UNIX_SOCKET" ]; then
        echo -e "${RED}✗${NC} Wayland socket not found: $IOS_UNIX_SOCKET"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Found iOS Wayland socket: $IOS_UNIX_SOCKET"
    echo -e "${GREEN}✓${NC} iOS XDG_RUNTIME_DIR: $IOS_XDG_RUNTIME_DIR"
}

# Source common variables and module functions (but skip iOS socket detection)
# We'll handle iOS TCP mode ourselves
source "$MODULES_DIR/common.sh" || true
source "$MODULES_DIR/waypipe-setup.sh"
source "$MODULES_DIR/docker-setup.sh"
source "$MODULES_DIR/container-setup.sh"

# Ensure required variables are set even if common.sh sourcing failed
# This is needed for iOS TCP mode where we don't use the iOS socket
if [ -z "${COCOMA_XDG_RUNTIME_DIR:-}" ]; then
    COCOMA_XDG_RUNTIME_DIR="${HOME}/.wayland-runtime"
fi
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR="/tmp/wayland-runtime"
fi

# Check iOS compositor is running via TCP
check_ios_compositor() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} iOS Colima Client Setup"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    find_ios_unix_socket
}

setup_waypipe_ios() {
    # Check if waypipe is available
    if ! command -v waypipe >/dev/null 2>&1; then
        # Try to find waypipe-rs in dependencies
        WAYPIPE_RS=""
        if [ -f "dependencies/waypipe/build/target/release/waypipe" ]; then
            WAYPIPE_RS="dependencies/waypipe/build/target/release/waypipe"
        elif [ -f "dependencies/waypipe/build/target/x86_64-apple-darwin/release/waypipe" ]; then
            WAYPIPE_RS="dependencies/waypipe/build/target/x86_64-apple-darwin/release/waypipe"
        elif [ -f "dependencies/waypipe/build/target/aarch64-apple-darwin/release/waypipe" ]; then
            WAYPIPE_RS="dependencies/waypipe/build/target/aarch64-apple-darwin/release/waypipe"
        fi
        
        if [ -n "$WAYPIPE_RS" ] && [ -x "$WAYPIPE_RS" ]; then
            echo -e "${GREEN}✓${NC} Using waypipe-rs from dependencies: $WAYPIPE_RS"
            export PATH="$(dirname "$WAYPIPE_RS"):$PATH"
            WAYPIPE_CMD="$WAYPIPE_RS"
        elif command -v waypipe >/dev/null 2>&1; then
            WAYPIPE_CMD="waypipe"
            # Check if it's waypipe-rs or waypipe-c
            WAYPIPE_VERSION=$(waypipe --version 2>&1 || echo "")
            if echo "$WAYPIPE_VERSION" | grep -q "waypipe-rs\|Rust"; then
                echo -e "${GREEN}✓${NC} Using waypipe-rs (supports dmabuf and video)"
            else
                echo -e "${YELLOW}⚠${NC} Using waypipe-c (may not support all features)"
                echo -e "${YELLOW}ℹ${NC} For full dmabuf/video support, build waypipe-rs:"
                echo -e "${YELLOW}ℹ${NC}   cd dependencies/waypipe && cargo build --release --features video,dmabuf"
            fi
        else
            echo -e "${RED}✗${NC} waypipe not found"
            echo -e "${YELLOW}ℹ${NC} Install waypipe: brew install waypipe"
            echo -e "${YELLOW}ℹ${NC} Or build waypipe-rs: cd dependencies/waypipe && cargo build --release --features video,dmabuf"
            exit 1
        fi
    else
        WAYPIPE_CMD="waypipe"
        WAYPIPE_VERSION=$(waypipe --version 2>&1 || echo "")
        if echo "$WAYPIPE_VERSION" | grep -q "waypipe-rs\|Rust"; then
            echo -e "${GREEN}✓${NC} Using waypipe-rs (supports dmabuf and video)"
        else
            echo -e "${YELLOW}⚠${NC} Using waypipe-c (may not support all features)"
            echo -e "${YELLOW}ℹ${NC} For full dmabuf/video support, build waypipe-rs:"
            echo -e "${YELLOW}ℹ${NC}   cd dependencies/waypipe && cargo build --release --features video,dmabuf"
        fi
    fi
    
    # Setup waypipe directory within project (to avoid safe_rm restrictions)
    WAYLAND_RUNTIME_DIR="$PWD/build/.wayland-runtime"
    if [ ! -d "$WAYLAND_RUNTIME_DIR" ]; then
        mkdir -p "$WAYLAND_RUNTIME_DIR"
    fi
    
    # Cleanup existing waypipe processes
    pkill -f "waypipe.*client.*waypipe-ios" 2>/dev/null || true
    pkill -f "socat .*waypipe-ios.sock" 2>/dev/null || true
    sleep 0.5
    if [ -e "$WAYLAND_RUNTIME_DIR/waypipe-ios.sock" ]; then
        rm -f "$WAYLAND_RUNTIME_DIR/waypipe-ios.sock" || true
    fi
    
    WAYPIPE_SOCKET="$WAYLAND_RUNTIME_DIR/waypipe-ios.sock"
    rm -f "$WAYPIPE_SOCKET"
    SHORT_LINK="$WAYLAND_RUNTIME_DIR/ios-wawona.sock"
    rm -f "$SHORT_LINK" 2>/dev/null || true
    ln -sf "$IOS_UNIX_SOCKET" "$SHORT_LINK"
    export XDG_RUNTIME_DIR="$WAYLAND_RUNTIME_DIR"
    export WAYLAND_DISPLAY="$(basename "$SHORT_LINK")"
    export WAYPIPE_ALLOW_WAIT=1
    WAYPIPE_SOCKET="$WAYPIPE_SOCKET" start_waypipe_client
    WAYPIPE_TCP_PORT=${WAYPIPE_TCP_PORT:-9999}
    
    # Check if port is already in use
    if lsof -ti :$WAYPIPE_TCP_PORT >/dev/null 2>&1; then
        EXISTING_PID=$(lsof -ti :$WAYPIPE_TCP_PORT | head -1)
        if ps -p $EXISTING_PID -o comm= 2>/dev/null | grep -q socat; then
            echo -e "${YELLOW}ℹ${NC} Killing existing socat process (PID: $EXISTING_PID)..."
            kill $EXISTING_PID 2>/dev/null || true
            sleep 1
        fi
    fi
    
    echo -e "${YELLOW}ℹ${NC} Starting TCP proxy for Docker compatibility (port $WAYPIPE_TCP_PORT)..."
    sleep 1
    socat TCP-LISTEN:$WAYPIPE_TCP_PORT,fork,reuseaddr,bind=0.0.0.0 UNIX-CONNECT:"$WAYPIPE_SOCKET",retry=5,interval=1 >/tmp/socat-waypipe.log 2>&1 &
    SOCAT_WAYPIPE_PID=$!
    sleep 2
    
    # Verify socat started
    if ! kill -0 $SOCAT_WAYPIPE_PID 2>/dev/null; then
        echo -e "${RED}✗${NC} Failed to start socat TCP proxy"
        cat /tmp/socat-waypipe.log 2>/dev/null | tail -10
        kill $SOCAT_PID 2>/dev/null || true
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} TCP proxy running (PID: $SOCAT_WAYPIPE_PID, port: $WAYPIPE_TCP_PORT)"
    echo -e "${GREEN}✓${NC} Waypipe client socket: $WAYPIPE_SOCKET"
    export WAYPIPE_TCP_PORT
    export SOCAT_PID
    export SOCAT_WAYPIPE_PID
    export WAYPIPE_SOCKET
    # Waypipe client PID is exported by start_waypipe_client via WAYPIPE_CLIENT_PID
}

# Cleanup function for waypipe
cleanup_waypipe_ios() {
    if [ -n "$SOCAT_WAYPIPE_PID" ] && kill -0 $SOCAT_WAYPIPE_PID 2>/dev/null; then
        kill $SOCAT_WAYPIPE_PID 2>/dev/null || true
    fi
    if [ -n "$SOCAT_PID" ] && kill -0 $SOCAT_PID 2>/dev/null; then
        kill $SOCAT_PID 2>/dev/null || true
    fi
    if [ -n "$WAYPIPE_SERVER_PID" ] && kill -0 $WAYPIPE_SERVER_PID 2>/dev/null; then
        kill $WAYPIPE_SERVER_PID 2>/dev/null || true
    fi
    if [ -e "$WAYPIPE_SOCKET" ]; then
        rm -f "$WAYPIPE_SOCKET"
    fi
    if [ -e "$SOCAT_SOCK" ]; then
        rm -f "$SOCAT_SOCK"
    fi
}

# Generate container command for waypipe server + weston (same as regular colima-client)
generate_container_waypipe_weston_command() {
    cat << 'CONTAINER_WAYPIPE_WESTON_EOF'
export XDG_RUNTIME_DIR=/run/user/1000
export PATH="/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:$PATH"
export WAYPIPE_SOCKET="/run/user/1000/waypipe.sock"
export WAYPIPE_DISPLAY="waypipe-server"
export WAYLAND_DISPLAY="$WAYPIPE_DISPLAY"
    
    
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
            INSTALL_OUTPUT=$(nix-env -iA nixpkgs.weston nixpkgs.dbus nixpkgs.xkeyboard_config nixpkgs.waypipe nixpkgs.socat 2>&1)
            INSTALL_EXIT=$?
            if [ $INSTALL_EXIT -eq 0 ] || echo "$INSTALL_OUTPUT" | grep -q "already installed"; then
                echo "✅ Weston installed via nix-env"
            else
                echo "⚠ Direct nix install failed, trying to find weston in nix store..."
                WESTON_BIN=$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                if [ -n "$WESTON_BIN" ]; then
                    export PATH="$(dirname $WESTON_BIN):$PATH"
                    echo "✅ Weston found in nix store at: $WESTON_BIN"
                else
                    echo "❌ Failed to install or find Weston"
                    exit 1
                fi
            fi
            if ! command -v weston >/dev/null 2>&1; then
                WESTON_BIN=$(find /nix/store -name weston -type f -executable 2>/dev/null | head -1)
                if [ -n "$WESTON_BIN" ]; then
                    export PATH="$(dirname $WESTON_BIN):$PATH"
                else
                    echo "❌ Weston not found after installation"
                    exit 1
                fi
            fi
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y weston wayland-protocols-devel dbus-x11 xkeyboard-config waypipe socat 2>/dev/null || \
            dnf install -y weston dbus-x11 xkeyboard-config waypipe socat 2>/dev/null || {
                echo "❌ Failed to install Weston"
                exit 1
            }
        elif command -v apk >/dev/null 2>&1; then
            rm -f /var/cache/apk/*.lock /var/lib/apk/lock.* /var/lib/apk/lock 2>/dev/null || true
            sleep 1
            apk update && apk add --no-cache weston weston-terminal dbus xkeyboard-config waypipe socat || {
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
    echo "🔌 Starting TCP→UNIX proxy for waypipe socket..."
    if command -v socat >/dev/null 2>&1; then
        socat UNIX-LISTEN:"$WAYPIPE_SOCKET",fork,reuseaddr,unlink-early TCP:host.docker.internal:${WAYPIPE_TCP_PORT:-9999} >/tmp/socat-container-waypipe.log 2>&1 &
        sleep 1
        echo "✅ Proxy started: $WAYPIPE_SOCKET ⇄ host.docker.internal:${WAYPIPE_TCP_PORT:-9999}"
    else
        echo "❌ socat not available in container"
        exit 1
    fi

    echo ""
    echo "🚀 Starting waypipe server in container..."
    waypipe --socket "$WAYPIPE_SOCKET" --display "$WAYPIPE_DISPLAY" server -- sh -c '
        export XDG_RUNTIME_DIR=/run/user/1000
        export WAYLAND_DISPLAY="$WAYPIPE_DISPLAY"
        export PATH="/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:$PATH"
        export LD_LIBRARY_PATH="/nix/var/nix/profiles/default/lib:/root/.nix-profile/lib:$LD_LIBRARY_PATH"
        weston --backend=wayland --socket=weston-0
    '
CONTAINER_WAYPIPE_WESTON_EOF
}

# Run container with waypipe server and weston (same as regular colima-client)
run_container_waypipe_weston() {
    local TTY_FLAG=$(get_tty_flag)
    
    docker exec $TTY_FLAG \
        -e "XDG_RUNTIME_DIR=/run/user/1000" \
        -e "HOME=/root" \
        -e "WAYPIPE_TCP_PORT=${WAYPIPE_TCP_PORT:-9999}" \
        "$CONTAINER_NAME" \
        sh -c "$(generate_container_waypipe_weston_command)"
}

# Create and run container (same as regular colima-client)
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
        sh -c "$(generate_container_waypipe_weston_command)"
}

# Main execution
main() {
    # Check iOS compositor is running
    check_ios_compositor
    
    # Setup waypipe for iOS Simulator (Unix socket) connection
    setup_waypipe_ios
    
    # Setup Docker (same as regular colima-client)
    ensure_colima_running
    ensure_container_image
    
    # Run container with waypipe server + weston (same as regular colima-client)
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} Running Weston in container..."
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Container management (same as regular colima-client)
    CONTAINER_EXISTS=false
    if check_container_exists; then
        CONTAINER_EXISTS=true
        stop_container_if_running
        
        if ! remove_container_if_needed; then
            CONTAINER_EXISTS=false
        else
            echo -e "${YELLOW}ℹ${NC} Using existing container: $CONTAINER_NAME"
        fi
    fi
    
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
        return 0
    fi
}

# Cleanup on exit
cleanup() {
    echo ""
    echo -e "${YELLOW}ℹ${NC} Cleaning up..."
    cleanup_waypipe_ios
}

trap cleanup EXIT

# Run main function
main "$@"
