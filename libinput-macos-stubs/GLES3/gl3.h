#ifndef __gl3_h_
#define __gl3_h_

#ifdef __APPLE__
// macOS stub OpenGL ES 3.0 header - allows compilation but functions will fail at runtime
// This is used for pixel format definitions; actual rendering uses Vulkan

#include "../GLES2/gl2.h"

// Basic format constants (from OpenGL ES 2.0/3.0)
#define GL_RED 0x1903
#define GL_GREEN 0x1904
#define GL_BLUE 0x1905
#define GL_ALPHA 0x1906
#define GL_RGB 0x1907
#define GL_RGBA 0x1908
#define GL_LUMINANCE 0x1909
#define GL_LUMINANCE_ALPHA 0x190A
#define GL_ONE 1
#define GL_ZERO 0

// OpenGL ES 3.0 format constants
#define GL_RG 0x8227
#define GL_RG_INTEGER 0x8228
#define GL_R8 0x8229
#define GL_RG8 0x822B
#define GL_R16F 0x822D
#define GL_R32F 0x822E
#define GL_RG16F 0x822F
#define GL_RG32F 0x8230
#define GL_R8I 0x8231
#define GL_R8UI 0x8232
#define GL_R16I 0x8233
#define GL_R16UI 0x8234
#define GL_R32I 0x8235
#define GL_R32UI 0x8236
#define GL_RG8I 0x8237
#define GL_RG8UI 0x8238
#define GL_RG16I 0x8239
#define GL_RG16UI 0x823A
#define GL_RG32I 0x823B
#define GL_RG32UI 0x823C

// Additional extension constants
#define GL_SR8_EXT 0x8F50
#define GL_R16_SNORM_EXT 0x8F98

// Internal format constants (from OpenGL ES 2.0/3.0)
#define GL_RGB565 0x8D62
#define GL_RGBA4 0x8056
#define GL_RGB5_A1 0x8057
#define GL_RGB8 0x8051
#define GL_RGBA8 0x8058
#define GL_RGB10_A2 0x8059
#define GL_RGBA16F 0x881A
#define GL_RGBA16_EXT 0x805B

// Type constants (from OpenGL ES 2.0/3.0)
#define GL_UNSIGNED_BYTE 0x1401
#define GL_UNSIGNED_SHORT 0x1403
#define GL_UNSIGNED_SHORT_4_4_4_4 0x8033
#define GL_UNSIGNED_SHORT_5_5_5_1 0x8034
#define GL_UNSIGNED_SHORT_5_6_5 0x8363

// OpenGL ES 3.0 type constants
#define GL_HALF_FLOAT 0x140B
#define GL_HALF_FLOAT_OES 0x8D61
#define GL_UNSIGNED_INT_2_10_10_10_REV 0x8368

// Extension constants (commonly used)
#define GL_R8_EXT 0x8229
#define GL_RG8_EXT 0x822B
#define GL_R16_EXT 0x822A
#define GL_RG16_EXT 0x822C
#define GL_RGBA16F_EXT 0x881A
#define GL_RGBA16_EXT 0x805B
#define GL_UNSIGNED_INT_2_10_10_10_REV_EXT 0x8368
#define GL_BGRA_EXT 0x80E1

#endif // __APPLE__
#endif // __gl3_h_

