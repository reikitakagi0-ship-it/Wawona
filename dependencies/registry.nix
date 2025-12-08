# Dependency Registry
#
# Add your dependencies here. Each dependency can specify:
#   - source: "github" or "gitlab" (defaults to "github")
#   - owner, repo: Repository owner and name
#   - rev/tag/branch: Version specification
#   - platforms: Which platforms to build for (ios, macos, android)
#   - buildSystem: Build system to use (cmake, meson, autotools, cargo/rust, etc.)
#   - patches: Platform-specific patches (paths relative to ./patches/)
#   - buildFlags: Platform-specific build flags
#
# Patches are applied using Nix's built-in patching mechanisms:
#   - File paths in patches array are applied before configurePhase
#   - Use postPatch for inline substitutions (see build.nix)
#
# Example:
#   wayland = {
#     source = "gitlab";  # or "github" (default)
#     owner = "wayland";
#     repo = "wayland";
#     rev = "abc123...";
#     platforms = [ "ios" "macos" "android" ];
#     buildSystem = "meson";
#     buildFlags = {
#       ios = [ "-Dlibraries=false" ];
#       macos = [ "-Dlibraries=false" ];
#       android = [ "-Dlibraries=false" ];
#     };
#     patches = {
#       ios = [ ./patches/wayland/ios-remove-signalfd.patch ];
#       macos = [ ./patches/wayland/macos-epoll-shim.patch ];
#     };
#   };

{
  # Wayland - Core Wayland protocol library
  # Official repo: https://gitlab.freedesktop.org/wayland/wayland
  wayland = {
    source = "gitlab";
    owner = "wayland";
    repo = "wayland";
    # Use latest stable release tag (update as needed)
    tag = "1.23.0";
    sha256 = "sha256-oK0Z8xO2ILuySGZS0m37ZF0MOyle2l8AXb0/6wai0/w=";
    platforms = [ "ios" "macos" "android" ];
    buildSystem = "meson";
    buildFlags = {
      ios = [
        "-Dlibraries=false"
        "-Ddocumentation=false"
        "-Dtests=false"
      ];
      macos = [
        "-Dlibraries=false"
        "-Ddocumentation=false"
        "-Dtests=false"
      ];
      android = [
        "-Dlibraries=false"
        "-Ddocumentation=false"
        "-Dtests=false"
      ];
    };
    # Patches will be added when needed - for now build without patches
    patches = {
      ios = [];
      macos = [];
      android = [];
    };
  };

  # Waypipe - Network transparency for Wayland applications (Rust implementation)
  # Official repo: https://gitlab.freedesktop.org/mstoeckl/waypipe
  # Note: Waypipe was rewritten in Rust (version 0.10.0+)
  waypipe = {
    source = "gitlab";
    owner = "mstoeckl";
    repo = "waypipe";
    # Use latest release tag (update as needed)
    tag = "0.10.5";  # Update to actual tag/rev
    platforms = [ "ios" "macos" "android" ];
    buildSystem = "cargo";  # Rust/Cargo build system
    # Rust-specific configuration
    cargoLock = null;  # Will be generated or provided
    cargoSha256 = null;  # Will be computed during build
    buildFlags = {
      ios = [
        # Rust build flags for iOS
        "--target=aarch64-apple-ios"
        "--features=vulkan"  # Enable Vulkan support (requires KosmicKrisp)
      ];
      macos = [
        # Rust build flags for macOS
        "--target=aarch64-apple-darwin"
        "--features=vulkan"  # Enable Vulkan support (requires KosmicKrisp)
      ];
      android = [
        # Rust build flags for Android
        "--target=aarch64-linux-android"
        "--features=vulkan,dmabuf"  # Enable Vulkan and DMA-BUF on Android
      ];
    };
    patches = {
      ios = [
        # Ensure waypipe uses KosmicKrisp Vulkan driver on iOS
        ./patches/waypipe/ios-kosmickrisp-vulkan.patch
      ];
      macos = [
        # Ensure waypipe uses KosmicKrisp Vulkan driver on macOS
        ./patches/waypipe/macos-kosmickrisp-vulkan.patch
      ];
      android = [
        # Android-specific adjustments for gralloc/DMA-BUF
        ./patches/waypipe/android-gralloc-support.patch
      ];
    };
  };

  # Mesa with KosmicKrisp - Vulkan-to-Metal driver for Apple Silicon
  # Mesa source: https://gitlab.freedesktop.org/mesa/mesa
  # KosmicKrisp is a Vulkan driver integrated into Mesa
  mesa-kosmickrisp = {
    source = "gitlab";
    owner = "mesa";
    repo = "mesa";
    # Use latest stable release tag (update as needed)
    tag = "24.3.0";  # Update to actual tag/rev
    platforms = [ "ios" "macos" ];
    buildSystem = "meson";
    buildFlags = {
      ios = [
        "-Dvulkan-drivers=kosmickrisp"
        "-Dgallium-drivers="  # Disable Gallium drivers (we only need Vulkan)
        "-Dplatforms="  # Disable platform backends (we'll use Metal directly)
        "-Ddri-drivers="  # Disable DRI drivers
        "-Dglx=disabled"  # Disable GLX
        "-Degl=disabled"  # Disable EGL
        "-Dgbm=disabled"  # Disable GBM
        "-Dtools="  # Disable tools
        "-Dvulkan-beta=true"  # Enable Vulkan beta extensions
        "-Dbuildtype=release"
      ];
      macos = [
        "-Dvulkan-drivers=kosmickrisp"
        "-Dgallium-drivers="  # Disable Gallium drivers
        "-Dplatforms="  # Disable platform backends
        "-Ddri-drivers="  # Disable DRI drivers
        "-Dglx=disabled"  # Disable GLX
        "-Degl=disabled"  # Disable EGL
        "-Dgbm=disabled"  # Disable GBM
        "-Dtools="  # Disable tools
        "-Dvulkan-beta=true"  # Enable Vulkan beta extensions
        "-Dbuildtype=release"
      ];
    };
    patches = {
      ios = [
        # iOS-specific Metal/Vulkan integration patches
        ./patches/kosmickrisp-vulkan/ios-metal-integration.patch
      ];
      macos = [
        # macOS-specific Metal/Vulkan integration patches (if needed)
        ./patches/kosmickrisp-vulkan/macos-metal-integration.patch
      ];
    };
  };
}
