# Wayland on macOS (Darwin) - Research from ChatGPT

Wayland's core libraries can be built on macOS, but macOS lacks many Linux-specific interfaces. In practice Wayland's protocol library and tools compile on Darwin using shims. For example, MacPorts provides a Wayland port (v2023.01.28) that depends only on `epoll-shim`, `libffi`, and `libxml2` (plus build tools like clang, Meson, Ninja)[1]. The crucial missing piece on macOS is Linux's `epoll`: this is handled by using `epoll-shim`, a small library that implements epoll on top of BSD's `kqueue`. Epoll-shim has been "successfully used to port libinput, libevdev, Wayland and more software to FreeBSD"[2], and it supports macOS (tested on macOS 13.7.1)[3]. In short, a developer can compile Wayland on macOS today by installing epoll-shim and the other dependencies (Meson, Ninja, pkg-config, etc.)[1][2].

However, building the Wayland protocol libraries is only half the story. Running a real Wayland compositor on macOS is more complex. macOS has no DRM/KMS or Linux input stack; instead it uses the Quartz Compositor and Cocoa for windowing and events. Any Mac compositor must hook into Cocoa (for OpenGL/Metal drawing and input events). In fact, the Owl project demonstrates this approach: Owl is a Wayland compositor written in Objective-C that uses Cocoa. It "makes it possible to run Wayland clients inside OS X's native Quartz graphics environment" – essentially acting like an XQuartz or XWayland for Wayland[4]. Owl (and similar forks) show that a macOS Wayland compositor must translate Wayland surfaces into native Quartz windows and convert macOS input (NSEvents) into Wayland events.

In summary, Wayland on macOS requires:

- **Shimming Linux APIs** (using epoll-shim for event loops, and providing or emulating missing syscalls like `timerfd`/`signalfd`). In fact, porting Weston to Android already required removing Linux-only calls like `signalfd` and `timerfd` because Android's Bionic libc lacks them[5]; the same will hold for Darwin's libc.
- **Custom compositor code** on top of Cocoa. There are no ready-made compositors for macOS aside from experimental ones like Owl. A developer would have to write (or adapt) a compositor to use macOS graphics and window APIs.
- **Input device support**. Linux compositors use libinput and evdev; on macOS you'd instead use native input APIs (or port libinput via something like a wscons backend, but more likely just use Cocoa events). No out-of-the-box solution exists.

Despite these hurdles, the basic Wayland libraries can run on macOS. Maintained forks on GitHub (for example XQuartz's wayland mirror or Owl's wayland mirror) exist, and tools like MacPorts make installation straightforward[1][4]. Some low-level code (like epoll-shim) is already upstreamable and works across BSD/Darwin. But high-level support (graphics, input) must be handled by a compositor implementation for macOS.

## Dependencies and Portability

The Wayland protocol is implemented in a set of C libraries (`libwayland-client`, `libwayland-server`, etc.) with relatively few dependencies beyond basic infrastructure. Key build dependencies are a recent C compiler and build tools (Meson, Ninja, pkg-config)[6]. The only library dependencies are `libxml2` and `libffi` (both available on macOS), and an epoll-replacement for non-Linux systems. MacPorts' Wayland port explicitly lists `epoll-shim`, `libffi`, and `libxml2`[1]. On BSD/Darwin, `libudev` (Linux device enumeration) isn't needed for the protocol itself, though it would be needed if using libinput for input devices.

Notably, Wayland was designed for Linux kernel features (DRM/KMS, udev, evdev). On FreeBSD/OpenBSD, ports exist that reimplement these via kqueue or wscons. For example, `libinput-openbsd` uses wscons(4) and kqueue to mimic Linux input[7]. Epoll-shim works with FreeBSD's kqueue (and macOS's kqueue)[2]. Thus, in principle Wayland can be "ported" to any BSD-like system by providing these shims. In fact, epoll-shim's documentation explicitly mentions macOS support[3], and there are experimental Wayland ports on FreeBSD (via FreshPorts)[8]. The main missing pieces across non-Linux targets are the graphics and input backends (i.e. how buffers get to the screen, how keyboard/mouse events are read).

## Wayland on iOS

iOS presents even greater challenges. iOS (iPhone/iPad OS) is not a general-purpose Unix environment and does not allow third-party display servers. There is no X or Wayland at all; apps must use UIKit/Metal/OpenGL ES to render to the screen. Unlike macOS, you cannot spawn a rootless compositor to take over the display. In addition, iOS's system libraries lack many Linux APIs (similar to Android's Bionic). For example, iOS has no `epoll`, no `timerfd`/`signalfd` (only kqueue, and even that is limited), and the app sandbox prevents opening arbitrary Unix sockets without special entitlement.

In practical terms, running Wayland on iOS would mean writing a custom compositor within an iOS app (essentially a full-screen app that implements the Wayland server API), and using Core Animation/Metal to present client buffers. There is no public example of a Wayland port to iOS. The closest analogy is that macOS requires an Owl-like compositor; iOS would require an even more bespoke solution. Given the constraints, Wayland will not work on iOS out of the box – it would need a complete rewrite of input/output layers to use iOS APIs, and even then it may violate iOS's sandbox.

(For context, a similar effort on Android had to remove Linux-specific calls: Paalanen's Weston port to Android "completely remove[d] signal handling and timers from libwayland, because signalfd and timerfd … do not exist in Bionic"[5]. Darwin's libc lacks those too, so the same modifications would be needed on iOS.)

## Wayland on Android

Android is closer to Linux under the hood, but its graphics stack is very different. Vanilla Android uses the SurfaceFlinger compositor with an `ANativeWindow` interface, not X11 or Wayland. To run Wayland on Android, one typically uses the `libhybris` compatibility layer. In effect, libhybris provides a meta-EGL implementation that exposes Wayland's EGL extensions on top of Android's windowing. Projects like Sailfish OS (by Jolla) use this: a Wayland compositor runs on an Android device by rendering to an `ANativeWindow` provided by SurfaceFlinger.

In practice, developers have ported Weston to Android. Paalanen's proof-of-concept showed Weston driving an Android phone's framebuffer by writing an Android-specific backend, but it required heavy hacks: removing unsupported syscalls, using Android's gralloc and wrapper-libEGL, and killing SurfaceFlinger to take over the display[9][10]. More recently, Faith Ekstrand explains that libhybris works by implementing Wayland's EGL (`eglBindWaylandDisplayWL`) using Android's fences and ANativeWindow. This approach has succeeded enough that "Jolla (among others) is shipping devices" running Wayland on Android hardware[11].

However, fundamental mismatches remain. Android's EGL swap semantics conflict with Wayland's expectations. In Wayland, each `eglSwapBuffers()` must implicitly attach and commit a `wl_buffer` to the surface. But on Android, swapping an `ANativeWindow` can be delayed or even skipped (the driver may preserve the previous buffer), violating Wayland's assumption[12]. Ekstrand notes the "core collision" – "Android provides no real guarantees as to what a driver has to do inside of eglSwapBuffers", making the Wayland guarantee effectively impossible[12]. Libhybris hacks (like using sync fences) can mitigate this, but not without edge cases.

So, on Android you can compile Wayland and even run Weston via libhybris, but expect many issues. You will need to integrate with Android's HAL: use `ANativeWindow` for drawing, use Android's event loop or rewrite Wayland's loop, handle power/button events via JNI, etc. In short, porting Wayland to Android involves gluing Wayland to Android's graphics/input (as done in custom Android kernels or Sailfish builds). It is not plug-and-play. Still, the Collabora/Android Weston port[9] and libhybris efforts show it is possible on some devices.

## Work Required and Upstream Considerations

**macOS:** To run a Wayland compositor on macOS, you'll basically be developing a native app that speaks Wayland. You should expect to implement a custom graphics backend (using Cocoa or Metal) and translate input from NSEvents to Wayland. You can re-use the Wayland protocol library largely unmodified (with epoll-shim installed), but you will need to handle timing, signals, and file-descriptor polling using macOS mechanisms (dispatch sources, or shim libraries) instead of Linux syscalls. Concretely, this often means using the `epoll-shim` library (which is already on MacPorts) and possibly the accompanying interposition library to emulate `read`/`write` on `timerfd`/`signalfd`[2]. You would also link against `libxml2`/`libffi` (which are standard macOS libraries).

**iOS:** Running Wayland here is more like writing a Wayland-to-iOS adapter. You'd create an iOS app (probably with a single UIWindow) and implement the Wayland server logic inside it. You'd use Core Animation or Metal to composite client buffers into the window. Input (touch, keyboard) would be converted to Wayland pointer/keyboard events. Because iOS does not allow multiple top-level windows from one app, your compositor is the app. You must also compile a custom libc extension or shim for missing Linux APIs. In short, expect a huge amount of work: it's essentially writing a new Wayland compositor using iOS APIs. There is no existing example and it may run afoul of iOS app restrictions.

**Android:** You would use libhybris or similar. Typically you fork Wayland and Weston, add Android-specific backends, and integrate with the Android build system. Paalanen's Android port shows you'll patch out unsupported calls (no signalfd, etc.)[5], use the Android EGL and native window, and probably run as a root/System app (to kill the stock compositor). Getting input means reading from Android's event input (or using JNI to call into Java). Essentially, building Wayland/Weston on Android is possible but requires a complete Android-optimized build environment (usually done inside AOSP or using an Android tree)[13]. Upstream Wayland/Weston do not officially support Android, so this would be a fork with many patches.

**Differences from macOS and iOS:** On Windows/macOS/iOS/Android (the common desktop/mobile systems), graphical apps normally use the system's built-in compositor. Each of those systems has its own windowing and event model, which is "relatively similar" across them, whereas Wayland's model is quite different[14]. For example, placing windows, handling popups/menus, global shortcuts, etc. are not defined by core Wayland (they rely on compositor extensions). Mac and Windows expect clients to call specific OS APIs, not a generic protocol socket. Wayland on these targets would feel foreign: "Wayland is the odd one out" compared to the native APIs on macOS/iOS/Android[14]. In practice, to port to those targets you have to embed the Wayland compositor into the native UI framework (as Owl does on macOS[4]) rather than replacing it wholesale.

## Forking and Upstream

Wayland is open-source (MIT license), so you are free to fork and modify it. Many developers maintain their own forks for specific platforms (e.g. XQuartz's wayland mirror or owl-compositor's Wayland mirror). You can host your fork on GitHub or elsewhere. The official upstream is on freedesktop.org (GitLab), but GitHub forks are common.

If you create Mac- or mobile-specific patches, you could propose upstreaming those that make sense (for example, epoll-shim integration could benefit BSD users). In fact, epoll-shim was eventually integrated into some BSD build environments[2]. However, large platform-specific changes (like a Cocoa backend) would not be merged into core Wayland; they belong in separate compositor projects. Upstream Wayland is focused on cross-Linux improvements.

In summary: Yes, fork Wayland and Wayland-compositor repos for your project and host on GitHub. Use GitHub for issue tracking and collaboration if you prefer; just be aware the main Wayland project uses GitLab. Make liberal use of existing shims (epoll-shim, libhybris) and study previous ports (Owl on macOS[4], Collabora's Android port[9]) to guide your implementation.

## Sources

Documentation and ports (MacPorts, FreshPorts) of Wayland show the dependencies and build status on macOS[1][2]. The Owl compositor README describes running Wayland clients on macOS/Quartz[4]. Paalanen's blog and Ekstrand's analysis describe the challenges of running Weston/Wayland on Android[5][12]. The Avalonia project notes the fundamental API differences between Wayland and desktop/mobile systems[14]. These sources underline that while the core Wayland libraries can be built on non-Linux systems, full functionality requires substantial platform-specific work[1][4][5].

### References

[1][6] wayland | MacPorts  
https://ports.macports.org/port/wayland/summary/

[2][3] GitHub - jiixyj/epoll-shim: small epoll implementation using kqueue; includes all features needed for libinput/libevdev  
https://github.com/jiixyj/epoll-shim

[4] GitHub - owl-compositor/owl: The portable Wayland compositor in Objective-C  
https://github.com/owl-compositor/owl

[5][9][10][13] Pekka Paalanen: First light from Weston on Android  
https://ppaalanen.blogspot.com/2012/04/first-light-from-weston-on-android.html

[7] OpenBSD Ports Readme: port wayland/libinput-openbsd  
https://openports.pl/path/wayland/libinput-openbsd

[8] FreshPorts -- graphics/wayland: Core Wayland window system code and protocol  
https://www.freshports.org/graphics/wayland

[11][12] Why Wayland on Android is a hard problem  
https://www.gfxstrand.net/faith/projects/wayland/wayland-android/

[14] Bringing Wayland Support to Avalonia - Avalonia UI  
https://avaloniaui.net/blog/bringing-wayland-support-to-avalonia
