# Android JNI Bridge

This directory contains the Android JNI (Java Native Interface) bridge for the Wawona compositor.

## Overview

The Android JNI bridge provides a native interface between the Android Java/Kotlin application layer and the Wawona Wayland compositor. It handles:

- Vulkan surface creation and management
- Android WindowInsets integration for safe area support
- iOS settings compatibility layer
- Thread-safe rendering initialization

## Files

- `android_jni.c` - Main Android JNI implementation with iOS settings and safe area support

## JNI Functions

The bridge exposes the following JNI functions to the Android application:

- `nativeInit()` - Initialize the Vulkan instance
- `nativeSetSurface()` - Create and configure the Vulkan surface from an Android Surface
- `nativeDestroySurface()` - Clean up Vulkan resources
- `nativeApplySettings()` - Apply iOS-compatible settings

## Usage

This code is experimental and not currently integrated into the main CMake build system. To use it:

1. Build the Android APK using Gradle/Android Studio
2. Link this JNI code in your Android build configuration
3. Call the JNI functions from your Android Activity

## Features

- **Vulkan Rendering**: Uses Vulkan for hardware-accelerated rendering
- **Safe Area Support**: Respects Android display cutouts and system gesture insets
- **iOS Settings Compatibility**: Provides 1:1 mapping of iOS settings to Android
- **Thread Safety**: Uses pthread mutexes for thread-safe operations

## Notes

- Requires Android NDK for building
- Requires Vulkan support on the target device (Freedreno/Turnip or SwiftShader fallback)
- Safe area detection uses Android WindowInsets API
