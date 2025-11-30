#pragma once

// Compatibility header for macOS/iOS backend
// Provides alias for WawonaCompositor

#include "WawonaCompositor.h"

// Alias for backward compatibility
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
typedef WawonaCompositor MacOSCompositor;
#else
typedef WawonaCompositor MacOSCompositor;
#endif

