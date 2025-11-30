#!/bin/bash

# CALayerWayland Documentation Server
# Uses Node.js/Express to serve documentation with proper markdown rendering

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default port
DEFAULT_PORT=8080

# Parse port argument
if [ -z "$1" ]; then
    PORT=$DEFAULT_PORT
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    PORT=$1
else
    echo -e "${YELLOW}Usage: $0 [port]${NC}"
    echo "Example: $0 3000"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCS_DIR="$SCRIPT_DIR/docs"

echo -e "${GREEN}📚 CALayerWayland Documentation Server${NC}"
echo "======================================"
echo ""

# Check if docs directory exists
if [ ! -d "$DOCS_DIR" ]; then
    echo -e "${YELLOW}Error: docs/ directory not found!${NC}"
    exit 1
fi

cd "$DOCS_DIR"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    if ! command -v npm &> /dev/null; then
        echo -e "${YELLOW}Error: npm not found. Please install Node.js:${NC}"
        echo "  brew install node"
        exit 1
    fi
    npm install
    echo ""
fi

# Note: Markdown files are rendered dynamically in the browser
# No need to pre-convert to HTML - the server handles this via the marked library

# Check if port is in use and kill if necessary
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo -e "${YELLOW}Port $PORT is already in use, stopping existing process...${NC}"
    PID=$(lsof -Pi :$PORT -sTCP:LISTEN -t)
    kill -9 $PID 2>/dev/null
    echo -e "${GREEN}Stopped process $PID${NC}"
    # Give it a moment to release the port
    sleep 1
    echo ""
fi

echo -e "Serving directory: ${BLUE}$DOCS_DIR${NC}"
echo -e "Port: ${BLUE}$PORT${NC}"
echo ""
echo -e "${GREEN}Starting server...${NC}"
echo ""

# Start server with port
PORT=$PORT npm start

