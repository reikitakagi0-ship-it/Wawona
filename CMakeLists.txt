cmake_minimum_required(VERSION 3.20)
project(Wawona LANGUAGES C OBJC)

# From-scratch Wayland compositor for macOS
# We use ONLY libwayland-server (no WLRoots - it's Linux-only)

# Use latest C standard (C17/C18) for maximum type safety and features
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)  # Disable GNU extensions for strict compliance

set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJC_STANDARD_REQUIRED ON)

# Strict compiler flags - treat warnings as errors (like Rust)
# Maximum warnings and strict type checking
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -Wpedantic -Werror")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wstrict-prototypes -Wmissing-prototypes")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wold-style-definition -Wmissing-declarations")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wuninitialized -Winit-self")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wpointer-arith -Wcast-qual")
# Note: -Wcast-align disabled due to wayland-server-core.h alignment casts
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wwrite-strings -Wconversion -Wsign-conversion")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wformat=2 -Wformat-security")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wundef -Wshadow -Wstrict-overflow=5")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wswitch-default -Wswitch-enum")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wunreachable-code -Wfloat-equal")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wstack-protector -fstack-protector-strong")
# macOS doesn't support -pie flag for executables (only for shared libraries)
# Use -fPIC for position-independent code instead
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")

# Objective-C flags (slightly less strict due to Cocoa framework patterns)
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wall -Wextra -Wpedantic -Werror")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wuninitialized -Winit-self")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wpointer-arith -Wcast-qual")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wformat=2 -Wformat-security")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wundef -Wshadow")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wstack-protector -fstack-protector-strong")
# Suppress deprecated-declarations only for Objective-C (Cocoa APIs)
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wno-deprecated-declarations")

# Optimization flags - maximum optimization with debug info
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -DNDEBUG -flto")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g3 -O0 -DDEBUG")
set(CMAKE_OBJC_FLAGS_RELEASE "${CMAKE_OBJC_FLAGS_RELEASE} -O3 -DNDEBUG -flto")
set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -g3 -O0 -DDEBUG")

# Enable sanitizers in debug builds for better error detection
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -fsanitize=address -fsanitize=undefined")
    set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -fsanitize=leak -fno-omit-frame-pointer")
    set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -fsanitize=address -fsanitize=undefined")
    set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -fsanitize=leak -fno-omit-frame-pointer")
endif()

# Set up pkg-config path to check both Homebrew and /usr/local (where wayland gets installed)
# Apple Silicon: /opt/homebrew
# Intel Mac: /usr/local
# Manual installs: /usr/local
set(ENV{PKG_CONFIG_PATH} "/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")

# Headers - support both Apple Silicon and Intel Macs
# Check both locations since wayland may be installed in either
if(EXISTS /opt/homebrew/include)
    include_directories(/opt/homebrew/include)
endif()
if(EXISTS /usr/local/include)
    include_directories(/usr/local/include)
endif()

# Libraries - support both Apple Silicon and Intel Macs
# Check both locations since wayland may be installed in either
if(EXISTS /opt/homebrew/lib)
    link_directories(/opt/homebrew/lib)
endif()
if(EXISTS /usr/local/lib)
    link_directories(/usr/local/lib)
endif()

# macOS Frameworks
find_library(COCOA_LIB Cocoa REQUIRED)
find_library(QUARTZCORE_LIB QuartzCore REQUIRED)
find_library(COREVIDEO_LIB CoreVideo REQUIRED)
find_library(COREMEDIA_LIB CoreMedia REQUIRED)
find_library(COREGRAPHICS_LIB CoreGraphics REQUIRED)
find_library(METAL_LIB Metal REQUIRED)
find_library(METALKIT_LIB MetalKit REQUIRED)
find_library(IOSURFACE_LIB IOSurface REQUIRED)
find_library(VIDEOTOOLBOX_LIB VideoToolbox REQUIRED)
find_library(AVFOUNDATION_LIB AVFoundation REQUIRED)

# Source files
set(SOURCES
    src/main.m
    src/macos_backend.m
    src/macos_backend.h
    src/logging.c
    src/logging.h
    src/wayland_compositor.c
    src/wayland_compositor.h
    src/wayland_output.c
    src/wayland_output.h
    src/wayland_seat.c
    src/wayland_seat.h
    src/wayland_shm.c
    src/wayland_shm.h
    src/wayland_subcompositor.c
    src/wayland_subcompositor.h
    src/wayland_data_device_manager.c
    src/wayland_data_device_manager.h
    src/wayland_primary_selection.c
    src/wayland_primary_selection.h
    src/wayland_protocol_stubs.c
    src/wayland_protocol_stubs.h
    src/cursor_shape_bridge.m
    src/primary-selection-protocol.c
    src/primary-selection-protocol.h
    src/xdg-activation-protocol.c
    src/xdg-activation-protocol.h
    src/fractional-scale-protocol.c
    src/fractional-scale-protocol.h
    src/cursor-shape-protocol.c
    src/cursor-shape-protocol.h
    src/text-input-v3-protocol.c
    src/text-input-v3-protocol.h
    src/xdg-decoration-protocol.c
    src/xdg-decoration-protocol.h
    src/xdg-toplevel-icon-protocol.c
    src/xdg-toplevel-icon-protocol.h
    src/surface_renderer.m
    src/surface_renderer.h
    src/input_handler.m
    src/input_handler.h
    src/xdg-shell-protocol.c
    src/xdg-shell-protocol.h
    src/xdg_shell.c
    src/xdg_shell.h
    src/wayland_viewporter.c
    src/wayland_viewporter.h
    src/wayland_shell.c
    src/wayland_gtk_shell.c
    src/wayland_gtk_shell.h
    src/wayland_plasma_shell.c
    src/wayland_plasma_shell.h
    src/wayland_qt_extensions.c
    src/wayland_qt_extensions.h
    src/wayland_shell.h
    src/wayland_screencopy.c
    src/wayland_screencopy.h
    src/wayland_presentation.c
    src/wayland_presentation.h
    src/presentation-time-protocol.c
    src/presentation-time-protocol.h
    src/wayland_color_management.c
    src/wayland_color_management.h
    src/color-management-v1-protocol.h
    src/wayland_linux_dmabuf.c
    src/wayland_linux_dmabuf.h
    src/wayland_idle_inhibit.c
    src/wayland_idle_inhibit.h
    src/wayland_pointer_gestures.c
    src/wayland_pointer_gestures.h
    src/wayland_relative_pointer.c
    src/wayland_relative_pointer.h
    src/wayland_pointer_constraints.c
    src/wayland_pointer_constraints.h
    src/metal_renderer.m
    src/metal_renderer.h
    src/metal_dmabuf.m
    src/metal_dmabuf.h
    src/metal_waypipe.m
    src/metal_waypipe.h
    src/wayland_tablet.c
    src/wayland_tablet.h
    src/wayland_idle_manager.c
    src/wayland_idle_manager.h
    src/wayland_keyboard_shortcuts.c
    src/wayland_keyboard_shortcuts.h
)

# Compile Metal shaders
# Metal shaders need to be compiled into a .metallib file
# Use xcrun to find Metal compiler (part of Xcode command-line tools)
find_program(XCRUN xcrun)
if(XCRUN)
    execute_process(
        COMMAND ${XCRUN} --find metal
        OUTPUT_VARIABLE METAL_COMPILER_PATH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(METAL_COMPILER_PATH AND EXISTS ${METAL_COMPILER_PATH})
        set(METAL_COMPILER ${METAL_COMPILER_PATH})
        message(STATUS "Found Metal compiler: ${METAL_COMPILER}")
    endif()
endif()

# Fallback: try direct find_program
if(NOT METAL_COMPILER)
    find_program(METAL_COMPILER metal PATHS /usr/bin /usr/local/bin)
endif()

if(METAL_COMPILER)
    set(METAL_SHADER_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/src/metal_shaders.metal)
    set(METAL_SHADER_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/metal_shaders.metallib)
    set(METAL_SHADER_AIR ${CMAKE_CURRENT_BINARY_DIR}/metal_shaders.air)
    
    # Compile Metal shader to AIR (intermediate representation)
    add_custom_command(
        OUTPUT ${METAL_SHADER_AIR}
        COMMAND ${METAL_COMPILER} -c ${METAL_SHADER_SOURCE} -o ${METAL_SHADER_AIR}
        DEPENDS ${METAL_SHADER_SOURCE}
        COMMENT "Compiling Metal shaders to AIR"
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
    
    # Link AIR to metallib
    # Use xcrun to find metallib linker
    set(METAL_LINKER "")
    if(XCRUN)
        execute_process(
            COMMAND ${XCRUN} --find metallib
            OUTPUT_VARIABLE METAL_LINKER_PATH
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(METAL_LINKER_PATH AND EXISTS ${METAL_LINKER_PATH})
            set(METAL_LINKER ${METAL_LINKER_PATH})
            message(STATUS "Found Metal linker: ${METAL_LINKER}")
        endif()
    endif()
    
    # Fallback: try direct find_program
    if(NOT METAL_LINKER)
        find_program(METAL_LINKER metallib PATHS /usr/bin /usr/local/bin)
    endif()
    
    if(METAL_LINKER)
        add_custom_command(
            OUTPUT ${METAL_SHADER_OUTPUT}
            COMMAND ${METAL_LINKER} ${METAL_SHADER_AIR} -o ${METAL_SHADER_OUTPUT}
            DEPENDS ${METAL_SHADER_AIR}
            COMMENT "Linking Metal shaders to metallib"
        )
        
        # Add metallib as a dependency
        add_custom_target(metal_shaders ALL DEPENDS ${METAL_SHADER_OUTPUT})
        message(STATUS "Metal shaders will be compiled to: ${METAL_SHADER_OUTPUT}")
    else()
        message(WARNING "metallib not found - Metal shaders will not be compiled")
    endif()
else()
    message(WARNING "Metal compiler (metal) not found - Metal shaders will not be compiled")
endif()

# Executable
add_executable(Wawona ${SOURCES})

# Make sure Metal shaders are built before the executable
if(METAL_COMPILER AND METAL_LINKER)
    add_dependencies(Wawona metal_shaders)
endif()

# Find wayland libraries using pkg-config (preferred method)
find_package(PkgConfig REQUIRED)

# Find wayland-server using pkg-config (preferred)
pkg_check_modules(WAYLAND_SERVER wayland-server)
if(WAYLAND_SERVER_FOUND)
    message(STATUS "Found wayland-server via pkg-config: ${WAYLAND_SERVER_VERSION}")
    message(STATUS "  Include dirs: ${WAYLAND_SERVER_INCLUDE_DIRS}")
    message(STATUS "  Library dirs: ${WAYLAND_SERVER_LIBRARY_DIRS}")
    message(STATUS "  Libraries: ${WAYLAND_SERVER_LIBRARIES}")
else()
    # Fallback: try to find wayland-server library manually
    message(STATUS "wayland-server not found via pkg-config, trying manual search...")
    find_library(WAYLAND_SERVER_LIB
        NAMES wayland-server
        PATHS
            /usr/local/lib
            /opt/homebrew/lib
        NO_DEFAULT_PATH
    )
    if(WAYLAND_SERVER_LIB)
        message(STATUS "Found wayland-server library manually: ${WAYLAND_SERVER_LIB}")
        set(WAYLAND_SERVER_LIBRARIES ${WAYLAND_SERVER_LIB})
        # Try to find headers
        find_path(WAYLAND_SERVER_INCLUDE_DIR
            NAMES wayland-server.h
            PATHS
                /usr/local/include/wayland
                /opt/homebrew/include/wayland
            NO_DEFAULT_PATH
        )
        if(WAYLAND_SERVER_INCLUDE_DIR)
            set(WAYLAND_SERVER_INCLUDE_DIRS ${WAYLAND_SERVER_INCLUDE_DIR})
            message(STATUS "Found wayland-server headers: ${WAYLAND_SERVER_INCLUDE_DIRS}")
        endif()
    else()
        message(FATAL_ERROR "wayland-server not found! Install wayland first using ./install-wayland.sh")
    endif()
endif()

# Find pixman using pkg-config
pkg_check_modules(PIXMAN pixman-1)
if(PIXMAN_FOUND)
    message(STATUS "Found pixman via pkg-config: ${PIXMAN_VERSION}")
else()
    # Fallback: find pixman manually
    find_library(PIXMAN_LIB
        NAMES pixman-1
        PATHS
            /usr/local/lib
            /opt/homebrew/lib
        NO_DEFAULT_PATH
    )
    if(PIXMAN_LIB)
        message(STATUS "Found pixman library manually: ${PIXMAN_LIB}")
        set(PIXMAN_LIBRARIES ${PIXMAN_LIB})
    else()
        message(FATAL_ERROR "pixman-1 not found! Install with: brew install pixman")
    endif()
endif()

# Link libraries
# NOTE: We do NOT link wlroots (Linux-only, not needed)
target_link_libraries(Wawona
    ${COCOA_LIB}
    ${QUARTZCORE_LIB}
    ${COREVIDEO_LIB}
    ${COREMEDIA_LIB}
    ${COREGRAPHICS_LIB}
    ${METAL_LIB}
    ${METALKIT_LIB}
    ${IOSURFACE_LIB}
    ${VIDEOTOOLBOX_LIB}
    ${AVFOUNDATION_LIB}
    ${WAYLAND_SERVER_LIBRARIES}
    ${PIXMAN_LIBRARIES}
)

# Include directories for wayland
if(WAYLAND_SERVER_FOUND AND WAYLAND_SERVER_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${WAYLAND_SERVER_INCLUDE_DIRS})
elseif(WAYLAND_SERVER_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${WAYLAND_SERVER_INCLUDE_DIRS})
endif()
if(PIXMAN_FOUND AND PIXMAN_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${PIXMAN_INCLUDE_DIRS})
endif()

# Copy Metal shader library to build directory (next to executable)
if(METAL_COMPILER AND METAL_LINKER)
    add_custom_command(TARGET Wawona POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${METAL_SHADER_OUTPUT}
            $<TARGET_FILE_DIR:Wawona>/metal_shaders.metallib
        COMMENT "Copying Metal shader library to build directory"
    )
endif()

# Code formatting target (like `cargo fmt`)
find_program(CLANG_FORMAT clang-format)
if(CLANG_FORMAT)
    file(GLOB_RECURSE ALL_SOURCES
        "${CMAKE_SOURCE_DIR}/src/*.c"
        "${CMAKE_SOURCE_DIR}/src/*.h"
        "${CMAKE_SOURCE_DIR}/src/*.m"
    )
    add_custom_target(format
        COMMAND ${CLANG_FORMAT} -i ${ALL_SOURCES}
        COMMENT "Formatting all source files with clang-format"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
    message(STATUS "Format target available: make format")
else()
    message(WARNING "clang-format not found - format target unavailable")
endif()

# Code linting target (like `cargo clippy`)
find_program(CLANG_TIDY clang-tidy)
if(CLANG_TIDY)
    add_custom_target(lint
        COMMAND ${CLANG_TIDY} ${ALL_SOURCES} -p ${CMAKE_BINARY_DIR}
        COMMENT "Linting all source files with clang-tidy"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
    message(STATUS "Lint target available: make lint")
else()
    message(WARNING "clang-tidy not found - lint target unavailable")
endif()

# Check formatting target (for CI)
if(CLANG_FORMAT)
    add_custom_target(check-format
        COMMAND ${CLANG_FORMAT} --dry-run --Werror ${ALL_SOURCES}
        COMMENT "Checking code formatting"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
    message(STATUS "Check-format target available: make check-format")
endif()

