# Build module for Wawona Compositor
#
# This module provides functions to build Wawona for iOS, macOS, and Android
# using Nix cross-compilation, including all dependencies.

{ lib, pkgs, stdenv, buildPackages, depsModule, buildModule, wawonaSrc }:

let
  # Get dependencies for each platform
  iosDeps = buildModule.ios;
  macosDeps = buildModule.macos;
  androidDeps = buildModule.android;
  
  # iOS cross-compilation setup
  iosPkgs = pkgs.pkgsCross.iphone64-darwin;
  
  # Android cross-compilation setup
  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
  
  # Helper to get dependency paths for a platform
  getDependencyPaths = platform: deps:
    let
      depList = lib.mapAttrsToList (name: pkg: pkg) deps;
    in
      depList;
  
  # Build Wawona for iOS
  buildWawonaIOS = let
    deps = getDependencyPaths "ios" iosDeps;
    wayland = iosDeps.wayland or null;
    mesa = iosDeps.mesa-kosmickrisp or null;
    waypipe = iosDeps.waypipe or null;
  in
    iosPkgs.stdenv.mkDerivation {
      pname = "wawona-ios";
      version = "1.0.0";
      src = wawonaSrc;
      
      nativeBuildInputs = with iosPkgs; [
        cmake
        pkg-config
        python3
      ];
      
      buildInputs = with iosPkgs; [
        # Add iOS dependencies here
      ] ++ lib.optional (wayland != null) wayland
        ++ lib.optional (mesa != null) mesa
        ++ lib.optional (waypipe != null) waypipe;
      
      cmakeFlags = [
        "-DCMAKE_SYSTEM_NAME=iOS"
        "-DCMAKE_OSX_ARCHITECTURES=arm64"
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0"
      ];
      
      # Set PKG_CONFIG_PATH for dependencies
      PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" (
        lib.filter (pkg: pkg != null) [ wayland mesa waypipe ]
      );
      
      # Set environment variables for Vulkan/KosmicKrisp
      preConfigure = lib.optionalString (mesa != null) ''
        export VULKAN_SDK=${mesa}
        export VK_ICD_FILENAMES=${mesa}/share/vulkan/icd.d/kosmickrisp_icd.json
      '';
    };
  
  # Build Wawona for macOS
  buildWawonaMacOS = let
    deps = getDependencyPaths "macos" macosDeps;
    wayland = macosDeps.wayland or null;
    mesa = macosDeps.mesa-kosmickrisp or null;
    waypipe = macosDeps.waypipe or null;
  in
    pkgs.stdenv.mkDerivation {
      pname = "wawona-macos";
      version = "1.0.0";
      src = wawonaSrc;
      
      nativeBuildInputs = with pkgs; [
        cmake
        pkg-config
        python3
      ];
      
      buildInputs = with pkgs; [
        # Add macOS dependencies here
      ] ++ lib.optional (wayland != null) wayland
        ++ lib.optional (mesa != null) mesa
        ++ lib.optional (waypipe != null) waypipe;
      
      cmakeFlags = [
        "-DCMAKE_BUILD_TYPE=Release"
      ];
      
      # Set PKG_CONFIG_PATH for dependencies
      PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" (
        lib.filter (pkg: pkg != null) [ wayland mesa waypipe ]
      );
      
      # Set environment variables for Vulkan/KosmicKrisp
      preConfigure = lib.optionalString (mesa != null) ''
        export VULKAN_SDK=${mesa}
        export VK_ICD_FILENAMES=${mesa}/share/vulkan/icd.d/kosmickrisp_icd.json
        export DYLD_LIBRARY_PATH=${mesa}/lib:$DYLD_LIBRARY_PATH
      '';
    };
  
  # Build Wawona for Android
  buildWawonaAndroid = let
    deps = getDependencyPaths "android" androidDeps;
    wayland = androidDeps.wayland or null;
    waypipe = androidDeps.waypipe or null;
  in
    androidPkgs.stdenv.mkDerivation {
      pname = "wawona-android";
      version = "1.0.0";
      src = wawonaSrc;
      
      nativeBuildInputs = with androidPkgs; [
        cmake
        pkg-config
        python3
      ];
      
      buildInputs = with androidPkgs; [
        # Add Android dependencies here
      ] ++ lib.optional (wayland != null) wayland
        ++ lib.optional (waypipe != null) waypipe;
      
      cmakeFlags = [
        "-DCMAKE_SYSTEM_NAME=Android"
        "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
        "-DCMAKE_ANDROID_NDK=${androidPkgs.stdenv.cc}"
      ];
      
      # Set PKG_CONFIG_PATH for dependencies
      PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" (
        lib.filter (pkg: pkg != null) [ wayland waypipe ]
      );
    };
in
{
  inherit buildWawonaIOS buildWawonaMacOS buildWawonaAndroid;
  
  # Convenience attributes
  ios = buildWawonaIOS;
  macos = buildWawonaMacOS;
  android = buildWawonaAndroid;
}
