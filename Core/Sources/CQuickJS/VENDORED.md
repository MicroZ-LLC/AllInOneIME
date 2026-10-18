# QuickJS-ng, vendored

The JavaScript engine of the core off Apple platforms (AllInOneIMEQuickJS's `QuickJSEngine`): QuickJS-ng's C sources,
as released, under the MIT license (LICENSE, beside them).

- Version: **v0.17.0** (2026-09-18), commit 6d46d07d04041b40f4f49eaa7fdebe44c314c699
- Release: https://github.com/quickjs-ng/quickjs/releases/tag/v0.17.0
- Source: https://github.com/quickjs-ng/quickjs/archive/refs/tags/v0.17.0.tar.gz
  (SHA-256 559bc4c420475e55c7ab4510adbc562f55d7524d75e8e89d79ce4bb02f5687d9)

## What is kept

The engine and what it includes, unmodified: `quickjs.c`, `quickjs.h`, `quickjs-atom.h`, `quickjs-opcode.h`,
`quickjs-c-atomics.h`, `cutils.h`, `list.h`, `dtoa.c`, `dtoa.h`, `libregexp.c`, `libregexp.h`, `libregexp-opcode.h`,
`libunicode.c`, `libunicode.h`, `libunicode-table.h`, `builtin-array-fromasync.h`, `builtin-iterator-zip.h`,
`builtin-iterator-zip-keyed.h`, and `LICENSE`. They are upstream's `qjs_sources` (CMakeLists.txt) and their headers.

Left out: quickjs-libc (the `std` and `os` modules: files, processes, timers, none of which a plugin or `@js` may have),
the `qjs` and `qjsc` programs, the tests, test262, the examples, the docs, the build files and the Unicode table
generator.

## What is ours

- `module.modulemap`: the module Swift imports (`CQuickJS`), of `quickjs.h` and `quickjs-swift.h` only.
- `quickjs-swift.h`: `JS_UNDEFINED` and `JS_NULL` as functions; they are macros Swift can't import. Off Apple platforms
  and Windows, `QJS_ThreadStack` too (`pthread_getattr_np`, which Swift's Glibc doesn't declare), for `ThreadStack`.
- `swift-quickjs.c`, `swift-dtoa.c`, `swift-libregexp.c`, `swift-libunicode.c`: what SwiftPM compiles, each one
  upstream file included as it is, with clang's `-Wshorten-64-to-32` off (`#pragma clang diagnostic ignored`, under
  `#ifdef __clang__`); the upstream `.c` files are excluded from the target, so each is compiled once, through its
  wrapper.
- `VENDORED.md`, this file.

The target's settings (Package.swift) are upstream's CMake ones: `_GNU_SOURCE`; `NDEBUG` in release, as upstream's
Release build has it (QuickJS's asserts take half its time: fib(25) 20 ms with them, 11 ms without, on Windows); on
Windows `WIN32_LEAN_AND_MEAN`, `_WIN32_WINNT=0x0601` and `_CRT_SECURE_NO_WARNINGS`; libm on Linux and Android.
Upstream's optimization level isn't there (SwiftPM's release builds C with -Os), nor its warning flags
(the core has no unsafe flags), nor `-funsigned-char`, which its CMake gives gcc and clang: `char` stays signed where
the platform has it so (Apple's and Windows's x86-64 and arm64, Linux x86-64), as upstream's own MSVC build has it,
and the tests pass with it. On Windows (Swift 6.4.1) SwiftPM's clang builds upstream's files without a warning; on
Apple platforms Swift Build adds `-Wshorten-64-to-32`, which upstream's code doesn't heed (297 warnings a build, all of
that one), hence the wrappers above, which turn it off for these files alone. The files lie flat, as upstream has them, with the folder for the public headers (`publicHeadersPath: "."`), so that each
`#include "…"` finds its file beside it.

## Updating

Download the new release's source, copy the same files over these (and any new header `quickjs.c` includes; a new
`.c` in `qjs_sources` too, with a `swift-*.c` of its own and its name in the target's `exclude`), note the version here and in THIRD_PARTY_NOTICES.md, and run the tests of the JavaScript
engines: `swift test --filter 'ScriptEngineTests|QuickJSEngineTests|OnQuickJSTests|PluginTests|XEPluginTests|InlineCodeTests'`.
AllInOneIMEQuickJS uses QuickJS's allocator interface (`JSMallocFunctions`, `MemoryBudget.swift`) and its interrupt
handler: a release that changes either needs them changed too.
