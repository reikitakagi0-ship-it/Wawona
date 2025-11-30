#!/bin/bash
# update-dependencies.sh
# Updates dependencies while preserving patches

set -e
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES_DIR="${ROOT_DIR}/patches"

echo "Updating dependencies with patch preservation..."

# Function to update a dependency
update_dependency() {
    local dep_name=$1
    local dep_dir="${ROOT_DIR}/dependencies/${dep_name}"
    local patches_dir="${PATCHES_DIR}/${dep_name}"
    
    if [ ! -d "$dep_dir" ]; then
        echo "Warning: ${dep_name} not found, skipping..."
        return
    fi
    
    echo "Updating ${dep_name}..."
    cd "$dep_dir"
    
    # Stash local changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "Stashing local changes..."
        git stash push -m "Wawona local changes before update $(date +%Y-%m-%d)"
    fi
    
    # Get current branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Fetch upstream
    if git remote | grep -q upstream; then
        git fetch upstream
        git merge upstream/${current_branch} || git merge upstream/main || git merge upstream/master
    else
        git pull origin ${current_branch} || git pull origin main || git pull origin master
    fi
    
    # Apply patches
    if [ -d "$patches_dir" ] && [ -n "$(ls -A $patches_dir/*.patch 2>/dev/null)" ]; then
        echo "Applying patches..."
        for patch in "$patches_dir"/*.patch; do
            if [ -f "$patch" ]; then
                echo "Applying $(basename $patch)..."
                git apply "$patch" || {
                    echo "Warning: Patch $(basename $patch) failed to apply"
                    echo "You may need to resolve conflicts manually"
                }
            fi
        done
    fi
    
    # Restore stashed changes if any
    if git stash list | grep -q "Wawona local changes"; then
        echo "Restoring stashed changes..."
        git stash pop || {
            echo "Warning: Could not restore stashed changes"
            echo "Check git stash list and resolve manually"
        }
    fi
    
    echo "✓ ${dep_name} updated"
}

# Update all dependencies
for dep in wayland waypipe kosmickrisp pixman libffi epoll-shim lz4 zstd xkbcommon weston; do
    update_dependency "$dep"
done

echo ""
echo "Dependency update complete!"
echo ""
echo "Next steps:"
echo "1. Test builds: make ios-wayland && make kosmickrisp"
echo "2. Verify patches applied correctly"
echo "3. Resolve any conflicts"
echo "4. Update patches if needed: git format-patch upstream/main"

