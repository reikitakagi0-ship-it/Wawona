# kosmickrisp Build Comparison: Standard vs Nix

## Standard Build Process (macOS)

### Prerequisites
```bash
# Install build tools
brew install meson ninja pkg-config bison flex
pip3 install mako pyyaml

# Install dependencies
brew install llvm spirv-tools spirv-headers spirv-llvm-translator
# Note: libclc may need to be built separately or obtained from nixpkgs
```

### Standard Meson Build Command
```bash
git clone https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa

meson setup builddir \
  --prefix=/usr/local \
  --libdir=lib \
  -Dvulkan-drivers=kosmickrisp \
  -Dgallium-drivers= \
  -Dplatforms= \
  -Dglx=disabled \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dtools= \
  -Dvulkan-beta=true \
  -Dbuildtype=release \
  -Dglvnd=disabled \
  -Dgallium-va=disabled \
  --default-library=shared

ninja -C builddir
ninja -C builddir install
```

### Key Dependencies (Standard Build)
- **LLVM** (with Clang) - Required for NIR compilation
- **SPIRV-Tools** - SPIR-V manipulation library
- **SPIRV-Headers** - SPIR-V header files
- **SPIRV-LLVM-Translator** - LLVM-SPIRV translation
- **libclc** - OpenCL C library (may be optional for kosmickrisp)
- **zlib, zstd, expat** - Standard libraries
- **Python packages**: mako, pyyaml, setuptools, packaging
- **Metal frameworks** - Automatically found on macOS

### Environment Variables (if needed)
```bash
export PKG_CONFIG_PATH="/path/to/spirv-tools/lib/pkgconfig:/path/to/spirv-llvm-translator/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="/path/to/llvm/bin:$PATH"
```

---

## Our Nix Build Setup

### macOS (`dependencies/deps/mesa-kosmickrisp/macos.nix`)

**Build Flags:**
```nix
buildFlags = [
  "-Dvulkan-drivers=kosmickrisp"      # ✅ Matches standard
  "-Dgallium-drivers="                 # ✅ Matches standard (empty)
  "-Dplatforms="                       # ✅ Matches standard (empty)
  "-Dglx=disabled"                     # ✅ Matches standard
  "-Degl=disabled"                     # ✅ Matches standard
  "-Dgbm=disabled"                     # ✅ Matches standard
  "-Dtools="                           # ✅ Matches standard (empty)
  "-Dvulkan-beta=true"                 # ✅ Matches standard
  "-Dbuildtype=release"                # ✅ Matches standard
  "-Dglvnd=disabled"                   # ✅ Matches standard
  "-Dgallium-va=disabled"              # ✅ Matches standard
]
```

**Dependencies:**
```nix
depInputs = [
  "zlib"                    # ✅ Standard
  "zstd"                    # ✅ Standard
  "expat"                   # ✅ Standard
  "llvm"                    # ✅ Standard (includes LLVM)
  "clang"                   # ✅ Standard (part of LLVM)
  "spirv-llvm-translator"   # ✅ Standard
  "spirv-tools"             # ✅ Standard
  "spirv-headers"           # ✅ Standard
  "libclc"                  # ⚠️  May not be needed for kosmickrisp
]
```

**Native Build Inputs:**
```nix
nativeBuildInputs = [
  meson ninja pkg-config
  python3.withPackages (mako pyyaml setuptools pip packaging)
  bison flex
]
# ✅ All standard build tools present
```

**Configuration:**
```nix
configurePhase = ''
  # Metal frameworks via LDFLAGS
  export LDFLAGS="-framework Metal -framework MetalKit -framework Foundation -framework IOKit -L${llvm.lib}/lib"
  
  # PKG_CONFIG_PATH for SPIRV deps
  export PKG_CONFIG_PATH="${spirv-llvm-translator}/lib/pkgconfig:${spirv-tools}/lib/pkgconfig:${spirv-headers}/lib/pkgconfig:${llvm.dev}/lib/pkgconfig"
  
  # llvm-config in PATH
  export PATH="${llvm.dev}/bin:$PATH"
  
  meson setup build \
    --prefix=$out \
    --libdir=$out/lib \
    --default-library=shared \  # ✅ Ensures .dylib output
    ${buildFlags}
''
```

### iOS (`dependencies/deps/mesa-kosmickrisp/ios.nix`)

**Cross-Compilation Setup:**
```nix
preConfigure = ''
  # Xcode SDK detection
  SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
  
  # Cross-compilation file
  cat > ios-cross-file.txt <<EOF
  [binaries]
  c = '$IOS_CC'
  cpp = '$IOS_CXX'
  ar = 'ar'
  strip = 'strip'
  pkgconfig = 'pkg-config'
  
  [host_machine]
  system = 'darwin'
  cpu_family = 'aarch64'
  cpu = 'aarch64'
  endian = 'little'
  
  [built-in options]
  c_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-fPIC']
  cpp_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-fPIC']
  c_link_args = ['-arch', 'arm64', '-isysroot', '$SDKROOT', '-miphoneos-version-min=15.0', '-framework', 'Metal', ...]
  EOF
''

configurePhase = ''
  meson setup build \
    --cross-file=ios-cross-file.txt \  # ✅ Standard cross-compilation approach
    --default-library=shared \          # ✅ Ensures .dylib output
    ${buildFlags}
''
```

---

## Comparison Summary

### ✅ What We Got Right

1. **Build Flags**: All meson options match the standard build
2. **Dependencies**: All required dependencies are included
3. **Shared Library Output**: `--default-library=shared` ensures .dylib files
4. **Metal Framework Linking**: Properly configured for macOS/iOS
5. **Cross-Compilation**: iOS setup follows standard Meson cross-file approach
6. **PKG_CONFIG_PATH**: Properly configured for SPIRV dependencies

### ⚠️ Potential Issues / Differences

1. **libclc Dependency**:
   - **Standard**: May be optional for kosmickrisp (Vulkan-only, no OpenCL)
   - **Our Setup**: Currently included, but causing clangBasic linking issues
   - **Action**: Investigate if kosmickrisp actually needs libclc

2. **clangBasic Library Issue**:
   - **Problem**: Mesa's meson.build requires `clangBasic` when libclc is present
   - **Standard Build**: Would have same issue if libclc is installed
   - **Action**: Either:
     a) Make libclc optional/disable it for kosmickrisp
     b) Fix clangBasic detection in Mesa's meson.build
     c) Ensure Clang libraries are properly exposed

3. **Missing from Standard Examples**:
   - Standard examples don't show explicit Metal framework linking (auto-detected)
   - Our explicit `-framework` flags are fine, but may be redundant

### 🔍 Investigation Results

**✅ CONFIRMED: kosmickrisp DOES need libclc**

From Mesa's `meson.build`:
```meson
with_driver_using_cl = [
  with_gallium_iris, with_intel_vk,
  with_gallium_asahi, with_asahi_vk, with_tools.contains('asahi'),
  with_gallium_panfrost, with_panfrost_vk,
  with_nouveau_vk, with_imagination_vk,
  with_kosmickrisp_vk,  # <-- kosmickrisp is listed here!
].contains(true)

with_clc = get_option('mesa-clc') != 'auto' or \
           with_microsoft_clc or with_gallium_rusticl or \
           with_drivers_clc or with_driver_using_cl  # <-- includes kosmickrisp

dep_clc = null_dep
if with_clc
  dep_clc = dependency('libclc')  # <-- Required when kosmickrisp is enabled
endif
```

**✅ CONFIRMED: clangBasic requirement comes from libclc**

From Mesa's `meson.build`:
```meson
if with_clc
  llvm_libdir = dep_llvm.get_variable(cmake : 'LLVM_LIBRARY_DIR', configtool: 'libdir')
  
  dep_clang = cpp.find_library('clang-cpp', dirs : llvm_libdir, required : false)
  
  if not dep_clang.found() or not _shared_llvm
    clang_modules = [
      'clangBasic', 'clangAST', 'clangCodeGen', ...  # <-- Falls back to individual modules
    ]
```

**The Problem:**
- Mesa first tries to find `clang-cpp` library
- If not found, it tries individual Clang modules (`clangBasic`, etc.)
- Our Nix setup has Clang but Mesa can't find the libraries

**The Problem:**
- Mesa first tries to find `clang-cpp` library via `cpp.find_library('clang-cpp', dirs : llvm_libdir)`
- `llvm_libdir` comes from `dep_llvm.get_variable(configtool: 'libdir')` which uses `llvm-config --libdir`
- In nixpkgs, Clang libraries are NOT in LLVM's libdir - they're separate packages
- When `clang-cpp` isn't found, Mesa falls back to individual modules (`clangBasic`, etc.)
- But those modules also need to be in `llvm_libdir` or Mesa can't find them

**The Solution:**
We need to ensure Clang libraries are findable where Mesa expects them. Options:

1. **Symlink Clang libraries into LLVM libdir** (during build):
   ```nix
   preConfigure = ''
     # Symlink Clang libs to where Mesa expects them (LLVM libdir)
     LLVM_LIBDIR="${pkgs.llvmPackages.llvm.lib}/lib"
     CLANG_LIBDIR="${pkgs.llvmPackages.clang.lib}/lib"
     for lib in $CLANG_LIBDIR/libclang*.dylib $CLANG_LIBDIR/libclang*.a; do
       if [ -f "$lib" ]; then
         ln -sf "$lib" "$LLVM_LIBDIR/$(basename $lib)"
       fi
     done
   '';
   ```

2. **Use meson's dirs parameter** - Patch Mesa's meson.build to also search Clang libdir

3. **Ensure Clang is in buildInputs** - Already done, but may need explicit library paths

4. **Check if nixpkgs LLVM includes Clang** - May need to use a different LLVM package that includes Clang

---

## Recommended Next Steps

### 1. Test Standard Build Locally (to verify it works)
```bash
git clone https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa

# Install dependencies via Homebrew
brew install llvm spirv-tools spirv-headers spirv-llvm-translator libclc
pip3 install mako pyyaml

# Build kosmickrisp
meson setup builddir \
  --prefix=/usr/local \
  --libdir=lib \
  -Dvulkan-drivers=kosmickrisp \
  -Dgallium-drivers= \
  -Dplatforms= \
  -Dglx=disabled \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dtools= \
  -Dvulkan-beta=true \
  -Dbuildtype=release \
  --default-library=shared

ninja -C builddir
```

**Expected Result**: Should build successfully if Clang libraries are available

### 2. Fix clangBasic Issue in Nix

**Root Cause**: Mesa's meson.build looks for Clang C++ libraries (`clangBasic`, `clangAST`, etc.) in the directory returned by `llvm-config --libdir`. In nixpkgs, these libraries may not be in that location or may not be built as shared libraries.

**Solutions**:

**Option A: Patch Mesa's meson.build** (Recommended)
Create a patch that makes Clang library detection more flexible:
```nix
patches = [
  (pkgs.writeText "mesa-clang-libdir.patch" ''
    diff --git a/meson.build b/meson.build
    index... 
    --- a/meson.build
    +++ b/meson.build
    @@ -XXX,XXX +XXX,XXX @@
    -  dep_clang = cpp.find_library('clang-cpp', dirs : llvm_libdir, required : false)
    +  # Also search in common Clang library locations
    +  clang_libdirs = [llvm_libdir]
    +  if get_option('clang-libdir') != ''
    +    clang_libdirs += [get_option('clang-libdir')]
    +  endif
    +  dep_clang = cpp.find_library('clang-cpp', dirs : clang_libdirs, required : false)
  '')
];
```

**Option B: Ensure Clang libraries are available**
- Check if nixpkgs LLVM includes Clang C++ libraries
- If not, build Clang with shared libraries enabled
- Or use a different LLVM package that includes Clang

**Option C: Use Mesa's system libclc option**
- Set `-Dmesa-clc=system` and provide a pre-built libclc
- This might avoid the Clang library requirement

### 3. Verify Our Configuration Matches Standard

**✅ Confirmed Matches:**
- All meson build flags are identical
- Dependencies match standard requirements
- Cross-compilation setup follows Meson conventions
- Metal framework linking is correct

**⚠️ Known Difference:**
- Clang library detection issue (affects both standard and Nix if Clang libs aren't in expected location)

---

## Standard Build Command (Reference)

```bash
# macOS - Standard way
meson setup builddir \
  --prefix=/usr/local \
  --libdir=lib \
  -Dvulkan-drivers=kosmickrisp \
  -Dgallium-drivers= \
  -Dplatforms= \
  -Dglx=disabled \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dtools= \
  -Dvulkan-beta=true \
  -Dbuildtype=release \
  --default-library=shared

ninja -C builddir
```

**Our Nix equivalent:**
```nix
meson setup build \
  --prefix=$out \
  --libdir=$out/lib \
  -Dvulkan-drivers=kosmickrisp \
  -Dgallium-drivers= \
  -Dplatforms= \
  -Dglx=disabled \
  -Degl=disabled \
  -Dgbm=disabled \
  -Dtools= \
  -Dvulkan-beta=true \
  -Dbuildtype=release \
  --default-library=shared
```

**✅ Configuration is identical!** The only issue is Clang library detection, which is a dependency/environment issue, not a configuration problem.
