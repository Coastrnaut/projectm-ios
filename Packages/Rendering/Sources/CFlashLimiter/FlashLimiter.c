// FlashLimiter.c — the strobe safety envelope post-pass for projectM frames (FX-019, ADR-0011;
// research FX-019-D4, D5; Reduce flashing FR-072, tasks T104, T119). GPU only; no read-back on the
// frame path. Shared by ANGLERenderer (entry points from eglGetProcAddress) and the GLES fallback
// renderer (PMAppleGLESLoadProc's static table): the caller passes the loader, and each limiter
// keeps its own function table. Nothing here calls dlsym.
//
// The engine renders into this limiter's offscreen texture on every frame (with Reduce flashing off
// the always-on cap applies). Each frame:
//   1. Measure (4 x 4 target): each fragment reads 16 x 16 texels of its tile of the scene (4,096
//      in all, T104's sample budget), decodes sRGB exactly and writes the tile's mean WCAG relative
//      luminance and redness max(R - G - B, 0), each packed in two 8-bit channels (16 bits).
//   2. State (10 x 18 target, ping-pong): every fragment recomputes the frame's gain from the
//      previous state and the tile means — the rule of FlashSafety's FlashEnvelope (keep the two in
//      step; GPU tests compare them) — then writes one slot of the updated state of one area
//      (rows 0-15 tiles, row 16 the whole frame; columns 0-4 luminance, 5-9 redness). Row 17 holds
//      the gain.
//   3. Output: the frame x gain in linear light (exact sRGB decode/encode), never lifted; with
//      gain 1 the scene is copied unchanged.
// Tile rows are counted from the bottom of the picture (GL's origin); only consistency matters.

#define TILE_SIDE 4
#define STATE_WIDTH 10
#define STATE_HEIGHT 18
#include "CFlashLimiter.h"
#include <stdlib.h>

#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE0 0x84C0
#define GL_TEXTURE1 0x84C1
#define GL_TEXTURE2 0x84C2
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_LINEAR 0x2601
#define GL_NEAREST 0x2600
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

typedef struct GLTable {
    void (*genTextures)(GLsizei, GLuint *);
    void (*deleteTextures)(GLsizei, const GLuint *);
    void (*bindTexture)(GLenum, GLuint);
    void (*texImage2D)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *);
    void (*texParameteri)(GLenum, GLenum, GLint);
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
} GLTable;

#define LOAD(field, name) if ((*(void **)&gl->field = load(name, user)) == 0) return 0;

static int loadGL(GLTable *gl, PMFlashLoadProc load, void *user) {
    LOAD(genTextures, "glGenTextures") LOAD(deleteTextures, "glDeleteTextures")
    LOAD(bindTexture, "glBindTexture") LOAD(texImage2D, "glTexImage2D")
    LOAD(texParameteri, "glTexParameteri") LOAD(activeTexture, "glActiveTexture")
    LOAD(genFramebuffers, "glGenFramebuffers") LOAD(deleteFramebuffers, "glDeleteFramebuffers")
    LOAD(bindFramebuffer, "glBindFramebuffer") LOAD(framebufferTexture2D, "glFramebufferTexture2D")
    LOAD(checkFramebufferStatus, "glCheckFramebufferStatus")
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
    "precision highp int;\n" \
    "vec2 pack(float v) { v = clamp(v, 0.0, 1.0); float hi = floor(v * 255.0) / 255.0; return vec2(hi, (v - hi) * 255.0); }\n" \
    "float unpack(vec2 p) { return p.x + p.y / 255.0; }\n" \
    "vec3 decodeSRGB(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }\n" \
    "vec3 encodeSRGB(vec3 l) { return mix(l * 12.92, 1.055 * pow(max(l, vec3(1e-10)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), l)); }\n"

static const char *measureSource =
    COMMON
    "uniform sampler2D scene;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "    ivec2 tile = ivec2(gl_FragCoord.xy);\n"
    "    ivec2 size = textureSize(scene, 0);\n"
    "    float y = 0.0;\n"
    "    float r = 0.0;\n"
    "    for (int j = 0; j < 16; j++) {\n"
    "        for (int i = 0; i < 16; i++) {\n"
    "            vec2 f = (vec2(tile) + (vec2(float(i), float(j)) + 0.5) / 16.0) / 4.0;\n"
    "            ivec2 p = min(ivec2(f * vec2(size)), size - 1);\n"
    "            vec3 c = decodeSRGB(texelFetch(scene, p, 0).rgb);\n"
    "            y += dot(c, vec3(0.2126, 0.7152, 0.0722));\n"
    "            r += max(c.r - c.g - c.b, 0.0);\n"
    "        }\n"
    "    }\n"
    "    color = vec4(pack(y / 256.0), pack(r / 256.0));\n"
    "}\n";

// The rule of FlashSafety's FlashEnvelope (FX-019-R1, R5, R6, R8): keep in step with FlashEnvelope.swift.
static const char *stateSource =
    COMMON
    "uniform sampler2D tiles;\n"
    "uniform sampler2D previous;\n"
    "uniform float dt;\n"
    "uniform float window;\n"
    "uniform float lumThreshold;\n"
    "uniform float redThreshold;\n"
    "uniform float margin;\n"
    "uniform float rise;\n"
    "uniform float budget;\n"
    "uniform float resetState;\n"
    "out vec4 color;\n"
    "const float windowTolerance = 0.002;\n"   // FlashEnvelope.windowTolerance
    "float levels[34];\n"
    "struct Track { float last; float low; float high; float dir; bool init; float ages[6]; };\n"
    "void loadLevels() {\n"
    "    float sy = 0.0; float sr = 0.0;\n"
    "    for (int k = 0; k < 16; k++) {\n"
    "        vec4 t = texelFetch(tiles, ivec2(k % 4, k / 4), 0);\n"
    "        levels[k * 2] = unpack(t.rg); levels[k * 2 + 1] = unpack(t.ba);\n"
    "        sy += levels[k * 2]; sr += levels[k * 2 + 1];\n"
    "    }\n"
    "    levels[32] = sy / 16.0; levels[33] = sr / 16.0;\n"
    "}\n"
    "float threshold(int s) { return s == 0 ? lumThreshold : redThreshold; }\n"
    "Track readTrack(int zone, int s) {\n"
    "    int c = s * 5;\n"
    "    vec4 t0 = texelFetch(previous, ivec2(c, zone), 0);\n"
    "    vec4 t1 = texelFetch(previous, ivec2(c + 1, zone), 0);\n"
    "    vec4 t2 = texelFetch(previous, ivec2(c + 2, zone), 0);\n"
    "    vec4 t3 = texelFetch(previous, ivec2(c + 3, zone), 0);\n"
    "    vec4 t4 = texelFetch(previous, ivec2(c + 4, zone), 0);\n"
    "    Track t;\n"
    "    t.last = unpack(t0.rg); t.low = unpack(t0.ba); t.high = unpack(t1.rg);\n"
    "    t.dir = floor(t1.b * 2.0 + 0.5); t.init = t1.a > 0.5 && resetState < 0.5;\n"
    "    t.ages[0] = unpack(t2.rg) * 2.0; t.ages[1] = unpack(t2.ba) * 2.0;\n"
    "    t.ages[2] = unpack(t3.rg) * 2.0; t.ages[3] = unpack(t3.ba) * 2.0;\n"
    "    t.ages[4] = unpack(t4.rg) * 2.0; t.ages[5] = unpack(t4.ba) * 2.0;\n"
    "    if (!t.init) { for (int k = 0; k < 6; k++) t.ages[k] = 2.0; }\n"
    "    return t;\n"
    "}\n"
    "float ceilingOf(Track t, int s) {\n"
    "    if (!t.init) return 1e9;\n"
    "    float c = 1e9;\n"
    "    if (rise >= 0.0) c = t.last + rise * dt;\n"
    "    if (t.dir != 1.0) {\n"
    "        int n = 0;\n"
    "        for (int k = 0; k < 6; k++) { if (t.ages[k] + dt < window + windowTolerance) n++; }\n"
    "        if (float(n) > budget - 2.0) c = min(c, t.low + threshold(s) - margin);\n"
    "    }\n"
    "    return c;\n"
    "}\n"
    "float frameGain() {\n"
    "    float g = 1.0;\n"
    "    for (int z = 0; z < 17; z++) {\n"
    "        for (int s = 0; s < 2; s++) {\n"
    "            float v = levels[z * 2 + s];\n"
    "            float c = ceilingOf(readTrack(z, s), s);\n"
    "            if (v > c) g = min(g, max(c, 0.0) / v);\n"
    "        }\n"
    "    }\n"
    "    return clamp(g, 0.0, 1.0);\n"
    "}\n"
    "Track updateTrack(Track t, float v, int s) {\n"
    "    for (int k = 0; k < 6; k++) t.ages[k] = min(t.ages[k] + dt, 2.0);\n"
    "    if (!t.init) { t.init = true; t.last = v; t.low = v; t.high = v; t.dir = 0.0; return t; }\n"
    "    float T = threshold(s);\n"
    "    bool transition = false;\n"
    "    if (t.dir == 0.0) {\n"
    "        if (v >= t.low + T) { t.dir = 1.0; t.high = v; transition = true; }\n"
    "        else if (v <= t.high - T) { t.dir = 2.0; t.low = v; transition = true; }\n"
    "        else { t.low = min(t.low, v); t.high = max(t.high, v); }\n"
    "    } else if (t.dir == 1.0) {\n"
    "        if (v > t.high) t.high = v;\n"
    "        else if (v <= t.high - T) { t.dir = 2.0; t.low = v; transition = true; }\n"
    "    } else {\n"
    "        if (v < t.low) t.low = v;\n"
    "        else if (v >= t.low + T) { t.dir = 1.0; t.high = v; transition = true; }\n"
    "    }\n"
    "    t.last = v;\n"
    "    if (transition) {\n"
    "        int oldest = 0;\n"
    "        for (int k = 1; k < 6; k++) { if (t.ages[k] > t.ages[oldest]) oldest = k; }\n"
    "        t.ages[oldest] = 0.0;\n"
    "    }\n"
    "    return t;\n"
    "}\n"
    "void main() {\n"
    "    loadLevels();\n"
    "    ivec2 p = ivec2(gl_FragCoord.xy);\n"
    "    float g = frameGain();\n"
    "    if (p.y == 17) { color = vec4(pack(g), 0.0, 1.0); return; }\n"
    "    int s = p.x / 5;\n"
    "    int slot = p.x - s * 5;\n"
    "    Track t = updateTrack(readTrack(p.y, s), g * levels[p.y * 2 + s], s);\n"
    "    if (slot == 0) color = vec4(pack(t.last), pack(t.low));\n"
    "    else if (slot == 1) color = vec4(pack(t.high), t.dir / 2.0, t.init ? 1.0 : 0.0);\n"
    "    else if (slot == 2) color = vec4(pack(t.ages[0] / 2.0), pack(t.ages[1] / 2.0));\n"
    "    else if (slot == 3) color = vec4(pack(t.ages[2] / 2.0), pack(t.ages[3] / 2.0));\n"
    "    else color = vec4(pack(t.ages[4] / 2.0), pack(t.ages[5] / 2.0));\n"
    "}\n";

static const char *outputSource =
    COMMON
    "uniform sampler2D scene;\n"
    "uniform sampler2D state;\n"
    "in vec2 uv;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "    float g = unpack(texelFetch(state, ivec2(0, 17), 0).rg);\n"
    "    vec3 c = texture(scene, uv).rgb;\n"
    "    if (g < 1.0) c = encodeSRGB(decodeSRGB(c) * g);\n"
    "    color = vec4(c, 1.0);\n"
    "}\n";

struct PMFlashLimiter {
    GLTable gl;             // this limiter's entry points (from the caller's loader)
    GLuint measureProgram, stateProgram, outputProgram, vertexArray;
    GLuint sceneTexture, sceneFramebuffer;
    GLuint tileTexture, tileFramebuffer;
    GLuint stateTextures[2], stateFramebuffers[2];
    int current;            // index of the latest state
    int width, height;
    int needsReset;
    GLint measureScene;
    GLint stateTiles, statePrevious, stateDt, stateWindow, stateLum, stateRed, stateMargin, stateRise, stateBudget, stateReset;
    GLint outputScene, outputState;
};

static GLuint compile(const GLTable *gl, GLenum type, const char *source) {
    GLuint shader = gl->createShader(type);
    gl->shaderSource(shader, 1, &source, 0);
    gl->compileShader(shader);
    GLint ok = 0;
    gl->getShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) { gl->deleteShader(shader); return 0; }
    return shader;
}

static GLuint link(const GLTable *gl, const char *fragmentSource) {
    GLuint vertex = compile(gl, GL_VERTEX_SHADER, vertexSource);
    GLuint fragment = compile(gl, GL_FRAGMENT_SHADER, fragmentSource);
    if (!vertex || !fragment) {
        if (vertex) gl->deleteShader(vertex);
        if (fragment) gl->deleteShader(fragment);
        return 0;
    }
    GLuint program = gl->createProgram();
    gl->attachShader(program, vertex);
    gl->attachShader(program, fragment);
    gl->linkProgram(program);
    gl->deleteShader(vertex);
    gl->deleteShader(fragment);
    GLint ok = 0;
    gl->getProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) { gl->deleteProgram(program); return 0; }
    return program;
}

static void textureParameters(const GLTable *gl, GLint filter) {
    gl->texParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
    gl->texParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
    gl->texParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl->texParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

/// A small RGBA8 render target; 0 on failure.
static GLuint makeTarget(const GLTable *gl, GLuint *texture, int width, int height) {
    GLuint framebuffer = 0;
    gl->genTextures(1, texture);
    gl->bindTexture(GL_TEXTURE_2D, *texture);
    gl->texImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
    textureParameters(gl, GL_NEAREST);
    gl->genFramebuffers(1, &framebuffer);
    gl->bindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    gl->framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, *texture, 0);
    GLenum status = gl->checkFramebufferStatus(GL_FRAMEBUFFER);
    gl->bindFramebuffer(GL_FRAMEBUFFER, 0);
    gl->bindTexture(GL_TEXTURE_2D, 0);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        gl->deleteFramebuffers(1, &framebuffer);
        return 0;
    }
    return framebuffer;
}

PMFlashLimiter *PMFlashLimiterCreate(PMFlashLoadProc load, void *user) {
    PMFlashLimiter *limiter = calloc(1, sizeof(PMFlashLimiter));
    if (!limiter) return 0;
    if (!loadGL(&limiter->gl, load, user)) {
        free(limiter);
        return 0;
    }
    const GLTable *gl = &limiter->gl;
    limiter->measureProgram = link(gl, measureSource);
    limiter->stateProgram = link(gl, stateSource);
    limiter->outputProgram = link(gl, outputSource);
    if (!limiter->measureProgram || !limiter->stateProgram || !limiter->outputProgram) {
        PMFlashLimiterDestroy(limiter);
        return 0;
    }
    limiter->measureScene = gl->getUniformLocation(limiter->measureProgram, "scene");
    GLuint s = limiter->stateProgram;
    limiter->stateTiles = gl->getUniformLocation(s, "tiles");
    limiter->statePrevious = gl->getUniformLocation(s, "previous");
    limiter->stateDt = gl->getUniformLocation(s, "dt");
    limiter->stateWindow = gl->getUniformLocation(s, "window");
    limiter->stateLum = gl->getUniformLocation(s, "lumThreshold");
    limiter->stateRed = gl->getUniformLocation(s, "redThreshold");
    limiter->stateMargin = gl->getUniformLocation(s, "margin");
    limiter->stateRise = gl->getUniformLocation(s, "rise");
    limiter->stateBudget = gl->getUniformLocation(s, "budget");
    limiter->stateReset = gl->getUniformLocation(s, "resetState");
    limiter->outputScene = gl->getUniformLocation(limiter->outputProgram, "scene");
    limiter->outputState = gl->getUniformLocation(limiter->outputProgram, "state");
    gl->genVertexArrays(1, &limiter->vertexArray);
    limiter->tileFramebuffer = makeTarget(gl, &limiter->tileTexture, TILE_SIDE, TILE_SIDE);
    limiter->stateFramebuffers[0] = makeTarget(gl, &limiter->stateTextures[0], STATE_WIDTH, STATE_HEIGHT);
    limiter->stateFramebuffers[1] = makeTarget(gl, &limiter->stateTextures[1], STATE_WIDTH, STATE_HEIGHT);
    if (!limiter->tileFramebuffer || !limiter->stateFramebuffers[0] || !limiter->stateFramebuffers[1]) {
        PMFlashLimiterDestroy(limiter);
        return 0;
    }
    limiter->needsReset = 1;
    return limiter;
}

void PMFlashLimiterDestroy(PMFlashLimiter *limiter) {
    if (!limiter) return;
    const GLTable *gl = &limiter->gl;
    if (limiter->sceneFramebuffer) gl->deleteFramebuffers(1, &limiter->sceneFramebuffer);
    if (limiter->sceneTexture) gl->deleteTextures(1, &limiter->sceneTexture);
    if (limiter->tileFramebuffer) gl->deleteFramebuffers(1, &limiter->tileFramebuffer);
    if (limiter->tileTexture) gl->deleteTextures(1, &limiter->tileTexture);
    for (int i = 0; i < 2; i++) {
        if (limiter->stateFramebuffers[i]) gl->deleteFramebuffers(1, &limiter->stateFramebuffers[i]);
        if (limiter->stateTextures[i]) gl->deleteTextures(1, &limiter->stateTextures[i]);
    }
    if (limiter->vertexArray) gl->deleteVertexArrays(1, &limiter->vertexArray);
    if (limiter->measureProgram) gl->deleteProgram(limiter->measureProgram);
    if (limiter->stateProgram) gl->deleteProgram(limiter->stateProgram);
    if (limiter->outputProgram) gl->deleteProgram(limiter->outputProgram);
    free(limiter);
}

void PMFlashLimiterReset(PMFlashLimiter *limiter) {
    limiter->needsReset = 1;
}

unsigned int PMFlashLimiterBegin(PMFlashLimiter *limiter, int width, int height) {
    if (width <= 0 || height <= 0) return 0;
    const GLTable *gl = &limiter->gl;
    if (width != limiter->width || height != limiter->height || !limiter->sceneFramebuffer) {
        if (!limiter->sceneTexture) gl->genTextures(1, &limiter->sceneTexture);
        if (!limiter->sceneFramebuffer) gl->genFramebuffers(1, &limiter->sceneFramebuffer);
        gl->bindTexture(GL_TEXTURE_2D, limiter->sceneTexture);
        gl->texImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        textureParameters(gl, GL_LINEAR);
        gl->bindTexture(GL_TEXTURE_2D, 0);
        gl->bindFramebuffer(GL_FRAMEBUFFER, limiter->sceneFramebuffer);
        gl->framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, limiter->sceneTexture, 0);
        GLenum status = gl->checkFramebufferStatus(GL_FRAMEBUFFER);
        gl->bindFramebuffer(GL_FRAMEBUFFER, 0);
        if (status != GL_FRAMEBUFFER_COMPLETE) return 0;
        limiter->width = width;
        limiter->height = height;
        // The envelope's history is kept across a resize (FX-019-R11).
    }
    return limiter->sceneFramebuffer;
}

static void prepareState(const GLTable *gl) {
    gl->disable(GL_BLEND);
    gl->disable(GL_DEPTH_TEST);
    gl->disable(GL_SCISSOR_TEST);
    gl->disable(GL_CULL_FACE);
    gl->disable(GL_STENCIL_TEST);
    gl->colorMask(1, 1, 1, 1);
}

void PMFlashLimiterFinish(PMFlashLimiter *limiter, unsigned int targetFramebuffer, const PMFlashEnvelopeParameters *p) {
    const GLTable *gl = &limiter->gl;
    prepareState(gl);
    gl->bindVertexArray(limiter->vertexArray);

    // 1. Measure: tile means of the scene.
    gl->bindFramebuffer(GL_FRAMEBUFFER, limiter->tileFramebuffer);
    gl->viewport(0, 0, TILE_SIDE, TILE_SIDE);
    gl->useProgram(limiter->measureProgram);
    gl->activeTexture(GL_TEXTURE0);
    gl->bindTexture(GL_TEXTURE_2D, limiter->sceneTexture);
    gl->uniform1i(limiter->measureScene, 0);
    gl->drawArrays(GL_TRIANGLES, 0, 3);

    // 2. State: previous → next, with the frame's gain in row 17.
    int next = 1 - limiter->current;
    gl->bindFramebuffer(GL_FRAMEBUFFER, limiter->stateFramebuffers[next]);
    gl->viewport(0, 0, STATE_WIDTH, STATE_HEIGHT);
    gl->useProgram(limiter->stateProgram);
    gl->activeTexture(GL_TEXTURE1);
    gl->bindTexture(GL_TEXTURE_2D, limiter->tileTexture);
    gl->uniform1i(limiter->stateTiles, 1);
    gl->activeTexture(GL_TEXTURE2);
    gl->bindTexture(GL_TEXTURE_2D, limiter->stateTextures[limiter->current]);
    gl->uniform1i(limiter->statePrevious, 2);
    gl->uniform1f(limiter->stateDt, p->frameTime > 0 ? p->frameTime : 0);
    gl->uniform1f(limiter->stateWindow, p->window);
    gl->uniform1f(limiter->stateLum, p->luminanceThreshold);
    gl->uniform1f(limiter->stateRed, p->rednessThreshold);
    gl->uniform1f(limiter->stateMargin, p->gateMargin);
    gl->uniform1f(limiter->stateRise, p->riseRatePerSecond);
    gl->uniform1f(limiter->stateBudget, (float)p->transitionBudget);
    gl->uniform1f(limiter->stateReset, limiter->needsReset ? 1.0f : 0.0f);
    gl->drawArrays(GL_TRIANGLES, 0, 3);
    limiter->current = next;
    limiter->needsReset = 0;

    // 3. Output: the scene × gain into the target.
    gl->bindFramebuffer(GL_FRAMEBUFFER, targetFramebuffer);
    gl->viewport(0, 0, limiter->width, limiter->height);
    gl->useProgram(limiter->outputProgram);
    gl->activeTexture(GL_TEXTURE0);
    gl->bindTexture(GL_TEXTURE_2D, limiter->sceneTexture);
    gl->uniform1i(limiter->outputScene, 0);
    gl->activeTexture(GL_TEXTURE1);
    gl->bindTexture(GL_TEXTURE_2D, limiter->stateTextures[next]);
    gl->uniform1i(limiter->outputState, 1);
    gl->drawArrays(GL_TRIANGLES, 0, 3);

    // Leave neutral bindings for the engine's next frame.
    gl->bindTexture(GL_TEXTURE_2D, 0);
    gl->activeTexture(GL_TEXTURE2);
    gl->bindTexture(GL_TEXTURE_2D, 0);
    gl->activeTexture(GL_TEXTURE0);
    gl->bindTexture(GL_TEXTURE_2D, 0);
    gl->useProgram(0);
    gl->bindVertexArray(0);
}

float PMFlashLimiterLastGain(PMFlashLimiter *limiter) {
    unsigned char pixel[4] = {0, 0, 0, 0};
    const GLTable *gl = &limiter->gl;
    gl->bindFramebuffer(GL_FRAMEBUFFER, limiter->stateFramebuffers[limiter->current]);
    gl->readPixels(0, STATE_HEIGHT - 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    gl->bindFramebuffer(GL_FRAMEBUFFER, 0);
    return pixel[0] / 255.0f + pixel[1] / 65025.0f;
}

unsigned int PMFlashLimiterSceneFramebuffer(PMFlashLimiter *limiter) {
    return limiter->sceneFramebuffer;
}
