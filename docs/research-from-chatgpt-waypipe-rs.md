# Waypipe-RS (Rust) Overview, DMA-BUF and Video - Research from ChatGPT

Waypipe is a proxy for Wayland clients (like SSH X forwarding for Wayland). The Rust rewrite of Waypipe ("waypipe-rs") implements the same proxy logic but uses Vulkan for DMA-BUF buffer handling and FFmpeg for optional video encoding[1][2]. By default Waypipe tries to use GPU-acceleration: as one blog notes, "waypipe enables GPU acceleration on the remote side, extracts the result as a texture via DMABUF"[2]. In the Rust port, DMABUF support was re-implemented with Vulkan instead of libgbm[3], and hardware video encoding is done via recent Vulkan video extensions through FFmpeg's encoder/decoder[4]. In practice on Linux this means Wayland clients use the `zwp_linux_dmabuf_v1` protocol, and Waypipe transfers those GPU buffers (or their diffs) over the network.

## macOS Support

macOS does not natively support Linux's DRM or DMA-BUF APIs. To run Wayland clients on macOS you need a compatible compositor (e.g. the Owl compositor). Owl is an Objective-C/Cocoa Wayland compositor that lets you "run Wayland clients inside OS X's native Quartz graphics environment"[5]. To use it you must compile the Wayland libraries and an "epoll-shim" (on BSD/macOS you replace Linux epoll with kqueue) – the Owl GitHub org provides these macOS ports of libwayland, etc.[6]. Once built, Owl.app can display Wayland apps on macOS.

However, without Linux GPU APIs, the GPU path in Waypipe effectively falls back. In fact on similar systems (e.g. SailfishOS), packages disable Waypipe's DMA-BUF and VAAPI video support due to missing `libgbm`/`libvaapi`[7]. On macOS you likewise lack libgbm and the standard hw video path. One strategy is to use a Vulkan-on-Metal driver (such as LunarG's KosmicKrisp) on Apple Silicon[8]. KosmicKrisp provides Vulkan 1.3 on macOS/Metal, so the Waypipe Vulkan code can run (copying and encoding buffers via GPU). This allows the Rust code to process buffers much like on Linux (the DMABUF data itself is still copied into a Vulkan image on the Mac side). In effect, you can use "GPU acceleration" via Vulkan on Metal[8], even though there's no true DMA-FD sharing. If Vulkan isn't available, Waypipe-rs will use shared-memory copies (the `--no-gpu` path).

For video, on macOS/iOS one must supply FFmpeg or similar libraries. The Rust Waypipe dynamically loads `libavcodec`/`libavutil`, so you can install FFmpeg (e.g. via Homebrew) or use a mobile FFmpeg kit. Hardware H.264 support on Apple could come from VideoToolbox; FFmpeg can be built with `-hwaccel videotoolbox`. In any case, video encoding in waypipe would work as on Linux once FFmpeg is present[4]. (Note: without libvaapi on macOS, you rely on other hw encoders. Sailfish examples disabled video for lack of VAAPI[7], but macOS has its own APIs.)

## iOS Support

iOS is similar to macOS but more restrictive. You could embed a Wayland compositor in an iOS app (using UIKit/Cocoa Touch). In principle Owl or a similar compositor could be ported to iOS. Rust supports the `aarch64-apple-ios` target, but you must cross-compile all C libs (Wayland, epoll-shim, Vulkan loader, FFmpeg) for iOS. Like macOS, iOS has no Linux DMA-BUF or VAAPI; the Vulkan/MoltenVK route is possible (MoltenVK runs on iOS). Thus Waypipe-rs on iOS would essentially use shared-memory buffers or Vulkan on Metal for GPU paths, just as on macOS. DMA-FD from Linux won't work; one would treat those buffers as generic image data. Video on iOS would use FFmpeg or Apple's encoder (FFmpegKit provides iOS packages). In summary, the behavior is the same as macOS: no true DMA-BUF, but you can enable the Vulkan+FFmpeg features via alternate APIs[8][1], while disabling/removing Linux-specific bits (which Sailfish did for lack of GBM[7]).

## Android Support

Android runs on a Linux kernel, so DMA-BUF is available (e.g. gralloc buffers). If you have a Wayland compositor on Android (such as Waydroid's Weston/Wayfire or a custom app), Waypipe-rs can run on Android as it does on desktop Linux. You would cross-compile for Android (via the NDK, target `aarch64-linux-android` or `armv7`) and build libwayland, Vulkan loader, FFmpeg, etc. The GPU path works normally: Android's GPU drivers support `zwp_linux_dmabuf_v1` for buffer passing. Thus Waypipe can accelerate via DMABUF on Android just like Linux. Video encoding on Android can be done via FFmpeg (NDK build) or Android's MediaCodec (FFmpegKit also supports Android).

One thing to watch: Rust's foreign types differ by platform. For example, C's `char` may map to signed vs unsigned differently[9], so the Rust bindings should use `std::ffi::c_char` for portability[9]. In practice you'd ensure all C ABI types (`c_char`, `c_int`, etc.) are handled correctly when cross-compiling to Android vs Apple.

## Summary: What to Port and How

In summary, to use waypipe-rs from Linux onto macOS/iOS/Android, you need:

- A Wayland server on the target device (e.g. Owl on macOS/iOS, or a Wayland compositor on Android) that supports `zwp_linux_dmabuf_v1` and basic protocols. Owl's instructions emphasize building Wayland and epoll-shim for macOS[6].
- Vulkan (KosmicKrisp/MoltenVK) if you want GPU acceleration: this satisfies the Vulkan-based DMABUF/video code in waypipe[1][8]. Without it, use `--no-gpu`.
- FFmpeg libraries (or OS video codecs) for the video feature. You can compile FFmpeg for each platform or embed a prebuilt kit. The Rust code will load `libavcodec` at runtime[4].
- For macOS/iOS: expect that Waypipe's DMA-BUF and hardware video flags may default to off (as on Sailfish)[7], so you must handle buffers in software or via Vulkan.
- For Android: treat it like a Linux desktop – install Vulkan (most devices have it) and FFmpeg via NDK. DMA-BUF behaves normally.

Rust's porting is straightforward as long as dependencies are met. The key is replacing Linux-specific bits (GBM, VAAPI) with equivalent paths on each OS. The cited examples show that Waypipe-rs's use of Vulkan/FFmpeg makes it fundamentally portable, relying on cross-platform GPU interfaces[1]. Just compile the C libraries and link against them. With those in place, Waypipe-rs can run Linux Wayland clients and display them on your macOS/iOS/Android compositor, even though the underlying buffer passing is different on each OS.

## Sources

Waypipe (Rust) implementation details[1][9]; Owl compositor docs for macOS Wayland[5][6]; GPU/Vulkan on Apple (KosmicKrisp)[8]; Waypipe DMA-BUF default behavior[2]; examples of DMABUF/VAAPI disabled on non-Linux OS[7].

### References

[1][3][4][9] On rewriting Waypipe in Rust  
https://mstoeckl.com/notes/code/waypipe_to_rust.html

[2] Waypipe fixes  
https://trofi.github.io/posts/265-waypipe-fixes.html

[5][6] GitHub - owl-compositor/owl: The portable Wayland compositor in Objective-C  
https://github.com/owl-compositor/owl

[7] Fun with remote Wayland: WayPipe - Applications - Sailfish OS Forum  
https://forum.sailfishos.org/t/fun-with-remote-wayland-waypipe/16997

[8] KosmicKrisp Now Vulkan 1.3 Compliant For Apple Devices - Phoronix  
https://www.phoronix.com/news/KosmicKrisp-Vulkan-1.3
