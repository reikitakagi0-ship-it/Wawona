#!/bin/bash
# Waypipe client setup and management

# Check if waypipe is available, build if needed
check_waypipe() {
    if ! command -v waypipe >/dev/null 2>&1; then
        echo -e "${YELLOW}ℹ${NC} waypipe not found - checking if we can build it..."
        if [ -d "waypipe" ] && command -v cargo >/dev/null 2>&1 && command -v meson >/dev/null 2>&1; then
            echo -e "${YELLOW}ℹ${NC} Building waypipe..."
            cd waypipe
            cargo fetch --locked >/dev/null 2>&1 || true
            if [ ! -d "build" ]; then
                meson setup build >/dev/null 2>&1 || {
                    echo -e "${RED}✗${NC} Failed to build waypipe"
                    echo -e "${YELLOW}ℹ${NC} Install waypipe: brew install waypipe"
                    exit 1
                }
            fi
            meson compile -C build >/dev/null 2>&1 || {
                echo -e "${RED}✗${NC} Failed to compile waypipe"
                exit 1
            }
            export PATH="$PWD/build:$PATH"
            cd ..
            echo -e "${GREEN}✓${NC} waypipe built"
        else
            echo -e "${RED}✗${NC} waypipe not found"
            echo -e "${YELLOW}ℹ${NC} Install waypipe: brew install waypipe"
            echo -e "${YELLOW}ℹ${NC} Or build from source in waypipe/ directory"
            exit 1
        fi
    fi
}

# Setup waypipe proxy directory
setup_waypipe_directory() {
    if [ ! -d "${HOME}/.wayland-runtime" ]; then
        mkdir -p "${HOME}/.wayland-runtime"
    fi
}

# Cleanup existing waypipe processes and sockets
cleanup_existing_waypipe() {
    pkill -f "waypipe.*client.*${WAYPIPE_SOCKET}" 2>/dev/null || true
    sleep 0.5
    if [ -e "$WAYPIPE_SOCKET" ]; then
        rm -f "$WAYPIPE_SOCKET"
    fi
}

# Start waypipe client with TCP proxy for Docker compatibility
start_waypipe_client() {
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
                echo -e "${YELLOW}ℹ${NC} Killing existing socat process (PID: $EXISTING_PID)..."
                kill $EXISTING_PID 2>/dev/null || true
                sleep 1
                # Verify it's gone
                if lsof -ti :$WAYPIPE_TCP_PORT >/dev/null 2>&1; then
                    echo -e "${RED}✗${NC} Port $WAYPIPE_TCP_PORT still in use after killing socat"
                    echo -e "${YELLOW}ℹ${NC} Another process is using port $WAYPIPE_TCP_PORT"
                    echo -e "${YELLOW}ℹ${NC} Set WAYPIPE_TCP_PORT environment variable to use a different port"
                    kill $WAYPIPE_CLIENT_PID 2>/dev/null || true
                    exit 1
                fi
            else
                echo -e "${RED}✗${NC} Port $WAYPIPE_TCP_PORT is in use by non-socat process (PID: $EXISTING_PID)"
                echo -e "${YELLOW}ℹ${NC} Set WAYPIPE_TCP_PORT environment variable to use a different port"
                kill $WAYPIPE_CLIENT_PID 2>/dev/null || true
                exit 1
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
        kill $WAYPIPE_CLIENT_PID 2>/dev/null || true
        exit 1
    fi
    
    # Verify TCP port is listening
    if ! nc -z 127.0.0.1 $WAYPIPE_TCP_PORT 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC} TCP port $WAYPIPE_TCP_PORT not ready yet, continuing anyway..."
    fi
    
    echo -e "${GREEN}✓${NC} Waypipe client running (PID: $WAYPIPE_CLIENT_PID)"
    echo -e "${GREEN}✓${NC} Waypipe socket: $WAYPIPE_SOCKET"
    echo -e "${GREEN}✓${NC} TCP proxy running (PID: $SOCAT_PID, port: $WAYPIPE_TCP_PORT)"
    export WAYPIPE_TCP_PORT
    export SOCAT_PID
    export WAYPIPE_CLIENT_PID
}

# Cleanup function for waypipe
cleanup_waypipe() {
    if [ -n "$SOCAT_PID" ] && kill -0 $SOCAT_PID 2>/dev/null; then
        kill $SOCAT_PID 2>/dev/null || true
    fi
    if [ -n "$WAYPIPE_CLIENT_PID" ] && kill -0 $WAYPIPE_CLIENT_PID 2>/dev/null; then
        kill $WAYPIPE_CLIENT_PID 2>/dev/null || true
    fi
    if [ -e "$WAYPIPE_SOCKET" ]; then
        rm -f "$WAYPIPE_SOCKET"
    fi
}

# Initialize waypipe setup
init_waypipe() {
    check_waypipe
    setup_waypipe_directory
    cleanup_existing_waypipe
    start_waypipe_client
    # Set up signal handlers for cleanup (SIGINT, SIGTERM)
    # Don't use EXIT trap - waypipe client needs to stay alive while container runs
    trap cleanup_waypipe INT TERM
}

