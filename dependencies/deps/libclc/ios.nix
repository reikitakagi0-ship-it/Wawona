{ lib, pkgs, buildPackages, common, buildModule }:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # libclc is part of LLVM project - fetch from LLVM monorepo
  # Using same source structure as nixpkgs
  src = pkgs.fetchFromGitHub {
    owner = "llvm";
    repo = "llvm-project";
    rev = "llvmorg-21.1.2";
    sha256 = "sha256-0000000000000000000000000000000000000000000000000000";  # Will be updated
  };
in
pkgs.stdenv.mkDerivation {
  name = "libclc-ios";
  # libclc is in libclc subdirectory of llvm-project
  src = pkgs.runCommand "libclc-src" {} ''
    mkdir -p $out
    cp -r ${src}/libclc $out/
  '';
  patches = [];
  nativeBuildInputs = with buildPackages; [ cmake pkg-config ninja ];
  buildInputs = [
    pkgs.llvmPackages.llvm.dev
    pkgs.llvmPackages.clang-unwrapped.dev
  ];
  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    fi
    export NIX_CFLAGS_COMPILE="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0"
    export NIX_CXXFLAGS_COMPILE="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0"
    export NIX_LDFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0"
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    TOOLCHAIN_FILE="$PWD/ios-toolchain.cmake"
    cat > ios-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
set(CMAKE_C_COMPILER "$IOS_CC")
set(CMAKE_CXX_COMPILER "$IOS_CXX")
set(CMAKE_SYSROOT "$SDKROOT")
set(BUILD_SHARED_LIBS OFF)
set(CMAKE_BUILD_TYPE Release)
set(CMAKE_MAKE_PROGRAM "${buildPackages.ninja}/bin/ninja")
set(CMAKE_C_FLAGS "-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0")
set(CMAKE_CXX_FLAGS "-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0")
set(CMAKE_C_FLAGS_INIT "-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0")
set(CMAKE_CXX_FLAGS_INIT "-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=26.0")
EOF
  '';
  configurePhase = ''
    runHook preConfigure
    TOOLCHAIN_FILE="$PWD/ios-toolchain.cmake"
    cmakeFlagsArray+=("-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE")
    cmakeFlagsArray+=("-DCMAKE_BUILD_TYPE=Release")
    cmakeFlagsArray+=("-DLLVM_DIR=${pkgs.llvmPackages.llvm.dev}/lib/cmake/llvm")
    cmakeFlagsArray+=("-DCLANG_DIR=${pkgs.llvmPackages.clang-unwrapped.dev}/lib/cmake/clang")
    cmake . -GNinja
    runHook postConfigure
  '';
  cmakeFlags = [];
}
