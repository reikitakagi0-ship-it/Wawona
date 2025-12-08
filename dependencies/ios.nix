# iOS-specific dependency builds

{ lib, pkgs, buildPackages, common }:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
in

{
  # Build a dependency for iOS
  buildForIOS = name: entry:
    let
      # iOS cross-compilation setup - use a function to delay evaluation
      # This prevents infinite recursion when accessing the package set
      getIosPkgs = pkgs.pkgsCross.iphone64;
      iosPkgs = getIosPkgs;
      
      # Import Xcode wrapper utilities - inside function to delay evaluation
      xcodeUtils = import ./xcode-wrapper.nix { inherit lib pkgs; };
      
      src = fetchSource entry;
      
      buildSystem = getBuildSystem entry;
      buildFlags = entry.buildFlags.ios or [];
      patches = entry.patches.ios or [];
      
      # Determine build inputs based on dependency name
      # For wayland, dependencies will be found via pkg-config
      # We avoid explicit references to avoid circular dependencies
      depInputs = [];
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
        # Use regular stdenv but configure for iOS cross-compilation
        # We'll use Xcode's compiler directly to avoid macOS flag conflicts
        pkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          src = src;
          patches = lib.filter (p: p != null && builtins.pathExists (toString p)) patches;
          
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
                
                # Note: Dependencies (expat, libffi, libxml2) will need to be built for iOS
                # For now, we'll let the build fail if they're missing, then add them
              else
                echo "Warning: Xcode not found. iOS build may fail."
              fi
            fi
          '';
          
          # Meson setup command
          # Use Xcode's compiler directly to avoid macOS flag conflicts
          configurePhase = ''
            runHook preConfigure
            # Always use Xcode's compiler if available (it handles iOS properly)
            # Use xcrun to find the compiler, or check common locations
            if [ -n "''${DEVELOPER_DIR:-}" ] && [ -d "$DEVELOPER_DIR" ]; then
              # Try xcrun first (most reliable)
              if command -v xcrun >/dev/null 2>&1; then
                IOS_CC=$(xcrun --find clang 2>/dev/null || echo "")
                IOS_CXX=$(xcrun --find clang++ 2>/dev/null || echo "")
                if [ -n "$IOS_CC" ] && [ -f "$IOS_CC" ]; then
                  echo "Using Xcode compiler via xcrun: $IOS_CC"
                else
                  # Fallback to direct path
                  IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                  IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
                fi
              else
                # Try toolchain path
                IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
              fi
              
              # Check if compiler exists
              if [ -f "$IOS_CC" ]; then
                IOS_AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
                IOS_STRIP="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/strip"
                echo "Using Xcode compiler: $IOS_CC"
                echo "Using Xcode SDK: $SDKROOT"
              else
                # Fallback to Nix's clang with iOS target
                IOS_CC="${buildPackages.clang}/bin/clang"
                IOS_CXX="${buildPackages.clang}/bin/clang++"
                IOS_AR="${buildPackages.binutils}/bin/ar"
                IOS_STRIP="${buildPackages.binutils}/bin/strip"
                echo "Xcode compiler not found, using Nix compiler: $IOS_CC"
              fi
            else
              # Fallback to Nix's clang with iOS target
              IOS_CC="${buildPackages.clang}/bin/clang"
              IOS_CXX="${buildPackages.clang}/bin/clang++"
              IOS_AR="${buildPackages.binutils}/bin/ar"
              IOS_STRIP="${buildPackages.binutils}/bin/strip"
              echo "Xcode not found, using Nix compiler: $IOS_CC"
            fi
            
            # Create iOS cross file for Meson
            # Add SDK root if available
            if [ -n "''${SDKROOT:-}" ]; then
              SDK_ARGS=", '-isysroot', '$SDKROOT'"
            else
              SDK_ARGS=""
            fi
            
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
            c_args = ['-arch', 'arm64', '-mios-version-min=15.0'$SDK_ARGS]
            cpp_args = ['-arch', 'arm64', '-mios-version-min=15.0'$SDK_ARGS]
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
      else if buildSystem == "cargo" || buildSystem == "rust" then
        # Rust/Cargo build for iOS
        iosPkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          
          # Use cargoHash (newer SRI format) or cargoSha256 (older)
          # If neither provided, use fakeHash to let Nix compute it
          cargoHash = if entry ? cargoHash && entry.cargoHash != null then entry.cargoHash else lib.fakeHash;
          cargoSha256 = entry.cargoSha256 or null;
          cargoLock = entry.cargoLock or null;
          
          nativeBuildInputs = with iosPkgs; [
            pkg-config
          ];
          
          buildInputs = depInputs;
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
              else
                echo "Warning: Xcode not found. iOS build may fail."
              fi
            fi
          '';
          
          configureFlags = buildFlags;
        };
}
