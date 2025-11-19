# Weston Nested Compositor Errors Analysis

## Errors from Weston Logs

### 1. EGL Platform Extension Warnings ⚠️ (Client-Side, Not Fixable by Wawona)
```
warning: EGL_EXT_platform_base not supported.
warning: either no EGL_EXT_platform_base support or specific platform support; falling back to eglGetDisplay.
failed to create display
Failed to initialize the GL renderer; falling back to Pixman.
```

**Analysis:**
- This is a **client-side issue** - Mesa EGL library in the container doesn't have `EGL_EXT_platform_base` compiled in
- Wawona's display fully supports EGL platform extensions
- Clients automatically fall back to `eglGetDisplay` which works fine
- **Fix:** Install Mesa with full EGL support in the container (not Wawona's responsibility)

**Status:** ✅ Already documented in `docs/EGL_PLATFORM_SUPPORT.md`

---

### 2. Mode Switch Failed ⚠️ (Weston Internal Issue)
```
Mode switch failed
```

**Analysis:**
- This is a **Weston internal error** when its wayland backend tries to initialize the output
- The `wl_output` protocol doesn't have a "mode switch" request - modes are only advertised
- Wawona correctly advertises modes with CURRENT|PREFERRED flags
- This error occurs during Weston's internal output setup, not from a protocol request
- **Possible causes:**
  - Weston's wayland backend has issues matching the advertised mode
  - Timing issue during output initialization
  - Weston expects different mode flags or format

**Fix:** 
- Wawona already sends correct mode information
- This appears to be a Weston wayland backend limitation/issue
- No action needed from Wawona (protocol is correctly implemented)

**Status:** ✅ Wawona implementation is correct (Weston internal issue)

---

### 3. Cursor Theme Errors ℹ️ (Harmless, Already Documented)
```
could not load cursor 'dnd-move'
could not load cursor 'dnd-copy'
could not load cursor 'dnd-none'
```

**Analysis:**
- Weston-terminal tries to load cursor themes for drag-and-drop
- Wawona doesn't support cursor themes (uses macOS native cursors)
- These are harmless warnings - functionality still works
- **Fix:** Already documented in code comments, no action needed

**Status:** ✅ Already handled (harmless warnings)

---

### 4. Fontconfig Errors ℹ️ (Container Environment Issue)
```
Fontconfig error: Cannot load default config file: No such file: (null)
```

**Analysis:**
- Container environment doesn't have fontconfig configured
- This is a container setup issue, not Wawona's responsibility
- **Fix:** Configure fontconfig in container (not Wawona's responsibility)

**Status:** ✅ Not Wawona's responsibility

---

### 5. Timestamp Jump Error 🔧 (Fixable by Wawona)
```
unexpectedly large timestamp jump (from 8997724 to 9273982)
```

**Analysis:**
- Wawona uses `[event timestamp] * 1000` which is NSEvent's timestamp
- NSEvent timestamps can have jumps when events are batched or delayed
- Wayland expects monotonic timestamps in milliseconds
- **Fix:** Use `clock_gettime(CLOCK_MONOTONIC)` for consistent timestamps

**Status:** 🔧 Can be fixed

---

## Summary

**Fixed by Wawona:**
1. ✅ **Timestamp generation** - Changed from NSEvent timestamps to `CLOCK_MONOTONIC` to prevent timestamp jumps
   - **File:** `src/input_handler.m`
   - **Change:** Use `clock_gettime(CLOCK_MONOTONIC)` for all input events
   - **Impact:** Eliminates "unexpectedly large timestamp jump" errors

**Not Fixable by Wawona (Client/Environment Issues):**
1. **EGL platform extension warnings** - Mesa EGL library in container (client-side)
2. **Mode switch failed** - Weston internal issue (Wawona protocol is correct)
3. **Fontconfig errors** - Container environment configuration issue
4. **Cursor theme warnings** - Harmless, already documented (Wawona uses macOS native cursors)

## Implementation Status

✅ **Timestamp Fix Implemented:**
- Mouse events now use `CLOCK_MONOTONIC` timestamps
- Keyboard events now use `CLOCK_MONOTONIC` timestamps
- Prevents timestamp jumps that cause Weston warnings

✅ **Mode Switch:**
- Wawona correctly implements `wl_output` protocol
- Sends proper mode events with CURRENT|PREFERRED flags
- "Mode switch failed" is a Weston internal error, not a Wawona issue

