Nice — I searched upstream Mesa and the KosmicKrisp announcements and pulled together a concrete, source-backed inventory of what you need to build **KosmicKrisp (KosmicKrisp = LunarG’s Vulkan→Metal Mesa driver)** on **macOS**, what the driver’s build-time library dependencies are, and what it needs at runtime.

I couldn’t find a single “one-line” manifest in the announcements, so I compiled the lists from the Mesa build docs/meson files and LunarG/Khronos/Phoronix announcements (links cited inline). Where something is optional or platform-specific I call that out and point to how to confirm it from upstream.

---

# Short summary (high level)

* KosmicKrisp is a **Mesa Vulkan driver** that translates Vulkan to **Apple Metal** and has been published/announced by LunarG and upstreamed to Mesa. ([LunarG][1])
* Building it on macOS uses **Mesa’s Meson/Ninja build**; you must satisfy the usual Mesa build toolchain plus the Vulkan shader/SPIR-V toolchain and a few Apple tool/framework requirements (Xcode SDK/Metal). ([docs.mesa3d.org][2])

---

# A. **Build-tools / toolchain (what to install to *build* KosmicKrisp on macOS)**

These are the *tools* (programs, build system components, SDKs) you need before configuring/building Mesa with `-Dvulkan-drivers=kosmickrisp`:

1. **Xcode Command Line Tools / macOS SDK** — clang/clang++ toolchain and system headers (required to compile C/C++ and link against system frameworks like Metal). *(install via `xcode-select --install`)*. (Required). ([LunarG][1])
2. **git** — to clone upstream Mesa. ([docs.mesa3d.org][3])
3. **Python 3** (python3) and `pip` — Meson is a Python tool; Mesa build uses Python for codegen. ([mesonbuild.com][4])
4. **meson** (recent version; install with `pip3 install --user meson` or via Homebrew). Mesa’s docs require Meson for the modern build. ([docs.mesa3d.org][2])
5. **ninja** — Meson’s default backend. (`brew install ninja` or `pipx` package wrappers). ([mesonbuild.com][4])
6. **pkg-config** — Meson + many deps use pkg-config. (`brew install pkg-config`). ([mesonbuild.com][4])
7. **Mako Python module** (`pip3 install mako`) — Mesa templates depend on it. Mesa macOS notes explicitly mention Mako. ([docs.mesa3d.org][5])
8. **Flex and Bison** — used for some generated parsers; Meson docs and Mesa note them as build requirements in some configurations. (`brew install flex bison`). ([docs.mesa3d.org][2])
9. **(optional / conditional) LLVM toolchain** — some Mesa subcomponents (and optional shader compiler backends) use LLVM; Meson has `-Dllvm=enabled/disabled` options. Install via `brew install llvm` if you want the LLVM-based parts. (Optional but commonly required for full feature builds). ([gensoft.pasteur.fr][6])

Practical Homebrew-ish install line (example):
`xcode-select --install` then, roughly:
`brew install git python3 meson ninja pkg-config flex bison llvm spirv-tools spirv-headers glslang`
and `pip3 install --user mako meson` (meson usually via pip or brew). (I list the package names below in the library section too). ([Homebrew Formulae][7])

---

# B. **Build-time library / third-party dependencies used when building the *KosmicKrisp* driver inside Mesa**

These are the libraries/dependencies Mesa expects to find when building **Vulkan drivers** and — specifically — what KosmicKrisp reuses from Mesa upstream. (Where upstream makes something required, I cite the Meson dependency usage in Mesa.)

**Required / strongly expected at build time** (driver will not configure if these are missing):

1. **SPIRV-Tools** (`SPIRV-Tools`) — Mesa’s meson build checks for this and it is required for Vulkan driver builds (assembler/validator/optimizer for SPIR-V). Homebrew: `brew install spirv-tools`. ([GitHub][8])
2. **SPIRV-Headers** — headers for SPIR-V. (Often a build dependency together with SPIRV-Tools). ([Linux From Scratch][9])
3. **glslang** (glslangValidator) — used by many Vulkan stacks to compile GLSL to SPIR-V during tests/tooling; commonly pulled in for build/test flows. (Homebrew: `glslang` / `glslangValidator` packages). ([LunarXchange][10])
4. **zlib, expat** — standard small libraries used by Mesa build system (zlib for compression, expat for XML parsing in some tools). (Common Mesa deps). ([Mesa Documentation][11])
5. **Python modules used by Meson/Mesa** — `mako`, `packaging` (already noted above). ([docs.mesa3d.org][2])

**Mesa / Vulkan-driver specific pieces that KosmicKrisp relies on (in-tree or as usual dependencies):**

6. **Mesa’s NIR + in-tree shader toolchain** — KosmicKrisp intentionally leverages Mesa’s NIR IR and in-tree tools to remove the need for SPIRV-Cross. Upstream presentation explicitly mentions NIR and removing SPIRV-Cross. (This is why some SPIR-V→NIR tooling is required at build time). ([The Khronos Group][12])
7. **(possible) SPIRV-LLVM-Translator / SPIRV-LLVM (optional)** — depends on your Meson options and whether LLVMPIR translation is used; many distributions include it for completeness. (Optional depending on build flags). ([Linux From Scratch][9])

**Optional / configuration-dependent deps you may see in `meson configure` for kosmickrisp:**

8. **LLVM if you enable llvm backends** (see Meson options `-Dllvm=`). ([gensoft.pasteur.fr][6])
9. **libdrm / libepoxy / X11 / Wayland** — *not required on macOS for the Metal-based path*, but Mesa’s meson options include them for other drivers; on macOS these are usually disabled. (You will see these listed by Meson if you try to build other plumbing). ([docs.mesa3d.org][13])

**Where to confirm exact, current build-time deps for the version you’re using:** clone upstream Mesa and run Meson configure (Meson prints required/missing deps). Upstream source + meson.options / meson.build are authoritative. Example: `git clone https://gitlab.freedesktop.org/mesa/mesa.git && meson setup build -Dvulkan-drivers=kosmickrisp && meson configure build`. The Mesa docs explain this workflow. ([docs.mesa3d.org][3])

---

# C. **Runtime dependencies of KosmicKrisp driver on macOS (what must be present on the *target* machine when you run apps using KosmicKrisp)**

These are the libraries/frameworks the driver needs at runtime (what the driver calls into on a running macOS system):

1. **Apple Metal framework** — KosmicKrisp translates Vulkan calls to Metal; it *runs on top of Metal*, so the system **Metal.framework** is a hard runtime dependency. (LunarG explicitly states KosmicKrisp translates Vulkan to Apple Metal and targets macOS 13/15 baselines.) ([LunarG][1])

2. **macOS system frameworks / runtime (CoreFoundation, CoreGraphics as typical)** — standard system frameworks used by drivers and Mesa plumbing. (Implicit; provided by macOS.) ([LunarG][1])

3. **IOSurface (and related frameworks) — likely/commonly used for texture/buffer sharing**

   * Rationale:* Metal textures can be backed by IOSurface for efficient sharing and zero-copy. Many cross-process/VM/guest→host buffer schemes on macOS use IOSurface. A Vulkan→Metal driver that needs shared buffers (for example when integrating with VMs or compositors) will commonly use IOSurface APIs at runtime. Apple docs show `makeTexture(descriptor: iosurface: plane:)` and IOSurface is the canonical system facility for sharing pixel buffers on macOS. If KosmicKrisp implements things like WSI/texture import or VM buffer exchange, IOSurface will be involved. (Labelled **likely** — check mesa WSI/metal backend code to see which exact APIs are used). ([Apple Developer][14])

4. **(Possibly) Video/CoreVideo/CoreMedia frameworks** — if the driver (or tests) interoperate with video/decoder pipelines, these frameworks may be used — but this is scenario dependent. (Optional.) ([Apple Developer][15])

5. **No external Vulkan loader binary required for Mesa driver itself** — the usual model is that Mesa builds a Vulkan ICD (driver) library that is enumerated by the Vulkan loader (on systems where a loader is used). On macOS the runtime arrangement depends on how you package: LunarG also ships a Vulkan SDK and loader pieces; LunarG’s Vulkan SDK packaging and their KosmicKrisp work are coordinated. In short: at runtime you need the loader/environment that will find the ICD built from Mesa — LunarG’s SDK handles that for app integration. ([LunarG][16])

---

# D. **Concrete, actionable commands & how to confirm exactly for the upstream tree you’ll build**

1. Clone upstream Mesa (authoritative):

```bash
git clone https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa
```

2. Install build tools (example macOS / Homebrew quick list):

```bash
xcode-select --install
brew install git python3 meson ninja pkg-config flex bison spirv-tools spirv-headers glslang
pip3 install --user mako
```

(Adjust for LLVM if you enable `-Dllvm=enabled`.) ([docs.mesa3d.org][5])

3. Configure Meson for KosmicKrisp (example):

```bash
meson setup build -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dplatforms=osx
meson configure build   # shows which dependencies are found / missing
meson compile -C build
sudo meson install -C build
```

Meson prints missing/optional deps and the active options; that’s the single-source way to know the exact deps for the exact Mesa commit you built. ([docs.mesa3d.org][2])

---

# E. **Where I got this / important source references (most relevant upstream sources)**

* LunarG KosmicKrisp announcement and XDC slides (overview + Mac / Metal target details). ([LunarG][1])
* Mesa build docs / Meson instructions (how Mesa builds on macOS; Meson & Ninja; Mako requirement). ([docs.mesa3d.org][2])
* Mesa meson.build references showing SPIRV-Tools as a Meson dependency for Vulkan toolchain. ([GitHub][8])
* Homebrew `spirv-tools` formula (practical install). ([Homebrew Formulae][7])
* Apple docs for **IOSurface** and Metal texture APIs (why IOSurface is likely a runtime requirement for zero-copy textures on macOS). ([Apple Developer][17])
* News coverage / upstream merge notes showing KosmicKrisp merged into Mesa (Phoronix / news / repo logs). ([Phoronix][18])

---

# F. **Caveats / recommended next steps**

* **Exact dependencies change with Mesa commit / Meson options.** The authoritative source is the exact Mesa commit you intend to build — `meson configure` will show “found / missing” dependencies for that tree. I strongly recommend cloning the exact upstream Mesa commit and running `meson configure` to get the guaranteed inventory. (Meson prints the list and which ones are required vs optional). ([docs.mesa3d.org][2])

* **Runtime nuance:** KosmicKrisp is *a* Mesa Vulkan driver that targets Metal — that makes **Metal.framework** an inescapable runtime requirement. Other macOS kernel or compositor integration details (IOSurface, CVPixelBuffer, compositor glue) depend on which features WSI / VM / emulator integrations you need; inspect the *wsi/metal* and *vulkan/kosmic* code in the Mesa tree for exact runtime API usage. (I can fetch the exact files / code lines if you want me to extract them from the current upstream Mesa commit.) ([Freedesktop][19])

---

If you want, I can do one of the following *right now* (pick one and I’ll run it and paste the results):

* A. Clone the current upstream Mesa tree (I’ll use the public freedesktop repo) and run `meson configure` (read the meson options) for the commit that contains `kosmickrisp` and extract the exact Meson options and dependency names (the authoritative list for that commit).
* B. Open the exact Mesa files that add KosmicKrisp (wsi/metal and the kosmickrisp driver src) and list the `#include`/linking references that reveal explicit runtime frameworks/APIs used (e.g., `#import <Metal/Metal.h>`, `IOSurface.h`, etc.). That will let us enumerate exact runtime frameworks (Metal, IOSurface, etc.) used by the driver code.
* C. Give a ready-to-paste Homebrew + pip install script tailored to the current upstream Mesa + KosmicKrisp so you can start a build locally.

Tell me which of A / B / C you want and I’ll fetch the exact upstream files and give a precise, line-by-line list (this will remove any remaining uncertainty about optional vs required items).

[1]: https://www.lunarg.com/lunarg-at-xdc-2025-kosmickrisp-overview/?utm_source=chatgpt.com "LunarG at XDC 2025: KosmicKrisp Overview"
[2]: https://docs.mesa3d.org/meson.html?utm_source=chatgpt.com "Compilation and Installation Using Meson - Mesa 3D"
[3]: https://docs.mesa3d.org/repository.html?utm_source=chatgpt.com "Source Code Repository - The Mesa 3D Graphics Library"
[4]: https://mesonbuild.com/Quick-guide.html?utm_source=chatgpt.com "Quickstart Guide"
[5]: https://docs.mesa3d.org/macos.html?utm_source=chatgpt.com "Notes for macOS - The Mesa 3D Graphics Library"
[6]: https://gensoft.pasteur.fr/docs/mesa/19.0.8/meson.html?utm_source=chatgpt.com "Compilation and Installation using Meson"
[7]: https://formulae.brew.sh/formula/spirv-tools?utm_source=chatgpt.com "spirv-tools"
[8]: https://github.com/Igalia/mesa/blob/main/meson.build?utm_source=chatgpt.com "meson.build - Igalia/mesa"
[9]: https://www.linuxfromscratch.org/blfs/view/svn/general/spirv-tools.html?utm_source=chatgpt.com "SPIRV-Tools-1.4.328.1"
[10]: https://vulkan.lunarg.com/doc/view/latest/windows/spirv_toolchain.html?utm_source=chatgpt.com "SPIR-V Toolchain"
[11]: https://mesa-docs.readthedocs.io/en/latest/install.html?utm_source=chatgpt.com "Compiling and Installing — Mesa 12.0 documentation"
[12]: https://www.khronos.org/developers/linkto/kosmickrisp-a-vulkan-to-metal-mesa-driver?utm_source=chatgpt.com "KosmicKrisp A Vulkan to Metal Mesa driver"
[13]: https://docs.mesa3d.org/install.html?utm_source=chatgpt.com "Compiling and Installing - The Mesa 3D Graphics Library"
[14]: https://developer.apple.com/documentation/metal/mtldevice/maketexture%28descriptor%3Aiosurface%3Aplane%3A%29?utm_source=chatgpt.com "makeTexture(descriptor:iosurface:plane:)"
[15]: https://developer.apple.com/la/videos/play/wwdc2020/10090/?utm_source=chatgpt.com "Decode ProRes with AVFoundation and VideoToolbox ..."
[16]: https://www.lunarg.com/where-do-i-find-the-list-of-whats-included-in-the-vulkan-sdk/?utm_source=chatgpt.com "Where do I find the list of what's included in the Vulkan SDK?"
[17]: https://developer.apple.com/documentation/iosurface?utm_source=chatgpt.com "IOSurface | Apple Developer Documentation"
[18]: https://www.phoronix.com/news/KosmicKrisp-Merged-Mesa-26.0?utm_source=chatgpt.com "KosmicKrisp Vulkan To Apple Metal Driver Merged For ..."
[19]: https://cgit.freedesktop.org/mesa/mesa/log/?q=lunarg&qt=author&utm_source=chatgpt.com "mesa/mesa - The Mesa 3D Graphics Library (mirrored from ..."
