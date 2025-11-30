#ifndef __gl2_h_
#define __gl2_h_

#ifdef __APPLE__
// macOS stub OpenGL ES 2.0 header - allows compilation but functions will fail at runtime

#include <stdint.h>

typedef void GLvoid;
typedef unsigned int GLenum;
typedef float GLfloat;
typedef int GLint;
typedef int GLsizei;
typedef unsigned int GLbitfield;
typedef unsigned char GLboolean;
typedef signed char GLbyte;
typedef short GLshort;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef int GLfixed;
typedef intptr_t GLintptr;
typedef intptr_t GLsizeiptr;
typedef unsigned long long GLuint64;
typedef unsigned int GLbitfield;
typedef char GLchar;

#define GL_FALSE 0
#define GL_TRUE 1
#define GL_NONE 0

#define GL_VERTEX_SHADER 0x8B31
#define GL_FRAGMENT_SHADER 0x8B30

#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_INFO_LOG_LENGTH 0x8B84

#define GL_ARRAY_BUFFER 0x8892
#define GL_ELEMENT_ARRAY_BUFFER 0x8893

#define GL_STATIC_DRAW 0x88E4
#define GL_DYNAMIC_DRAW 0x88E8

#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_DEPTH_BUFFER_BIT 0x00000100

#define GL_TRIANGLES 0x0004
#define GL_TRIANGLE_STRIP 0x0005
#define GL_TRIANGLE_FAN 0x0006

// Type constants (needed by clients)
#define GL_FLOAT 0x1406
#define GL_UNSIGNED_BYTE 0x1401
#define GL_UNSIGNED_SHORT 0x1403

// Texture constants
#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_NEAREST 0x2600
#define GL_LINEAR 0x2601
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_REPEAT 0x2901
#define GL_TEXTURE0 0x84C0
#define GL_TEXTURE1 0x84C1
#define GL_TEXTURE2 0x84C2
#define GL_TEXTURE3 0x84C3
#define GL_TEXTURE4 0x84C4
#define GL_TEXTURE5 0x84C5
#define GL_TEXTURE6 0x84C6
#define GL_TEXTURE7 0x84C7
#define GL_TEXTURE8 0x84C8
#define GL_TEXTURE9 0x84C9
#define GL_TEXTURE10 0x84CA
#define GL_TEXTURE11 0x84CB
#define GL_TEXTURE12 0x84CC
#define GL_TEXTURE13 0x84CD
#define GL_TEXTURE14 0x84CE
#define GL_TEXTURE15 0x84CF
#define GL_TEXTURE16 0x84D0
#define GL_TEXTURE17 0x84D1
#define GL_TEXTURE18 0x84D2
#define GL_TEXTURE19 0x84D3
#define GL_TEXTURE20 0x84D4
#define GL_TEXTURE21 0x84D5
#define GL_TEXTURE22 0x84D6
#define GL_TEXTURE23 0x84D7
#define GL_TEXTURE24 0x84D8
#define GL_TEXTURE25 0x84D9
#define GL_TEXTURE26 0x84DA
#define GL_TEXTURE27 0x84DB
#define GL_TEXTURE28 0x84DC
#define GL_TEXTURE29 0x84DD
#define GL_TEXTURE30 0x84DE
#define GL_TEXTURE31 0x84DF

// Stub function declarations
GLuint glCreateShader(GLenum type);
void glShaderSource(GLuint shader, GLsizei count, const GLchar *const*string, const GLint *length);
void glCompileShader(GLuint shader);
void glGetShaderiv(GLuint shader, GLenum pname, GLint *params);
void glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
void glDeleteShader(GLuint shader);

GLuint glCreateProgram(void);
void glAttachShader(GLuint program, GLuint shader);
void glLinkProgram(GLuint program);
void glGetProgramiv(GLuint program, GLenum pname, GLint *params);
void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
void glDeleteProgram(GLuint program);
void glUseProgram(GLuint program);

GLint glGetUniformLocation(GLuint program, const GLchar *name);
void glUniform1f(GLint location, GLfloat v0);
void glUniform2f(GLint location, GLfloat v0, GLfloat v1);
void glUniform3f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2);
void glUniform4f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);
void glUniformMatrix4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);

GLint glGetAttribLocation(GLuint program, const GLchar *name);
void glEnableVertexAttribArray(GLuint index);
void glDisableVertexAttribArray(GLuint index);
void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid *pointer);

void glGenBuffers(GLsizei n, GLuint *buffers);
void glDeleteBuffers(GLsizei n, const GLuint *buffers);
void glBindBuffer(GLenum target, GLuint buffer);
void glBufferData(GLenum target, GLsizeiptr size, const GLvoid *data, GLenum usage);

void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glClear(GLbitfield mask);
void glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices);

void glBindTexture(GLenum target, GLuint texture);
void glGenTextures(GLsizei n, GLuint *textures);
void glDeleteTextures(GLsizei n, const GLuint *textures);
void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
void glTexParameteri(GLenum target, GLenum pname, GLint param);
void glActiveTexture(GLenum texture);
void glBindAttribLocation(GLuint program, GLuint index, const GLchar *name);
void glUniform1i(GLint location, GLint v0);
void glUniform1fv(GLint location, GLsizei count, const GLfloat *value);
void glUniform2fv(GLint location, GLsizei count, const GLfloat *value);
void glUniform3fv(GLint location, GLsizei count, const GLfloat *value);
void glUniform4fv(GLint location, GLsizei count, const GLfloat *value);
void glUniformMatrix2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniform4iv(GLint location, GLsizei count, const GLint *value);
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels);
void glPixelStorei(GLenum pname, GLint param);
void glFlush(void);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glBindBuffer(GLenum target, GLuint buffer);
void glScissor(GLint x, GLint y, GLsizei width, GLsizei height);
void glBlendFunc(GLenum sfactor, GLenum dfactor);
void glGetIntegerv(GLenum pname, GLint *params);
void glBindFramebuffer(GLenum target, GLuint framebuffer);
void glGenRenderbuffers(GLsizei n, GLuint *renderbuffers);
void glBindRenderbuffer(GLenum target, GLuint renderbuffer);
void glDeleteRenderbuffers(GLsizei n, const GLuint *renderbuffers);
void glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);
void glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);
void glGenFramebuffers(GLsizei n, GLuint *framebuffers);
void glDeleteFramebuffers(GLsizei n, const GLuint *framebuffers);
void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
GLenum glCheckFramebufferStatus(GLenum target);
const GLubyte *glGetString(GLenum name);
void glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname, GLint *params);
void glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const void *pixels);
void glTexParameteriv(GLenum target, GLenum pname, const GLint *params);

GLenum glGetError(void);

#endif // __APPLE__
#endif // __gl2_h_

