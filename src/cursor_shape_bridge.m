#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#include "wayland_protocol_stubs.h"

// Bridge function to set macOS cursor from C code
void set_macos_cursor_shape(uint32_t shape) {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Cursor shapes not applicable
    (void)shape;
#else
    @autoreleasepool {
        NSCursor *cursor = nil;
        
        // Map Wayland cursor shapes to macOS NSCursor
        switch (shape) {
            case 0: // default
                cursor = [NSCursor arrowCursor];
                break;
            case 1: // context-menu
                cursor = [NSCursor contextualMenuCursor];
                break;
            case 2: // help
            case 3: // pointer
                cursor = [NSCursor pointingHandCursor];
                break;
            case 4: // progress
                cursor = [NSCursor arrowCursor];
                break;
            case 5: // wait
                cursor = [NSCursor disappearingItemCursor];
                break;
            case 6: // cell
            case 7: // crosshair
                cursor = [NSCursor crosshairCursor];
                break;
            case 8: // text
            case 9: // vertical-text
                cursor = [NSCursor IBeamCursor];
                break;
            case 10: // alias
                cursor = [NSCursor dragLinkCursor];
                break;
            case 11: // copy
                cursor = [NSCursor dragCopyCursor];
                break;
            case 12: // move
            case 15: // grab
            case 17: // all-scroll
                cursor = [NSCursor openHandCursor];
                break;
            case 13: // no-drop
            case 14: // not-allowed
                cursor = [NSCursor operationNotAllowedCursor];
                break;
            case 16: // grabbing
                cursor = [NSCursor closedHandCursor];
                break;
            case 18: // col-resize
            case 21: // e-resize
            case 23: // w-resize
            case 28: // ew-resize
                cursor = [NSCursor resizeLeftRightCursor];
                break;
            case 19: // row-resize
            case 20: // n-resize
            case 22: // s-resize
            case 29: // ns-resize
                cursor = [NSCursor resizeUpDownCursor];
                break;
            case 24: // ne-resize
            case 25: // nw-resize
            case 26: // se-resize
            case 27: // sw-resize
            case 30: // nesw-resize
            case 31: // nwse-resize
                cursor = [NSCursor resizeUpDownCursor]; // Approximate
                break;
            case 32: // zoom-in
            case 33: // zoom-out
                cursor = [NSCursor arrowCursor];
                break;
            default:
                cursor = [NSCursor arrowCursor];
                break;
        }
        
        if (cursor) {
            [cursor set];
        }
    }
#endif
}

