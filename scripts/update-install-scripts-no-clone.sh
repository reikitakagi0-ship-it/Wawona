#!/bin/bash

# Helper script to update all install scripts to remove cloning

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${ROOT_DIR}/scripts"

# Function to replace cloning logic with check
update_script() {
    local script="$1"
    local dep_name="$2"
    local dep_dir_var="${3:-${dep_name^^}_DIR}"
    
    if [ ! -f "$script" ]; then
        return
    fi
    
    # Replace cloning block with check
    sed -i.bak \
        -e "/# Clone.*if not exists/,/^fi$/c\\
# Check if dependency is cloned\\
if [ ! -d \"\${${dep_dir_var}}\" ]; then\\
    echo \"Error: ${dep_name} not found at \${${dep_dir_var}}\"\\
    echo \"Run: ./scripts/clone-all-dependencies.sh first\"\\
    exit 1\\
fi" \
        "$script"
    
    # Also handle "Clone X if not exists" patterns
    sed -i.bak \
        -e "s/^# Clone ${dep_name} if not exists$/# Check if dependency is cloned/" \
        -e "s/^if \[ ! -d \".*\" \]; then$/# Check if dependency is cloned\nif [ ! -d \"\${${dep_dir_var}}\" ]; then/" \
        -e "s/^    echo \"Cloning ${dep_name}...\"$/    echo \"Error: ${dep_name} not found at \${${dep_dir_var}}\"/" \
        -e "s/^    git clone.*$/    echo \"Run: .\/scripts\/clone-all-dependencies.sh first\"/" \
        "$script"
}

# Update all scripts
for script in install-*-ios.sh; do
    if [ -f "$script" ]; then
        dep_name=$(echo "$script" | sed 's/install-\(.*\)-ios.sh/\1/')
        echo "Updating $script for $dep_name..."
        # Simple replacement - remove git clone blocks
        perl -i.bak -0pe 's/# Clone.*?if \[ ! -d.*?\n.*?git clone.*?\nfi\n\n/# Check if dependency is cloned\nif [ ! -d "${'${dep_name^^}'_DIR}" ]; then\n    echo "Error: '${dep_name}' not found at ${'${dep_name^^}'_DIR}"\n    echo "Run: .\/scripts\/clone-all-dependencies.sh first"\n    exit 1\nfi\n\n/g' "$script" 2>/dev/null || true
    fi
done

echo "Done updating scripts"

