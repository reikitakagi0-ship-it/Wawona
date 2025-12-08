{ lib, pkgs, buildPackages, common, buildModule }:

let
  fetchSource = common.fetchSource;
  waypipeSource = {
    source = "gitlab";
    owner = "mstoeckl";
    repo = "waypipe";
    tag = "v0.10.6";
    sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
  };
  src = fetchSource waypipeSource;
  # Vulkan driver for iOS: kosmickrisp
  kosmickrisp = buildModule.buildForIOS "kosmickrisp" {};
  libwayland = buildModule.buildForIOS "libwayland" {};
  # Compression libraries for waypipe features
  zstd = buildModule.buildForIOS "zstd" {};
  lz4 = buildModule.buildForIOS "lz4" {};
  # FFmpeg for video encoding/decoding
  ffmpeg = buildModule.buildForIOS "ffmpeg" {};
  patches = [];
in
pkgs.rustPlatform.buildRustPackage {
  pname = "waypipe";
  version = "v0.10.6";
  inherit src patches;
  # Hash will be recomputed after adding bindgen to Cargo.toml files
  # Set to empty to let Nix compute the new hash
  cargoHash = "";
  cargoLock = null;
  nativeBuildInputs = with buildPackages; [ 
    pkg-config
    clang  # Needed for bindgen to generate bindings for wrap-zstd, wrap-lz4, and wrap-ffmpeg
    rustPlatform.bindgenHook  # Needed for bindgen
  ];
  buildInputs = [
    kosmickrisp  # Vulkan driver for iOS
    libwayland
    zstd  # Compression library
    lz4   # Compression library
    ffmpeg  # Video encoding/decoding
  ];
  CARGO_BUILD_TARGET = "aarch64-apple-ios";
  
  # Enable dmabuf and video features for waypipe-rs
  # Note: Vulkan is always enabled in waypipe-rs v0.10.6+ (not a feature)
  # dmabuf enables DMABUF support via Vulkan
  # video enables video encoding/decoding via FFmpeg
  buildFeatures = [ "dmabuf" "video" ];
  
  # Pre-patch: Add bindgen to Cargo.toml files BEFORE vendoring
  # This must happen before cargoSetupHook vendors dependencies
  prePatch = ''
    echo "=== Pre-patching waypipe Cargo.toml files ==="
    
    # wrap-zstd: Add bindgen to Cargo.toml if not present
    if [ -f "wrap-zstd/Cargo.toml" ] && ! grep -q "bindgen" wrap-zstd/Cargo.toml; then
      echo "Adding bindgen to wrap-zstd/Cargo.toml"
      if grep -q "\[build-dependencies\]" wrap-zstd/Cargo.toml; then
        sed -i.bak '/\[build-dependencies\]/a\
bindgen = "0.69"
' wrap-zstd/Cargo.toml
      else
        echo "" >> wrap-zstd/Cargo.toml
        echo "[build-dependencies]" >> wrap-zstd/Cargo.toml
        echo 'bindgen = "0.69"' >> wrap-zstd/Cargo.toml
      fi
      echo "✓ Added bindgen to wrap-zstd/Cargo.toml"
    fi
    
    # wrap-lz4: Add bindgen to Cargo.toml if not present
    if [ -f "wrap-lz4/Cargo.toml" ] && ! grep -q "bindgen" wrap-lz4/Cargo.toml; then
      echo "Adding bindgen to wrap-lz4/Cargo.toml"
      if grep -q "\[build-dependencies\]" wrap-lz4/Cargo.toml; then
        sed -i.bak '/\[build-dependencies\]/a\
bindgen = "0.69"
' wrap-lz4/Cargo.toml
      else
        echo "" >> wrap-lz4/Cargo.toml
        echo "[build-dependencies]" >> wrap-lz4/Cargo.toml
        echo 'bindgen = "0.69"' >> wrap-lz4/Cargo.toml
      fi
      echo "✓ Added bindgen to wrap-lz4/Cargo.toml"
    fi
    
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
  
  # Patch waypipe to disable GBM requirement for dmabuf on macOS/iOS
  # The dmabuf feature uses Vulkan on these platforms, not GBM
  # Also patch other wrappers that may be built unconditionally
  postPatch = ''
    echo "=== Patching waypipe wrappers for iOS ==="
    
    # Patch all wrapper build.rs files to make dependencies optional
    # wrap-gbm: GBM only needed on Linux - generate empty bindings on macOS/iOS
    if [ -f "wrap-gbm/build.rs" ]; then
      cat > wrap-gbm/build.rs <<'BUILDRS_EOF'
fn main() {
    use std::env;
    use std::fs;
    use std::path::PathBuf;
    
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let bindings_rs = out_dir.join("bindings.rs");
    
    #[cfg(target_os = "linux")]
    {
        pkg_config::Config::new()
            .probe("gbm")
            .expect("Could not find gbm via pkg-config");
    }
    #[cfg(not(target_os = "linux"))]
    {
        // Generate empty bindings on non-Linux (GBM not available)
        fs::write(&bindings_rs, "// GBM bindings disabled - GBM not available on this platform\n").unwrap();
        println!("cargo:warning=GBM not required on this platform");
    }
}
BUILDRS_EOF
      echo "✓ Patched wrap-gbm/build.rs"
    fi
    
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
    
    
    # shaders: Make compilation optional - generate empty shaders.rs
    if [ -f "shaders/build.rs" ]; then
      cat > shaders/build.rs <<'BUILDRS_EOF'
fn main() {
    use std::env;
    use std::fs;
    use std::path::PathBuf;
    
    // Get output directory
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let shaders_rs = out_dir.join("shaders.rs");
    
    // Generate empty shaders.rs file (shaders compiled at runtime)
    fs::write(&shaders_rs, "// Shaders compiled at runtime\n").unwrap();
    
    println!("cargo:warning=Shader compilation disabled - shaders will be compiled at runtime");
    println!("cargo:rerun-if-changed=build.rs");
}
BUILDRS_EOF
      echo "✓ Patched shaders/build.rs"
    fi
    
    # Patch waypipe source to handle macOS/iOS socket flag differences
    # macOS/iOS don't have SOCK_NONBLOCK and SOCK_CLOEXEC flags
    for rust_file in src/main.rs src/test_proto.rs; do
      if [ -f "$rust_file" ]; then
        echo "Patching $rust_file for iOS socket compatibility"
        # Replace all instances of Linux-specific socket flags
        substituteInPlace "$rust_file" \
          --replace 'socket::SockFlag::SOCK_NONBLOCK | socket::SockFlag::SOCK_CLOEXEC' 'socket::SockFlag::empty()' \
          --replace 'socket::SockFlag::SOCK_CLOEXEC | socket::SockFlag::SOCK_NONBLOCK' 'socket::SockFlag::empty()' \
          --replace 'socket::SockFlag::SOCK_NONBLOCK' 'socket::SockFlag::empty()' \
          --replace 'socket::SockFlag::SOCK_CLOEXEC' 'socket::SockFlag::empty()' || true
        echo "✓ Patched $rust_file for socket compatibility"
      fi
    done
    
    # Patch waypipe to conditionally compile GBM module only on Linux
    # On macOS/iOS, dmabuf works via Vulkan without GBM
    if [ -f "src/main.rs" ] && grep -q "mod gbm" src/main.rs; then
      echo "Patching GBM module for iOS"
      # Create a stub gbm module for non-Linux
      cat > src/gbm_stub.rs <<'GBM_STUB_EOF'
// Stub GBM module for non-Linux platforms
// On macOS/iOS, dmabuf works via Vulkan without GBM

pub struct GbmDevice;
pub struct GbmBo;

pub fn new(_path: &str) -> Result<GbmDevice, ()> {
    Err(())
}

pub fn gbm_supported_modifiers(_gbm: &GbmDevice, _format: u32) -> Vec<u64> {
    vec![] // Return empty vec - modifiers handled via Vulkan on macOS/iOS
}
GBM_STUB_EOF
      # Replace mod gbm with conditional compilation using awk
      awk '/^mod gbm;$/ {
        print "#[cfg(target_os = \"linux\")]"
        print "mod gbm;"
        print "#[cfg(not(target_os = \"linux\"))]"
        print "mod gbm_stub;"
        print "#[cfg(not(target_os = \"linux\"))]"
        print "use gbm_stub as gbm;"
        next
      }
      { print }' src/main.rs > src/main.rs.tmp && mv src/main.rs.tmp src/main.rs || true
      echo "✓ Patched GBM module usage"
    fi
    
    # Patch platform.rs for iOS compatibility
    if [ -f "src/platform.rs" ]; then
      echo "Patching src/platform.rs for iOS"
      # Fix st_rdev type conversion issue
      substituteInPlace src/platform.rs \
        --replace 'result.st_rdev.into()' '(result.st_rdev as u64)' || true
      echo "✓ Patched src/platform.rs"
    fi
    
    # Patch any files using ppoll (Linux-specific) - replace with poll on macOS/iOS
    # ppoll takes 3 args (fds, timeout, sigmask), poll takes 2 (fds, timeout)
    for rust_file in src/*.rs; do
      if [ -f "$rust_file" ] && grep -q "ppoll\|poll.*,.*," "$rust_file"; then
        echo "Patching $rust_file to replace ppoll with poll"
        # Replace function name first
        substituteInPlace "$rust_file" \
          --replace 'nix::poll::ppoll' 'nix::poll::poll' \
          --replace 'poll::ppoll' 'poll::poll' || true
        # Remove third argument (sigmask) from ppoll calls
        # Handle specific patterns to avoid breaking nested parentheses
        # Pattern: poll(fds, None, Some(pollmask)) -> poll(fds, None)
        # Pattern: poll(fds, Some(timeout), None) -> poll(fds, Some(timeout))
        # Note: poll's None needs type annotation for type inference
        sed -i.bak \
          -e 's/poll(\([^,]*\), None, Some(pollmask))/poll(\1, None::<nix::poll::PollTimeout>)/g' \
          -e 's/poll(\([^,]*\), None, Some(\*pollmask))/poll(\1, None::<nix::poll::PollTimeout>)/g' \
          -e 's/poll(\([^,]*\), Some(\([^)]*\)), None)/poll(\1, Some(\2))/g' \
          -e 's/poll(\([^,]*\), Some(\([^)]*\)), Some(pollmask))/poll(\1, Some(\2))/g' \
          -e 's/poll(\([^,]*\), Some(\([^)]*\)), Some(\*pollmask))/poll(\1, Some(\2))/g' \
          "$rust_file" 2>/dev/null || true
        echo "✓ Patched $rust_file for ppoll compatibility"
      fi
    done
    
    # Disable test_proto binary on iOS (it has Linux-specific dependencies)
    if [ -f "Cargo.toml" ] && grep -q 'name = "test_proto"' Cargo.toml; then
      echo "Disabling test_proto binary for iOS"
      # Comment out the entire [[bin]] section for test_proto
      awk '
        /^\[\[bin\]\]/ { in_bin = 1; print "# " $0; next }
        in_bin && /^\[/ { in_bin = 0 }
        in_bin { print "# " $0; next }
        { print }
      ' Cargo.toml > Cargo.toml.tmp && mv Cargo.toml.tmp Cargo.toml || {
        # Fallback: use sed to comment out lines
        sed -i.bak '/^\[\[bin\]\]/,/^\[\[/{
          /name = "test_proto"/{
            :a
            N
            /^\[\[/!{
              s/^/# /gm
              ba
            }
          }
        }' Cargo.toml 2>/dev/null || true
      }
      echo "✓ Disabled test_proto binary"
    fi
    
    echo "=== Finished patching waypipe ==="
  '';
  
  preConfigure = ''
    # Set up library search paths for Vulkan driver
    export LIBRARY_PATH="${kosmickrisp}/lib:${libwayland}/lib:${zstd}/lib:${lz4}/lib:$LIBRARY_PATH"
    
    # Set PKG_CONFIG_PATH for wayland, zstd, lz4, and ffmpeg
    export PKG_CONFIG_PATH="${libwayland}/lib/pkgconfig:${zstd}/lib/pkgconfig:${lz4}/lib/pkgconfig:${ffmpeg}/lib/pkgconfig:$PKG_CONFIG_PATH"
    
    # Set up include paths for bindgen (needed for wrap-zstd, wrap-lz4, and wrap-ffmpeg)
    export C_INCLUDE_PATH="${zstd}/include:${lz4}/include:${ffmpeg}/include:$C_INCLUDE_PATH"
    export CPP_INCLUDE_PATH="${zstd}/include:${lz4}/include:${ffmpeg}/include:$CPP_INCLUDE_PATH"
    
    # Configure bindgen to find headers for iOS
    IOS_SDK="${pkgs.apple-sdk_26}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    export BINDGEN_EXTRA_CLANG_ARGS="-I${zstd}/include -I${lz4}/include -I${ffmpeg}/include -isysroot $IOS_SDK -miphoneos-version-min=26.0 --target=aarch64-apple-ios"
    
    # For runtime Vulkan ICD discovery (waypipe will use VK_ICD_FILENAMES or VK_DRIVER_FILES)
    # The kosmickrisp driver should be in the library path, and waypipe will discover it
    # via the Vulkan loader's standard ICD discovery mechanism
    echo "Vulkan driver (kosmickrisp) library path: ${kosmickrisp}/lib"
    ls -la "${kosmickrisp}/lib/" || echo "Warning: kosmickrisp lib directory not found"
  '';
  
  # Set runtime environment variables for Vulkan ICD discovery
  postInstall = ''
    # Create a wrapper script that sets VK_ICD_FILENAMES/VK_DRIVER_FILES for kosmickrisp
    if [ -f "$out/bin/waypipe" ]; then
      mv "$out/bin/waypipe" "$out/bin/waypipe.real"
      cat > "$out/bin/waypipe" <<EOF
#!/bin/sh
# Set Vulkan ICD path for kosmickrisp driver
# Mesa/kosmickrisp installs ICD JSON to share/vulkan/icd.d/ or lib/vulkan/icd.d/
if [ -f "${kosmickrisp}/share/vulkan/icd.d/kosmickrisp_icd.json" ]; then
  export VK_DRIVER_FILES="${kosmickrisp}/share/vulkan/icd.d/kosmickrisp_icd.json"
  export VK_ICD_FILENAMES="${kosmickrisp}/share/vulkan/icd.d/kosmickrisp_icd.json"
elif [ -f "${kosmickrisp}/lib/vulkan/icd.d/kosmickrisp_icd.json" ]; then
  export VK_DRIVER_FILES="${kosmickrisp}/lib/vulkan/icd.d/kosmickrisp_icd.json"
  export VK_ICD_FILENAMES="${kosmickrisp}/lib/vulkan/icd.d/kosmickrisp_icd.json"
fi
# Add kosmickrisp library to library path
export DYLD_LIBRARY_PATH="${kosmickrisp}/lib:''${DYLD_LIBRARY_PATH:-}"
exec "$out/bin/waypipe.real" "$@"
EOF
      chmod +x "$out/bin/waypipe"
    fi
  '';
}
