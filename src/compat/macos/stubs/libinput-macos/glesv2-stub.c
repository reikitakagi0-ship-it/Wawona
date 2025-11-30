/*
 * macOS stub implementation of OpenGL ES 2.0 functions
 * These are weak symbols that allow linking but fail at runtime
 */

#ifdef __APPLE__

#include "GLES2/gl2.h"
#include <stdio.h>
#include <stdlib.h>

// Weak attribute allows these to be overridden if real implementations exist
#define WEAK __attribute__((weak))

// Stub implementations that fail at runtime
static void stub_error(const char *func) {
    fprintf(stderr, "Error: %s called but OpenGL ES is not available on macOS (stub implementation)\n", func);
    exit(1);
}

// OpenGL ES 2.0 function stubs
WEAK GLuint glCreateShader(GLenum type) { stub_error("glCreateShader"); return 0; }
WEAK void glShaderSource(GLuint shader, GLsizei count, const GLchar *const*string, const GLint *length) { stub_error("glShaderSource"); }
WEAK void glCompileShader(GLuint shader) { stub_error("glCompileShader"); }
WEAK void glGetShaderiv(GLuint shader, GLenum pname, GLint *params) { stub_error("glGetShaderiv"); }
WEAK void glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog) { stub_error("glGetShaderInfoLog"); }
WEAK void glDeleteShader(GLuint shader) { stub_error("glDeleteShader"); }

WEAK GLuint glCreateProgram(void) { stub_error("glCreateProgram"); return 0; }
WEAK void glAttachShader(GLuint program, GLuint shader) { stub_error("glAttachShader"); }
WEAK void glLinkProgram(GLuint program) { stub_error("glLinkProgram"); }
WEAK void glGetProgramiv(GLuint program, GLenum pname, GLint *params) { stub_error("glGetProgramiv"); }
WEAK void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog) { stub_error("glGetProgramInfoLog"); }
WEAK void glDeleteProgram(GLuint program) { stub_error("glDeleteProgram"); }
WEAK void glUseProgram(GLuint program) { stub_error("glUseProgram"); }

WEAK GLint glGetUniformLocation(GLuint program, const GLchar *name) { stub_error("glGetUniformLocation"); return -1; }
WEAK void glUniform1f(GLint location, GLfloat v0) { stub_error("glUniform1f"); }
WEAK void glUniform2f(GLint location, GLfloat v0, GLfloat v1) { stub_error("glUniform2f"); }
WEAK void glUniform3f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2) { stub_error("glUniform3f"); }
WEAK void glUniform4f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) { stub_error("glUniform4f"); }
WEAK void glUniformMatrix4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { stub_error("glUniformMatrix4fv"); }
WEAK void glUniform1i(GLint location, GLint v0) { stub_error("glUniform1i"); }
WEAK void glUniform1fv(GLint location, GLsizei count, const GLfloat *value) { stub_error("glUniform1fv"); }
WEAK void glUniform2fv(GLint location, GLsizei count, const GLfloat *value) { stub_error("glUniform2fv"); }
WEAK void glUniform3fv(GLint location, GLsizei count, const GLfloat *value) { stub_error("glUniform3fv"); }
WEAK void glUniform4fv(GLint location, GLsizei count, const GLfloat *value) { stub_error("glUniform4fv"); }
WEAK void glUniform4iv(GLint location, GLsizei count, const GLint *value) { stub_error("glUniform4iv"); }
WEAK void glUniformMatrix2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { stub_error("glUniformMatrix2fv"); }
WEAK void glUniformMatrix3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { stub_error("glUniformMatrix3fv"); }

WEAK GLint glGetAttribLocation(GLuint program, const GLchar *name) { stub_error("glGetAttribLocation"); return -1; }
WEAK void glEnableVertexAttribArray(GLuint index) { stub_error("glEnableVertexAttribArray"); }
WEAK void glDisableVertexAttribArray(GLuint index) { stub_error("glDisableVertexAttribArray"); }
WEAK void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid *pointer) { stub_error("glVertexAttribPointer"); }
WEAK void glBindAttribLocation(GLuint program, GLuint index, const GLchar *name) { stub_error("glBindAttribLocation"); }

WEAK void glGenBuffers(GLsizei n, GLuint *buffers) { stub_error("glGenBuffers"); }
WEAK void glDeleteBuffers(GLsizei n, const GLuint *buffers) { stub_error("glDeleteBuffers"); }
WEAK void glBindBuffer(GLenum target, GLuint buffer) { stub_error("glBindBuffer"); }
WEAK void glBufferData(GLenum target, GLsizeiptr size, const GLvoid *data, GLenum usage) { stub_error("glBufferData"); }

WEAK void glViewport(GLint x, GLint y, GLsizei width, GLsizei height) { stub_error("glViewport"); }
WEAK void glClear(GLbitfield mask) { stub_error("glClear"); }
WEAK void glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) { stub_error("glClearColor"); }
WEAK void glDrawArrays(GLenum mode, GLint first, GLsizei count) { stub_error("glDrawArrays"); }
WEAK void glDrawElements(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices) { stub_error("glDrawElements"); }

WEAK void glBindTexture(GLenum target, GLuint texture) { stub_error("glBindTexture"); }
WEAK void glGenTextures(GLsizei n, GLuint *textures) { stub_error("glGenTextures"); }
WEAK void glDeleteTextures(GLsizei n, const GLuint *textures) { stub_error("glDeleteTextures"); }
WEAK void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels) { stub_error("glTexImage2D"); }
WEAK void glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const void *pixels) { stub_error("glTexSubImage2D"); }
WEAK void glTexParameteri(GLenum target, GLenum pname, GLint param) { stub_error("glTexParameteri"); }
WEAK void glTexParameteriv(GLenum target, GLenum pname, const GLint *params) { stub_error("glTexParameteriv"); }
WEAK void glActiveTexture(GLenum texture) { stub_error("glActiveTexture"); }
WEAK void glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname, GLint *params) { stub_error("glGetTexLevelParameteriv"); }

WEAK void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels) { stub_error("glReadPixels"); }
WEAK void glPixelStorei(GLenum pname, GLint param) { stub_error("glPixelStorei"); }
WEAK void glFlush(void) { stub_error("glFlush"); }
WEAK void glEnable(GLenum cap) { stub_error("glEnable"); }
WEAK void glDisable(GLenum cap) { stub_error("glDisable"); }
WEAK void glScissor(GLint x, GLint y, GLsizei width, GLsizei height) { stub_error("glScissor"); }
WEAK void glBlendFunc(GLenum sfactor, GLenum dfactor) { stub_error("glBlendFunc"); }
WEAK void glGetIntegerv(GLenum pname, GLint *params) { stub_error("glGetIntegerv"); }
WEAK const GLubyte *glGetString(GLenum name) { stub_error("glGetString"); return NULL; }

WEAK void glBindFramebuffer(GLenum target, GLuint framebuffer) { stub_error("glBindFramebuffer"); }
WEAK void glGenFramebuffers(GLsizei n, GLuint *framebuffers) { stub_error("glGenFramebuffers"); }
WEAK void glDeleteFramebuffers(GLsizei n, const GLuint *framebuffers) { stub_error("glDeleteFramebuffers"); }
WEAK void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) { stub_error("glFramebufferTexture2D"); }
WEAK GLenum glCheckFramebufferStatus(GLenum target) { stub_error("glCheckFramebufferStatus"); return 0; }

WEAK void glGenRenderbuffers(GLsizei n, GLuint *renderbuffers) { stub_error("glGenRenderbuffers"); }
WEAK void glBindRenderbuffer(GLenum target, GLuint renderbuffer) { stub_error("glBindRenderbuffer"); }
WEAK void glDeleteRenderbuffers(GLsizei n, const GLuint *renderbuffers) { stub_error("glDeleteRenderbuffers"); }
WEAK void glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height) { stub_error("glRenderbufferStorage"); }
WEAK void glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) { stub_error("glFramebufferRenderbuffer"); }

WEAK GLenum glGetError(void) { return 0; }

#endif // __APPLE__

