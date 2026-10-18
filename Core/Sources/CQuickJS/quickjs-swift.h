// Not QuickJS-ng's: what Swift can't take from quickjs.h as it is. Its constant values are macros that build a JSValue
// (a compound literal, or a NaN-boxed integer on 32-bit systems), which Swift doesn't import.
#ifndef QUICKJS_SWIFT_H
#define QUICKJS_SWIFT_H

#include "quickjs.h"

static inline JSValue QJS_Undefined(void) { return JS_UNDEFINED; }
static inline JSValue QJS_Null(void) { return JS_NULL; }

// JS_ThrowTypeError and JS_ThrowInternalError take a format and its arguments, which Swift can't call: a message as it
// is. They make the error from the realm's own prototypes, never from the globals a script may have replaced
// (`globalThis.TypeError = …`). The message is cut at 255 bytes, as QuickJS cuts its own.
static inline JSValue QJS_ThrowTypeError(JSContext *ctx, const char *message) {
    return JS_ThrowTypeError(ctx, "%s", message);
}
static inline JSValue QJS_ThrowInternalError(JSContext *ctx, const char *message) {
    return JS_ThrowInternalError(ctx, "%s", message);
}

#if !defined(_WIN32) && !defined(__APPLE__)
#include <pthread.h>
#include <stddef.h>
// glibc and musl declare pthread_getattr_np only under _GNU_SOURCE, which Swift's Glibc and Musl modules aren't built
// with; the same declaration here (Android's Bionic has it anyway). The lowest address of this thread's stack and its
// size, for ThreadStack; 0 when they could be read, else the error.
extern int pthread_getattr_np(pthread_t thread, pthread_attr_t *attr);
static inline int QJS_ThreadStack(void **address, size_t *size) {
    pthread_attr_t attributes;
    int status = pthread_getattr_np(pthread_self(), &attributes);
    if (status != 0) return status;
    status = pthread_attr_getstack(&attributes, address, size);
    pthread_attr_destroy(&attributes);
    return status;
}
#endif

#endif
