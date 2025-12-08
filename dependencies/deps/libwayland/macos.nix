{ lib, pkgs, common, buildModule }:

let
  fetchSource = common.fetchSource;
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
      if depName == "expat" then pkgs.expat
      else if depName == "libffi" then pkgs.libffi
      else if depName == "libxml2" then pkgs.libxml2
      else throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [ "expat" "libffi" "libxml2" ];
  # epoll-shim: Required for macOS Wayland builds (implements epoll on top of kqueue)
  # Reference: MacPorts Wayland port depends on epoll-shim, libffi, libxml2
  # See: docs/research-from-chatgpt-wayland-macos.md
  # Use our epoll-shim build (which falls back to nixpkgs if available)
  epollShim = buildModule.buildForMacOS "epoll-shim" {};
in
pkgs.stdenv.mkDerivation {
  name = "libwayland-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
    bison flex
    apple-sdk_26
  ];
  buildInputs = depInputs ++ [ epollShim ];
  postPatch = ''
    # macOS syscall compatibility: Remove signalfd/timerfd usage
    # These syscalls don't exist on macOS (Darwin)
    # Note: Only needed if building libraries (-Dlibraries=true)
    if [ -f src/event-loop.c ]; then
      echo "=== Applying macOS syscall compatibility patches ==="
      # Replace signalfd with alternative signal handling
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/signalfd.h>" "/* macOS: signalfd not available on Darwin */" \
        --replace "signalfd(" "/* signalfd removed for macOS */ (void)0; /* signalfd(" \
        --replace "SFD_CLOEXEC\|SFD_NONBLOCK" "0"
      
      # Replace timerfd with alternative timer handling
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/timerfd.h>" "/* macOS: timerfd not available on Darwin */" \
        --replace "timerfd_create(" "/* timerfd_create removed for macOS */ (void)0; /* timerfd_create(" \
        --replace "timerfd_settime(" "/* timerfd_settime removed for macOS */ (void)0; /* timerfd_settime(" \
        --replace "TFD_CLOEXEC\|TFD_NONBLOCK\|TFD_TIMER_ABSTIME" "0"
      
      # macOS epoll compatibility: Use epoll-shim
      # epoll-shim implements epoll on top of kqueue for macOS/BSD
      # Reference: MacPorts Wayland port depends on epoll-shim
      # See: docs/research-from-chatgpt-wayland-macos.md
      echo "Using epoll-shim for epoll compatibility on macOS"
      # epoll-shim provides epoll.h - replace include to use epoll-shim's version
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/epoll.h>" "#include <epoll-shim/epoll.h>" || true
      
      echo "Applied macOS syscall compatibility patches"
    else
      echo "Note: event-loop.c not found (libraries disabled), skipping syscall patches"
    fi
  '';
  configurePhase = ''
    runHook preConfigure
    # Use macOS SDK 26+
    MACOS_SDK="${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
    # Add epoll-shim include paths for macOS
    # epoll-shim is required for Wayland on macOS (implements epoll on top of kqueue)
    export CFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=26.0 -I${epollShim}/include ''${NIX_CFLAGS_COMPILE:-}"
    export LDFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=26.0 -L${epollShim}/lib -lepoll-shim ''${NIX_LDFLAGS:-}"
    export PKG_CONFIG_PATH="${epollShim}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    echo "Configured epoll-shim paths: CFLAGS includes ${epollShim}/include"
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
