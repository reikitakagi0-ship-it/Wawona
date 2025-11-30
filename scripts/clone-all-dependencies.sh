#!/bin/bash

# clone-all-dependencies.sh
# Clones all dependencies needed for iOS and macOS builds

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="${ROOT_DIR}/dependencies"

mkdir -p "${DEPS_DIR}"

echo "Cloning all dependencies..."
echo "============================"

# Function to clone if not exists
clone_if_missing() {
    local name="$1"
    local url="$2"
    local dir="${DEPS_DIR}/${name}"
    local branch="${3:-}"
    
    if [ -d "${dir}" ]; then
        echo "✓ ${name} already cloned"
        return 0
    fi
    
    echo "Cloning ${name}..."
    if [ -n "$branch" ]; then
        git clone --depth 1 --branch "$branch" "$url" "${dir}" || git clone --depth 1 "$url" "${dir}"
    else
        git clone --depth 1 "$url" "${dir}"
    fi
    echo "✓ ${name} cloned"
}

# Foundational dependencies
clone_if_missing "epoll-shim" "https://github.com/jiixyj/epoll-shim.git"
clone_if_missing "zlib" "https://github.com/madler/zlib.git"
clone_if_missing "libffi" "https://github.com/libffi/libffi.git"
clone_if_missing "pcre2" "https://github.com/PCRE2Project/pcre2.git"
clone_if_missing "gettext" "https://git.savannah.gnu.org/git/gettext.git"

# Image/Format libraries
clone_if_missing "expat" "https://github.com/libexpat/libexpat.git"
clone_if_missing "libxml2" "https://gitlab.gnome.org/GNOME/libxml2.git"
clone_if_missing "libpng" "https://github.com/glennrp/libpng.git"

# OpenMP (from LLVM)
if [ ! -d "${DEPS_DIR}/llvm-project" ]; then
    echo "Cloning OpenMP from LLVM..."
    git clone --depth 1 --branch release/18.x https://github.com/llvm/llvm-project.git "${DEPS_DIR}/llvm-project"
    echo "✓ OpenMP source available (in llvm-project/openmp)"
else
    echo "✓ OpenMP source already available (in llvm-project/openmp)"
fi

# Font/Graphics libraries
clone_if_missing "freetype" "https://gitlab.freedesktop.org/freetype/freetype.git"
clone_if_missing "fontconfig" "https://gitlab.freedesktop.org/fontconfig/fontconfig.git"
clone_if_missing "pixman" "https://gitlab.freedesktop.org/pixman/pixman.git"
clone_if_missing "cairo" "https://gitlab.freedesktop.org/cairo/cairo.git"
clone_if_missing "harfbuzz" "https://github.com/harfbuzz/harfbuzz.git"
clone_if_missing "fribidi" "https://github.com/fribidi/fribidi.git"

# GLib ecosystem
clone_if_missing "glib" "https://gitlab.gnome.org/GNOME/glib.git"
clone_if_missing "pango" "https://gitlab.gnome.org/GNOME/pango.git"
clone_if_missing "atk" "https://gitlab.gnome.org/GNOME/atk.git"
clone_if_missing "gdk-pixbuf" "https://gitlab.gnome.org/GNOME/gdk-pixbuf.git"
clone_if_missing "gtk" "https://gitlab.gnome.org/GNOME/gtk.git"

# Wayland ecosystem
clone_if_missing "wayland-protocols" "https://gitlab.freedesktop.org/wayland/wayland-protocols.git"
clone_if_missing "xkbcommon" "https://github.com/xkbcommon/libxkbcommon.git"
clone_if_missing "wayland" "https://gitlab.freedesktop.org/wayland/wayland.git"

# Multimedia libraries
clone_if_missing "ffmpeg" "https://git.ffmpeg.org/ffmpeg.git"

echo ""
echo "✓ All dependencies cloned to ${DEPS_DIR}"

