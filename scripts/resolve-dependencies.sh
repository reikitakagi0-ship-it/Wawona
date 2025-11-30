#!/bin/bash

# resolve-dependencies.sh
# Resolves all transitive dependencies recursively and determines build order

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR_IOS="${ROOT_DIR}/build/ios-install"
INSTALL_DIR_MACOS="${ROOT_DIR}/build/macos-install"
PKG_CONFIG_PATH_IOS="${INSTALL_DIR_IOS}/lib/pkgconfig:${INSTALL_DIR_IOS}/libdata/pkgconfig"
PKG_CONFIG_PATH_MACOS="${INSTALL_DIR_MACOS}/lib/pkgconfig:${INSTALL_DIR_MACOS}/libdata/pkgconfig"

# Dependency database - maps package name to install script and dependencies
declare -A DEPENDENCY_SCRIPTS
declare -A DEPENDENCY_DEPS
declare -A DEPENDENCY_BUILD_ORDER

# Initialize with known dependencies
init_dependency_db() {
    # Core dependencies (no dependencies)
    DEPENDENCY_SCRIPTS["epoll-shim"]="install-epoll-shim"
    DEPENDENCY_DEPS["epoll-shim"]=""
    
    DEPENDENCY_SCRIPTS["libffi"]="install-libffi"
    DEPENDENCY_DEPS["libffi"]=""
    
    DEPENDENCY_SCRIPTS["zlib"]="install-zlib"
    DEPENDENCY_DEPS["zlib"]=""
    
    DEPENDENCY_SCRIPTS["pcre2"]="install-pcre2"
    DEPENDENCY_DEPS["pcre2"]=""
    
    DEPENDENCY_SCRIPTS["gettext"]="install-gettext"
    DEPENDENCY_DEPS["gettext"]=""
    
    # Dependencies with known deps
    DEPENDENCY_SCRIPTS["expat"]="install-expat"
    DEPENDENCY_DEPS["expat"]=""
    
    DEPENDENCY_SCRIPTS["libxml2"]="install-libxml2"
    DEPENDENCY_DEPS["libxml2"]="zlib"
    
    DEPENDENCY_SCRIPTS["openmp"]="install-openmp"
    DEPENDENCY_DEPS["openmp"]=""
    
    DEPENDENCY_SCRIPTS["pixman"]="install-pixman"
    DEPENDENCY_DEPS["pixman"]="libffi"
    
    DEPENDENCY_SCRIPTS["freetype"]="install-freetype"
    DEPENDENCY_DEPS["freetype"]="zlib"
    
    DEPENDENCY_SCRIPTS["fontconfig"]="install-fontconfig"
    DEPENDENCY_DEPS["fontconfig"]="freetype expat"
    
    DEPENDENCY_SCRIPTS["libpng"]="install-libpng"
    DEPENDENCY_DEPS["libpng"]="zlib"
    
    DEPENDENCY_SCRIPTS["cairo"]="install-cairo"
    DEPENDENCY_DEPS["cairo"]="pixman fontconfig libpng"
    
    DEPENDENCY_SCRIPTS["fribidi"]="install-fribidi"
    DEPENDENCY_DEPS["fribidi"]=""
    
    DEPENDENCY_SCRIPTS["harfbuzz"]="install-harfbuzz"
    DEPENDENCY_DEPS["harfbuzz"]="freetype"
    
    DEPENDENCY_SCRIPTS["glib"]="install-glib"
    DEPENDENCY_DEPS["glib"]="pcre2 gettext libffi zlib"
    
    DEPENDENCY_SCRIPTS["pango"]="install-pango"
    DEPENDENCY_DEPS["pango"]="glib cairo harfbuzz fribidi"
    
    DEPENDENCY_SCRIPTS["atk"]="install-atk"
    DEPENDENCY_DEPS["atk"]="glib"
    
    DEPENDENCY_SCRIPTS["gdk-pixbuf"]="install-gdk-pixbuf"
    DEPENDENCY_DEPS["gdk-pixbuf"]="glib libpng"
    
    DEPENDENCY_SCRIPTS["gtk+3.0"]="install-gtk"
    DEPENDENCY_DEPS["gtk+3.0"]="glib cairo pango atk gdk-pixbuf"
    
    DEPENDENCY_SCRIPTS["wayland"]="install-wayland"
    DEPENDENCY_DEPS["wayland"]="libffi expat libxml2"
}

# Parse pkg-config file to find dependencies
parse_pkgconfig_deps() {
    local pc_file="$1"
    local deps=""
    
    if [ ! -f "$pc_file" ]; then
        return
    fi
    
    # Extract Requires and Requires.private
    local requires=$(grep -E "^Requires:" "$pc_file" | sed 's/Requires://' | tr ',' ' ' | xargs)
    local requires_private=$(grep -E "^Requires\.private:" "$pc_file" | sed 's/Requires.private://' | tr ',' ' ' | xargs)
    
    echo "$requires $requires_private" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

# Resolve dependencies recursively
resolve_deps() {
    local package="$1"
    local platform="$2"  # ios or macos
    local visited="$3"
    local result=""
    
    # Check if already visited
    if [[ "$visited" == *"|$package|"* ]]; then
        return
    fi
    visited="${visited}|$package|"
    
    # Get dependencies from database
    local deps="${DEPENDENCY_DEPS[$package]}"
    
    # Also check pkg-config if available
    local install_dir=""
    local pkg_config_path=""
    if [ "$platform" = "ios" ]; then
        install_dir="$INSTALL_DIR_IOS"
        pkg_config_path="$PKG_CONFIG_PATH_IOS"
    else
        install_dir="$INSTALL_DIR_MACOS"
        pkg_config_path="$PKG_CONFIG_PATH_MACOS"
    fi
    
    # Check for .pc file
    local pc_file="${install_dir}/lib/pkgconfig/${package}.pc"
    if [ -f "$pc_file" ]; then
        local pc_deps=$(parse_pkgconfig_deps "$pc_file")
        deps="$deps $pc_deps"
    fi
    
    # Resolve each dependency
    for dep in $deps; do
        # Remove version constraints (e.g., "glib-2.0" -> "glib")
        local dep_name=$(echo "$dep" | sed 's/-[0-9].*$//' | sed 's/^[0-9]*\.//')
        
        # Normalize package names
        case "$dep_name" in
            "glib-2.0"|"glib2") dep_name="glib" ;;
            "gtk+-3.0"|"gtk+3") dep_name="gtk+3.0" ;;
            "libffi") dep_name="libffi" ;;
            "pixman-1") dep_name="pixman" ;;
            "cairo") dep_name="cairo" ;;
            "pango") dep_name="pango" ;;
            "harfbuzz") dep_name="harfbuzz" ;;
            "fribidi") dep_name="fribidi" ;;
            "freetype2"|"freetype") dep_name="freetype" ;;
            "fontconfig") dep_name="fontconfig" ;;
            "libpng16"|"libpng") dep_name="libpng" ;;
            "zlib") dep_name="zlib" ;;
            "pcre2") dep_name="pcre2" ;;
            "gettext") dep_name="gettext" ;;
            "expat") dep_name="expat" ;;
            "libxml-2.0"|"libxml2") dep_name="libxml2" ;;
            "openmp") dep_name="openmp" ;;
            "atk") dep_name="atk" ;;
            "gdk-pixbuf-2.0"|"gdk-pixbuf") dep_name="gdk-pixbuf" ;;
        esac
        
        if [ -n "$dep_name" ] && [ -n "${DEPENDENCY_SCRIPTS[$dep_name]}" ]; then
            result="$result $(resolve_deps "$dep_name" "$platform" "$visited")"
            result="$result $dep_name"
        fi
    done
    
    echo "$result" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

# Topological sort for build order
topological_sort() {
    local packages="$1"
    local sorted=""
    local visited=""
    
    # Simple topological sort (Kahn's algorithm)
    declare -A in_degree
    declare -A edges
    
    # Initialize
    for pkg in $packages; do
        in_degree[$pkg]=0
    done
    
    # Build graph
    for pkg in $packages; do
        local deps="${DEPENDENCY_DEPS[$pkg]}"
        for dep in $deps; do
            local dep_name=$(echo "$dep" | sed 's/-[0-9].*$//')
            if [[ "$packages" == *"$dep_name"* ]]; then
                in_degree[$pkg]=$((${in_degree[$pkg]} + 1))
                edges["$dep_name"]="${edges[$dep_name]} $pkg"
            fi
        done
    done
    
    # Find nodes with no incoming edges
    local queue=""
    for pkg in $packages; do
        if [ "${in_degree[$pkg]}" -eq 0 ]; then
            queue="$queue $pkg"
        fi
    done
    
    # Process queue
    while [ -n "$queue" ]; do
        local current=$(echo "$queue" | awk '{print $1}')
        queue=$(echo "$queue" | sed "s/^$current //")
        sorted="$sorted $current"
        
        # Process edges from current
        local targets="${edges[$current]}"
        for target in $targets; do
            in_degree[$target]=$((${in_degree[$target]} - 1))
            if [ "${in_degree[$target]}" -eq 0 ]; then
                queue="$queue $target"
            fi
        done
    done
    
    echo "$sorted" | xargs
}

# Main function
main() {
    local platform="${1:-ios}"
    local target_packages="${2:-pixman wayland}"
    
    echo "Resolving dependencies for platform: $platform"
    echo "Target packages: $target_packages"
    echo ""
    
    init_dependency_db
    
    # Resolve all dependencies
    local all_deps=""
    for pkg in $target_packages; do
        local resolved=$(resolve_deps "$pkg" "$platform" "")
        all_deps="$all_deps $resolved $pkg"
    done
    
    # Remove duplicates and sort
    all_deps=$(echo "$all_deps" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')
    
    # Topological sort
    local build_order=$(topological_sort "$all_deps")
    
    echo "Build order:"
    echo "============"
    local i=1
    for pkg in $build_order; do
        echo "$i. $pkg"
        i=$((i + 1))
    done
    echo ""
    
    # Generate install commands
    echo "Install commands:"
    echo "================="
    for pkg in $build_order; do
        local script="${DEPENDENCY_SCRIPTS[$pkg]}"
        if [ -n "$script" ]; then
            # Check if the script supports the platform flag or has a specific name
            if [ -f "./scripts/${script}.sh" ]; then
                echo "./scripts/${script}.sh --platform ${platform}"
            elif [ -f "./scripts/${script}-${platform}.sh" ]; then
                echo "./scripts/${script}-${platform}.sh"
            else
                echo "# Warning: Script for $pkg not found: ./scripts/${script}.sh or ./scripts/${script}-${platform}.sh"
            fi
        fi
    done
}

main "$@"

