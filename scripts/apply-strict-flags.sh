#!/bin/bash
# apply-strict-flags.sh
# Applies strict compilation flags to all build scripts

set -e

STRICT_C_FLAGS="-Wall -Wextra -Wpedantic -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC"

echo "Applying strict compilation flags to all install scripts..."

for script in scripts/install-*-ios.sh; do
    if [ -f "$script" ]; then
        echo "Updating $script..."
        # Check if already has strict flags
        if ! grep -q "Werror" "$script"; then
            # Add strict flags to meson setup commands
            sed -i.bak 's/meson setup/meson setup -Dc_args="'"$STRICT_C_FLAGS"'" /g' "$script"
            echo "  ✓ Added strict flags"
        else
            echo "  ⊙ Already has strict flags"
        fi
    fi
done

echo "Done!"

