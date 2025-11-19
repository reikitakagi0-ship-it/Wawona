# Frame Callback Animation Issue

## Problem Summary

The Wayland test client (`test_color_client.c`) was crashing the compositor or getting disconnected with `EPIPE` (Broken Pipe) errors. The animation loop was not functioning correctly, and the compositor was unstable under load.

## Root Cause Analysis (2025-11-19)

### 1. Thread Safety Violation (Critical Architecture Issue)
**Symptoms**: Random crashes/segfaults, EPIPE errors, especially during buffer churn or client disconnects.
**Analysis**:
- **The Bug**: The global `surfaces` list and `wl_surface_impl` structures were accessed concurrently by two threads without locking:
    1. **Wayland Event Thread**: Modifies the list (add/remove surfaces) and surface state (attach/destroy buffers).
    2. **Main Thread (Renderer)**: Iterates the list in `renderFrame` (via CVDisplayLink) to render surfaces.
- **Crash Scenario**:
    1. `renderFrame` (Main Thread) gets a pointer to `surface->buffer_resource`.
    2. `wl_buffer_destroy` (Event Thread) runs, clearing the reference and **freeing the resource**.
    3. `renderFrame` tries to access the now-freed buffer resource -> **Use-After-Free Segfault**.

### 2. Buffer Destruction Race Condition
**Symptoms**: Client logs `Display dispatch failed: ret=-1, err=32` (EPIPE).
**Analysis**:
- Related to #1. The client destroys a buffer (`wl_buffer#13`) and attaches a new one.
- If the renderer is mid-frame using the old buffer when it's destroyed, it crashes.
- `wl_compositor_clear_buffer_reference` handles the logic correctly, but it wasn't thread-safe against the renderer.

### 3. Async Removal Race Condition
**Analysis**:
- `remove_surface_from_renderer` in `src/macos_backend.m` used `dispatch_async`.
- If `surface_destroy` (Event Thread) freed the surface before the async block (Main Thread) ran, the block accessed freed memory.

### 4. Color Management Detachment
**Analysis**:
- `wp_color_management_surface_impl` was created but not linked to `wl_surface_impl`.
- The renderer had no way to retrieve color profiles for a surface.

## Fixes Implemented (2025-11-19)

### 1. Thread Safety for Surface List
- Added `pthread_mutex_t surfaces_mutex` to `src/wayland_compositor.c`.
- Protected all modifications to the `surfaces` list (add, remove) with the mutex.
- Protected all iterations of the `surfaces` list (frame callbacks, buffer clearing) with the mutex.
- Implemented `wl_compositor_for_each_surface(iterator, data)` to allow external modules (renderer) to iterate surfaces safely while holding the lock.

### 2. Safe Rendering Loop
- Updated `src/macos_backend.m` to use `wl_compositor_for_each_surface` instead of iterating the list directly.
- This ensures that the surface list and surface state (like `buffer_resource`) cannot be modified by the event thread while the renderer is processing a frame.

### 3. Synchronous Surface Removal
- Updated `remove_surface_from_renderer` in `src/macos_backend.m` to use `dispatch_sync` (or direct call if on main thread).
- This ensures the renderer cleanup happens **before** the `wl_surface_impl` struct is freed by the event thread.

### 4. Color Management Linkage
- Added `void *color_management` field to `wl_surface_impl` in `src/wayland_compositor.h`.
- Updated `src/wayland_color_management.c` to link the `wp_color_management_surface_impl` to the `wl_surface_impl` upon creation and clear it upon destruction.
- This enables the renderer to access color profiles in the future.

### 5. Frame Callback Timing Issue (2025-11-19)
**Symptoms**: Client disconnects with EPIPE after creating color management surface. Animation stops working.
**Analysis**:
- Frame callbacks were only sent by a timer that fires every 16ms.
- When a client requested a frame callback (via `wl_surface_frame`), it had to wait up to 16ms for the timer to fire.
- In some cases (especially after creating color management surfaces), the delay caused the client to timeout or disconnect.
- The `macos_compositor_frame_callback_requested` callback only ensured the timer was running, but didn't trigger an immediate send.

**Fix**:
- Updated `macos_compositor_frame_callback_requested` in `src/macos_backend.m` to **always** trigger an immediate frame callback send via an idle callback when a frame callback is requested.
- This ensures clients receive frame callbacks immediately (within the same event loop iteration) rather than waiting up to 16ms for the timer.
- The timer still runs continuously for regular frame callbacks, but immediate sends prevent client timeouts.

### 6. Client Disconnect Crash (2025-11-19)
**Symptoms**: Compositor crashes with SIGABRT in `wl_closure_invoke` when client disconnects (end of test).
**Analysis**:
- When a client disconnects, Wayland automatically destroys all resources belonging to that client.
- The `client_destroy_listener` was accessing `wl_resource_get_client()` on resources that might have already been destroyed.
- Color management surfaces were not being cleaned up properly, leading to use-after-free when accessing `surface_mgmt->surface->resource` after the surface was freed.
- The `color_management_surface_destroy` handler was accessing freed surface memory.
- **Frame Callback Race Condition**: `wl_send_frame_callbacks()` could be running concurrently (from the timer) and try to send a callback to a frame callback resource that was being destroyed, causing a crash in `wl_closure_invoke`.

**Fix**:
- Updated `client_destroy_listener` in `src/wayland_compositor.c` to safely check if resources are still valid before accessing them.
- **CRITICAL**: Clear frame callbacks IMMEDIATELY when detecting a surface belongs to a disconnected client, BEFORE doing any other cleanup. This prevents `wl_send_frame_callbacks()` from accessing destroyed resources.
- Added cleanup of color management surfaces in the client destroy listener (clear pointer to avoid use-after-free).
- Updated `color_management_surface_destroy` in `src/wayland_color_management.c` to check if the surface is still valid (by checking `surface->resource != NULL`) before accessing it.
- Removed `wl_resource_destroy()` call from `color_management_surface_destroy` as Wayland handles resource destruction automatically.
- Enhanced `wl_send_frame_callbacks()` to add additional validation: check if the surface's resource is still valid (by verifying `wl_resource_get_user_data()` returns the expected surface) before sending callbacks. This provides an extra safety check against race conditions.

## Verification

Run the test client:
```bash
make client
```

Expected behavior:
- Client connects and runs without crashing.
- Animation plays smoothly (60fps).
- Logs show consistent frame callbacks.
- Resizing the window works without crashing.
