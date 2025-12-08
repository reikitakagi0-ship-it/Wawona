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
  ];
  patches = [];
  getDeps = depNames:
    map (depName:
      if depName == "libclc" then pkgs.libclc
      else if depName == "zlib" then pkgs.zlib
      else if depName == "zstd" then pkgs.zstd
      else if depName == "expat" then pkgs.expat
      else if depName == "llvm" then pkgs.llvmPackages.llvm
      else throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [ "libclc" "zlib" "zstd" "expat" "llvm" ];
in
pkgs.stdenv.mkDerivation {
  name = "mesa-kosmickrisp-ios";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
    bison flex
  ];
  buildInputs = depInputs;
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
c_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-fPIC']
cpp_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-fPIC']
c_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0']
EOF
  '';
  configurePhase = ''
    runHook preConfigure
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
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
