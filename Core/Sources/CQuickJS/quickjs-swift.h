// Not QuickJS-ng's: what Swift can't take from quickjs.h as it is. Its constant values are macros that build a JSValue
// (a compound literal, or a NaN-boxed integer on 32-bit systems), which Swift doesn't import.
#ifndef QUICKJS_SWIFT_H
#define QUICKJS_SWIFT_H

#include "quickjs.h"

static inline JSValue QJS_Undefined(void) { return JS_UNDEFINED; }
static inline JSValue QJS_Null(void) { return JS_NULL; }

#endif
