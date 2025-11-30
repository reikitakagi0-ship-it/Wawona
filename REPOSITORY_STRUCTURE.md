# Wawona Repository Structure

This document describes the forward-thinking repository structure designed to scale efficiently as the project grows.

## Overview

The repository is organized to clearly separate:
- **Dependencies** - Upstream repositories (forks)
- **Compatibility Layers** - Platform-specific compatibility code
- **Stubs** - Minimal implementations for unsupported libraries
- **Native Code** - Platform-specific native implementations
- **Ported Code** - Code adapted from other platforms
- **Patches** - Modifications to dependencies

## Directory Structure

```
Wawona/
├── dependencies/          # Upstream dependency repositories (forks)
│   ├── wayland/          # Wayland protocol library
│   ├── waypipe/          # Wayland forwarding tool
│   ├── kosmickrisp/      # Mesa-based Vulkan driver
│   └── ...               # Other dependencies
│
├── scripts/              # Build and utility scripts
│   ├── install-*.sh      # Dependency installation scripts
│   └── ...
│
├── src/                   # Main source code (Unified iOS/macOS)
│   ├── applications/      # Application-specific code
│   │   ├── clients/       # Client applications
│   │   └── compositors/   # Compositor implementations
│   ├── compat/            # Compatibility layers (platform-specific)
│   │   ├── ios/           # iOS compatibility
│   │   └── macos/         # macOS compatibility
│   ├── protocols/         # Protocol implementations
│   ├── resources/         # App resources (bundles, plists)
│   ├── WawonaCompositor.m # Unified compositor backend
│   ├── main.m             # Unified entry point
│   └── ...
│
├── tests/                 # Test suite
│   ├── test-clients/      # Test client binaries
│   ├── test_client.c      # Main test client source
│   └── ...
```

## Key Principles

### 1. Clear Separation of Concerns

- **Dependencies** are separate from our code
- **Compatibility** layers are separate from native code
- **Stubs** are separate from full implementations
- **Native** code is separate from ported code

### 2. Platform-Specific Organization

- Each platform has its own directory structure
- Shared code is clearly identified
- Platform detection happens at build time

### 3. Scalability

- Easy to add new platforms
- Easy to add new dependencies
- Easy to add new compatibility layers
- Easy to track patches and modifications

### 4. Maintainability

- Clear documentation in each directory
- Patches are tracked separately
- Compatibility code is centralized
- Native code is organized by platform

## Usage Examples

### Adding iOS Compatibility Function

```bash
# Add to src/compat/ios/headers/ios_compat.h
# Update build system to include header
# Document in src/compat/ios/README.md
```

### Adding New Platform Stub

```bash
# Create src/compat/macos/stubs/<library>-<platform>/
# Add headers and implementations
# Document in src/compat/macos/stubs/README.md
```

### Adding Unified Source Code

```bash
# Add to src/
# Use #if TARGET_OS_IPHONE for iOS-specific logic
# Use #if !TARGET_OS_IPHONE for macOS-specific logic
```

### Creating Dependency Patch

```bash
# Make changes in dependencies/<dependency>/
# Create patch: git format-patch upstream/main
# Save to patches/<dependency>/
# Document in patches/README.md
```

## Migration Guide

To migrate existing code to this structure:

1. **Move compatibility headers** to `src/compat/ios/headers/`
2. **Move stubs** to `src/compat/macos/stubs/<library>-<platform>/`
3. **Organize source code** in `src/` (unified)
4. **Extract ported code** to `ports/`
5. **Create patches** for dependency modifications
6. **Update build system** to reference new paths
7. **Update documentation** to reflect new structure

## Benefits

- **Clarity**: Easy to find platform-specific code
- **Scalability**: Easy to add new platforms/features
- **Maintainability**: Clear organization and documentation
- **Collaboration**: Clear structure for contributors
- **Testing**: Easy to test platform-specific code
- **Documentation**: Self-documenting structure

## See Also

- `src/compat/ios/README.md` - iOS compatibility layer
- `src/compat/macos/stubs/README.md` - Platform stubs
- `ports/README.md` - Ported code
- `patches/README.md` - Dependency patches
