#!/bin/bash
# Colima client script for running weston-simple-egl via waypipe
# Uses Colima with VirtioFS for Unix domain socket support
# Runs weston-simple-egl client in NixOS container, connected to host compositor

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/colima-client"

# Container command file
CONTAINER_COMMAND_FILE="/tmp/weston-container-command.sh"

# Source common variables
source "$MODULES_DIR/common.sh"

# Source module functions
source "$MODULES_DIR/waypipe-setup.sh"
source "$MODULES_DIR/docker-setup.sh"
source "$MODULES_DIR/container-setup.sh"

# Check compositor socket exists
check_compositor_socket() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} Colima weston-simple-egl Setup"
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
}

# Generate container command for waypipe server + weston-simple-egl
generate_container_waypipe_egl_command() {
    cat << 'CONTAINER_WAYPIPE_EGL_EOF'
export PATH="/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:$PATH"

echo '📦 Installing waypipe with Nix...'
if command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
    echo '   Using Nix package manager...'
    if [ ! -d "/root/.nix-defexpr/channels" ] || [ ! -L "/root/.nix-defexpr/channels/nixpkgs" ]; then
        echo '   Setting up nixpkgs channel...'
        mkdir -p /root/.nix-defexpr/channels
        nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
        nix-channel --update nixpkgs 2>/dev/null || true
    fi
    nix-env -iA nixpkgs.waypipe 2>/dev/null || {
        echo '❌ Failed to install waypipe'
        exit 1
    }
    echo '✅ waypipe installed via nix-env'
else
    echo '❌ Nix package manager not found'
    exit 1
fi

echo '📦 Installing weston-simple-egl with Nix...'
# Try to install weston-simple-egl directly
nix-env -iA nixpkgs.weston 2>/dev/null || {
        echo '❌ Failed to install weston'
        exit 1
    }
    
    # Check if weston-simple-egl is available in the weston package
    if [ ! -f "/root/.nix-profile/bin/weston-simple-egl" ] && [ ! -f "/nix/var/nix/profiles/default/bin/weston-simple-egl" ]; then
        echo '   weston-simple-egl not found in weston package, trying alternative packages...'
        
        # Try installing mesa-demos which might contain egl examples
        nix-env -iA nixpkgs.mesa-demos 2>/dev/null && echo '   mesa-demos installed' || echo '   mesa-demos not available'
        
        # Install procps for ps command
        nix-env -iA nixpkgs.procps 2>/dev/null && echo '   procps installed' || echo '   procps not available'
        
        # Try installing weston with all outputs
        nix-env -iA nixpkgs.weston.passthru.tests 2>/dev/null || true
    fi
    
    echo '✅ Packages installed'
    echo '   Available weston binaries:'
    find /nix/store -name '*weston*' -type f -executable 2>/dev/null | grep -E '(simple|egl|demo)' | head -10
    echo '   Profile binaries:'
    ls -la /root/.nix-profile/bin/weston* 2>/dev/null || echo '   No weston binaries in profile'

# Find weston-simple-egl binary first
WESTON_BIN=""
EGL_DEMO=""

# Try to find weston-simple-egl first
if command -v weston-simple-egl >/dev/null 2>&1; then
    WESTON_BIN=$(which weston-simple-egl)
    EGL_DEMO="weston-simple-egl"
    echo "   Found weston-simple-egl in PATH: $WESTON_BIN"
else
    WESTON_BIN=$(find /nix/store -name weston-simple-egl -type f -executable 2>/dev/null | head -1)
    if [ -n "$WESTON_BIN" ]; then
        export PATH="$(dirname $WESTON_BIN):$PATH"
        EGL_DEMO="weston-simple-egl"
        echo "   Found weston-simple-egl at: $WESTON_BIN"
    else
        echo "   weston-simple-egl not found, looking for alternatives..."
        
        # Try to find alternative EGL demos
        for demo in weston-simple-egl es2gears_wayland weston-smoke weston-flower; do
            if command -v $demo >/dev/null 2>&1; then
                EGL_DEMO=$demo
                echo "   Found alternative EGL demo: $demo"
                break
            fi
        done
        
        if [ -z "$EGL_DEMO" ]; then
            echo "❌ No suitable EGL demo found"
            echo "   Available weston binaries:"
            find /nix/store -name '*weston*' -type f -executable 2>/dev/null | grep -E '(simple|egl|demo|smoke|flower)' | head -5
            exit 1
        fi
    fi
fi

# Set up waypipe socket path inside container
CONTAINER_WAYPIPE_SOCKET="/run/user/1000/waypipe.sock"

# Create a script to run inside the container directly
echo "   Creating EGL demo script inside container..."

# Start waypipe server in background with explicit socket path
echo "   Starting waypipe server with EGL demo..."
echo "   Container waypipe socket: $CONTAINER_WAYPIPE_SOCKET"

# First ensure the socket directory exists
mkdir -p "$(dirname "$CONTAINER_WAYPIPE_SOCKET")"

# Create and run the EGL demo script directly via waypipe server
echo "   Starting waypipe server with inline EGL demo..."

# Start waypipe server in the background, then run the demo
# The waypipe server will create a wayland socket that the demo can connect to
nohup waypipe --socket "$CONTAINER_WAYPIPE_SOCKET" server > /tmp/waypipe-server.log 2>&1 &

WAYPIPE_PID=$!
echo "   Waypipe server started with PID: $WAYPIPE_PID"

# Give the waypipe server time to start and create the socket
sleep 3

# Now run the EGL demo, connecting to the waypipe-created wayland socket
echo "   Running EGL demo via waypipe client..."

# Set up environment for the EGL demo
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY="wayland-0"
export PATH="/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:$PATH"
export LD_LIBRARY_PATH="/nix/var/nix/profiles/default/lib:/root/.nix-profile/lib:$LD_LIBRARY_PATH"

# Ensure XDG_RUNTIME_DIR exists
mkdir -p "$XDG_RUNTIME_DIR"

# Find the EGL demo
EGL_DEMO=""
for demo in es2gears_wayland weston-smoke weston-flower weston-eventdemo; do
    if command -v $demo >/dev/null 2>&1; then
        EGL_DEMO=$demo
        echo "   Found EGL demo: $demo"
        break
    fi
done

if [ -n "$EGL_DEMO" ]; then
    echo "   Running $EGL_DEMO via waypipe client..."
    nohup waypipe --socket "$CONTAINER_WAYPIPE_SOCKET" client -- $EGL_DEMO >> /tmp/waypipe-server.log 2>&1 &
    EGL_DEMO_PID=$!
    echo "   EGL demo started with PID: $EGL_DEMO_PID"
else
    echo "❌ No suitable EGL demo found"
    exit 1
fi

# Give it a moment to start
sleep 2
    
    echo ''
    echo '🔍 Verifying Wayland socket (waypipe proxy)...'
    echo "   Checking waypipe server log..."
    if [ -f /tmp/waypipe-server.log ]; then
        echo "   Log file contents:"
        cat /tmp/waypipe-server.log
    else
        echo "   No log file found"
    fi
    
    echo "   Checking if waypipe server is running..."
    if command -v ps >/dev/null 2>&1; then
        ps aux | grep waypipe | grep -v grep || echo "   No waypipe processes found"
    else
        echo "   ps command not available, checking PID file..."
        if [ -n "$WAYPIPE_PID" ] && kill -0 "$WAYPIPE_PID" 2>/dev/null; then
            echo "   Waypipe server process $WAYPIPE_PID is running"
        else
            echo "   Waypipe server process not found"
        fi
    fi
    
    echo "   Checking for waypipe sockets..."
    find /run/user/1000 /tmp -name "*waypipe*" -o -name "*wayland*" 2>/dev/null || true
    
    sleep 3
    SOCKET_FOUND=false
    ACTUAL_SOCKET=""
    EXPECTED_SOCKET="$CONTAINER_WAYPIPE_SOCKET"
    
    if [ -S "$EXPECTED_SOCKET" ]; then
        SOCKET_FOUND=true
        ACTUAL_SOCKET="$EXPECTED_SOCKET"
        echo "✅ Waypipe compositor socket found at expected location: $ACTUAL_SOCKET"
    else
        echo "   Searching for waypipe compositor socket..."
        # Find sockets in XDG_RUNTIME_DIR
        for sock in $(find "$XDG_RUNTIME_DIR" -name "waypipe-*" -o -name "wayland-*" 2>/dev/null | grep -v waypipe.sock$); do
            if [ -n "$sock" ] && [ -S "$sock" ]; then
                SOCKET_NAME=$(basename "$sock")
                if [ "$SOCKET_NAME" = "wayland-0" ] && [ -S "$XDG_RUNTIME_DIR/waypipe-server" ]; then
                    continue
                fi
                SOCKET_FOUND=true
                ACTUAL_SOCKET="$sock"
                echo "✅ Found waypipe compositor socket: $ACTUAL_SOCKET"
                export WAYLAND_DISPLAY="$SOCKET_NAME"
                echo "   Updated WAYLAND_DISPLAY to: $WAYLAND_DISPLAY"
                break
            fi
        done
        if [ "$SOCKET_FOUND" = false ] && [ -S "$XDG_RUNTIME_DIR/waypipe-server" ]; then
            SOCKET_FOUND=true
            ACTUAL_SOCKET="$XDG_RUNTIME_DIR/waypipe-server"
            export WAYLAND_DISPLAY="waypipe-server"
            echo "✅ Found waypipe compositor socket: $ACTUAL_SOCKET"
            echo "   Updated WAYLAND_DISPLAY to: $WAYLAND_DISPLAY"
        fi
    fi
    
    if [ "$SOCKET_FOUND" = false ]; then
        echo "❌ Waypipe compositor socket not found in $XDG_RUNTIME_DIR"
        ls -la "$XDG_RUNTIME_DIR/" 2>/dev/null || echo "   Directory not accessible"
        exit 1
    fi
    
    echo "   Using socket: $ACTUAL_SOCKET"
    echo "   WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    echo "   Verifying socket is ready..."
    sleep 4
    
    if [ ! -S "$ACTUAL_SOCKET" ]; then
        echo "❌ Socket not found: $ACTUAL_SOCKET"
        echo "   Directory contents:"
        ls -la "$XDG_RUNTIME_DIR/" 2>/dev/null || echo "   Directory not accessible"
        exit 1
    fi
    
    echo "   Socket is ready"
    echo ''
    echo '🚀 Running weston-simple-egl (via waypipe proxy)...'
    echo "   Backend: wayland (nested)"
    echo "   Parent socket: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY (waypipe proxy)"
    echo ''
    
    export LD_LIBRARY_PATH="/nix/var/nix/profiles/default/lib:/root/.nix-profile/lib:$LD_LIBRARY_PATH"
    echo "   Starting weston-simple-egl with wayland backend..."
    
    if ! command -v weston-simple-egl >/dev/null 2>&1; then
        WESTON_BIN=$(find /nix/store -name weston-simple-egl -type f -executable 2>/dev/null | head -1)
        if [ -n "$WESTON_BIN" ]; then
            export PATH="$(dirname $WESTON_BIN):$PATH"
        else
            echo "❌ weston-simple-egl binary not found"
            exit 1
        fi
    fi
    
    # Set up fontconfig to avoid errors
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf
    if [ ! -f \"\$FONTCONFIG_FILE\" ]; then
        mkdir -p /etc/fonts
        cat > \"\$FONTCONFIG_FILE\" << '\''FONTCONFIG_EOF'\''
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
    
    echo \"   Using weston-simple-egl: \$(command -v weston-simple-egl)\"
    echo \"   WAYLAND_DISPLAY=\$WAYLAND_DISPLAY\"
    echo \"   XDG_RUNTIME_DIR=\$XDG_RUNTIME_DIR\"
    echo \"   Socket path: \$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY\"
    
    # CRITICAL: Create/fix XDG_RUNTIME_DIR permissions BEFORE anything else
    if [ -d \"\$XDG_RUNTIME_DIR\" ]; then
        if ! chmod 0700 \"\$XDG_RUNTIME_DIR\" 2>/dev/null; then
            rm -rf \"\$XDG_RUNTIME_DIR\"/* 2>/dev/null || true
            rmdir \"\$XDG_RUNTIME_DIR\" 2>/dev/null || true
        fi
    fi
    
    mkdir -p \"\$XDG_RUNTIME_DIR\" 2>/dev/null || true
    chmod 0700 \"\$XDG_RUNTIME_DIR\" 2>/dev/null || true
    chown root:root \"\$XDG_RUNTIME_DIR\" 2>/dev/null || true
    
    # Suppress harmless warnings while keeping important errors visible
    weston-simple-egl 2>&1 | grep -v \"could not load cursor\" | grep -v \"Fontconfig error\" | grep -v \"XDG_RUNTIME_DIR.*is not configured correctly\" || true
" &
WAYPIPE_SERVER_PID=$!
sleep 2
wait $WAYPIPE_SERVER_PID
CONTAINER_WAYPIPE_EGL_EOF
}

# Initialize waypipe client
init_waypipe() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} Initializing Waypipe client"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    check_waypipe
    setup_waypipe_directory
    cleanup_existing_waypipe
    
    # Start waypipe client to proxy compositor connection
    echo -e "${YELLOW}ℹ${NC} Starting waypipe client to proxy compositor connection..."
    
    # Verify compositor socket exists before starting waypipe client
    COMPOSITOR_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    if [ ! -S "$COMPOSITOR_SOCKET" ]; then
        echo -e "${RED}✗${NC} Compositor socket not found: $COMPOSITOR_SOCKET"
        echo -e "${YELLOW}ℹ${NC} Start the compositor first: make compositor"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Compositor socket found: $COMPOSITOR_SOCKET"
    
    # Start waypipe client with Unix socket
    # waypipe client connects to the compositor and creates a proxy socket
    WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        waypipe --socket "$WAYPIPE_SOCKET" client >/tmp/waypipe-client.log 2>&1 &
    WAYPIPE_CLIENT_PID=$!
    sleep 3
    
    # Verify waypipe client started
    if ! kill -0 $WAYPIPE_CLIENT_PID 2>/dev/null; then
        echo -e "${RED}✗${NC} Failed to start waypipe client"
        echo -e "${YELLOW}ℹ${NC} Check logs: /tmp/waypipe-client.log"
        cat /tmp/waypipe-client.log 2>/dev/null | tail -10
        exit 1
    fi
    
    # Wait for waypipe socket to be created and ready
    echo -e "${YELLOW}ℹ${NC} Waiting for waypipe socket to be ready..."
    SOCKET_READY=false
    for i in 1 2 3 4 5 6; do
        if [ -S "$WAYPIPE_SOCKET" ]; then
            # Socket exists, wait a bit more for waypipe client to be fully ready
            sleep 1
            SOCKET_READY=true
            break
        fi
        sleep 1
    done
    
    if [ "$SOCKET_READY" = false ] || [ ! -S "$WAYPIPE_SOCKET" ]; then
        echo -e "${RED}✗${NC} Waypipe socket not created"
        kill $WAYPIPE_CLIENT_PID 2>/dev/null || true
        cat /tmp/waypipe-client.log 2>/dev/null | tail -10
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} Waypipe socket ready: $WAYPIPE_SOCKET"
    
    # Start socat TCP proxy for Docker compatibility (Unix sockets don't work through bind mounts on macOS)
    # Proxy Unix socket to TCP so container can connect
    # Bind to 0.0.0.0 to allow connections from Docker container via host.docker.internal
    # waypipe client creates a LISTEN socket, so socat connects to it
    # Use retry and interval to handle connection timing
    WAYPIPE_TCP_PORT=${WAYPIPE_TCP_PORT:-9999}
    
    # Check if port is already in use and kill existing socat process if it's ours
    if lsof -ti :$WAYPIPE_TCP_PORT >/dev/null 2>&1; then
        echo -e "${YELLOW}ℹ${NC} Port $WAYPIPE_TCP_PORT is already in use"
        EXISTING_PID=$(lsof -ti :$WAYPIPE_TCP_PORT | head -1)
        if [ -n "$EXISTING_PID" ]; then
            # Check if it's a socat process (likely from a previous run)
            if ps -p $EXISTING_PID -o comm= 2>/dev/null | grep -q socat; then
                echo -e "${YELLOW}ℹ${NC} Killing existing socat process (PID: $EXISTING_PID)"
                kill $EXISTING_PID 2>/dev/null || true
                sleep 1
            fi
        fi
    fi
    
    echo -e "${YELLOW}ℹ${NC} Starting TCP proxy for Docker compatibility (port $WAYPIPE_TCP_PORT)..."
    # Wait a moment more for waypipe client to be fully ready to accept connections
    sleep 1
    socat TCP-LISTEN:$WAYPIPE_TCP_PORT,fork,reuseaddr,bind=0.0.0.0 UNIX-CONNECT:"$WAYPIPE_SOCKET",retry=5,interval=1 >/tmp/socat-waypipe.log 2>&1 &
    SOCAT_PID=$!
    sleep 2
    
    # Verify socat started
    if ! kill -0 $SOCAT_PID 2>/dev/null; then
        echo -e "${RED}✗${NC} Failed to start socat TCP proxy"
        echo -e "${YELLOW}ℹ${NC} Check logs: /tmp/socat-waypipe.log"
        cat /tmp/socat-waypipe.log 2>/dev/null | tail -10
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} TCP proxy started (port $WAYPIPE_TCP_PORT)"
    echo ""
}

# Initialize Docker/Colima
init_docker() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} Initializing Docker/Colima"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Docker not found. Please install Docker."
        exit 1
    fi
    
    # Check if Colima is available and running
    if command -v colima >/dev/null 2>&1; then
        if ! colima status >/dev/null 2>&1; then
            echo -e "${YELLOW}ℹ${NC} Starting Colima..."
            colima start --mount-type virtiofs
            sleep 5
        fi
        
        if colima status >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Colima is running"
        else
            echo -e "${RED}✗${NC} Failed to start Colima"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠${NC} Colima not found. Using regular Docker."
        echo -e "${YELLOW}ℹ${NC} Note: Unix socket sharing may not work properly without Colima."
    fi
    
    echo ""
}

# Ensure container image exists
ensure_container_image() {
    echo -e "${YELLOW}ℹ${NC} Checking container image: ${GREEN}$CONTAINER_IMAGE${NC}"
    
    if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${CONTAINER_IMAGE}$"; then
        echo -e "${YELLOW}ℹ${NC} Pulling container image..."
        docker pull "$CONTAINER_IMAGE"
        echo -e "${GREEN}✓${NC} Container image pulled"
    else
        echo -e "${GREEN}✓${NC} Container image available"
    fi
    echo ""
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
        fi
    fi
    
    # Create and run container if needed
    if [ "$CONTAINER_EXISTS" = false ]; then
        create_container
        start_container
    fi
    
    # Generate container command
    generate_container_waypipe_egl_command > "$CONTAINER_COMMAND_FILE"
    
    # Run container with waypipe server and weston-simple-egl
    run_container_waypipe_egl
    
    echo -e "${GREEN}✓${NC} weston-simple-egl test completed"
}

# Create container with proper mounts
create_container() {
    echo -e "${YELLOW}ℹ${NC} Creating container: ${GREEN}$CONTAINER_NAME${NC}"
    
    ensure_runtime_directories
    
    TTY_FLAG=$(get_tty_flag)
    
    # Use tmpfs mount for /run/user/1000 to ensure correct permissions (0700)
    # This avoids permission issues with bind mounts inheriting host permissions
    # We'll still bind mount the waypipe socket separately if needed
    docker run -d --name "$CONTAINER_NAME" \
        --mount "type=tmpfs,target=/run/user/1000,tmpfs-mode=0700" \
        --mount "type=bind,source=$COCOMA_XDG_RUNTIME_DIR,target=/host-wayland-runtime,readonly" \
        -e "XDG_RUNTIME_DIR=/run/user/1000" \
        -e "HOME=/root" \
        -e "WAYPIPE_TCP_PORT=${WAYPIPE_TCP_PORT:-9999}" \
        "$CONTAINER_IMAGE" \
        sleep infinity || {
        echo -e "${RED}✗${NC} Failed to create container"
        exit 1
    }
    
    echo -e "${GREEN}✓${NC} Container created"
    echo ""
}

# Start existing container
start_container() {
    echo -e "${YELLOW}ℹ${NC} Starting container: ${GREEN}$CONTAINER_NAME${NC}"
    docker start "$CONTAINER_NAME" >/dev/null 2>&1 || {
        echo -e "${RED}✗${NC} Failed to start container"
        exit 1
    }
    
    # Wait for container to be ready
    sleep 2
    
    echo -e "${GREEN}✓${NC} Container started"
    echo ""
}

# Run container with waypipe server and weston-simple-egl
run_container_waypipe_egl() {
    echo -e "${YELLOW}ℹ${NC} Running waypipe server + weston-simple-egl in container..."
    echo ""
    
    # Execute the generated command
    docker exec $(get_tty_flag) "$CONTAINER_NAME" sh -c "$(cat "$CONTAINER_COMMAND_FILE")"
}

# Run main function
main "$@"