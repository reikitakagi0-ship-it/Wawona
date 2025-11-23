#import "input_handler.h"
#import "wayland_seat.h"
#include <wayland-server-protocol.h>
#include <wayland-server.h>
#include <time.h>

// Key code mapping: macOS key codes to Linux keycodes
// Reference: /usr/include/linux/input-event-codes.h
// Linux keycodes: Q=16, W=17, E=18, R=19, T=20, Y=21, U=22, I=23, O=24, P=25
//                  A=30, S=31, D=32, F=33, G=34, H=35, J=36, K=37, L=38
//                  Z=44, X=45, C=46, V=47, B=48, N=49, M=50
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static uint32_t macKeyCodeToLinuxKeyCode(unsigned short macKeyCode) {
    // Basic mapping - can be expanded
    switch (macKeyCode) {
        case 0x00: return 30; // A
        case 0x01: return 31; // S
        case 0x02: return 32; // D
        case 0x03: return 33; // F
        case 0x04: return 35; // H
        case 0x05: return 34; // G
        case 0x06: return 44; // Z
        case 0x07: return 45; // X
        case 0x08: return 46; // C
        case 0x09: return 47; // V
        case 0x0A: return 49; // N
        case 0x0B: return 48; // B
        case 0x0C: return 16; // Q
        case 0x0D: return 17; // W
        case 0x0E: return 18; // E
        case 0x0F: return 19; // R
        case 0x10: return 21; // Y
        case 0x11: return 20; // T
        case 0x12: return 2;  // 1 (Linux KEY_1 = 2)
        case 0x13: return 3;  // 2 (Linux KEY_2 = 3)
        case 0x14: return 4;  // 3 (Linux KEY_3 = 4)
        case 0x15: return 5;  // 4 (Linux KEY_4 = 5)
        case 0x16: return 6;  // 5 (Linux KEY_5 = 6)
        case 0x17: return 7;  // 6 (Linux KEY_6 = 7)
        case 0x18: return 8;  // 7 (Linux KEY_7 = 8)
        case 0x19: return 9;  // 8 (Linux KEY_8 = 9)
        case 0x1A: return 10; // 9 (Linux KEY_9 = 10)
        case 0x1B: return 11; // 0 (Linux KEY_0 = 11)
        case 0x1C: return 12; // - (Linux KEY_MINUS = 12)
        case 0x1D: return 13; // = (Linux KEY_EQUAL = 13)
        case 0x1E: return 27; // ] (Linux KEY_RIGHTBRACE = 27)
        case 0x1F: return 24; // O (macOS kVK_ANSI_O = 0x1F)
        case 0x20: return 22; // U (macOS kVK_ANSI_U = 0x20)
        case 0x21: return 26; // [ (Linux KEY_LEFTBRACE = 26)
        case 0x22: return 23; // I (macOS kVK_ANSI_I = 0x22)
        case 0x23: return 25; // P (macOS kVK_ANSI_P = 0x23)
        case 0x24: return 28; // Return/Enter (macOS kVK_Return = 0x24)
        case 0x25: return 38; // L (macOS kVK_ANSI_L = 0x25)
        case 0x26: return 36; // J (macOS kVK_ANSI_J = 0x26)
        case 0x27: return 41; // ` (KEY_GRAVE, macOS kVK_ANSI_Grave = 0x27)
        case 0x28: return 37; // K (macOS kVK_ANSI_K = 0x28)
        case 0x29: return 51; // ; (Linux KEY_SEMICOLON = 51) - FIXED: should map to 51, not 51 (was correct)
        case 0x2A: return 43; // \ (Linux KEY_BACKSLASH = 43)
        case 0x2B: return 51; // Comma (KEY_COMMA = 51) - macOS kVK_ANSI_Comma
        // Note: macOS uses different keycodes for punctuation
        // kVK_ANSI_Slash = 0x2C (same as right arrow on some keyboards)
        // kVK_ANSI_Period = 0x2F (same as down arrow on some keyboards)
        // We handle these via charactersIgnoringModifiers for accurate mapping
        case 0x2C: return 53; // Slash (KEY_SLASH = 53) - but also Right arrow, handled via characters
        case 0x2D: return 49; // N (macOS kVK_ANSI_N = 0x2D)
        case 0x2E: return 50; // M (macOS kVK_ANSI_M = 0x2E)
        case 0x2F: return 52; // Period (KEY_DOT = 52) - but also Down arrow, handled via characters
        case 0x30: return 57; // Space (KEY_SPACE) - alternate spacebar keycode
        case 0x31: return 57; // Space (KEY_SPACE) - primary spacebar keycode
        case 0x32: return 105; // Left (KEY_LEFT)
        case 0x34: return 103; // Up (KEY_UP) - alternate up arrow keycode
        case 0x33: return 14; // Backspace (macOS kVK_Delete = 0x33)
        case 0x35: return 1;  // Escape (KEY_ESC)
        case 0x37: return 125; // Left Command/Super (KEY_LEFTMETA)
        case 0x38: return 56;  // Left Shift (KEY_LEFTSHIFT)
        case 0x39: return 58;  // Caps Lock (KEY_CAPSLOCK)
        case 0x3A: return 29; // Left Alt (KEY_LEFTALT)
        case 0x3B: return 42; // Left Control (KEY_LEFTCTRL)
        case 0x3C: return 54; // Right Shift (KEY_RIGHTSHIFT)
        case 0x3D: return 100; // Right Alt (KEY_RIGHTALT)
        case 0x3E: return 97;  // Right Control (KEY_RIGHTCTRL)
        case 0x3F: return 126; // Right Command/Super (KEY_RIGHTMETA)
        
        // Function keys F1-F12 (macOS kVK_F1 = 0x7A, F2 = 0x78, etc.)
        case 0x7A: return 59; // F1 (KEY_F1 = 59)
        case 0x78: return 60; // F2 (KEY_F2 = 60)
        case 0x63: return 61; // F3 (KEY_F3 = 61)
        case 0x76: return 62; // F4 (KEY_F4 = 62)
        case 0x60: return 63; // F5 (KEY_F5 = 63)
        case 0x61: return 64; // F6 (KEY_F6 = 64)
        case 0x62: return 65; // F7 (KEY_F7 = 65)
        case 0x64: return 66; // F8 (KEY_F8 = 66)
        case 0x65: return 67; // F9 (KEY_F9 = 67)
        case 0x6D: return 68; // F10 (KEY_F10 = 68)
        case 0x67: return 87; // F11 (KEY_F11 = 87)
        case 0x6F: return 88; // F12 (KEY_F12 = 88)
        
        // Numpad keys (macOS kVK_ANSI_Keypad*)
        case 0x52: return 82; // Numpad 0 (KEY_KP0 = 82)
        case 0x53: return 79; // Numpad 1 (KEY_KP1 = 79)
        case 0x54: return 80; // Numpad 2 (KEY_KP2 = 80)
        case 0x55: return 81; // Numpad 3 (KEY_KP3 = 81)
        case 0x56: return 75; // Numpad 4 (KEY_KP4 = 75)
        case 0x57: return 76; // Numpad 5 (KEY_KP5 = 76)
        case 0x58: return 77; // Numpad 6 (KEY_KP6 = 77)
        case 0x59: return 71; // Numpad 7 (KEY_KP7 = 71)
        case 0x5B: return 72; // Numpad 8 (KEY_KP8 = 72)
        case 0x5C: return 73; // Numpad 9 (KEY_KP9 = 73)
        case 0x41: return 98; // Numpad Decimal (KEY_KPDOT = 98)
        case 0x4C: return 96; // Numpad Enter (KEY_KPENTER = 96)
        case 0x51: return 104; // Numpad Equals (KEY_KPEQUAL = 104)
        case 0x45: return 78; // Numpad Plus (KEY_KPPLUS = 78)
        case 0x4E: return 74; // Numpad Minus (KEY_KPMINUS = 74)
        case 0x43: return 55; // Numpad Multiply (KEY_KPASTERISK = 55)
        case 0x4B: return 83; // Numpad Divide (KEY_KPSLASH = 83)
        case 0x47: return 69; // Num Lock (KEY_NUMLOCK = 69)
        
        // Arrow keys (already mapped but ensuring completeness)
        case 0x7E: return 103; // Up Arrow (KEY_UP = 103)
        case 0x7D: return 108; // Down Arrow (KEY_DOWN = 108)
        case 0x7B: return 105; // Left Arrow (KEY_LEFT = 105)
        case 0x7C: return 106; // Right Arrow (KEY_RIGHT = 106)
        
        // Special macOS keys
        case 0x66: return 102; // Help (KEY_HELP = 102) or Insert on some keyboards
        case 0x72: return 111; // Insert (KEY_INSERT = 111) - Help key on some Mac keyboards
        case 0x73: return 110; // Home (KEY_HOME = 110)
        case 0x74: return 115; // Page Up (KEY_PAGEUP = 115)
        case 0x75: return 119; // Delete/Forward Delete (KEY_DELETE = 119)
        case 0x77: return 116; // End (KEY_END = 116)
        case 0x79: return 109; // Page Down (KEY_PAGEDOWN = 109)
        case 0x6A: return 113; // Clear (KEY_CLEAR = 113) - Num Lock on some keyboards
        
        // Tab and other keys
        case 0x48: return 15; // Tab (KEY_TAB = 15)
        case 0x49: return 41; // `/~ (KEY_GRAVE = 41)
        
        // Media keys (macOS special function keys)
        // Note: These may need special handling as they're often intercepted by macOS
        // F1-F12 with fn modifier become media keys on Mac keyboards
        // We'll handle these through modifier detection in handleKeyboardEvent
        
        // Additional punctuation handled via charactersIgnoringModifiers for accurate mapping
        
        default: return 0; // Unknown - will be handled via charactersIgnoringModifiers
    }
}
#endif

// Mouse button mapping
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static uint32_t macButtonToWaylandButton(NSEventType eventType, NSEvent *event) {
    (void)event; // eventType is sufficient for button mapping
    switch (eventType) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeLeftMouseUp:
            return 272; // BTN_LEFT
        case NSEventTypeRightMouseDown:
        case NSEventTypeRightMouseUp:
            return 273; // BTN_RIGHT
        case NSEventTypeOtherMouseDown:
        case NSEventTypeOtherMouseUp:
            return 274; // BTN_MIDDLE
        default:
            return 0;
    }
}
#endif

@implementation InputHandler

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithSeat:(struct wl_seat_impl *)seat window:(UIWindow *)window compositor:(id)compositor {
#else
- (instancetype)initWithSeat:(struct wl_seat_impl *)seat window:(NSWindow *)window compositor:(id)compositor {
#endif
    self = [super init];
    if (self) {
        _seat = seat;
        _window = window;
        _compositor = compositor;
    }
    return self;
}

- (void)setupInputHandling {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Touch events handled via gesture recognizers
    (void)_window;
#else
    // Set up event monitoring for the window
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:[_window.contentView bounds]
                                                                options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
                                                                  owner:self
                                                               userInfo:nil];
    [_window.contentView addTrackingArea:trackingArea];
    
    // Make window accept mouse events
    [_window setAcceptsMouseMovedEvents:YES];
#endif
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (void)handleMouseEvent:(NSEvent *)event {
    if (!_seat) return;
    
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInView = [_window.contentView convertPoint:locationInWindow fromView:nil];
    
    // Convert to Wayland coordinates
    // CompositorView.isFlipped returns YES, so it already uses top-left origin (like Wayland)
    // No need to flip Y coordinate - the view is already flipped
    double x = locationInView.x;
    double y = locationInView.y; // Use Y directly - view is already flipped
    
    NSEventType eventType = [event type];
    // Use CLOCK_MONOTONIC for consistent timestamps (prevents timestamp jumps)
    // Wayland expects monotonic timestamps in milliseconds
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint32_t time = (uint32_t)((ts.tv_sec * 1000) + (ts.tv_nsec / 1000000));
    
    switch (eventType) {
        case NSEventTypeMouseMoved:
        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDragged:
        case NSEventTypeOtherMouseDragged: {
            // Log cursor position at input handler level
            NSLog(@"[INPUT] Mouse moved: position=(%.1f, %.1f), window=(%.1f, %.1f), view=(%.1f, %.1f)", 
                  x, y, locationInWindow.x, locationInWindow.y, locationInView.x, locationInView.y);
            
            wl_seat_send_pointer_motion(_seat, time, x, y);
            // Trigger frame callback and redraw for mouse movement
            // This ensures surfaces update immediately when cursor moves
            [self triggerFrameCallback];
            break;
        }
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown: {
            uint32_t serial = wl_seat_get_serial(_seat);
            uint32_t button = macButtonToWaylandButton(eventType, event);
            wl_seat_send_pointer_button(_seat, serial, time, button, WL_POINTER_BUTTON_STATE_PRESSED);
            // Trigger frame callback so clients can render button press feedback
            [self triggerFrameCallback];
            break;
        }
        case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseUp: {
            uint32_t serial = wl_seat_get_serial(_seat);
            uint32_t button = macButtonToWaylandButton(eventType, event);
            wl_seat_send_pointer_button(_seat, serial, time, button, WL_POINTER_BUTTON_STATE_RELEASED);
            // Trigger frame callback so clients can render button release feedback
            [self triggerFrameCallback];
            break;
        }
        case NSEventTypeScrollWheel: {
            // Handle scroll events
            double deltaY = [event scrollingDeltaY];
            if (deltaY != 0) {
                // Send axis event (simplified)
                // TODO: Implement proper axis events
                // Trigger frame callback so clients can render scroll updates
                [self triggerFrameCallback];
            }
            break;
        }
        default:
            break;
    }
}
#endif

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#pragma mark - NSResponder forwarding

- (void)mouseMoved:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)mouseDown:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)rightMouseUp:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)otherMouseDown:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)otherMouseUp:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)rightMouseDragged:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)otherMouseDragged:(NSEvent *)event {
    [self handleMouseEvent:event];
}

- (void)scrollWheel:(NSEvent *)event {
    [self handleMouseEvent:event];
}
#endif

// Trigger frame callback and refresh - used for mouse/pointer events
- (void)triggerFrameCallback {
    // Trigger frame refresh for input events (mouse move, clicks)
    // This ensures the compositor view updates immediately when input occurs
    [self triggerRedraw];
}

// Trigger redraw after input events so UI updates are visible immediately
- (void)triggerRedraw {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (!_window || !_window.rootViewController.view) {
#else
    if (!_window || !_window.contentView) {
#endif
        return;
    }
    
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    UIView *contentView = _window.rootViewController.view;
#else
    NSView *contentView = _window.contentView;
#endif
    
    // Check if this is a CompositorView with Metal view
    if ([contentView respondsToSelector:@selector(metalView)]) {
        id metalView = [contentView performSelector:@selector(metalView)];
        if (metalView) {
            // For Metal view with continuous rendering (enableSetNeedsDisplay=NO),
            // we can still call setNeedsDisplay to ensure immediate update on mouse movement
            // The continuous rendering will handle regular updates, but mouse movement
            // should trigger immediate redraw for cursor updates
            dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
                if ([metalView respondsToSelector:@selector(setNeedsDisplay)]) {
                    [metalView performSelector:@selector(setNeedsDisplay)];
                }
#else
                if ([metalView respondsToSelector:@selector(setNeedsDisplay:)]) {
                    [metalView performSelector:@selector(setNeedsDisplay:) withObject:@YES];
                }
#endif
            });
        }
    } else {
        // Fallback: trigger regular view redraw
        dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
            [contentView setNeedsDisplay];
#else
            [contentView setNeedsDisplay:YES];
#endif
        });
    }
    
    // Access the compositor instance to trigger immediate frame callback dispatch
    // This ensures frame callbacks are sent immediately so clients can render updates
    id compositor = _compositor;
    if (compositor != nil) {
        // First, trigger immediate frame callback dispatch for input responsiveness
        SEL sendFrameCallbacksSelector = @selector(sendFrameCallbacksImmediately);
        if ([compositor respondsToSelector:sendFrameCallbacksSelector]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [compositor performSelector:sendFrameCallbacksSelector];
                #pragma clang diagnostic pop
            });
        }
        
        // Also trigger renderFrame to ensure surfaces are rendered
        SEL renderFrameSelector = @selector(renderFrame);
        if ([compositor respondsToSelector:renderFrameSelector]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [compositor performSelector:renderFrameSelector];
                #pragma clang diagnostic pop
            });
        }
    }
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (void)handleKeyboardEvent:(NSEvent *)event {
    if (!_seat) return;

    NSEventType eventType = [event type];
    // Use CLOCK_MONOTONIC for consistent timestamps (prevents timestamp jumps)
    // Wayland expects monotonic timestamps in milliseconds
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint32_t time = (uint32_t)((ts.tv_sec * 1000) + (ts.tv_nsec / 1000000));
    unsigned short macKeyCode = [event keyCode];
    
    // Use charactersIgnoringModifiers to determine the actual key pressed
    // This is more reliable than keycodes for punctuation and special keys
    NSString *charsIgnoringModifiers = [event charactersIgnoringModifiers];
    uint32_t linuxKeyCode = 0;
    
    // OPTIMIZED: Use keycode mapping first, then refine with character if needed
    // This ensures function keys, numpad, and special keys work correctly
    linuxKeyCode = macKeyCodeToLinuxKeyCode(macKeyCode);
    
    // CRITICAL: Never override Enter key (keycode 28) with character-based mapping
    // Enter must always be sent as keycode 28 to prevent terminal escape sequence issues
    if (linuxKeyCode == 28) {
        // Enter key is correctly mapped - skip character-based remapping
        // This prevents terminals from misinterpreting Enter as part of escape sequences
    }
    // If keycode mapping failed (returned 0) or we got a character for number keys, use character-based mapping
    // Character-based mapping is more reliable for punctuation and layout-dependent keys
    else if ((linuxKeyCode == 0 || (linuxKeyCode >= 2 && linuxKeyCode <= 13)) && charsIgnoringModifiers && charsIgnoringModifiers.length > 0) {
        unichar c = [charsIgnoringModifiers characterAtIndex:0];
        // Map characters to Linux keycodes (for punctuation and layout-dependent keys)
        switch (c) {
            case ' ': linuxKeyCode = 57; break; // KEY_SPACE = 57
            case ';': linuxKeyCode = 39; break; // KEY_SEMICOLON = 39
            case '\'': linuxKeyCode = 40; break; // KEY_APOSTROPHE = 40
            case ',': linuxKeyCode = 51; break; // KEY_COMMA = 51
            case '.': linuxKeyCode = 52; break; // KEY_DOT = 52
            case '/': linuxKeyCode = 53; break; // KEY_SLASH = 53
            case '`': linuxKeyCode = 41; break; // KEY_GRAVE = 41
            case '[': linuxKeyCode = 26; break; // KEY_LEFTBRACE = 26
            case ']': linuxKeyCode = 27; break; // KEY_RIGHTBRACE = 27
            case '\\': linuxKeyCode = 43; break; // KEY_BACKSLASH = 43
            case '-': linuxKeyCode = 12; break; // KEY_MINUS = 12
            case '=': linuxKeyCode = 13; break; // KEY_EQUAL = 13
            case '\r': linuxKeyCode = 28; break; // KEY_ENTER = 28
            case '\t': linuxKeyCode = 15; break; // KEY_TAB = 15
            // Numbers - prefer character mapping for international layouts
            case '1': linuxKeyCode = 2; break; // KEY_1 = 2
            case '2': linuxKeyCode = 3; break; // KEY_2 = 3
            case '3': linuxKeyCode = 4; break; // KEY_3 = 4
            case '4': linuxKeyCode = 5; break; // KEY_4 = 5
            case '5': linuxKeyCode = 6; break; // KEY_5 = 6
            case '6': linuxKeyCode = 7; break; // KEY_6 = 7
            case '7': linuxKeyCode = 8; break; // KEY_7 = 8
            case '8': linuxKeyCode = 9; break; // KEY_8 = 9
            case '9': linuxKeyCode = 10; break; // KEY_9 = 10
            case '0': linuxKeyCode = 11; break; // KEY_0 = 11
            // Letters - use keycode mapping (already done above)
            default:
                // If we already have a valid keycode from macKeyCodeToLinuxKeyCode, keep it
                // Otherwise, try to map common characters
                if (linuxKeyCode == 0) {
                    // Try lowercase letter mapping
                    if (c >= 'a' && c <= 'z') {
                        // Map 'a'=30, 'b'=48, 'c'=46, 'd'=32, 'e'=18, 'f'=33, 'g'=34, 'h'=35,
                        // 'i'=23, 'j'=36, 'k'=37, 'l'=38, 'm'=50, 'n'=49, 'o'=24, 'p'=25,
                        // 'q'=16, 'r'=19, 's'=31, 't'=20, 'u'=22, 'v'=47, 'w'=17, 'x'=45,
                        // 'y'=21, 'z'=44
                        static const uint32_t letter_map[26] = {
                            30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25,
                            16, 19, 31, 20, 22, 47, 17, 45, 21, 44
                        };
                        linuxKeyCode = letter_map[c - 'a'];
                    }
                }
                break;
        }
    }
    
    // Special handling for keys that might not have characters
    if (linuxKeyCode == 0) {
        // Fall back to keycode mapping for special keys
        linuxKeyCode = macKeyCodeToLinuxKeyCode(macKeyCode);
    }
    
    // Get modifier flags from the event
    NSEventModifierFlags modifierFlags = [event modifierFlags];
    
    // Update modifier state based on current modifier flags
    // This ensures modifier state is always accurate, even if modifier key events are missed
    // NOTE: wl_seat_send_keyboard_key also updates modifiers for modifier keys,
    // but we need to track modifiers from macOS events for non-modifier keys
    uint32_t old_mods_depressed = _seat->mods_depressed;
    
    // Map macOS modifier flags to XKB modifier masks
    uint32_t shift_mask = 1 << 0;   // Shift
    uint32_t lock_mask = 1 << 1;    // Caps Lock
    uint32_t control_mask = 1 << 2; // Control
    uint32_t mod1_mask = 1 << 3;     // Alt/Meta
    uint32_t mod4_mask = 1 << 6;    // Mod4 (Super/Windows)
    
    uint32_t new_mods_depressed = 0;
    
    if (modifierFlags & NSEventModifierFlagShift) {
        new_mods_depressed |= shift_mask;
    }
    if (modifierFlags & NSEventModifierFlagCapsLock) {
        new_mods_depressed |= lock_mask;
        _seat->mods_locked |= lock_mask; // Caps Lock is locked, not depressed
    }
    if (modifierFlags & NSEventModifierFlagControl) {
        new_mods_depressed |= control_mask;
    }
    if (modifierFlags & NSEventModifierFlagOption) {
        new_mods_depressed |= mod1_mask; // Option/Alt is mod1
    }
    if (modifierFlags & NSEventModifierFlagCommand) {
        new_mods_depressed |= mod4_mask; // Command is mod4 (Super)
    }
    
    // Update modifier state if it changed
    if (old_mods_depressed != new_mods_depressed) {
        _seat->mods_depressed = new_mods_depressed;
    }
    
    // Clear locked modifiers when they're not pressed (except Caps Lock which toggles)
    if (!(modifierFlags & NSEventModifierFlagCapsLock)) {
        _seat->mods_locked &= ~lock_mask;
    }

    // Log key mapping for debugging - escape control characters for display
    NSString *chars = [event characters];
    
    // Escape control characters that would break NSLog formatting
    NSString *escapedChars = @"";
    if (chars && chars.length > 0) {
        unichar c = [chars characterAtIndex:0];
        if (c == '\r') escapedChars = @"\\r";
        else if (c == '\n') escapedChars = @"\\n";
        else if (c == '\t') escapedChars = @"\\t";
        else if (c == 0x7F) escapedChars = @"\\x7F";
        else if (c < 32) escapedChars = [NSString stringWithFormat:@"\\x%02X", c];
        else escapedChars = chars;
    }
    
    NSString *escapedModChars = @"";
    if (charsIgnoringModifiers && charsIgnoringModifiers.length > 0) {
        unichar c = [charsIgnoringModifiers characterAtIndex:0];
        if (c == '\r') escapedModChars = @"\\r";
        else if (c == '\n') escapedModChars = @"\\n";
        else if (c == '\t') escapedModChars = @"\\t";
        else if (c == 0x7F) escapedModChars = @"\\x7F";
        else if (c < 32) escapedModChars = [NSString stringWithFormat:@"\\x%02X", c];
        else escapedModChars = charsIgnoringModifiers;
    }
    
    // Reduced logging - only log first few key events for debugging
    static int key_event_count = 0;
    if (key_event_count < 5) {
        NSLog(@"[INPUT] Key event: macKeyCode=0x%02X (%u), linuxKeyCode=%u, modifiers=0x%llX, chars='%@', charsIgnoringModifiers='%@', type=%lu",
              macKeyCode, macKeyCode, linuxKeyCode, (unsigned long long)modifierFlags, escapedChars, escapedModChars, (unsigned long)eventType);
        key_event_count++;
    }

    if (linuxKeyCode == 0) {
        // Unknown key, skip
        return;
    }
    
    uint32_t state;
    switch (eventType) {
        case NSEventTypeKeyDown:
            state = WL_KEYBOARD_KEY_STATE_PRESSED;
            break;
        case NSEventTypeKeyUp:
            state = WL_KEYBOARD_KEY_STATE_RELEASED;
            break;
        default:
            return;
    }
    
    uint32_t serial = wl_seat_get_serial(_seat);
    
    // Send key event - wl_seat_send_keyboard_key handles modifier updates internally for modifier keys
    // For non-modifier keys, we've already updated the modifier state above based on macOS events
    wl_seat_send_keyboard_key(_seat, serial, time, linuxKeyCode, state);
    
    // NOTE: We don't send modifier updates here because:
    // 1. wl_seat_send_keyboard_key sends modifiers AFTER the key event for modifier keys
    // 2. For non-modifier keys, modifiers should already be correct from previous modifier key events
    // 3. Sending modifiers before the key event can cause "bad length field 0" errors in waypipe
    
    // Trigger redraw after keyboard input so text/UI updates are visible immediately
    [self triggerRedraw];
}
#endif

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)handleTouchEvent:(UIEvent *)event {
    // iOS: Touch events - stub for now
    (void)event;
    // TODO: Implement touch-to-pointer conversion for iOS
}
#endif

@end

