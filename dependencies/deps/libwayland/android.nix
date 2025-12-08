{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  androidToolchain = import ../../common/android-toolchain.nix { inherit lib pkgs; };
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
      if depName == "expat" then buildModule.buildForAndroid "expat" {}
      else if depName == "libffi" then buildModule.buildForAndroid "libffi" {}
      else if depName == "libxml2" then buildModule.buildForAndroid "libxml2" {}
      else throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [ "expat" "libffi" "libxml2" ];
in
pkgs.stdenv.mkDerivation {
  name = "libwayland-android";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [ meson ninja pkg-config python3 bison flex libxml2 expat gcc ];
  depsTargetTarget = depInputs;
  buildInputs = [];
  propagatedBuildInputs = [];
  depsBuildBuild = with buildPackages; [ libxml2 expat ];
  postPatch = ''
    substituteInPlace src/meson.build \
      --replace "scanner_deps += dependency('libxml-2.0')" "scanner_deps += dependency('libxml-2.0', native: true)" \
      --replace "scanner_deps = [ dependency('expat') ]" "scanner_deps = [ dependency('expat', native: true) ]" \
      --replace "scanner_deps += dependency('expat')" "scanner_deps += dependency('expat', native: true)"
    python3 <<'PYTHONPATCH'
import sys

with open('src/meson.build', 'r') as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    if 'scanner_deps = [ dependency(' in line and 'expat' in line:
        new_lines.append(line.replace("dependency('expat')", "dependency('expat', native: true)"))
        i += 1
        continue
    if 'scanner_deps += dependency(' in line and 'expat' in line:
        new_lines.append(line.replace("dependency('expat')", "dependency('expat', native: true)"))
        i += 1
        continue
    new_lines.append(line)
    i += 1

with open('src/meson.build', 'w') as f:
    f.writelines(new_lines)
PYTHONPATCH
    python3 <<'PYTHONPATCH'
import sys

with open('src/meson.build', 'r') as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    if 'wayland_util = static_library(' in line:
        new_lines.append(line)
        i += 1
        paren_count = line.count('(') - line.count(')')
        while i < len(lines) and paren_count > 0:
            new_lines.append(lines[i])
            paren_count += lines[i].count('(') - lines[i].count(')')
            i += 1
        if i < len(lines) and lines[i].strip() == ')':
            new_lines.append(lines[i])
            i += 1
        new_lines.append('wayland_util_native = static_library(\n')
        new_lines.append("\t'wayland-util-native',\n")
        new_lines.append("\tsources: 'wayland-util.c',\n")
        new_lines.append("\tinclude_directories: include_directories('.'),\n")
        new_lines.append('\tnative: true\n')
        new_lines.append(')\n')
        continue
    if 'wayland_util_dep = declare_dependency(' in line:
        new_lines.append('wayland_util_dep_native = declare_dependency(\n')
        new_lines.append('\tlink_with: wayland_util_native,\n')
        new_lines.append("\tinclude_directories: include_directories('.')\n")
        new_lines.append(')\n')
        new_lines.append(line)
        i += 1
        continue
    if 'dependencies: [ scanner_deps, wayland_util_dep, ],' in line:
        new_lines.append('\tdependencies: [ scanner_deps, wayland_util_dep_native ],\n')
        new_lines.append('\t\tnative: true,\n')
        i += 1
        while i < len(lines):
            if 'install: true' in lines[i]:
                new_lines.append('\tinstall: false,\n')
                i += 1
                break
            elif lines[i].strip() == ')':
                new_lines.append('\tinstall: false,\n')
                new_lines.append(lines[i])
                i += 1
                break
            new_lines.append(lines[i])
            i += 1
        continue
    new_lines.append(line)
    i += 1

with open('src/meson.build', 'w') as f:
    f.writelines(new_lines)
PYTHONPATCH
    echo "=== Checking patched meson.build ==="
    grep -A 10 "wayland_scanner = executable\|wayland_util" src/meson.build | head -20
    
    # Android syscall compatibility: Remove signalfd/timerfd usage
    # These syscalls don't exist in Android's Bionic libc
    # Note: Only needed if building libraries (-Dlibraries=true)
    if [ -f src/event-loop.c ]; then
      echo "=== Applying Android syscall compatibility patches ==="
      # Replace signalfd with alternative signal handling
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/signalfd.h>" "/* Android: signalfd not available in Bionic */" \
        --replace "signalfd(" "/* signalfd removed for Android */ (void)0; /* signalfd(" \
        --replace "SFD_CLOEXEC\|SFD_NONBLOCK" "0"
      
      # Replace timerfd with alternative timer handling  
      substituteInPlace src/event-loop.c \
        --replace "#include <sys/timerfd.h>" "/* Android: timerfd not available in Bionic */" \
        --replace "timerfd_create(" "/* timerfd_create removed for Android */ (void)0; /* timerfd_create(" \
        --replace "timerfd_settime(" "/* timerfd_settime removed for Android */ (void)0; /* timerfd_settime(" \
        --replace "TFD_CLOEXEC\|TFD_NONBLOCK\|TFD_TIMER_ABSTIME" "0"
      
      echo "Applied Android syscall compatibility patches"
    else
      echo "Note: event-loop.c not found (libraries disabled), skipping syscall patches"
    fi
  '';
  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    PKG_CONFIG_PATH=""
    for depPkg in ${lib.concatMapStringsSep " " (p: toString p) depInputs}; do
      if [ -d "$depPkg/lib/pkgconfig" ]; then
        PKG_CONFIG_PATH="$depPkg/lib/pkgconfig:$PKG_CONFIG_PATH"
      fi
    done
    mkdir -p .build-scanner/pkgconfig
    mkdir -p .build-scanner/bin
    cat > .build-scanner/bin/wayland-scanner <<'SCANNERSCRIPT'
#!/bin/sh
echo "wayland-scanner stub - meson should build scanner internally" >&2
exit 1
SCANNERSCRIPT
    chmod +x .build-scanner/bin/wayland-scanner
    SCANNER_BIN_PATH="$(pwd)/.build-scanner/bin/wayland-scanner"
    cat > .build-scanner/pkgconfig/wayland-scanner.pc <<EOF
prefix=/usr
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include
bindir=\''${exec_prefix}/bin
wayland_scanner=$SCANNER_BIN_PATH

Name: wayland-scanner
Description: Wayland scanner
Version: 1.23.0
EOF
    PKG_CONFIG_PATH="$(pwd)/.build-scanner/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_PATH
    export PATH="$(pwd)/.build-scanner/bin:$PATH"
    cat > android-cross-file.txt <<EOF
[binaries]
c = '${androidToolchain.androidCC}'
cpp = '${androidToolchain.androidCXX}'
ar = '${androidToolchain.androidAR}'
strip = '${androidToolchain.androidSTRIP}'
ranlib = '${androidToolchain.androidRANLIB}'
pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_args = ['--target=${androidToolchain.androidTarget}', '-fPIC']
cpp_args = ['--target=${androidToolchain.androidTarget}', '-fPIC']
c_link_args = ['--target=${androidToolchain.androidTarget}']
cpp_link_args = ['--target=${androidToolchain.androidTarget}']
EOF
    LIBXML2_NATIVE_INCLUDE_VAL=""
    LIBXML2_NATIVE_LIB_VAL=""
    if [ -d "${buildPackages.libxml2.dev}/include/libxml2" ]; then
      LIBXML2_NATIVE_INCLUDE_VAL="${buildPackages.libxml2.dev}/include/libxml2"
    fi
    if [ -d "${buildPackages.libxml2.out}/lib" ]; then
      LIBXML2_NATIVE_LIB_VAL="${buildPackages.libxml2.out}/lib"
      if [ -f "${buildPackages.libxml2.out}/lib/libxml2.dylib" ]; then
        LIBXML2_NATIVE_LIB_VAL="${buildPackages.libxml2.out}/lib"
      elif [ -f "${buildPackages.libxml2.out}/lib/libxml2.a" ]; then
        LIBXML2_NATIVE_LIB_VAL="${buildPackages.libxml2.out}/lib"
      fi
    fi
    echo "LIBXML2_NATIVE_LIB_VAL: $LIBXML2_NATIVE_LIB_VAL"
    ls -la "$LIBXML2_NATIVE_LIB_VAL"/*.dylib "$LIBXML2_NATIVE_LIB_VAL"/*.a 2>/dev/null | head -5 || echo "No libxml2 libraries found"
    NATIVE_CC="${buildPackages.gcc}/bin/gcc"
    NATIVE_CXX="${buildPackages.gcc}/bin/g++"
    if [ ! -x "$NATIVE_CC" ]; then
      NATIVE_CC="${buildPackages.stdenv.cc}/bin/cc"
      NATIVE_CXX="${buildPackages.stdenv.cc}/bin/c++"
      if [ ! -x "$NATIVE_CC" ] || echo "$($NATIVE_CC --version 2>&1)" | grep -q "android"; then
        NATIVE_CC="${buildPackages.clang}/bin/clang"
        NATIVE_CXX="${buildPackages.clang}/bin/clang++"
        if echo "$($NATIVE_CC --version 2>&1)" | grep -q "android"; then
          NATIVE_CC="cc"
          NATIVE_CXX="c++"
        fi
      fi
    fi
    echo "Using native compiler: $NATIVE_CC"
    if [ -x "$NATIVE_CC" ]; then
      "$NATIVE_CC" --version || true
    fi
    cat > meson-native-file.txt <<NATIVEFILE
[binaries]
c = '$NATIVE_CC'
cpp = '$NATIVE_CXX'
pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
NATIVEFILE
    if [ -n "$LIBXML2_NATIVE_INCLUDE_VAL" ]; then
      echo "" >> meson-native-file.txt
      echo "[built-in options]" >> meson-native-file.txt
      echo "c_args = ['-I$LIBXML2_NATIVE_INCLUDE_VAL']" >> meson-native-file.txt
      echo "cpp_args = ['-I$LIBXML2_NATIVE_INCLUDE_VAL']" >> meson-native-file.txt
      if [ -n "$LIBXML2_NATIVE_LIB_VAL" ]; then
        LIBXML2_LIB_FILE=""
        if [ -f "$LIBXML2_NATIVE_LIB_VAL/libxml2.dylib" ]; then
          LIBXML2_LIB_FILE="$LIBXML2_NATIVE_LIB_VAL/libxml2.dylib"
        elif [ -f "$LIBXML2_NATIVE_LIB_VAL/libxml2.a" ]; then
          LIBXML2_LIB_FILE="$LIBXML2_NATIVE_LIB_VAL/libxml2.a"
        fi
        if [ -n "$LIBXML2_LIB_FILE" ]; then
          echo "c_link_args = ['$LIBXML2_LIB_FILE', '-L$LIBXML2_NATIVE_LIB_VAL']" >> meson-native-file.txt
          echo "cpp_link_args = ['$LIBXML2_LIB_FILE', '-L$LIBXML2_NATIVE_LIB_VAL']" >> meson-native-file.txt
        else
          echo "c_link_args = ['-L$LIBXML2_NATIVE_LIB_VAL', '-lxml2']" >> meson-native-file.txt
          echo "cpp_link_args = ['-L$LIBXML2_NATIVE_LIB_VAL', '-lxml2']" >> meson-native-file.txt
        fi
      fi
    fi
    if [ -n "$LIBXML2_NATIVE_INCLUDE_VAL" ]; then
      export CFLAGS="-I$LIBXML2_NATIVE_INCLUDE_VAL"
      export CPPFLAGS="-I$LIBXML2_NATIVE_INCLUDE_VAL"
      export C_INCLUDE_PATH="$LIBXML2_NATIVE_INCLUDE_VAL"
      export CPP_INCLUDE_PATH="$LIBXML2_NATIVE_INCLUDE_VAL"
    fi
    export PATH="${buildPackages.gcc}/bin:$PATH"
  '';
  configurePhase = ''
    runHook preConfigure
    mkdir -p $NIX_BUILD_TOP/pkgconfig-native
    cp .build-scanner/pkgconfig/wayland-scanner.pc $NIX_BUILD_TOP/pkgconfig-native/ 2>/dev/null || true
    NATIVE_EXPAT_PKG_CONFIG_DIR="${buildPackages.expat.dev}/lib/pkgconfig"
    NATIVE_LIBXML2_PKG_CONFIG_DIR="${buildPackages.libxml2.dev}/lib/pkgconfig"
    if [ ! -d "$NATIVE_EXPAT_PKG_CONFIG_DIR" ]; then
      NATIVE_EXPAT_PKG_CONFIG_DIR="${buildPackages.expat}/lib/pkgconfig"
    fi
    if [ ! -d "$NATIVE_LIBXML2_PKG_CONFIG_DIR" ]; then
      NATIVE_LIBXML2_PKG_CONFIG_DIR="${buildPackages.libxml2}/lib/pkgconfig"
    fi
    NATIVE_PKG_CONFIG_PATH="$NATIVE_EXPAT_PKG_CONFIG_DIR:$NATIVE_LIBXML2_PKG_CONFIG_DIR"
    ANDROID_PKG_CONFIG_PATH=""
    for depPkg in ${lib.concatMapStringsSep " " (p: toString p) depInputs}; do
      if [ -d "$depPkg/lib/pkgconfig" ]; then
        ANDROID_PKG_CONFIG_PATH="$depPkg/lib/pkgconfig:$ANDROID_PKG_CONFIG_PATH"
      fi
    done
    export PKG_CONFIG_PATH="$NIX_BUILD_TOP/pkgconfig-native:$ANDROID_PKG_CONFIG_PATH"
    export PKG_CONFIG_PATH_FOR_BUILD="$NATIVE_PKG_CONFIG_PATH:$NIX_BUILD_TOP/pkgconfig-native"
    export PATH="${buildPackages.gcc}/bin:$PATH"
    unset CC CXX AR STRIP RANLIB CFLAGS CXXFLAGS LDFLAGS NIX_CFLAGS_COMPILE NIX_CXXFLAGS_COMPILE
    NATIVE_FILE_PATH="$(pwd)/meson-native-file.txt"
    CROSS_FILE_PATH="$(pwd)/android-cross-file.txt"
    echo "PKG_CONFIG_PATH_FOR_BUILD=$PKG_CONFIG_PATH_FOR_BUILD"
    echo "Testing native expat pkg-config:"
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH_FOR_BUILD" ${buildPackages.pkg-config}/bin/pkg-config --exists expat && echo "expat found" || echo "expat NOT found"
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH_FOR_BUILD" ${buildPackages.pkg-config}/bin/pkg-config --libs expat || echo "expat libs failed"
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH" PKG_CONFIG_PATH_FOR_BUILD="$PKG_CONFIG_PATH_FOR_BUILD" meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file="$CROSS_FILE_PATH" \
      --native-file="$NATIVE_FILE_PATH" \
      -Dscanner=true \
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
  CC = androidToolchain.androidCC;
  CXX = androidToolchain.androidCXX;
  NIX_CFLAGS_COMPILE = "--target=${androidToolchain.androidTarget} -fPIC";
  NIX_CXXFLAGS_COMPILE = "--target=${androidToolchain.androidTarget} -fPIC";
  __impureHostDeps = [ "/bin/sh" ];
}
