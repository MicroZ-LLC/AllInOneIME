// What the whole DLL shares: its module, its ids, the object count, and the guard every COM method runs in.

#pragma once

#include <windows.h>

#include <new>

namespace aio {

extern HINSTANCE g_module;

// The text service's COM class, and its one language profile (registered for each language in `kLanguages`).
extern const CLSID kClsidTextService;
extern const GUID kGuidProfile;

// The display attributes of the composition's styles (§6).
extern const GUID kGuidDisplayRaw;
extern const GUID kGuidDisplayDraft;
extern const GUID kGuidDisplayConverted;
extern const GUID kGuidDisplayTarget;

inline constexpr LANGID kLanguages[] = {
    MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US),            // en-US, 0x0409
    MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED),    // zh-CN, 0x0804
};

inline constexpr wchar_t kDisplayName[] = L"AllInOneIME";

// `hello.client`: the app's version (Resources/Info.plist).
inline constexpr char kClientName[] = "tip/0.6.4";

#if defined(_M_ARM64)
inline constexpr char kArch[] = "arm64";
#elif defined(_M_X64)
inline constexpr char kArch[] = "x64";
#elif defined(_M_IX86)
inline constexpr char kArch[] = "x86";
#else
#error "an architecture the wire doesn't name"
#endif

// Live COM objects and server locks, for DllCanUnloadNow.
void DllAddRef() noexcept;
void DllRelease() noexcept;
LONG DllRefCount() noexcept;

// Runs a COM method's body: no exception crosses the COM boundary.
template <class F>
HRESULT ComGuard(F&& body) noexcept {
    try {
        return body();
    } catch (const std::bad_alloc&) {
        return E_OUTOFMEMORY;
    } catch (...) {
        return E_UNEXPECTED;
    }
}

// Same, for the sink methods TSF ignores the result of: the failure is only logged.
template <class F>
void NoThrow(const char* where, F&& body) noexcept;

} // namespace aio

#include "Log.h"

namespace aio {

template <class F>
void NoThrow(const char* where, F&& body) noexcept {
    try {
        body();
    } catch (...) {
        Log("exception in %s", where);
    }
}

} // namespace aio
