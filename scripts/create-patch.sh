#!/bin/bash
# create-patch.sh
# Creates a patch file for a dependency modification

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <dependency-name> <patch-name>"
    echo "Example: $0 wayland ios-compat"
    exit 1
fi

DEP_NAME=$1
PATCH_NAME=$2
DEP_DIR="dependencies/${DEP_NAME}"
PATCHES_DIR="patches/${DEP_NAME}"

if [ ! -d "$DEP_DIR" ]; then
    echo "Error: Dependency ${DEP_NAME} not found"
    exit 1
fi

mkdir -p "$PATCHES_DIR"

cd "$DEP_DIR"

# Check if we have upstream remote
if git remote | grep -q upstream; then
    UPSTREAM_BRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} | sed 's/.*\///')
    BASE_BRANCH="upstream/${UPSTREAM_BRANCH}"
else
    BASE_BRANCH="origin/main"
fi

# Create patch
echo "Creating patch ${PATCH_NAME}.patch..."
git format-patch ${BASE_BRANCH} --stdout > "../../${PATCHES_DIR}/${PATCH_NAME}.patch"

echo "Patch created: ${PATCHES_DIR}/${PATCH_NAME}.patch"
echo ""
echo "To apply this patch later:"
echo "  cd ${DEP_DIR}"
echo "  git apply ../../${PATCHES_DIR}/${PATCH_NAME}.patch"
