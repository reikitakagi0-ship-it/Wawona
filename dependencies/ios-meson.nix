# iOS Meson build configuration
# Separate file to avoid recursion issues

{ lib, pkgs, buildPackages, xcodeUtils, src, patches, buildFlags, depInputs }:

pkgs.stdenv.mkDerivation {
  name = "wayland-ios";
  inherit src patches;
  
  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    bison
    flex
    xcodeUtils.findXcodeScript
  ];
  
  buildInputs = depInputs;
  
  # Automatically find and use Xcode if available
  preConfigure = ''
    # Find Xcode and set up environment
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        echo "Found Xcode at: $XCODE_APP"
        echo "Using iOS SDK: $SDKROOT"
      else
        echo "Warning: Xcode not found. iOS build may fail."
      fi
    fi
  '';
  
  # Meson setup command
  # Use Xcode's compiler directly to avoid macOS flag conflicts
  configurePhase = ''
    runHook preConfigure
    # Use Xcode's clang if available (it handles iOS properly)
    if [ -n "''${DEVELOPER_DIR:-}" ] && [ -f "$DEVELOPER_DIR/usr/bin/clang" ]; then
      IOS_CC="$DEVELOPER_DIR/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/usr/bin/clang++"
      IOS_AR="$DEVELOPER_DIR/usr/bin/ar"
      IOS_STRIP="$DEVELOPER_DIR/usr/bin/strip"
      echo "Using Xcode compiler: $IOS_CC"
    else
      # Fallback to Nix's clang with iOS target
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
      IOS_AR="${buildPackages.binutils}/bin/ar"
      IOS_STRIP="${buildPackages.binutils}/bin/strip"
      echo "Using Nix compiler: $IOS_CC"
    fi
    
    # Create iOS cross file for Meson
    cat > ios-cross-file.txt <<EOF
    [binaries]
    c = '$IOS_CC'
    cpp = '$IOS_CXX'
    ar = '$IOS_AR'
    strip = '$IOS_STRIP'
    
    [host_machine]
    system = 'darwin'
    cpu_family = 'aarch64'
    cpu = 'aarch64'
    endian = 'little'
    
    [built-in options]
    c_args = ['-arch', 'arm64', '-mios-version-min=15.0']
    cpp_args = ['-arch', 'arm64', '-mios-version-min=15.0']
    EOF
    
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=ios-cross-file.txt \
      ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  
  # Override compiler to avoid macOS flags from stdenv
  # We'll use Xcode's compiler in configurePhase instead
  CC = "${buildPackages.clang}/bin/clang";
  CXX = "${buildPackages.clang}/bin/clang++";
  
  # Filter out macOS-specific flags - use empty flags to avoid conflicts
  # The actual compiler flags will be set in the Meson cross file
  NIX_CFLAGS_COMPILE = "";
  NIX_CXXFLAGS_COMPILE = "";
  
  # Allow access to Xcode
  __impureHostDeps = [ "/bin/sh" ];
  
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
