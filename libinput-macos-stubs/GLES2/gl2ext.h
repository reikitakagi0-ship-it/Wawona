#ifndef __gl2ext_h_
#define __gl2ext_h_

#ifdef __APPLE__
// macOS stub OpenGL ES 2.0 extensions header

#include "gl2.h"

// Minimal extensions - just enough to compile
// Real implementation would need many more definitions

// Extension format constants
#define GL_BGRA_EXT 0x80E1
#define GL_BGRA_IMG 0x80E1

// Basic format constants (needed for gl-utils.c and gl-renderer.c)
#define GL_RED 0x1903
#define GL_GREEN 0x1904
#define GL_BLUE 0x1905
#define GL_ALPHA 0x1906
#define GL_RGB 0x1907
#define GL_RGBA 0x1908
#define GL_RED_INTEGER 0x8D94
#define GL_RG_INTEGER 0x8228
#define GL_ZERO 0
#define GL_ONE 1
#define GL_LUMINANCE 0x1909
#define GL_LUMINANCE_ALPHA 0x190A
#define GL_HALF_FLOAT_OES 0x8D61

// Type constants
#define GL_BYTE 0x1400
#define GL_SHORT 0x1402
#define GL_INT 0x1404
#define GL_UNSIGNED_INT 0x1405

// OpenGL ES 3.0 constants (needed when GLES3 headers aren't included)
#define GL_R8 0x8229
#define GL_R8_SNORM 0x8F94
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
#define GL_RG8_SNORM 0x8F95
#define GL_FLOAT 0x1406
#define GL_R32F 0x822E
#define GL_HALF_FLOAT 0x140B
#define GL_UNSIGNED_INT_2_10_10_10_REV 0x8368
#define GL_UNSIGNED_SHORT_5_6_5 0x8363
#define GL_UNSIGNED_INT_10F_11F_11F_REV 0x8C3B
#define GL_UNSIGNED_INT_5_9_9_9_REV 0x8C3E
#define GL_UNSIGNED_SHORT_5_5_5_1 0x8034
#define GL_UNSIGNED_SHORT_4_4_4_4 0x8033
#define GL_RGB32F 0x8815
#define GL_TEXTURE_3D 0x806F
#define GL_RGB16I 0x8D89
#define GL_RGB16UI 0x8D8A
#define GL_RG16_EXT 0x822C
#define GL_RG16_SNORM_EXT 0x8F99
#define GL_RG 0x8227
#define GL_RGB8I 0x8D8F
#define GL_RGB8UI 0x8D8D
#define GL_RGB_INTEGER 0x8D98
#define GL_RGB8 0x8051
#define GL_RGB8_SNORM 0x8F96
#define GL_RGB16F 0x881B
#define GL_R16F 0x822D
#define GL_SR8_EXT 0x8F50
#define GL_RGBA16UI 0x8D76
#define GL_RGBA32I 0x8D82
#define GL_RGBA32UI 0x8D70
#define GL_RGB10_A2UI 0x906F
#define GL_R16_EXT 0x822A
#define GL_R16_SNORM_EXT 0x8F98
#define GL_RG8 0x822B
#define GL_TEXTURE_EXTERNAL_OES 0x8D65
#define GL_RG16F 0x822F
#define GL_RG32F 0x8230
#define GL_SRG8_EXT 0x8F43
#define GL_R11F_G11F_B10F 0x8F3A
#define GL_RGB9_E5 0x8C3D
#define GL_RGB565 0x8D62
#define GL_SRGB8 0x8C41
#define GL_RGB16_EXT 0x8054
#define GL_RGB16_SNORM_EXT 0x8F9A
#define GL_RGBA8I 0x8D8E
#define GL_RGBA8UI 0x8D7C
#define GL_RGBA16I 0x8D88
#define GL_RGBA_INTEGER 0x8D99
#define GL_RGBA8 0x8058
#define GL_RGBA8_SNORM 0x8F97
#define GL_RGBA16F 0x881A
#define GL_RGBA32F 0x8814
#define GL_RGB10_A2 0x8059
#define GL_SRGB8_ALPHA8 0x8C43
#define GL_RGB5_A1 0x8057
#define GL_RGBA4 0x8056
#define GL_RGBA16_EXT 0x805B
#define GL_RGBA16_SNORM_EXT 0x8F9B
#define GL_BGRA8_EXT 0x93A1
#define GL_RGB32I 0x8D83
#define GL_RGB32UI 0x8D87

// GL_EXT_disjoint_timer_query constants
#define GL_TIME_ELAPSED_EXT 0x88BF
#define GL_QUERY_RESULT_AVAILABLE_EXT 0x8867
#define GL_QUERY_RESULT_EXT 0x8866
#define GL_QUERY_COUNTER_BITS_EXT 0x8864
#define GL_STREAM_READ 0x88E1
#define GL_STREAM_DRAW 0x88E0

// GL_ANGLE_pack_reverse_row_order extension
#define GL_PACK_REVERSE_ROW_ORDER_ANGLE 0x93A4

// GL_EXT_map_buffer_range extension constants
#define GL_PIXEL_PACK_BUFFER 0x88EB
#define GL_MAP_READ_BIT 0x0001

// Blend constants
#define GL_BLEND 0x0BE2
#define GL_ONE_MINUS_SRC_ALPHA 0x0303
#define GL_SCISSOR_TEST 0x0C11
#define GL_LINEAR_MIPMAP_LINEAR 0x2703
#define GL_NEAREST_MIPMAP_NEAREST 0x2700
#define GL_NEAREST_MIPMAP_LINEAR 0x2702
#define GL_MAX_TEXTURE_SIZE 0x0D33
#define GL_FRAMEBUFFER 0x8D40
#define GL_PACK_ROW_LENGTH 0x0D02
#define GL_PACK_ALIGNMENT 0x0D05
#define GL_TEXTURE_BINDING_2D 0x8069
#define GL_TEXTURE_BINDING_3D 0x806A
#define GL_TEXTURE_BINDING_EXTERNAL_OES 0x8515
#define GL_LINEAR_MIPMAP_NEAREST 0x2701
#define GL_MIRRORED_REPEAT 0x8370
#define GL_NO_ERROR 0
#define GL_RENDERBUFFER 0x8D41
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_DEPTH_ATTACHMENT 0x8D00
#define GL_STENCIL_ATTACHMENT 0x8D20
#define GL_DEPTH_STENCIL_ATTACHMENT 0x821A
#define GL_FRAMEBUFFER_BINDING 0x8CA6
#define GL_RENDERBUFFER_BINDING 0x8CA7
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_VENDOR 0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#define GL_EXTENSIONS 0x1F03

// GL_EXT_texture extension constants
#define GL_LUMINANCE8_EXT 0x8040
#define GL_LUMINANCE16F_EXT 0x881E
#define GL_LUMINANCE32F_EXT 0x8818
#define GL_LUMINANCE8_ALPHA8_EXT 0x8045
#define GL_LUMINANCE_ALPHA16F_EXT 0x881F
#define GL_LUMINANCE_ALPHA32F_EXT 0x8819
#define GL_LUMINANCE8_OES 0x8040
#define GL_LUMINANCE8_ALPHA8_OES 0x8045
#define GL_TEXTURE_WIDTH 0x1000
#define GL_TEXTURE_HEIGHT 0x1001
#define GL_TEXTURE_DEPTH 0x8071
#define GL_TEXTURE_INTERNAL_FORMAT 0x1003
#define GL_TEXTURE_WRAP_R 0x8072
#define GL_TEXTURE_SWIZZLE_R 0x8E42
#define GL_TEXTURE_SWIZZLE_G 0x8E43
#define GL_TEXTURE_SWIZZLE_B 0x8E44
#define GL_TEXTURE_SWIZZLE_A 0x8E45

// OpenGL ES extension function pointer types (stubs for compilation)
typedef void (*PFNGLUNMAPBUFFEROESPROC)(GLenum target);
typedef void* (*PFNGLMAPBUFFERRANGEEXTPROC)(GLenum target, GLintptr offset, GLsizeiptr length, GLbitfield access);
typedef void (*PFNGLTEXIMAGE3DOESPROC)(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLenum format, GLenum type, const void* pixels);
typedef void (*PFNGLTEXSUBIMAGE3DOESPROC)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLenum type, const void* pixels);
typedef void (*PFNGLGENQUERIESEXTPROC)(GLsizei n, GLuint* ids);
typedef void (*PFNGLDELETEQUERIESEXTPROC)(GLsizei n, const GLuint* ids);
typedef void (*PFNGLBEGINQUERYEXTPROC)(GLenum target, GLuint id);
typedef void (*PFNGLENDQUERYEXTPROC)(GLenum target);
typedef void (*PFNGLGETQUERYOBJECTIVEXTPROC)(GLuint id, GLenum pname, GLint* params);
typedef void (*PFNGLGETQUERYOBJECTUI64VEXTPROC)(GLuint id, GLenum pname, GLuint64* params);
typedef void (*PFNGLGETQUERYIVEXTPROC)(GLenum target, GLenum pname, GLint* params);
typedef void (*PFNGLTEXSTORAGE2DEXTPROC)(GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height);
typedef void (*PFNGLTEXSTORAGE3DEXTPROC)(GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth);
typedef void (*PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)(GLenum target, void* image);
typedef void (*PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC)(GLenum target, void* image);
typedef void (*PFNGLEGLIMAGETARGETTEXTURESTORAGEEXTPROC)(GLenum target, void* image, const GLint* attrib_list);

#endif // __APPLE__
#endif // __gl2ext_h_

