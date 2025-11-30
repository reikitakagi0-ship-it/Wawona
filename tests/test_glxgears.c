#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <sys/time.h>

#include <wayland-client.h>
#include <wayland-egl.h>

#define GL_GLEXT_PROTOTYPES
#include <GLES2/gl2.h>
#include <EGL/egl.h>

#include "xdg-shell-client-protocol.h"

// Math constants
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Gear structure
typedef struct {
    GLfloat *vertices;
    GLfloat *normals;
    int nvertices;
} Gear;

// Client state
struct client_state {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct xdg_wm_base *xdg_wm_base;
    
    struct wl_surface *surface;
    struct xdg_surface *xdg_surface;
    struct xdg_toplevel *xdg_toplevel;
    struct wl_egl_window *egl_window;
    
    EGLDisplay egl_display;
    EGLContext egl_context;
    EGLSurface egl_surface;
    
    int width, height;
    int running;
    
    Gear *gear1, *gear2, *gear3;
    GLint modelview_loc, projection_loc, color_loc, normal_loc, light_loc;
    GLfloat view_rot[3];
    GLfloat view_pos[3];
    GLfloat angle;
};

// Shader sources
static const char *vertex_shader_source =
    "attribute vec3 position;\n"
    "attribute vec3 normal;\n"
    "uniform mat4 modelview;\n"
    "uniform mat4 projection;\n"
    "uniform vec3 light_pos;\n"
    "varying float intensity;\n"
    "void main() {\n"
    "   vec4 pos = modelview * vec4(position, 1.0);\n"
    "   vec3 n = normalize(mat3(modelview) * normal);\n"
    "   vec3 l = normalize(light_pos - pos.xyz);\n"
    "   intensity = max(dot(n, l), 0.0);\n"
    "   gl_Position = projection * pos;\n"
    "}\n";

static const char *fragment_shader_source =
    "precision mediump float;\n"
    "uniform vec4 color;\n"
    "varying float intensity;\n"
    "void main() {\n"
    "   gl_FragColor = color * (0.2 + 0.8 * intensity);\n"
    "}\n";

// Gear generation
static Gear *create_gear(GLfloat inner_radius, GLfloat outer_radius, GLfloat width,
                         GLint teeth, GLfloat tooth_depth) {
    Gear *gear = malloc(sizeof(Gear));
    GLfloat r0, r1, r2;
    GLfloat angle, da;
    GLfloat u, v, len;
    int i;
    
    r0 = inner_radius;
    r1 = outer_radius - tooth_depth / 2.0;
    r2 = outer_radius + tooth_depth / 2.0;
    
    da = 2.0 * M_PI / teeth / 4.0;
    
    // Allocate vertices (approximate count)
    int max_vertices = teeth * 40;
    gear->vertices = malloc(max_vertices * 3 * sizeof(GLfloat));
    gear->normals = malloc(max_vertices * 3 * sizeof(GLfloat));
    gear->nvertices = 0;
    
    #define ADD_VERTEX(x, y, z, nx, ny, nz) \
        gear->vertices[gear->nvertices*3+0] = x; \
        gear->vertices[gear->nvertices*3+1] = y; \
        gear->vertices[gear->nvertices*3+2] = z; \
        gear->normals[gear->nvertices*3+0] = nx; \
        gear->normals[gear->nvertices*3+1] = ny; \
        gear->normals[gear->nvertices*3+2] = nz; \
        gear->nvertices++;

    // Draw front face
    for (i = 0; i < teeth; i++) {
        angle = i * 2.0 * M_PI / teeth;
        
        ADD_VERTEX(r0 * cos(angle), r0 * sin(angle), width * 0.5, 0.0, 0.0, 1.0);
        ADD_VERTEX(r1 * cos(angle), r1 * sin(angle), width * 0.5, 0.0, 0.0, 1.0);
        ADD_VERTEX(r0 * cos(angle), r0 * sin(angle), width * 0.5, 0.0, 0.0, 1.0);
        ADD_VERTEX(r1 * cos(angle + 3 * da), r1 * sin(angle + 3 * da), width * 0.5, 0.0, 0.0, 1.0);
    }
    
    // Draw front sides of teeth
    da = 2.0 * M_PI / teeth / 4.0;
    for (i = 0; i < teeth; i++) {
        angle = i * 2.0 * M_PI / teeth;
        
        ADD_VERTEX(r1 * cos(angle), r1 * sin(angle), width * 0.5, 0.0, 0.0, 1.0);
        ADD_VERTEX(r2 * cos(angle + da), r2 * sin(angle + da), width * 0.5, 0.0, 0.0, 1.0);
        ADD_VERTEX(r2 * cos(angle + 2 * da), r2 * sin(angle + 2 * da), width * 0.5, 0.0, 0.0, 1.0);
        ADD_VERTEX(r1 * cos(angle + 3 * da), r1 * sin(angle + 3 * da), width * 0.5, 0.0, 0.0, 1.0);
    }
    
    // Back face
    for (i = 0; i < teeth; i++) {
        angle = i * 2.0 * M_PI / teeth;
        
        ADD_VERTEX(r1 * cos(angle), r1 * sin(angle), -width * 0.5, 0.0, 0.0, -1.0);
        ADD_VERTEX(r0 * cos(angle), r0 * sin(angle), -width * 0.5, 0.0, 0.0, -1.0);
        ADD_VERTEX(r1 * cos(angle + 3 * da), r1 * sin(angle + 3 * da), -width * 0.5, 0.0, 0.0, -1.0);
        ADD_VERTEX(r0 * cos(angle), r0 * sin(angle), -width * 0.5, 0.0, 0.0, -1.0);
    }
    
    // Back sides of teeth
    for (i = 0; i < teeth; i++) {
        angle = i * 2.0 * M_PI / teeth;
        
        ADD_VERTEX(r1 * cos(angle + 3 * da), r1 * sin(angle + 3 * da), -width * 0.5, 0.0, 0.0, -1.0);
        ADD_VERTEX(r2 * cos(angle + 2 * da), r2 * sin(angle + 2 * da), -width * 0.5, 0.0, 0.0, -1.0);
        ADD_VERTEX(r2 * cos(angle + da), r2 * sin(angle + da), -width * 0.5, 0.0, 0.0, -1.0);
        ADD_VERTEX(r1 * cos(angle), r1 * sin(angle), -width * 0.5, 0.0, 0.0, -1.0);
    }
    
    // Draw outward faces of teeth
    for (i = 0; i < teeth; i++) {
        angle = i * 2.0 * M_PI / teeth;
        
        ADD_VERTEX(r1 * cos(angle), r1 * sin(angle), width * 0.5, r1 * cos(angle), r1 * sin(angle), 0.0);
        ADD_VERTEX(r1 * cos(angle), r1 * sin(angle), -width * 0.5, r1 * cos(angle), r1 * sin(angle), 0.0);
        
        u = r2 * cos(angle + da) - r1 * cos(angle);
        v = r2 * sin(angle + da) - r1 * sin(angle);
        len = sqrt(u * u + v * v);
        u /= len;
        v /= len;
        
        ADD_VERTEX(r2 * cos(angle + da), r2 * sin(angle + da), width * 0.5, v, -u, 0.0);
        ADD_VERTEX(r2 * cos(angle + da), r2 * sin(angle + da), -width * 0.5, v, -u, 0.0);
        
        ADD_VERTEX(r2 * cos(angle + 2 * da), r2 * sin(angle + 2 * da), width * 0.5, cos(angle + 1.5 * da), sin(angle + 1.5 * da), 0.0);
        ADD_VERTEX(r2 * cos(angle + 2 * da), r2 * sin(angle + 2 * da), -width * 0.5, cos(angle + 1.5 * da), sin(angle + 1.5 * da), 0.0);
        
        u = r1 * cos(angle + 3 * da) - r2 * cos(angle + 2 * da);
        v = r1 * sin(angle + 3 * da) - r2 * sin(angle + 2 * da);
        
        ADD_VERTEX(r1 * cos(angle + 3 * da), r1 * sin(angle + 3 * da), width * 0.5, v, -u, 0.0);
        ADD_VERTEX(r1 * cos(angle + 3 * da), r1 * sin(angle + 3 * da), -width * 0.5, v, -u, 0.0);
    }
    
    return gear;
}

static void draw_gear(Gear *gear, GLfloat *transform, GLint modelview_loc, GLint color_loc, GLfloat *color) {
    glUniformMatrix4fv(modelview_loc, 1, GL_FALSE, transform);
    glUniform4fv(color_loc, 1, color);
    
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, gear->vertices);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, gear->normals);
    glEnableVertexAttribArray(1);
    
    glDrawArrays(GL_TRIANGLES, 0, gear->nvertices);
}

static void matrix_multiply(GLfloat *m, GLfloat *n) {
    GLfloat tmp[16];
    const GLfloat *row, *column;
    div_t d;
    int i, j;

    for (i = 0; i < 16; i++) {
        tmp[i] = 0;
        d = div(i, 4);
        row = n + d.quot * 4;
        column = m + d.rem;
        for (j = 0; j < 4; j++)
            tmp[i] += row[j] * column[j * 4];
    }
    memcpy(m, tmp, sizeof(tmp));
}

static void matrix_rotate(GLfloat *m, GLfloat angle, GLfloat x, GLfloat y, GLfloat z) {
    GLfloat s, c;
    GLfloat mag;
    GLfloat rot[16];

    mag = sqrt(x * x + y * y + z * z);
    if (mag > 0.0f) {
        x /= mag;
        y /= mag;
        z /= mag;
        
        s = sin(angle * M_PI / 180.0);
        c = cos(angle * M_PI / 180.0);

        rot[0] = x * x * (1 - c) + c;
        rot[1] = y * x * (1 - c) + z * s;
        rot[2] = x * z * (1 - c) - y * s;
        rot[3] = 0;
        rot[4] = x * y * (1 - c) - z * s;
        rot[5] = y * y * (1 - c) + c;
        rot[6] = y * z * (1 - c) + x * s;
        rot[7] = 0;
        rot[8] = x * z * (1 - c) + y * s;
        rot[9] = y * z * (1 - c) - x * s;
        rot[10] = z * z * (1 - c) + c;
        rot[11] = 0;
        rot[12] = 0;
        rot[13] = 0;
        rot[14] = 0;
        rot[15] = 1;
        
        matrix_multiply(m, rot);
    }
}

static void matrix_translate(GLfloat *m, GLfloat x, GLfloat y, GLfloat z) {
    GLfloat t[16] = {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, z, 1
    };
    matrix_multiply(m, t);
}

static void matrix_identity(GLfloat *m) {
    memset(m, 0, 16 * sizeof(GLfloat));
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static void draw(struct client_state *state) {
    GLfloat view[16], model[16];
    GLfloat red[4] = {0.8, 0.1, 0.0, 1.0};
    GLfloat green[4] = {0.0, 0.8, 0.2, 1.0};
    GLfloat blue[4] = {0.2, 0.2, 1.0, 1.0};
    
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    matrix_identity(view);
    matrix_translate(view, 0.0, 0.0, -40.0);
    matrix_rotate(view, state->view_rot[0], 1.0, 0.0, 0.0);
    matrix_rotate(view, state->view_rot[1], 0.0, 1.0, 0.0);
    matrix_rotate(view, state->view_rot[2], 0.0, 0.0, 1.0);
    
    // Gear 1
    memcpy(model, view, sizeof(model));
    matrix_translate(model, -3.0, -2.0, 0.0);
    matrix_rotate(model, state->angle, 0.0, 0.0, 1.0);
    draw_gear(state->gear1, model, state->modelview_loc, state->color_loc, red);
    
    // Gear 2
    memcpy(model, view, sizeof(model));
    matrix_translate(model, 3.1, -2.0, 0.0);
    matrix_rotate(model, -2.0 * state->angle - 9.0, 0.0, 0.0, 1.0);
    draw_gear(state->gear2, model, state->modelview_loc, state->color_loc, green);
    
    // Gear 3
    memcpy(model, view, sizeof(model));
    matrix_translate(model, -3.1, 4.2, 0.0);
    matrix_rotate(model, -2.0 * state->angle - 25.0, 0.0, 0.0, 1.0);
    draw_gear(state->gear3, model, state->modelview_loc, state->color_loc, blue);
    
    eglSwapBuffers(state->egl_display, state->egl_surface);
    
    state->angle += 1.0;
}

// Wayland callbacks
static void registry_handle_global(void *data, struct wl_registry *registry,
                                 uint32_t name, const char *interface, uint32_t version) {
    struct client_state *state = data;
    (void)version;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        state->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        state->xdg_wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    // Handle removal
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove
};

static void xdg_surface_handle_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    struct client_state *state = data;
    xdg_surface_ack_configure(xdg_surface, serial);
    
    if (state->egl_window) {
        wl_egl_window_resize(state->egl_window, state->width, state->height, 0, 0);
    }
    draw(state);
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_handle_configure,
};

static void xdg_toplevel_handle_close(void *data, struct xdg_toplevel *xdg_toplevel) {
    struct client_state *state = data;
    (void)xdg_toplevel;
    state->running = 0;
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    .configure = NULL,
    .close = xdg_toplevel_handle_close,
};

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    struct client_state state = {0};
    state.running = 1;
    state.width = 300;
    state.height = 300;
    state.view_rot[0] = 20.0;
    state.view_rot[1] = 30.0;
    state.view_rot[2] = 0.0;
    
    state.display = wl_display_connect(NULL);
    if (!state.display) {
        fprintf(stderr, "Failed to connect to display\n");
        return 1;
    }
    
    state.registry = wl_display_get_registry(state.display);
    wl_registry_add_listener(state.registry, &registry_listener, &state);
    wl_display_roundtrip(state.display);
    
    state.surface = wl_compositor_create_surface(state.compositor);
    state.xdg_surface = xdg_wm_base_get_xdg_surface(state.xdg_wm_base, state.surface);
    xdg_surface_add_listener(state.xdg_surface, &xdg_surface_listener, &state);
    
    state.xdg_toplevel = xdg_surface_get_toplevel(state.xdg_surface);
    xdg_toplevel_add_listener(state.xdg_toplevel, &xdg_toplevel_listener, &state);
    xdg_toplevel_set_title(state.xdg_toplevel, "Wawona GLX Gears");
    
    state.egl_window = wl_egl_window_create(state.surface, state.width, state.height);
    
    // EGL Setup
    state.egl_display = eglGetDisplay((EGLNativeDisplayType)state.display);
    eglInitialize(state.egl_display, NULL, NULL);
    
    EGLint config_attribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    
    EGLConfig config;
    EGLint num_configs;
    eglChooseConfig(state.egl_display, config_attribs, &config, 1, &num_configs);
    
    EGLint context_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };
    
    state.egl_context = eglCreateContext(state.egl_display, config, EGL_NO_CONTEXT, context_attribs);
    state.egl_surface = eglCreateWindowSurface(state.egl_display, config, (EGLNativeWindowType)state.egl_window, NULL);
    
    eglMakeCurrent(state.egl_display, state.egl_surface, state.egl_surface, state.egl_context);
    
    // GL Setup
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    
    GLuint vshader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vshader, 1, &vertex_shader_source, NULL);
    glCompileShader(vshader);
    
    GLuint fshader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fshader, 1, &fragment_shader_source, NULL);
    glCompileShader(fshader);
    
    GLuint program = glCreateProgram();
    glAttachShader(program, vshader);
    glAttachShader(program, fshader);
    glBindAttribLocation(program, 0, "position");
    glBindAttribLocation(program, 1, "normal");
    glLinkProgram(program);
    glUseProgram(program);
    
    state.modelview_loc = glGetUniformLocation(program, "modelview");
    state.projection_loc = glGetUniformLocation(program, "projection");
    state.color_loc = glGetUniformLocation(program, "color");
    state.light_loc = glGetUniformLocation(program, "light_pos");
    
    GLfloat light_pos[3] = {5.0, 5.0, 10.0};
    glUniform3fv(state.light_loc, 1, light_pos);
    
    GLfloat projection[16];
    matrix_identity(projection);
    // Simple ortho projection for now, better would be perspective
    // GLfloat h = (GLfloat)state.height / (GLfloat)state.width;
    projection[0] = 1.0/30.0;
    projection[5] = 1.0/30.0;
    projection[10] = -1.0/100.0;
    glUniformMatrix4fv(state.projection_loc, 1, GL_FALSE, projection);
    
    state.gear1 = create_gear(1.0, 4.0, 1.0, 20, 0.7);
    state.gear2 = create_gear(0.5, 2.0, 2.0, 10, 0.7);
    state.gear3 = create_gear(1.3, 2.0, 0.5, 10, 0.7);
    
    wl_surface_commit(state.surface);
    
    while (state.running && wl_display_dispatch(state.display) != -1) {
        draw(&state);
    }
    
    return 0;
}
