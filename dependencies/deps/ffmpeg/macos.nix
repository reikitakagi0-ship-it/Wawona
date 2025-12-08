{ lib, pkgs, common, buildModule }:

let
  fetchSource = common.fetchSource;
  ffmpegSource = {
    source = "github";
    owner = "FFmpeg";
    repo = "FFmpeg";
    tag = "n7.1";
    sha256 = "sha256-erTkv156VskhYEJWjpWFvHjmcr2hr6qgUi28Ho8NFYk=";
  };
  src = fetchSource ffmpegSource;
in
pkgs.stdenv.mkDerivation {
  name = "ffmpeg-macos";
  inherit src;
  
  nativeBuildInputs = with pkgs; [
    pkg-config
    nasm  # Required for x264/x265
    yasm  # Alternative assembler
  ];
  
  buildInputs = with pkgs; [
    # Core dependencies
    zlib
  ];
  
  MACOS_SDK = "${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  preConfigure = ''
    export SDKROOT="${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
    
    # FFmpeg uses configure script, not CMake
    # Set up cross-compilation flags
    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    export AR="${pkgs.llvmPackages.bintools}/bin/llvm-ar"
    export RANLIB="${pkgs.llvmPackages.bintools}/bin/llvm-ranlib"
    export STRIP="${pkgs.llvmPackages.bintools}/bin/llvm-strip"
    
    # Architecture and SDK flags
    # FFmpeg requires C11 support - set for both host and target
    export CFLAGS="-arch arm64 -isysroot ${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -mmacosx-version-min=26.0 -std=c11"
    export CXXFLAGS="-arch arm64 -isysroot ${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -mmacosx-version-min=26.0"
    export LDFLAGS="-arch arm64 -isysroot ${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -mmacosx-version-min=26.0"
    
    # Host compiler flags for FFmpeg's configure tests
    export HOSTCC="${pkgs.clang}/bin/clang"
    export HOSTCFLAGS="-std=c11"
  '';
  
  configureFlags = [
    "--cc=${pkgs.clang}/bin/clang"
    "--cxx=${pkgs.clang}/bin/clang++"
    "--host-cc=${pkgs.clang}/bin/clang"
    "--arch=arm64"
    "--target-os=darwin"
    "--enable-cross-compile"
    "--sysroot=${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    "--prefix=$out"
    "--extra-cflags=-std=c11"
    
    # Enable VideoToolbox for hardware encoding on macOS
    "--enable-videotoolbox"
    "--enable-hwaccel=h264_videotoolbox"
    "--enable-hwaccel=hevc_videotoolbox"
    
    # Enable Vulkan support (for waypipe)
    # Note: Vulkan support requires external Vulkan SDK/libs
    # For macOS/iOS, we rely on kosmickrisp/MoltenVK
    # "--enable-vulkan"  # Disabled for now - requires Vulkan SDK
    
    # Enable required codecs for waypipe
    "--enable-encoder=h264_videotoolbox"
    "--enable-encoder=hevc_videotoolbox"
    "--enable-encoder=libx264"
    "--enable-decoder=h264"
    "--enable-decoder=hevc"
    
    # Disable unnecessary features to reduce build time
    "--disable-doc"
    "--disable-ffplay"
    "--disable-ffprobe"
    "--disable-programs"
    "--disable-debug"
    "--disable-static"
    "--enable-shared"
  ];
  
  # FFmpeg uses autotools configure script
  configurePhase = ''
    runHook preConfigure
    ./configure $configureFlags
    runHook postConfigure
  '';
  
  # Build and install
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    # Install headers and libraries
    # FFmpeg installs headers with 'make install-headers' or 'make install' should include them
    make install
    
    # Ensure include directory exists - FFmpeg should install headers to $out/include
    # But if it doesn't, copy them manually from source
    if [ ! -d "$out/include" ] || [ -z "$(ls -A $out/include 2>/dev/null)" ]; then
      echo "Warning: include directory missing or empty, copying headers from source"
      mkdir -p "$out/include"
      # Copy headers from source build directory
      for libdir in libavcodec libavutil libavformat libswscale libswresample libavfilter libavdevice; do
        if [ -d "$libdir" ]; then
          # Copy header files
          find "$libdir" -name "*.h" -exec install -D {} "$out/include/{}" \; 2>/dev/null || true
        fi
      done
      # Also copy top-level headers if they exist
      if [ -f "libavcodec/avcodec.h" ]; then
        mkdir -p "$out/include/libavcodec"
        cp libavcodec/*.h "$out/include/libavcodec/" 2>/dev/null || true
      fi
      if [ -f "libavutil/avutil.h" ]; then
        mkdir -p "$out/include/libavutil"
        cp libavutil/*.h "$out/include/libavutil/" 2>/dev/null || true
      fi
    fi
    
    # Verify headers were installed
    if [ ! -f "$out/include/libavcodec/avcodec.h" ]; then
      echo "Error: libavcodec/avcodec.h not found after install" >&2
      exit 1
    fi
    if [ ! -f "$out/include/libavutil/avutil.h" ]; then
      echo "Error: libavutil/avutil.h not found after install" >&2
      exit 1
    fi
    
    runHook postInstall
  '';
  
  # Ensure pkg-config files are generated
  postInstall = ''
    # FFmpeg should generate .pc files, verify they exist
    if [ ! -f "$out/lib/pkgconfig/libavcodec.pc" ]; then
      echo "Warning: libavcodec.pc not found, creating minimal version"
      mkdir -p "$out/lib/pkgconfig"
      cat > "$out/lib/pkgconfig/libavcodec.pc" <<EOF
prefix=$out
exec_prefix=''${prefix}
libdir=''${exec_prefix}/lib
includedir=''${prefix}/include

Name: libavcodec
Description: FFmpeg codec library
Version: 7.1
Requires: libavutil
Libs: -L''${libdir} -lavcodec
Cflags: -I''${includedir}
EOF
    fi
    
    if [ ! -f "$out/lib/pkgconfig/libavutil.pc" ]; then
      echo "Warning: libavutil.pc not found, creating minimal version"
      cat > "$out/lib/pkgconfig/libavutil.pc" <<EOF
prefix=$out
exec_prefix=''${prefix}
libdir=''${exec_prefix}/lib
includedir=''${prefix}/include

Name: libavutil
Description: FFmpeg utility library
Version: 7.1
Libs: -L''${libdir} -lavutil
Cflags: -I''${includedir}
EOF
    fi
  '';
}
