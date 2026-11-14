// CANGLE.c — load proc and test helpers over ANGLE's EGL (task T077). Entry points come from
// eglGetProcAddress, ANGLE's documented resolver; nothing here calls dlsym.
#include "CANGLE.h"

#define GL_FRAMEBUFFER 0x8D40
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401

void *PMANGLELoadProc(const char *name, void *userData) {
    (void)userData;
    return (void *)eglGetProcAddress(name);
}

unsigned int PMANGLEReadPixelsRGBA(int x, int y, int width, int height, void *out) {
    typedef void (*ReadPixels)(int, int, int, int, unsigned int, unsigned int, void *);
    typedef unsigned int (*GetError)(void);
    ReadPixels readPixels = (ReadPixels)eglGetProcAddress("glReadPixels");
    GetError getError = (GetError)eglGetProcAddress("glGetError");
    if (readPixels == 0 || getError == 0) {
        return 0xFFFFFFFFu;
    }
    readPixels(x, y, width, height, GL_RGBA, GL_UNSIGNED_BYTE, out);
    return getError();
}

void PMANGLEBindDefaultFramebuffer(void) {
    typedef void (*BindFramebuffer)(unsigned int, unsigned int);
    BindFramebuffer bind = (BindFramebuffer)eglGetProcAddress("glBindFramebuffer");
    if (bind) {
        bind(GL_FRAMEBUFFER, 0);
    }
}

void PMANGLEClearFramebuffer(unsigned int framebuffer, float red, float green, float blue) {
    typedef void (*BindFramebuffer)(unsigned int, unsigned int);
    typedef void (*ClearColor)(float, float, float, float);
    typedef void (*Clear)(unsigned int);
    BindFramebuffer bind = (BindFramebuffer)eglGetProcAddress("glBindFramebuffer");
    ClearColor clearColor = (ClearColor)eglGetProcAddress("glClearColor");
    Clear clear = (Clear)eglGetProcAddress("glClear");
    if (bind && clearColor && clear) {
        bind(GL_FRAMEBUFFER, framebuffer);
        clearColor(red, green, blue, 1.0f);
        clear(0x00004000); // GL_COLOR_BUFFER_BIT
    }
}

void PMANGLEFinish(void) {
    typedef void (*Finish)(void);
    Finish finish = (Finish)eglGetProcAddress("glFinish");
    if (finish) {
        finish();
    }
}

#define GL_TEXTURE_2D 0x0DE1
#define GL_BGRA_EXT 0x80E1
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_LINEAR 0x2601

unsigned int PMANGLECreateBGRAFramebuffer(int width, int height, unsigned int *textureOut) {
    typedef void (*Gen)(int, unsigned int *);
    typedef void (*Bind)(unsigned int, unsigned int);
    typedef void (*TexImage2D)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *);
    typedef void (*TexParameteri)(unsigned int, unsigned int, int);
    typedef void (*FramebufferTexture2D)(unsigned int, unsigned int, unsigned int, unsigned int, int);
    typedef unsigned int (*CheckStatus)(unsigned int);
    Gen genTextures = (Gen)eglGetProcAddress("glGenTextures");
    Gen genFramebuffers = (Gen)eglGetProcAddress("glGenFramebuffers");
    Bind bindTexture = (Bind)eglGetProcAddress("glBindTexture");
    Bind bindFramebuffer = (Bind)eglGetProcAddress("glBindFramebuffer");
    TexImage2D texImage2D = (TexImage2D)eglGetProcAddress("glTexImage2D");
    TexParameteri texParameteri = (TexParameteri)eglGetProcAddress("glTexParameteri");
    FramebufferTexture2D framebufferTexture2D = (FramebufferTexture2D)eglGetProcAddress("glFramebufferTexture2D");
    CheckStatus checkStatus = (CheckStatus)eglGetProcAddress("glCheckFramebufferStatus");
    *textureOut = 0;
    if (!genTextures || !genFramebuffers || !bindTexture || !bindFramebuffer || !texImage2D || !texParameteri ||
        !framebufferTexture2D || !checkStatus) {
        return 0;
    }
    unsigned int texture = 0, framebuffer = 0;
    genTextures(1, &texture);
    bindTexture(GL_TEXTURE_2D, texture);
    texImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, width, height, 0, GL_BGRA_EXT, GL_UNSIGNED_BYTE, 0);
    texParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    genFramebuffers(1, &framebuffer);
    bindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (checkStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        PMANGLEDeleteFramebuffer(framebuffer, texture);
        return 0;
    }
    *textureOut = texture;
    return framebuffer;
}

void PMANGLEDeleteFramebuffer(unsigned int framebuffer, unsigned int texture) {
    typedef void (*Delete)(int, const unsigned int *);
    Delete deleteFramebuffers = (Delete)eglGetProcAddress("glDeleteFramebuffers");
    Delete deleteTextures = (Delete)eglGetProcAddress("glDeleteTextures");
    if (deleteFramebuffers && framebuffer) {
        deleteFramebuffers(1, &framebuffer);
    }
    if (deleteTextures && texture) {
        deleteTextures(1, &texture);
    }
}

#define GL_SCISSOR_TEST 0x0C11

unsigned int PMANGLECreateImageFramebuffer(EGLImage image, unsigned int *textureOut) {
    typedef void (*Gen)(int, unsigned int *);
    typedef void (*Bind)(unsigned int, unsigned int);
    typedef void (*ImageTarget)(unsigned int, void *);
    typedef void (*FramebufferTexture2D)(unsigned int, unsigned int, unsigned int, unsigned int, int);
    typedef unsigned int (*CheckStatus)(unsigned int);
    typedef unsigned int (*GetError)(void);
    Gen genTextures = (Gen)eglGetProcAddress("glGenTextures");
    Gen genFramebuffers = (Gen)eglGetProcAddress("glGenFramebuffers");
    Bind bindTexture = (Bind)eglGetProcAddress("glBindTexture");
    Bind bindFramebuffer = (Bind)eglGetProcAddress("glBindFramebuffer");
    ImageTarget imageTarget = (ImageTarget)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    FramebufferTexture2D framebufferTexture2D = (FramebufferTexture2D)eglGetProcAddress("glFramebufferTexture2D");
    CheckStatus checkStatus = (CheckStatus)eglGetProcAddress("glCheckFramebufferStatus");
    GetError getError = (GetError)eglGetProcAddress("glGetError");
    *textureOut = 0;
    if (!image || !genTextures || !genFramebuffers || !bindTexture || !bindFramebuffer || !imageTarget ||
        !framebufferTexture2D || !checkStatus || !getError) {
        return 0;
    }
    unsigned int texture = 0, framebuffer = 0;
    genTextures(1, &texture);
    bindTexture(GL_TEXTURE_2D, texture);
    imageTarget(GL_TEXTURE_2D, image);
    if (getError() != 0) {
        PMANGLEDeleteFramebuffer(0, texture);
        return 0;
    }
    genFramebuffers(1, &framebuffer);
    bindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    framebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (checkStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        PMANGLEDeleteFramebuffer(framebuffer, texture);
        return 0;
    }
    *textureOut = texture;
    return framebuffer;
}

void PMANGLEClearRect(unsigned int framebuffer, int x, int y, int width, int height,
                      float red, float green, float blue, float alpha) {
    typedef void (*BindFramebuffer)(unsigned int, unsigned int);
    typedef void (*ClearColor)(float, float, float, float);
    typedef void (*Clear)(unsigned int);
    typedef void (*Toggle)(unsigned int);
    typedef void (*Scissor)(int, int, int, int);
    BindFramebuffer bind = (BindFramebuffer)eglGetProcAddress("glBindFramebuffer");
    ClearColor clearColor = (ClearColor)eglGetProcAddress("glClearColor");
    Clear clear = (Clear)eglGetProcAddress("glClear");
    Toggle enable = (Toggle)eglGetProcAddress("glEnable");
    Toggle disable = (Toggle)eglGetProcAddress("glDisable");
    Scissor scissor = (Scissor)eglGetProcAddress("glScissor");
    if (bind && clearColor && clear && enable && disable && scissor) {
        bind(GL_FRAMEBUFFER, framebuffer);
        enable(GL_SCISSOR_TEST);
        scissor(x, y, width, height);
        clearColor(red, green, blue, alpha);
        clear(0x00004000); // GL_COLOR_BUFFER_BIT
        disable(GL_SCISSOR_TEST);
    }
}

void PMANGLEFlush(void) {
    typedef void (*Flush)(void);
    Flush flush = (Flush)eglGetProcAddress("glFlush");
    if (flush) {
        flush();
    }
}

void *PMANGLECopyMetalSharedEvent(EGLDisplay dpy, EGLSync sync) {
    typedef void *(*Copy)(EGLDisplay, EGLSync);
    Copy copy = (Copy)eglGetProcAddress("eglCopyMetalSharedEventANGLE");
    return copy ? copy(dpy, sync) : 0;
}

void PMANGLEBindFramebuffer(unsigned int framebuffer) {
    typedef void (*BindFramebuffer)(unsigned int, unsigned int);
    BindFramebuffer bind = (BindFramebuffer)eglGetProcAddress("glBindFramebuffer");
    if (bind) {
        bind(GL_FRAMEBUFFER, framebuffer);
    }
}
