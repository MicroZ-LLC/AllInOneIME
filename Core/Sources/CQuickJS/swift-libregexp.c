// Not QuickJS-ng's: upstream's libregexp.c as it is (Package.swift builds this file in its place), with clang's
// -Wshorten-64-to-32 off. Swift Build turns that warning on for C, upstream's code converts 64-bit values to 32 bits
// as it means to, and a flag for this target alone would be an unsafe flag (VENDORED.md). Only clang knows the
// pragma (clang-cl too); another compiler, MSVC's, skips it.
#ifdef __clang__
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#endif
#include "libregexp.c"
