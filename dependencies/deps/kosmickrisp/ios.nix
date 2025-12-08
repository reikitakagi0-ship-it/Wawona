{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  mesaSource = {
    source = "gitlab";
    owner = "mesa";
    repo = "mesa";
    branch = "main";
    sha256 = "sha256-Kw5xL5RllnCBWvQiGK5pAb5KedJZy/Tt6rVYVbkobh8=";
  };
  src = fetchSource mesaSource;
  buildFlags = [
    "-Dvulkan-drivers=kosmickrisp"
    "-Dgallium-drivers="
    "-Dplatforms="
    "-Dglx=disabled"
    "-Degl=disabled"
    "-Dgbm=disabled"
    "-Dtools="
    "-Dvulkan-beta=true"
    "-Dbuildtype=release"
    "-Dglvnd=disabled"
    "-Dgallium-va=disabled"
  ];
  patches = [];
  # For iOS, we need cross-compiled dependencies, not macOS versions
  # Build dependencies (meson, ninja, python) stay macOS-only (nativeBuildInputs) ✅
  # Runtime dependencies must be cross-compiled for iOS
  # Note: Some dependencies (like spirv-headers) are headers-only and can use macOS version
  # Others need iOS cross-compilation. For now, we'll use macOS versions where possible
  # and cross-compile when needed. LLVM/Clang can use macOS versions for cross-compilation.
  # Build iOS dependencies first so we can reference their paths
  zlibIOS = buildModule.buildForIOS "zlib" {};
  zstdIOS = buildModule.buildForIOS "zstd" {};
  expatIOS = buildModule.buildForIOS "expat" {};
  spirvLLVMTranslatorIOS = buildModule.buildForIOS "spirv-llvm-translator" {};
  spirvToolsIOS = buildModule.buildForIOS "spirv-tools" {};
  libclcIOS = buildModule.buildForIOS "libclc" {};
  
  getDeps = depNames:
    map (depName:
      if depName == "zlib" then zlibIOS
      else if depName == "zstd" then zstdIOS
      else if depName == "expat" then expatIOS
      else if depName == "spirv-llvm-translator" then spirvLLVMTranslatorIOS
      else if depName == "spirv-tools" then spirvToolsIOS
      else if depName == "libclc" then libclcIOS
      else if depName == "llvm" then pkgs.llvmPackages.llvm  # LLVM can use macOS version for cross-compilation
      else if depName == "clang" then pkgs.llvmPackages.clang-unwrapped.lib  # Clang libraries
      else if depName == "clang-dev" then pkgs.llvmPackages.clang-unwrapped.dev  # Clang headers
      else if depName == "spirv-headers" then pkgs.spirv-headers  # Headers-only, macOS OK
      else throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [ "zlib" "zstd" "expat" "llvm" "clang" "clang-dev" "spirv-llvm-translator" "spirv-tools" "spirv-headers" "libclc" ];
in
pkgs.stdenv.mkDerivation {
  name = "kosmickrisp-ios";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
    bison flex
  ];
  # Metal frameworks are linked via -framework flags, not as buildInputs
  # Mesa's meson.build will find them via pkg-config or direct linking
  buildInputs = depInputs;
  postPatch = ''
    echo "=== Patching Mesa meson.build for Clang library detection (iOS) ==="
    # Fix Clang library detection: Mesa expects Clang libraries in LLVM libdir
    # but in Nixpkgs, Clang libraries are in a separate package (clang-unwrapped.lib)
    # Write patch lines to a temp file to avoid Nix string escaping issues
    # Use $TMPDIR instead of /tmp for Nix sandbox compatibility
    CLANG_PATCH_FILE="$TMPDIR/clang_patch.txt"
    cat > "$CLANG_PATCH_FILE" <<ENDPATCH
  # Try multiple locations for Clang libraries
  # On some systems (like Nix), Clang libraries may be in a separate location
  clang_libdirs = [llvm_libdir]
  # Also check common alternative locations
  clang_libdirs += [join_paths(llvm_libdir, '..', 'clang', 'lib')]
  # In Nixpkgs, Clang libraries are in clang-unwrapped.lib, not LLVM libdir
  clang_libdirs += ['${pkgs.llvmPackages.clang-unwrapped.lib}/lib']
ENDPATCH
    
    # Insert after llvm_libdir line
    sed -i '/llvm_libdir = dep_llvm.get_variable/r '"$CLANG_PATCH_FILE" meson.build
    
    # Replace dep_clang line to use clang_libdirs instead of llvm_libdir
    substituteInPlace meson.build \
      --replace \
      "dep_clang = cpp.find_library('clang-cpp', dirs : llvm_libdir, required : false)" \
      "dep_clang = cpp.find_library('clang-cpp', dirs : clang_libdirs, required : false)"
    
    # Replace the foreach loop to use clang_libdirs instead of llvm_libdir
    substituteInPlace meson.build \
      --replace \
      "dep_clang += cpp.find_library(m, dirs : llvm_libdir, required : true)" \
      "dep_clang += cpp.find_library(m, dirs : clang_libdirs, required : true)"
    
    echo "Applied Clang library detection patch for iOS"
    echo "Verifying patch was applied:"
    grep -A 7 "clang_libdirs = \[llvm_libdir\]" meson.build || echo "WARNING: Patch may not have been applied correctly"
  '';
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
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    cat > ios-cross-file.txt <<EOF
[binaries]
c = '$IOS_CC'
cpp = '$IOS_CXX'
ar = 'ar'
strip = 'strip'
pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=26.0', '-fPIC', '-I${zlibIOS}/include', '-I${zstdIOS}/include', '-I${expatIOS}/include', '-I${spirvLLVMTranslatorIOS}/include', '-I${spirvToolsIOS}/include', '-I${libclcIOS}/include']
cpp_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=26.0', '-fPIC', '-I${zlibIOS}/include', '-I${zstdIOS}/include', '-I${expatIOS}/include', '-I${spirvLLVMTranslatorIOS}/include', '-I${spirvToolsIOS}/include', '-I${libclcIOS}/include']
c_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=26.0', '-L${zlibIOS}/lib', '-L${zstdIOS}/lib', '-L${expatIOS}/lib', '-L${spirvLLVMTranslatorIOS}/lib', '-L${spirvToolsIOS}/lib', '-L${libclcIOS}/lib', '-lz', '-lzstd', '-lexpat', '-framework', 'Metal', '-framework', 'MetalKit', '-framework', 'Foundation', '-framework', 'IOKit']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=26.0', '-L${zlibIOS}/lib', '-L${zstdIOS}/lib', '-L${expatIOS}/lib', '-L${spirvLLVMTranslatorIOS}/lib', '-L${spirvToolsIOS}/lib', '-L${libclcIOS}/lib', '-lz', '-lzstd', '-lexpat', '-framework', 'Metal', '-framework', 'MetalKit', '-framework', 'Foundation', '-framework', 'IOKit']
EOF
  '';
  configurePhase = ''
    runHook preConfigure
    # Ensure we build as .dylib (shared library) for iOS
    # Set PKG_CONFIG_PATH for iOS dependencies and SPIRV/LLVM dependencies
    # Note: iOS dependencies may not have pkg-config files, but we include paths anyway
    export PKG_CONFIG_PATH="${zlibIOS}/lib/pkgconfig:${zstdIOS}/lib/pkgconfig:${expatIOS}/lib/pkgconfig:${spirvLLVMTranslatorIOS}/lib/pkgconfig:${spirvToolsIOS}/lib/pkgconfig:${pkgs.spirv-headers}/lib/pkgconfig:${pkgs.llvmPackages.llvm.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    # Ensure llvm-config is in PATH
    export PATH="${pkgs.llvmPackages.llvm.dev}/bin:''${PATH}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --default-library=shared \
      --cross-file=ios-cross-file.txt \
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
