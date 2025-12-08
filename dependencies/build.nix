# Build module for dependencies
#
# This module provides functions to build dependencies for iOS, macOS, and Android
# using Nix cross-compilation.

{ lib, pkgs, stdenv, buildPackages }:

let
  # Import the dependency registry
  registry = import ./registry.nix;
  
  # iOS cross-compilation setup
  iosPkgs = pkgs.pkgsCross.iphone64;
  
  # Android cross-compilation setup (aarch64-android-prebuilt)
  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
  
  # Helper to get build system
  getBuildSystem = entry:
    entry.buildSystem or "autotools";
  
  # Helper to get source type
  getSource = entry: entry.source or "github";
  
  # Helper to fetch source from GitHub or GitLab
  fetchSource = entry:
    let
      source = getSource entry;
      sha256 = entry.sha256 or lib.fakeHash;
    in
    if source == "gitlab" then
      (
        if lib.hasAttr "tag" entry then
          # For tags, use fetchgit which handles them better
          pkgs.fetchgit {
            url = "https://gitlab.freedesktop.org/${entry.owner}/${entry.repo}.git";
            rev = "refs/tags/${entry.tag}";
            sha256 = sha256;
          }
        else if lib.hasAttr "rev" entry then
          pkgs.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.rev;
            sha256 = sha256;
          }
        else
          throw "GitLab source requires either 'rev' or 'tag'"
      )
    else
      (
        # GitHub
        if lib.hasAttr "tag" entry then
          pkgs.fetchFromGitHub {
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.tag;
            sha256 = sha256;
          }
        else if lib.hasAttr "rev" entry then
          pkgs.fetchFromGitHub {
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.rev;
            sha256 = sha256;
          }
        else
          throw "GitHub source requires either 'rev' or 'tag'"
      );
  
  # Build a dependency for iOS
  buildForIOS = name: entry:
    let
      src = fetchSource entry;
      
      buildSystem = getBuildSystem entry;
      buildFlags = entry.buildFlags.ios or [];
      patches = entry.patches.ios or [];
      
      # Determine build inputs based on dependency name
      waylandDeps = with iosPkgs; [ expat libffi libxml2 ];
      defaultDeps = [];
      depInputs = if name == "wayland" then waylandDeps else defaultDeps;
      
      # iOS-specific build configuration
      iosStdenv = iosPkgs.stdenv;
    in
      if buildSystem == "cmake" then
        iosPkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          
          nativeBuildInputs = with iosPkgs; [
            cmake
            pkg-config
          ];
          
          buildInputs = depInputs;
          
          cmakeFlags = [
            "-DCMAKE_SYSTEM_NAME=iOS"
            "-DCMAKE_OSX_ARCHITECTURES=arm64"
            "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0"
          ] ++ buildFlags;
          
          installPhase = ''
            runHook preInstall
            make install DESTDIR=$out
            runHook postInstall
          '';
        }
      else if buildSystem == "meson" then
        iosPkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          src = src;
          patches = lib.filter (p: p != null && builtins.pathExists (toString p)) patches;
          
          nativeBuildInputs = with iosPkgs; [
            meson
            ninja
            pkg-config
            python3
            bison
            flex
          ];
          
          buildInputs = depInputs;
          
          # Meson setup command
          configurePhase = ''
            runHook preConfigure
            meson setup build \
              --prefix=$out \
              --libdir=$out/lib \
              --cross-file=${iosPkgs.stdenv.cc.targetPrefix} \
              ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
            runHook postConfigure
          '';
          
          buildPhase = ''
            runHook preBuild
            meson compile -C build
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            meson install -C build
            runHook postInstall
          '';
        }
      else if buildSystem == "cargo" || buildSystem == "rust" then
        # Rust/Cargo build for iOS
        # Note: Dependencies like Mesa/KosmicKrisp should be passed via buildInputs
        # when building waypipe. This will be handled at the flake level.
        iosPkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          
          cargoLock = entry.cargoLock or null;
          cargoSha256 = entry.cargoSha256 or lib.fakeSha256;
          
          nativeBuildInputs = with iosPkgs; [
            pkg-config
          ];
          
          buildInputs = with iosPkgs; [
            # Add iOS-specific Rust dependencies here
            # Mesa/KosmicKrisp will be added as a dependency when building waypipe
          ];
          
          # Set environment variables for Vulkan/KosmicKrisp if building waypipe
          # The actual Mesa dependency will be injected at the flake level
          preBuild = lib.optionalString (name == "waypipe") ''
            # Vulkan/KosmicKrisp environment will be set by the build system
            # VULKAN_SDK and VK_ICD_FILENAMES should be set by the caller
          '';
          
          # Additional post-patch commands can be added here if needed
          # Patches are automatically applied via the patches attribute
        }
      else
        # Default to autotools
        iosPkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          
          nativeBuildInputs = with iosPkgs; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          
          configureFlags = buildFlags;
        };
  
  # Build a dependency for macOS
  buildForMacOS = name: entry:
    let
      src = fetchSource entry;
      
      buildSystem = getBuildSystem entry;
      buildFlags = entry.buildFlags.macos or [];
      patches = entry.patches.macos or [];
      
      # Determine build inputs based on dependency name
      waylandDeps = with pkgs; [ expat libffi libxml2 ];
      defaultDeps = [];
      depInputs = if name == "wayland" then waylandDeps else defaultDeps;
    in
      if buildSystem == "cmake" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-macos";
          inherit src patches;
          
          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
          ];
          
          cmakeFlags = buildFlags;
        }
      else if buildSystem == "meson" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-macos";
          src = src;
          patches = lib.filter (p: p != null && builtins.pathExists (toString p)) patches;
          
          nativeBuildInputs = with pkgs; [
            meson
            ninja
            pkg-config
            python3
            bison
            flex
          ];
          
          buildInputs = depInputs;
          
          # Meson setup command
          configurePhase = ''
            runHook preConfigure
            meson setup build \
              --prefix=$out \
              --libdir=$out/lib \
              ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
            runHook postConfigure
          '';
          
          buildPhase = ''
            runHook preBuild
            meson compile -C build
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            meson install -C build
            runHook postInstall
          '';
        }
      else if buildSystem == "cargo" || buildSystem == "rust" then
        # Rust/Cargo build for macOS
        # Note: Dependencies like Mesa/KosmicKrisp should be passed via buildInputs
        # when building waypipe. This will be handled at the flake level.
        pkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          
          cargoLock = entry.cargoLock or null;
          cargoSha256 = entry.cargoSha256 or lib.fakeSha256;
          
          nativeBuildInputs = with pkgs; [
            pkg-config
          ];
          
          buildInputs = with pkgs; [
            # Add macOS-specific Rust dependencies here
            # Mesa/KosmicKrisp will be added as a dependency when building waypipe
          ];
          
          # Set environment variables for Vulkan/KosmicKrisp if building waypipe
          # The actual Mesa dependency will be injected at the flake level
          preBuild = lib.optionalString (name == "waypipe") ''
            # Vulkan/KosmicKrisp environment will be set by the build system
            # VULKAN_SDK, VK_ICD_FILENAMES, and DYLD_LIBRARY_PATH should be set by the caller
          '';
          
          # Additional post-patch commands can be added here if needed
          # Patches are automatically applied via the patches attribute
        }
      else
        # Default to autotools
        pkgs.stdenv.mkDerivation {
          name = "${name}-macos";
          inherit src patches;
          
          nativeBuildInputs = with pkgs; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          
          configureFlags = buildFlags;
        };
  
  # Build a dependency for Android
  # Note: Android NDK cross-compilation from macOS may not be fully supported
  buildForAndroid = name: entry:
    let
      src = fetchSource entry;
      
      buildSystem = getBuildSystem entry;
      buildFlags = entry.buildFlags.android or [];
      patches = entry.patches.android or [];
      
      # Determine build inputs based on dependency name
      waylandDeps = with androidPkgs; [ expat libffi libxml2 ];
      defaultDeps = [];
      depInputs = if name == "wayland" then waylandDeps else defaultDeps;
      
      # Android-specific build configuration
      androidStdenv = androidPkgs.stdenv;
    in
      if buildSystem == "cmake" then
        androidPkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          
          nativeBuildInputs = with androidPkgs; [
            cmake
            pkg-config
          ];
          
          buildInputs = with androidPkgs; [
            # Add common Android dependencies here
          ];
          
          cmakeFlags = [
            "-DCMAKE_SYSTEM_NAME=Android"
            "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
            "-DCMAKE_ANDROID_NDK=${androidPkgs.stdenv.cc}"
          ] ++ buildFlags;
        }
      else if buildSystem == "meson" then
        androidPkgs.stdenv.mkDerivation {
          name = "${name}-android";
          src = src;
          patches = lib.filter (p: p != null && builtins.pathExists (toString p)) patches;
          
          nativeBuildInputs = with androidPkgs; [
            meson
            ninja
            pkg-config
          ];
          
          mesonFlags = [
            "--cross-file=${androidPkgs.stdenv.cc.targetPrefix}"
          ] ++ buildFlags;
        }
      else if buildSystem == "cargo" || buildSystem == "rust" then
        # Rust/Cargo build for Android
        androidPkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          
          cargoLock = entry.cargoLock or null;
          cargoSha256 = entry.cargoSha256 or lib.fakeSha256;
          
          nativeBuildInputs = with androidPkgs; [
            pkg-config
          ];
          
          buildInputs = with androidPkgs; [
            # Add Android-specific Rust dependencies here
          ];
          
          # Additional post-patch commands can be added here if needed
          # Patches are automatically applied via the patches attribute
        }
      else
        # Default to autotools
        androidPkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          
          nativeBuildInputs = with androidPkgs; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          
          configureFlags = buildFlags;
        };
  
  # Build all dependencies for a platform
  buildAllForPlatform = platform:
    lib.mapAttrs (name: entry:
      if platform == "ios" then buildForIOS name entry
      else if platform == "macos" then buildForMacOS name entry
      else if platform == "android" then buildForAndroid name entry
      else throw "Unknown platform: ${platform}"
    ) (lib.filterAttrs (_: entry:
      let platforms = entry.platforms or [ "ios" "macos" "android" ];
      in lib.elem platform platforms
    ) registry);
in
{
  inherit buildForIOS buildForMacOS buildForAndroid buildAllForPlatform;
  
  # Convenience functions
  ios = buildAllForPlatform "ios";
  macos = buildAllForPlatform "macos";
  android = buildAllForPlatform "android";
}
