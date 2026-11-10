// FlashLimiter.c — the "Reduce flashing" post-pass (task T104; FR-072). GPU only, no read-back.
//
// While Reduce flashing is on, the engine renders into this limiter's offscreen texture instead of
// the window surface. Each frame:
//   1. glGenerateMipmap: the smallest mip level is the frame's mean color.
//   2. Adapt pass (1 x 1): the adapted mean luminance moves toward the frame's mean luminance by at
//      most `maxStep` (the caller passes rate x frame time). Two 1 x 1 textures ping-pong; the value
//      is packed into two 8-bit channels (about 1/65000 precision).
//   3. Output pass: the frame is drawn to the target framebuffer, dimmed (gain <= 1) when it is
//      brighter than the adapted value and lifted by a uniform gray when it is darker, so its mean
//      luminance follows the adapted value. Rapid full-screen brightness changes become ramps; local
//      detail and motion stay.
// Luminance is Rec. 709 weights on squared (approximately linear) color; the mean comes from the
// mip chain of the encoded color, an approximation that is good enough for a rate limit.
// Entry points come from eglGetProcAddress; nothing here calls dlsym.
#include "CANGLE.h"
#include <stdlib.h>

#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE0 0x84C0
#define GL_TEXTURE1 0x84C1
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_LINEAR 0x2601
#define GL_NEAREST 0x2600
#define GL_LINEAR_MIPMAP_LINEAR 0x2703
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_RGBA 0x1908
#define GL_RGBA8 0x8058
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FRAMEBUFFER 0x8D40
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_VERTEX_SHADER 0x8B31
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_TRIANGLES 0x0004
#define GL_BLEND 0x0BE2
#define GL_DEPTH_TEST 0x0B71
#define GL_SCISSOR_TEST 0x0C11
#define GL_CULL_FACE 0x0B44
#define GL_STENCIL_TEST 0x0B90

typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef unsigned int GLenum;
typedef float GLfloat;
typedef unsigned char GLboolean;

static struct {
    int loaded;
    void (*genTextures)(GLsizei, GLuint *);
    void (*deleteTextures)(GLsizei, const GLuint *);
    void (*bindTexture)(GLenum, GLuint);
    void (*texImage2D)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *);
    void (*texParameteri)(GLenum, GLenum, GLint);
    void (*generateMipmap)(GLenum);
    void (*activeTexture)(GLenum);
    void (*genFramebuffers)(GLsizei, GLuint *);
    void (*deleteFramebuffers)(GLsizei, const GLuint *);
    void (*bindFramebuffer)(GLenum, GLuint);
    void (*framebufferTexture2D)(GLenum, GLenum, GLenum, GLuint, GLint);
    GLenum (*checkFramebufferStatus)(GLenum);
    GLuint (*createShader)(GLenum);
    void (*shaderSource)(GLuint, GLsizei, const char *const *, const GLint *);
    void (*compileShader)(GLuint);
    void (*getShaderiv)(GLuint, GLenum, GLint *);
    void (*deleteShader)(GLuint);
    GLuint (*createProgram)(void);
    void (*attachShader)(GLuint, GLuint);
    void (*linkProgram)(GLuint);
    void (*getProgramiv)(GLuint, GLenum, GLint *);
    void (*deleteProgram)(GLuint);
    void (*useProgram)(GLuint);
    GLint (*getUniformLocation)(GLuint, const char *);
    void (*uniform1i)(GLint, GLint);
    void (*uniform1f)(GLint, GLfloat);
    void (*genVertexArrays)(GLsizei, GLuint *);
    void (*deleteVertexArrays)(GLsizei, const GLuint *);
    void (*bindVertexArray)(GLuint);
    void (*viewport)(GLint, GLint, GLsizei, GLsizei);
    void (*disable)(GLenum);
    void (*colorMask)(GLboolean, GLboolean, GLboolean, GLboolean);
    void (*drawArrays)(GLenum, GLint, GLsizei);
    void (*readPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);
} gl;

#define LOAD(field, name) if ((*(void **)&gl.field = (void *)eglGetProcAddress(name)) == 0) return 0;

static int loadGL(void) {
    if (gl.loaded) return 1;
    LOAD(genTextures, "glGenTextures") LOAD(deleteTextures, "glDeleteTextures")
    LOAD(bindTexture, "glBindTexture") LOAD(texImage2D, "glTexImage2D")
    LOAD(texParameteri, "glTexParameteri") LOAD(generateMipmap, "glGenerateMipmap")
    LOAD(activeTexture, "glActiveTexture") LOAD(genFramebuffers, "glGenFramebuffers")
    LOAD(deleteFramebuffers, "glDeleteFramebuffers") LOAD(bindFramebuffer, "glBindFramebuffer")
    LOAD(framebufferTexture2D, "glFramebufferTexture2D") LOAD(checkFramebufferStatus, "glCheckFramebufferStatus")
    LOAD(createShader, "glCreateShader") LOAD(shaderSource, "glShaderSource")
    LOAD(compileShader, "glCompileShader") LOAD(getShaderiv, "glGetShaderiv")
    LOAD(deleteShader, "glDeleteShader") LOAD(createProgram, "glCreateProgram")
    LOAD(attachShader, "glAttachShader") LOAD(linkProgram, "glLinkProgram")
    LOAD(getProgramiv, "glGetProgramiv") LOAD(deleteProgram, "glDeleteProgram")
    LOAD(useProgram, "glUseProgram") LOAD(getUniformLocation, "glGetUniformLocation")
    LOAD(uniform1i, "glUniform1i") LOAD(uniform1f, "glUniform1f")
    LOAD(genVertexArrays, "glGenVertexArrays") LOAD(deleteVertexArrays, "glDeleteVertexArrays")
    LOAD(bindVertexArray, "glBindVertexArray") LOAD(viewport, "glViewport")
    LOAD(disable, "glDisable") LOAD(colorMask, "glColorMask") LOAD(drawArrays, "glDrawArrays")
    LOAD(readPixels, "glReadPixels")
    gl.loaded = 1;
    return 1;
}

// A full-screen triangle from gl_VertexID; no vertex buffer.
static const char *vertexSource =
    "#version 300 es\n"
    "out vec2 uv;\n"
    "void main() {\n"
    "    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));\n"
    "    uv = p;\n"
    "    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n"
    "}\n";

#define COMMON \
    "#version 300 es\n" \
    "precision highp float;\n" \
    "uniform sampler2D scene;\n" \
    "uniform float sceneLod;\n" \
    "float luminance(vec3 c) { return dot(c * c, vec3(0.2126, 0.7152, 0.0722)); }\n" \
    "float decode(vec4 c) { return c.r + c.g / 255.0; }\n" \
    "float sceneMean() { return luminance(textureLod(scene, vec2(0.5), sceneLod).rgb); }\n"

static const char *adaptSource =
    COMMON
    "uniform sampler2D previous;\n"
    "uniform float maxStep;\n"
    "uniform float resetAdaptation;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "    float current = sceneMean();\n"
    "    float before = decode(texture(previous, vec2(0.5)));\n"
    "    float adapted = resetAdaptation > 0.5 ? current : before + clamp(current - before, -maxStep, maxStep);\n"
    "    adapted = clamp(adapted, 0.0, 1.0);\n"
    "    float high = floor(adapted * 255.0) / 255.0;\n"
    "    color = vec4(high, (adapted - high) * 255.0, 0.0, 1.0);\n"
    "}\n";

static const char *outputSource =
    COMMON
    "uniform sampler2D adaptedTexture;\n"
    "in vec2 uv;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "    float current = sceneMean();\n"
    "    float adapted = decode(texture(adaptedTexture, vec2(0.5)));\n"
    "    vec3 linear = texture(scene, uv).rgb;\n"
    "    linear *= linear;\n"
    "    float gain = min(adapted / max(current, 1e-4), 1.0);\n"
    "    float lift = max(adapted - current * gain, 0.0);\n"
    "    color = vec4(sqrt(clamp(linear * gain + lift, 0.0, 1.0)), 1.0);\n"
    "}\n";

struct PMFlashLimiter {
    GLuint adaptProgram, outputProgram, vertexArray;
    GLuint sceneTexture, sceneFramebuffer;
    GLuint adaptTextures[2], adaptFramebuffers[2];
    int current;            // index of the latest adapted value
    int width, height, lod;
    int needsReset;
    GLint adaptScene, adaptLod, adaptPrevious, adaptMaxStep, adaptReset;
    GLint outputScene, outputLod, outputAdapted;
};

static GLuint compile(GLenum type, const char *source) {
    GLuint shader = gl.createShader(type);
    gl.shaderSource(shader, 1, &source, 0);
    gl.compileShader(shader);
    GLint ok = 0;
    gl.getShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) { gl.deleteShader(shader); return 0; }
    return shader;
}

static GLuint link(const char *fragmentSource) {
    GLuint vertex = compile(GL_VERTEX_SHADER, vertexSource);
    GLuint fragment = compile(GL_FRAGMENT_SHADER, fragmentSource);
    if (!vertex || !fragment) return 0;
    GLuint program = gl.createProgram();
    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    gl.deleteShader(vertex);
    gl.deleteShader(fragment);
    GLint ok = 0;
    gl.getProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) { gl.deleteProgram(program); return 0; }
    return program;
}

static void textureParameters(GLint minFilter) {
    gl.texParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter);
    gl.texParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, minFilter == GL_NEAREST ? GL_NEAREST : GL_LINEAR);
    gl.texParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.texParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

PMFlashLimiter *PMFlashLimiterCreate(void) {
    if (!loadGL()) return 0;
    PMFlashLimiter *limiter = calloc(1, sizeof(PMFlashLimiter));
    if (!limiter) return 0;
    limiter->adaptProgram = link(adaptSource);
    limiter->outputProgram = link(outputSource);
    if (!limiter->adaptProgram || !limiter->outputProgram) {
        PMFlashLimiterDestroy(limiter);
        return 0;
    }
    limiter->adaptScene = gl.getUniformLocation(limiter->adaptProgram, "scene");
    limiter->adaptLod = gl.getUniformLocation(limiter->adaptProgram, "sceneLod");
    limiter->adaptPrevious = gl.getUniformLocation(limiter->adaptProgram, "previous");
    limiter->adaptMaxStep = gl.getUniformLocation(limiter->adaptProgram, "maxStep");
    limiter->adaptReset = gl.getUniformLocation(limiter->adaptProgram, "resetAdaptation");
    limiter->outputScene = gl.getUniformLocation(limiter->outputProgram, "scene");
    limiter->outputLod = gl.getUniformLocation(limiter->outputProgram, "sceneLod");
    limiter->outputAdapted = gl.getUniformLocation(limiter->outputProgram, "adaptedTexture");
    gl.genVertexArrays(1, &limiter->vertexArray);
    gl.genTextures(2, limiter->adaptTextures);
    gl.genFramebuffers(2, limiter->adaptFramebuffers);
    for (int i = 0; i < 2; i++) {
        gl.bindTexture(GL_TEXTURE_2D, limiter->adaptTextures[i]);
        gl.texImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        textureParameters(GL_NEAREST);
        gl.bindFramebuffer(GL_FRAMEBUFFER, limiter->adaptFramebuffers[i]);
        gl.framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, limiter->adaptTextures[i], 0);
    }
    gl.bindTexture(GL_TEXTURE_2D, 0);
    gl.bindFramebuffer(GL_FRAMEBUFFER, 0);
    limiter->needsReset = 1;
    return limiter;
}

void PMFlashLimiterDestroy(PMFlashLimiter *limiter) {
    if (!limiter) return;
    if (limiter->sceneFramebuffer) gl.deleteFramebuffers(1, &limiter->sceneFramebuffer);
    if (limiter->sceneTexture) gl.deleteTextures(1, &limiter->sceneTexture);
    if (limiter->adaptFramebuffers[0]) gl.deleteFramebuffers(2, limiter->adaptFramebuffers);
    if (limiter->adaptTextures[0]) gl.deleteTextures(2, limiter->adaptTextures);
    if (limiter->vertexArray) gl.deleteVertexArrays(1, &limiter->vertexArray);
    if (limiter->adaptProgram) gl.deleteProgram(limiter->adaptProgram);
    if (limiter->outputProgram) gl.deleteProgram(limiter->outputProgram);
    free(limiter);
}

void PMFlashLimiterReset(PMFlashLimiter *limiter) {
    limiter->needsReset = 1;
}

unsigned int PMFlashLimiterBegin(PMFlashLimiter *limiter, int width, int height) {
    if (width <= 0 || height <= 0) return 0;
    if (width != limiter->width || height != limiter->height || !limiter->sceneFramebuffer) {
        if (!limiter->sceneTexture) gl.genTextures(1, &limiter->sceneTexture);
        if (!limiter->sceneFramebuffer) gl.genFramebuffers(1, &limiter->sceneFramebuffer);
        gl.bindTexture(GL_TEXTURE_2D, limiter->sceneTexture);
        gl.texImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        textureParameters(GL_LINEAR_MIPMAP_LINEAR);
        gl.bindTexture(GL_TEXTURE_2D, 0);
        gl.bindFramebuffer(GL_FRAMEBUFFER, limiter->sceneFramebuffer);
        gl.framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, limiter->sceneTexture, 0);
        GLenum status = gl.checkFramebufferStatus(GL_FRAMEBUFFER);
        gl.bindFramebuffer(GL_FRAMEBUFFER, 0);
        if (status != GL_FRAMEBUFFER_COMPLETE) return 0;
        int lod = 0;
        for (int size = width > height ? width : height; size > 1; size >>= 1) lod++;
        limiter->width = width;
        limiter->height = height;
        limiter->lod = lod;
        limiter->needsReset = 1;
    }
    return limiter->sceneFramebuffer;
}

static void prepareState(void) {
    gl.disable(GL_BLEND);
    gl.disable(GL_DEPTH_TEST);
    gl.disable(GL_SCISSOR_TEST);
    gl.disable(GL_CULL_FACE);
    gl.disable(GL_STENCIL_TEST);
    gl.colorMask(1, 1, 1, 1);
}

void PMFlashLimiterFinish(PMFlashLimiter *limiter, unsigned int targetFramebuffer, float maxStep) {
    prepareState();
    gl.bindVertexArray(limiter->vertexArray);
    gl.activeTexture(GL_TEXTURE0);
    gl.bindTexture(GL_TEXTURE_2D, limiter->sceneTexture);
    gl.generateMipmap(GL_TEXTURE_2D);

    // Adapt: previous → next.
    int next = 1 - limiter->current;
    gl.bindFramebuffer(GL_FRAMEBUFFER, limiter->adaptFramebuffers[next]);
    gl.viewport(0, 0, 1, 1);
    gl.useProgram(limiter->adaptProgram);
    gl.uniform1i(limiter->adaptScene, 0);
    gl.uniform1f(limiter->adaptLod, (GLfloat)limiter->lod);
    gl.activeTexture(GL_TEXTURE1);
    gl.bindTexture(GL_TEXTURE_2D, limiter->adaptTextures[limiter->current]);
    gl.uniform1i(limiter->adaptPrevious, 1);
    gl.uniform1f(limiter->adaptMaxStep, maxStep);
    gl.uniform1f(limiter->adaptReset, limiter->needsReset ? 1.0f : 0.0f);
    gl.drawArrays(GL_TRIANGLES, 0, 3);
    limiter->current = next;
    limiter->needsReset = 0;

    // Output: scene, adjusted toward the adapted value, into the target.
    gl.bindFramebuffer(GL_FRAMEBUFFER, targetFramebuffer);
    gl.viewport(0, 0, limiter->width, limiter->height);
    gl.useProgram(limiter->outputProgram);
    gl.uniform1i(limiter->outputScene, 0);
    gl.uniform1f(limiter->outputLod, (GLfloat)limiter->lod);
    gl.bindTexture(GL_TEXTURE_2D, limiter->adaptTextures[next]);   // unit 1
    gl.uniform1i(limiter->outputAdapted, 1);
    gl.drawArrays(GL_TRIANGLES, 0, 3);

    // Leave neutral bindings for the engine's next frame.
    gl.bindTexture(GL_TEXTURE_2D, 0);
    gl.activeTexture(GL_TEXTURE0);
    gl.bindTexture(GL_TEXTURE_2D, 0);
    gl.useProgram(0);
    gl.bindVertexArray(0);
}

float PMFlashLimiterAdaptedLuminance(PMFlashLimiter *limiter) {
    unsigned char pixel[4] = {0, 0, 0, 0};
    gl.bindFramebuffer(GL_FRAMEBUFFER, limiter->adaptFramebuffers[limiter->current]);
    gl.readPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    gl.bindFramebuffer(GL_FRAMEBUFFER, 0);
    return pixel[0] / 255.0f + pixel[1] / 65025.0f;
}

unsigned int PMFlashLimiterSceneFramebuffer(PMFlashLimiter *limiter) {
    return limiter->sceneFramebuffer;
}
