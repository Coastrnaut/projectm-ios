// CANGLE.h — the EGL subset ANGLERenderer uses (task T077). Types, prototypes and constant values
// are taken from ANGLE's include/EGL/egl.h and eglext_angle.h at the pinned ANGLE commit
// (ADR-0004); declared here so the package needs no copy of the Khronos headers.
#ifndef CANGLE_H
#define CANGLE_H

#include <stdint.h>

typedef void *_Nullable EGLDisplay;
typedef void *_Nullable EGLConfig;
typedef void *_Nullable EGLContext;
typedef void *_Nullable EGLSurface;
typedef void *_Nullable EGLNativeWindowType;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
typedef unsigned int EGLenum;
typedef intptr_t EGLAttrib;
typedef void (*_Nullable __eglMustCastToProperFunctionPointerType)(void);

#define EGL_FALSE 0
#define EGL_TRUE 1
#define EGL_SUCCESS 0x3000
#define EGL_NONE 0x3038
#define EGL_ALPHA_SIZE 0x3021
#define EGL_BLUE_SIZE 0x3022
#define EGL_GREEN_SIZE 0x3023
#define EGL_RED_SIZE 0x3024
#define EGL_DEPTH_SIZE 0x3025
#define EGL_STENCIL_SIZE 0x3026
#define EGL_SURFACE_TYPE 0x3033
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_HEIGHT 0x3056
#define EGL_WIDTH 0x3057
#define EGL_DRAW 0x3059
#define EGL_READ 0x305A
#define EGL_CONTEXT_MAJOR_VERSION 0x3098
#define EGL_CONTEXT_MINOR_VERSION 0x30FB
#define EGL_PBUFFER_BIT 0x0001
#define EGL_WINDOW_BIT 0x0004
#define EGL_OPENGL_ES3_BIT 0x00000040
// EGL_ANGLE_platform_angle, EGL_ANGLE_platform_angle_metal
#define EGL_PLATFORM_ANGLE_ANGLE 0x3202
#define EGL_PLATFORM_ANGLE_TYPE_ANGLE 0x3203
#define EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE 0x3489

// CMP-001 (ADR-0013): client buffers, so an ANGLE frame can be drawn into a texture Metal samples.
// Constant values from ANGLE's include/EGL/egl.h and eglext_angle.h at the pinned commit; every
// extension is queried at run time (eglQueryString) before it is used.
typedef void *_Nullable EGLImage;
typedef void *_Nullable EGLSync;
typedef void *_Nullable EGLClientBuffer;
#define EGL_VENDOR 0x3053
#define EGL_VERSION 0x3054
#define EGL_EXTENSIONS 0x3055
#define EGL_BIND_TO_TEXTURE_RGBA 0x303A
#define EGL_TEXTURE_RGBA 0x305E
#define EGL_TEXTURE_2D 0x305F
#define EGL_TEXTURE_FORMAT 0x3080
#define EGL_TEXTURE_TARGET 0x3081
// EGL_ANGLE_iosurface_client_buffer
#define EGL_IOSURFACE_ANGLE 0x3454
#define EGL_IOSURFACE_PLANE_ANGLE 0x345A
#define EGL_TEXTURE_TYPE_ANGLE 0x345C
#define EGL_TEXTURE_INTERNAL_FORMAT_ANGLE 0x345D
#define EGL_BIND_TO_TEXTURE_TARGET_ANGLE 0x348D
// EGL_ANGLE_metal_texture_client_buffer
#define EGL_METAL_TEXTURE_ANGLE 0x34A7
// EGL_ANGLE_metal_shared_event_sync
#define EGL_SYNC_METAL_SHARED_EVENT_ANGLE 0x34D8
#define EGL_SYNC_METAL_SHARED_EVENT_OBJECT_ANGLE 0x34D9
#define EGL_SYNC_METAL_SHARED_EVENT_SIGNAL_VALUE_LO_ANGLE 0x34DA
#define EGL_SYNC_METAL_SHARED_EVENT_SIGNAL_VALUE_HI_ANGLE 0x34DB

const char *_Nullable eglQueryString(EGLDisplay dpy, EGLint name);
EGLBoolean eglGetConfigAttrib(EGLDisplay dpy, EGLConfig config, EGLint attribute, EGLint *_Nonnull value);
EGLSurface eglCreatePbufferFromClientBuffer(EGLDisplay dpy, EGLenum buftype, EGLClientBuffer buffer, EGLConfig config,
                                            const EGLint *_Nullable attrib_list);
EGLImage eglCreateImage(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buffer,
                        const EGLAttrib *_Nullable attrib_list);
EGLBoolean eglDestroyImage(EGLDisplay dpy, EGLImage image);
EGLSync eglCreateSync(EGLDisplay dpy, EGLenum type, const EGLAttrib *_Nullable attrib_list);
EGLBoolean eglDestroySync(EGLDisplay dpy, EGLSync sync);

EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *_Nullable native_display, const EGLAttrib *_Nullable attrib_list);
EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *_Nullable major, EGLint *_Nullable minor);
EGLBoolean eglTerminate(EGLDisplay dpy);
EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *_Nullable attrib_list, EGLConfig *_Nullable configs,
                           EGLint config_size, EGLint *_Nonnull num_config);
EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config, EGLContext share_context, const EGLint *_Nullable attrib_list);
EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx);
EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win,
                                  const EGLint *_Nullable attrib_list);
EGLSurface eglCreatePbufferSurface(EGLDisplay dpy, EGLConfig config, const EGLint *_Nullable attrib_list);
EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface);
EGLBoolean eglQuerySurface(EGLDisplay dpy, EGLSurface surface, EGLint attribute, EGLint *_Nonnull value);
EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx);
EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface);
EGLContext eglGetCurrentContext(void);
EGLint eglGetError(void);
__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *_Nonnull procname);

/// The engine's load proc on ANGLE (contract projectm-bridge.md: `eglGetProcAddress` for ANGLE).
void *_Nullable PMANGLELoadProc(const char *_Nonnull name, void *_Nullable userData);

/// glReadPixels(x, y, width, height, GL_RGBA, GL_UNSIGNED_BYTE, out) through eglGetProcAddress, from
/// the current read framebuffer (tests). Returns 0 on success, or the GL error.
unsigned int PMANGLEReadPixelsRGBA(int x, int y, int width, int height, void *_Nonnull out);

/// glBindFramebuffer(GL_FRAMEBUFFER, 0) through eglGetProcAddress (tests).
void PMANGLEBindDefaultFramebuffer(void);

/// glBindFramebuffer(GL_FRAMEBUFFER, framebuffer), then clear it to an opaque color (tests).
void PMANGLEClearFramebuffer(unsigned int framebuffer, float red, float green, float blue);

/// glFinish through eglGetProcAddress: waits for the GPU (RendererLab timing).
void PMANGLEFinish(void);



/// CMP-001: a GL texture bound to `image` (glEGLImageTargetTexture2DOES, GL_OES_EGL_image) attached
/// to a new framebuffer. Returns the framebuffer (0 on failure) and writes the texture. Needs a
/// current context.
unsigned int PMANGLECreateImageFramebuffer(EGLImage image, unsigned int *_Nonnull textureOut);

/// CMP-001: clears the rectangle (x, y, width, height; GL's bottom-left origin) of `framebuffer` to a
/// color with alpha (scissored), then disables the scissor test (tests and the spike).
void PMANGLEClearRect(unsigned int framebuffer, int x, int y, int width, int height,
                      float red, float green, float blue, float alpha);

/// glFlush through eglGetProcAddress: submits the context's work without waiting.
void PMANGLEFlush(void);

/// eglCopyMetalSharedEventANGLE (EGL_ANGLE_metal_shared_event_sync) through eglGetProcAddress: the
/// MTLSharedEvent of a sync, retained (+1), or NULL when unavailable.
void *_Nullable PMANGLECopyMetalSharedEvent(EGLDisplay dpy, EGLSync sync);

#endif

/// Feature 002 SC-104 (preset warm-up): a framebuffer with one BGRA8 color texture, the window
/// surface's format, so pipelines built while warming match the visible ones. Returns the
/// framebuffer (0 on failure) and writes the texture to `textureOut`. Needs a current context.
unsigned int PMANGLECreateBGRAFramebuffer(int width, int height, unsigned int *_Nonnull textureOut);

/// Deletes a framebuffer and texture from PMANGLECreateBGRAFramebuffer.
void PMANGLEDeleteFramebuffer(unsigned int framebuffer, unsigned int texture);
