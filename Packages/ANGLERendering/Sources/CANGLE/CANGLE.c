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
