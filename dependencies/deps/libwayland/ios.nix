{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  waylandSource = {
    source = "gitlab";
    owner = "wayland";
    repo = "wayland";
    tag = "1.23.0";
    sha256 = "sha256-oK0Z8xO2ILuySGZS0m37ZF0MOyle2l8AXb0/6wai0/w=";
  };
  src = fetchSource waylandSource;
  buildFlags = [ "-Dlibraries=false" "-Ddocumentation=false" "-Dtests=false" ];
  patches = [];
  getDeps = depNames:
    map (depName:
      if depName == "expat" then buildModule.buildForIOS "expat" {}
      else if depName == "libffi" then buildModule.buildForIOS "libffi" {}
      else if depName == "libxml2" then buildModule.buildForIOS "libxml2" {}
      else throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [ "expat" "libffi" "libxml2" ];
  # epoll-shim: Required for iOS Wayland builds (implements epoll on top of kqueue)
  # Reference: Same as macOS - epoll-shim works on iOS/Darwin
  # See: docs/research-from-chatgpt-wayland-macos.md
  # Use buildModule to properly resolve dependencies (fixes store path issues)
  # This ensures epoll-shim is built and available before libwayland uses it
  epollShim = buildModule.buildForIOS "epoll-shim" {};
in
pkgs.stdenv.mkDerivation {
  name = "libwayland-ios";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
    bison flex
  ];
  buildInputs = depInputs ++ [ epollShim ];
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
  postPatch = ''
    # iOS syscall compatibility: Remove signalfd/timerfd usage
    # These syscalls don't exist on iOS (Darwin)
    # Note: Only needed if building libraries (-Dlibraries=true)
    if [ -f src/event-loop.c ]; then
      echo "=== Applying iOS syscall compatibility patches ==="
      # Replace signalfd with alternative signal handling
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/signalfd.h>" "/* iOS: signalfd not available on Darwin */" \
        --replace "signalfd(" "/* signalfd removed for iOS */ (void)0; /* signalfd(" \
        --replace "SFD_CLOEXEC\|SFD_NONBLOCK" "0"
      
      # Replace timerfd with alternative timer handling
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/timerfd.h>" "/* iOS: timerfd not available on Darwin */" \
        --replace "timerfd_create(" "/* timerfd_create removed for iOS */ (void)0; /* timerfd_create(" \
        --replace "timerfd_settime(" "/* timerfd_settime removed for iOS */ (void)0; /* timerfd_settime(" \
        --replace "TFD_CLOEXEC\|TFD_NONBLOCK\|TFD_TIMER_ABSTIME" "0"
      
      # iOS epoll compatibility: Use epoll-shim
      # epoll-shim implements epoll on top of kqueue for iOS/Darwin
      # Reference: Same as macOS - epoll-shim works on iOS
      # See: docs/research-from-chatgpt-wayland-macos.md
      echo "Using epoll-shim for epoll compatibility on iOS"
      # epoll-shim provides epoll.h - replace include to use epoll-shim's version
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/epoll.h>" "#include <epoll-shim/epoll.h>" || true
      
      echo "Applied iOS syscall compatibility patches"
    else
      echo "Note: event-loop.c not found (libraries disabled), skipping syscall patches"
    fi
  '';
  configurePhase = ''
    runHook preConfigure
    # Add epoll-shim include paths for iOS
    # epoll-shim is required for Wayland on iOS (implements epoll on top of kqueue)
    # Same approach as macOS - epoll-shim works on iOS/Darwin
    export CFLAGS="-I${epollShim}/include ''${NIX_CFLAGS_COMPILE:-}"
    export LDFLAGS="-L${epollShim}/lib -lepoll-shim ''${NIX_LDFLAGS:-}"
    export PKG_CONFIG_PATH="${epollShim}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    echo "Configured epoll-shim paths for iOS:"
    echo "  CFLAGS includes ${epollShim}/include"
    echo "  LDFLAGS includes ${epollShim}/lib"
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
