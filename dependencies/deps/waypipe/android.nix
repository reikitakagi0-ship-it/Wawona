{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  androidToolchain = import ../../common/android-toolchain.nix { inherit lib pkgs; };
  waypipeSource = {
    source = "gitlab";
    owner = "mstoeckl";
    repo = "waypipe";
    tag = "v0.10.6";
    sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
  };
  src = fetchSource waypipeSource;
  
  # Dependencies
  libwayland = buildModule.buildForAndroid "libwayland" {};
  # Vulkan driver for Android: SwiftShader (CPU-based fallback)
  swiftshader = buildModule.buildForAndroid "swiftshader" {};
  # Compression libraries for waypipe features
  zstd = buildModule.buildForAndroid "zstd" {};
  lz4 = buildModule.buildForAndroid "lz4" {};
  # FFmpeg for video encoding/decoding
  ffmpeg = buildModule.buildForAndroid "ffmpeg" {};
  # wayland-protocols is needed for protocol definitions (XMLs)
  waylandProtocols = pkgs.wayland-protocols;
  
  # Build flags and features
  # waypipe-rs uses Vulkan-only backend (no more GBM/DRM)
  # Note: Vulkan is always enabled in waypipe-rs v0.10.6+ (not a feature)
  # dmabuf enables DMABUF support via Vulkan
  # Enable dmabuf and video features for waypipe-rs
  # Note: Vulkan is always enabled in waypipe-rs v0.10.6+ (not a feature)
  # dmabuf enables DMABUF support via Vulkan
  # video enables video encoding/decoding via FFmpeg
  cargoBuildFeatures = [ "dmabuf" "video" ]; 
in
pkgs.rustPlatform.buildRustPackage {
  pname = "waypipe";
  version = "v0.10.6";
  inherit src;
  
  # Set to empty to let Nix recompute hash after adding bindgen to Cargo.toml
  cargoHash = "";
  
  # Pre-patch: Add bindgen and pkg-config to wrap-ffmpeg Cargo.toml BEFORE vendoring
  prePatch = ''
    echo "=== Pre-patching waypipe Cargo.toml files ==="
    
    # wrap-ffmpeg: Add bindgen and pkg-config to Cargo.toml if not present
    if [ -f "wrap-ffmpeg/Cargo.toml" ]; then
      if ! grep -q "bindgen" wrap-ffmpeg/Cargo.toml; then
        echo "Adding bindgen to wrap-ffmpeg/Cargo.toml"
        if grep -q "\[build-dependencies\]" wrap-ffmpeg/Cargo.toml; then
          sed -i.bak '/\[build-dependencies\]/a\
bindgen = "0.69"
' wrap-ffmpeg/Cargo.toml
        else
          echo "" >> wrap-ffmpeg/Cargo.toml
          echo "[build-dependencies]" >> wrap-ffmpeg/Cargo.toml
          echo 'bindgen = "0.69"' >> wrap-ffmpeg/Cargo.toml
        fi
        echo "✓ Added bindgen to wrap-ffmpeg/Cargo.toml"
      fi
      if ! grep -q "pkg-config" wrap-ffmpeg/Cargo.toml; then
        echo "Adding pkg-config to wrap-ffmpeg/Cargo.toml"
        if grep -q "\[build-dependencies\]" wrap-ffmpeg/Cargo.toml; then
          sed -i.bak '/\[build-dependencies\]/a\
pkg-config = "0.3"
' wrap-ffmpeg/Cargo.toml
        else
          echo "" >> wrap-ffmpeg/Cargo.toml
          echo "[build-dependencies]" >> wrap-ffmpeg/Cargo.toml
          echo 'pkg-config = "0.3"' >> wrap-ffmpeg/Cargo.toml
        fi
        echo "✓ Added pkg-config to wrap-ffmpeg/Cargo.toml"
      fi
    fi
    
    echo "=== Finished pre-patching ==="
  '';
  
  nativeBuildInputs = with buildPackages; [ 
    pkg-config 
    waylandProtocols
    # Bindgen hook might be needed for generating bindings to C libs
    rustPlatform.bindgenHook
  ];
  
  buildInputs = [ 
    libwayland
    swiftshader  # Vulkan ICD driver for Android
    zstd  # Compression library
    lz4   # Compression library
    ffmpeg  # Video encoding/decoding
  ];

  # Cross-compilation targets
  CARGO_BUILD_TARGET = "aarch64-linux-android";
  
  # Configure compilers for the target
  CC_aarch64_linux_android = androidToolchain.androidCC;
  CXX_aarch64_linux_android = androidToolchain.androidCXX;
  AR_aarch64_linux_android = androidToolchain.androidAR;
  
  # Enable cross-compilation for pkg-config via env var in preConfigure or env attr
  # PKG_CONFIG_aarch64_linux_android = "${buildPackages.pkg-config}/bin/pkg-config";
  
  buildFeatures = cargoBuildFeatures;

  preConfigure = ''
    # Set PKG_CONFIG_PATH to find target libraries
    export PKG_CONFIG_PATH="${libwayland}/lib/pkgconfig:${waylandProtocols}/share/pkgconfig:${zstd}/lib/pkgconfig:${lz4}/lib/pkgconfig:${ffmpeg}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1
    export PKG_CONFIG_aarch64_linux_android="${buildPackages.pkg-config}/bin/pkg-config"
    echo "Using PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
    
    # Set up library search paths for Vulkan driver
    export LIBRARY_PATH="${swiftshader}/lib:${libwayland}/lib:${zstd}/lib:${lz4}/lib:$LIBRARY_PATH"
    
    # Set up include paths for bindgen (needed for wrap-zstd, wrap-lz4, and wrap-ffmpeg)
    export C_INCLUDE_PATH="${zstd}/include:${lz4}/include:${ffmpeg}/include:$C_INCLUDE_PATH"
    export CPP_INCLUDE_PATH="${zstd}/include:${lz4}/include:${ffmpeg}/include:$CPP_INCLUDE_PATH"
    
    # Configure Bindgen to find Android NDK headers and FFmpeg
    # We need to point to the sysroot include directories
    NDK_SYSROOT="${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"
    export BINDGEN_EXTRA_CLANG_ARGS="-isystem ${zstd}/include -isystem ${lz4}/include -isystem ${ffmpeg}/include -isystem $NDK_SYSROOT/usr/include -isystem $NDK_SYSROOT/usr/include/aarch64-linux-android --target=aarch64-linux-android"
    echo "BINDGEN_EXTRA_CLANG_ARGS: $BINDGEN_EXTRA_CLANG_ARGS"
    
    echo "Vulkan driver (SwiftShader) library path: ${swiftshader}/lib"
    ls -la "${swiftshader}/lib/" || echo "Warning: SwiftShader lib directory not found"
  '';
  
  # Patch waypipe wrappers for Android
  postPatch = ''
    echo "=== Patching waypipe wrappers for Android ==="
    
    # wrap-ffmpeg: Use pkg-config to find FFmpeg and generate bindings with bindgen
    if [ -f "wrap-ffmpeg/build.rs" ]; then
      cat > wrap-ffmpeg/build.rs <<'BUILDRS_EOF'
fn main() {
    use std::env;
    use std::path::PathBuf;
    
    // Find FFmpeg via pkg-config
    let ffmpeg = pkg_config::Config::new()
        .probe("libavutil")
        .expect("Could not find libavutil via pkg-config");
    
    // Also probe libavcodec for video features
    let _ = pkg_config::Config::new().probe("libavcodec");
    
    // Tell cargo to link against FFmpeg libraries
    for lib in &ffmpeg.libs {
        println!("cargo:rustc-link-lib={}", lib);
    }
    
    // Add include paths for bindgen
    let mut clang_args: Vec<String> = ffmpeg.include_paths.iter()
        .map(|path| format!("-I{}", path.display()))
        .collect();
    
    // Try to find wrapper.h, otherwise use libavutil/avutil.h
    let header = if PathBuf::from("wrapper.h").exists() {
        "wrapper.h"
    } else {
        "libavutil/avutil.h"
    };
    
    let mut bindgen_builder = bindgen::Builder::default()
        .header(header)
        .clang_args(&clang_args);
    
    // Generate bindings
    let bindings = bindgen_builder
        .generate()
        .expect("Unable to generate bindings");
    
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
BUILDRS_EOF
      echo "✓ Patched wrap-ffmpeg/build.rs to use FFmpeg"
    fi
    
    echo "=== Finished patching waypipe ==="
  '';
  
  # Set runtime environment variables for Vulkan ICD discovery
  postInstall = ''
    # Create a wrapper script that sets VK_ICD_FILENAMES/VK_DRIVER_FILES for SwiftShader
    if [ -f "$out/bin/waypipe" ]; then
      mv "$out/bin/waypipe" "$out/bin/waypipe.real"
      cat > "$out/bin/waypipe" <<EOF
#!/bin/sh
# Set Vulkan ICD path for SwiftShader driver
# Check for ICD JSON manifest in standard locations
if [ -f "${swiftshader}/lib/vulkan/icd.d/vk_swiftshader_icd.json" ]; then
  export VK_DRIVER_FILES="${swiftshader}/lib/vulkan/icd.d/vk_swiftshader_icd.json"
  export VK_ICD_FILENAMES="${swiftshader}/lib/vulkan/icd.d/vk_swiftshader_icd.json"
elif [ -f "${swiftshader}/share/vulkan/icd.d/vk_swiftshader_icd.json" ]; then
  export VK_DRIVER_FILES="${swiftshader}/share/vulkan/icd.d/vk_swiftshader_icd.json"
  export VK_ICD_FILENAMES="${swiftshader}/share/vulkan/icd.d/vk_swiftshader_icd.json"
fi
# Add SwiftShader library to library path
export LD_LIBRARY_PATH="${swiftshader}/lib:''${LD_LIBRARY_PATH:-}"
exec "$out/bin/waypipe.real" "$@"
EOF
      chmod +x "$out/bin/waypipe"
    fi
  '';
}
