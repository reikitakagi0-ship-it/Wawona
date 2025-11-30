#!/bin/bash
# Docker and Colima setup and verification

# Check if Docker/Colima are installed
check_docker_colima() {
    if ! command -v docker >/dev/null 2>&1 || ! command -v colima >/dev/null 2>&1; then
        echo -e "${YELLOW}ℹ${NC} Docker/Colima not found - installing via Homebrew..."
        echo ""
        
        # Check if Homebrew is available
        if ! command -v brew >/dev/null 2>&1; then
            echo -e "${RED}✗${NC} Homebrew not found"
            echo ""
            echo -e "${YELLOW}ℹ${NC} Install Homebrew first:"
            echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
        
        # Install Colima, Docker, and Docker Compose
        echo -e "${YELLOW}ℹ${NC} Installing Colima, Docker, and Docker Compose..."
        brew install colima docker docker-compose || {
            echo -e "${RED}✗${NC} Failed to install Colima/Docker"
            exit 1
        }
        echo -e "${GREEN}✓${NC} Colima and Docker installed"
        echo ""
    fi
}

# Check and start Colima if needed
ensure_colima_running() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${YELLOW}ℹ${NC} Docker daemon not running - starting Colima..."
        echo -e "${YELLOW}ℹ${NC} Starting Colima with VirtioFS (required for Unix domain sockets)..."
        
        # Start Colima and capture output (show it too)
        # Temporarily disable set -e to handle errors gracefully
        set +e
        echo ""
        COLIMA_START_OUTPUT=$(colima start --mount-type virtiofs 2>&1)
        COLIMA_EXIT_CODE=$?
        set -e
        echo "$COLIMA_START_OUTPUT"
        echo ""
        
        # Check for fatal errors in output (even if exit code is 0)
        # Colima can exit with 0 but still have fatal errors
        if echo "$COLIMA_START_OUTPUT" | grep -q "fatal\|error starting vm\|exiting, status"; then
            # Check if the error is about disk in use (stuck instance)
            if echo "$COLIMA_START_OUTPUT" | grep -q "in use by instance\|failed to run attach disk"; then
                echo "$COLIMA_START_OUTPUT"
                echo ""
                echo -e "${YELLOW}⚠${NC} Colima instance appears to be stuck - attempting recovery..."
                echo -e "${YELLOW}ℹ${NC} Stopping and cleaning up stuck instance..."
                
                # Try multiple cleanup methods
                # 1. Stop via colima
                colima stop 2>/dev/null || true
                sleep 2
                
                # 2. Try limactl stop
                limactl stop colima 2>/dev/null || true
                sleep 1
                
                # 3. Try to delete the stuck instance
                echo "y" | colima delete 2>/dev/null || true
                sleep 1
                
                # 4. Try limactl remove
                limactl remove colima 2>/dev/null || true
                sleep 1
                
                # 5. Manual cleanup of instance directory
                echo -e "${YELLOW}ℹ${NC} Attempting manual cleanup..."
                rm -rf ~/.colima/_lima/colima 2>/dev/null || true
                sleep 2
                
                sleep 2
                
                # Try starting again with VZ
                echo -e "${YELLOW}ℹ${NC} Starting Colima again after cleanup..."
                set +e
                COLIMA_START_OUTPUT=$(colima start --mount-type virtiofs 2>&1)
                COLIMA_EXIT_CODE=$?
                set -e
                echo "$COLIMA_START_OUTPUT"
                echo ""
                
                if echo "$COLIMA_START_OUTPUT" | grep -q "fatal\|error starting vm\|exiting, status"; then
                    echo "$COLIMA_START_OUTPUT"
                    echo ""
                    echo -e "${RED}✗${NC} Failed to start Colima after recovery attempt"
                    echo ""
                    echo -e "${YELLOW}ℹ${NC} VZ framework appears to have a stuck disk lock."
                    echo -e "${YELLOW}ℹ${NC} Try these steps to fix:"
                    echo -e "${YELLOW}   1.${NC} Restart your Mac (VZ framework locks are released on reboot)"
                    echo -e "${YELLOW}   2.${NC} Check for stuck VZ processes: ps aux | grep -i vz"
                    echo -e "${YELLOW}   3.${NC} Check system logs: log show --predicate 'process == \"Virtualization\"' --last 5m"
                    echo -e "${YELLOW}   4.${NC} Check Colima logs: cat ~/.colima/_lima/colima/ha.stderr.log"
                    echo ""
                    exit 1
                fi
            else
                # Generic VZ failure
                echo "$COLIMA_START_OUTPUT"
                echo ""
                echo -e "${RED}✗${NC} Failed to start Colima"
                echo ""
                echo -e "${YELLOW}ℹ${NC} VZ framework error detected. Check Colima logs: ~/.colima/_lima/colima/ha.stderr.log"
                echo -e "${YELLOW}ℹ${NC} Common fixes:"
                echo -e "${YELLOW}   -${NC} Restart your Mac (VZ framework locks are released on reboot)"
                echo -e "${YELLOW}   -${NC} Check for stuck processes: ps aux | grep -i vz"
                echo ""
                exit 1
            fi
        elif [ $COLIMA_EXIT_CODE -ne 0 ]; then
            echo "$COLIMA_START_OUTPUT"
            echo ""
            echo -e "${RED}✗${NC} Failed to start Colima (exit code: $COLIMA_EXIT_CODE)"
            echo ""
            exit 1
        fi
        
        # Wait for Docker to be ready (Colima may report success before Docker is accessible)
        echo -e "${YELLOW}ℹ${NC} Waiting for Docker daemon to be ready..."
        DOCKER_READY=false
        for i in {1..30}; do
            if docker info >/dev/null 2>&1; then
                DOCKER_READY=true
                break
            fi
            sleep 1
        done
        
        if [ "$DOCKER_READY" = false ]; then
            echo ""
            echo -e "${RED}✗${NC} Docker daemon not accessible after starting Colima"
            echo -e "${YELLOW}ℹ${NC} Colima may have started but Docker isn't ready yet"
            echo -e "${YELLOW}ℹ${NC} Check Colima status: colima status"
            echo -e "${YELLOW}ℹ${NC} Check Docker: docker info"
            echo ""
            exit 1
        fi
        
        echo -e "${GREEN}✓${NC} Colima started and Docker daemon is ready"
    else
        # Check if Colima is using VirtioFS
        if command -v colima >/dev/null 2>&1; then
            COLIMASTATUS=$(colima status 2>/dev/null || echo "")
            if echo "$COLIMASTATUS" | grep -q "mount.*virtiofs"; then
                echo -e "${GREEN}✓${NC} Colima running with VirtioFS"
            elif echo "$COLIMASTATUS" | grep -q "mount.*sshfs"; then
                echo -e "${YELLOW}⚠${NC} Colima is using SSHFS - Unix domain sockets may not work"
                echo -e "${YELLOW}ℹ${NC} Restart Colima with VirtioFS:"
                echo "   colima stop && colima start --mount-type virtiofs"
                echo ""
                read -p "Continue anyway? (y/N) " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            else
                echo -e "${GREEN}✓${NC} Docker daemon running"
            fi
        else
            echo -e "${GREEN}✓${NC} Docker daemon running"
        fi
    fi
    echo ""
}

# Initialize Docker/Colima setup
init_docker() {
    check_docker_colima
    ensure_colima_running
}

