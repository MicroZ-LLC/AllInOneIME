// The DLL's entry points: the module handle and object count, the class factory, DllGetClassObject / DllCanUnloadNow,
// and DllRegisterServer / DllUnregisterServer (§ Registration).

#include <windows.h>
#include <msctf.h>
#include <olectl.h>

#include <string>

#include "Globals.h"
#include "Log.h"
#include "TextService.h"
#include "res/resource.h"

namespace aio {

HINSTANCE g_module = nullptr;

// The CLSID of the text service's COM class, and the one language profile registered for each language.
// {DBB94280-C4C2-4C91-816F-79BB471AFE56}
const CLSID kClsidTextService = {0xDBB94280, 0xC4C2, 0x4C91, {0x81, 0x6F, 0x79, 0xBB, 0x47, 0x1A, 0xFE, 0x56}};
// {5BD6752B-379B-4ECD-9B1B-0819CBE55171}
const GUID kGuidProfile = {0x5BD6752B, 0x379B, 0x4ECD, {0x9B, 0x1B, 0x08, 0x19, 0xCB, 0xE5, 0x51, 0x71}};
// The display attributes (§6).
// {764BB2E7-F4E3-4D0E-9AFD-782C7CE5027D}
const GUID kGuidDisplayRaw = {0x764BB2E7, 0xF4E3, 0x4D0E, {0x9A, 0xFD, 0x78, 0x2C, 0x7C, 0xE5, 0x02, 0x7D}};
// {80EBBB47-5BE4-458E-8D7B-1229B010A3CD}
const GUID kGuidDisplayDraft = {0x80EBBB47, 0x5BE4, 0x458E, {0x8D, 0x7B, 0x12, 0x29, 0xB0, 0x10, 0xA3, 0xCD}};
// {327077E0-9C79-4F88-BA08-3B7579491C22}
const GUID kGuidDisplayConverted = {0x327077E0, 0x9C79, 0x4F88, {0xBA, 0x08, 0x3B, 0x75, 0x79, 0x49, 0x1C, 0x22}};
// {9B06229A-F5C7-44FA-AFF2-8309263DD3F8}
const GUID kGuidDisplayTarget = {0x9B06229A, 0xF5C7, 0x44FA, {0xAF, 0xF2, 0x83, 0x09, 0x26, 0x3D, 0xD3, 0xF8}};

namespace {

LONG g_objects = 0;
LONG g_locks = 0;

std::wstring ModulePath() {
    wchar_t path[MAX_PATH * 2] = {};
    GetModuleFileNameW(g_module, path, static_cast<DWORD>(std::size(path)));
    return path;
}

// ---- the class factory ----

class ClassFactory final : public IClassFactory {
public:
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory)) {
            *ppv = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return 2; } // a static singleton
    STDMETHODIMP_(ULONG) Release() override { return 1; }

    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        *ppv = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        return ComGuard([&]() -> HRESULT {
            auto* service = new TextService();
            const HRESULT hr = service->QueryInterface(riid, ppv);
            service->Release();
            return hr;
        });
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) {
            InterlockedIncrement(&g_locks);
        } else {
            InterlockedDecrement(&g_locks);
        }
        return S_OK;
    }
};

ClassFactory g_classFactory;

// ---- registry helpers ----

bool SetKeyValue(HKEY root, const std::wstring& subkey, const wchar_t* name, const std::wstring& value) {
    HKEY key = nullptr;
    if (RegCreateKeyExW(root, subkey.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    const auto bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
    const LONG r = RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()), bytes);
    RegCloseKey(key);
    return r == ERROR_SUCCESS;
}

std::wstring ClsidString() {
    wchar_t text[64] = {};
    StringFromGUID2(kClsidTextService, text, static_cast<int>(std::size(text)));
    return text;
}

// The COM server under HKCR\CLSID (regsvr32 runs elevated; HKCR maps to HKLM\Software\Classes).
HRESULT RegisterComServer() {
    const std::wstring clsid = ClsidString();
    const std::wstring base = L"CLSID\\" + clsid;
    if (!SetKeyValue(HKEY_CLASSES_ROOT, base, nullptr, kDisplayName)) return E_FAIL;
    if (!SetKeyValue(HKEY_CLASSES_ROOT, base + L"\\InprocServer32", nullptr, ModulePath())) return E_FAIL;
    if (!SetKeyValue(HKEY_CLASSES_ROOT, base + L"\\InprocServer32", L"ThreadingModel", L"Apartment")) return E_FAIL;
    return S_OK;
}

void UnregisterComServer() {
    const std::wstring base = L"CLSID\\" + ClsidString();
    RegDeleteKeyW(HKEY_CLASSES_ROOT, (base + L"\\InprocServer32").c_str());
    RegDeleteKeyW(HKEY_CLASSES_ROOT, base.c_str());
}

// The categories (§ Registration): the TIP's kind and capabilities, and that it is a display attribute provider.
const GUID* const kCategories[] = {
    &GUID_TFCAT_TIP_KEYBOARD,
    &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
    &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
    &GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
    &GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
};

HRESULT RegisterProfiles() {
    ITfInputProcessorProfiles* profiles = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfiles, reinterpret_cast<void**>(&profiles));
    if (FAILED(hr)) return hr;
    ITfInputProcessorProfileMgr* mgr = nullptr;
    hr = profiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&mgr));
    if (FAILED(hr)) {
        profiles->Release();
        return hr;
    }
    const std::wstring icon = ModulePath();
    HRESULT result = S_OK;
    for (LANGID lang : kLanguages) {
        // The icon index is negative: a resource id, as ExtractIconEx reads it. Enabled by default, so the profile can
        // be picked in Settings; adding it to the user's keyboard list is still the user's (or the installer's) call.
        hr = mgr->RegisterProfile(kClsidTextService, lang, kGuidProfile, kDisplayName,
                                  static_cast<ULONG>(wcslen(kDisplayName)), icon.c_str(),
                                  static_cast<ULONG>(icon.size()), static_cast<ULONG>(-IDI_TIP), nullptr, 0, TRUE, 0);
        if (FAILED(hr)) {
            Log("RegisterProfile for 0x%04x failed: 0x%08lx", lang, hr);
            result = hr;
        }
    }
    mgr->Release();
    profiles->Release();
    return result;
}

void UnregisterProfiles() {
    ITfInputProcessorProfiles* profiles = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                IID_ITfInputProcessorProfiles, reinterpret_cast<void**>(&profiles)))) {
        return;
    }
    ITfInputProcessorProfileMgr* mgr = nullptr;
    if (SUCCEEDED(profiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&mgr)))) {
        for (LANGID lang : kLanguages) {
            mgr->UnregisterProfile(kClsidTextService, lang, kGuidProfile, 0);
        }
        mgr->Release();
    }
    // The text service itself: UnregisterProfile and UnregisterCategory leave its (empty) key behind.
    profiles->Unregister(kClsidTextService);
    profiles->Release();
    // Whatever is left of its keys is ours alone: TSF's registration (HKLM) and its per-user state, the enabled flag
    // (HKCU).
    const std::wstring tip = L"Software\\Microsoft\\CTF\\TIP\\" + ClsidString();
    RegDeleteTreeW(HKEY_LOCAL_MACHINE, tip.c_str());
    RegDeleteKeyW(HKEY_LOCAL_MACHINE, tip.c_str());
    RegDeleteTreeW(HKEY_CURRENT_USER, tip.c_str());
    RegDeleteKeyW(HKEY_CURRENT_USER, tip.c_str());
}

HRESULT RegisterCategories() {
    ITfCategoryMgr* categories = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                  reinterpret_cast<void**>(&categories));
    if (FAILED(hr)) return hr;
    for (const GUID* cat : kCategories) {
        categories->RegisterCategory(kClsidTextService, *cat, kClsidTextService);
    }
    categories->Release();
    return S_OK;
}

void UnregisterCategories() {
    ITfCategoryMgr* categories = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                reinterpret_cast<void**>(&categories)))) {
        return;
    }
    for (const GUID* cat : kCategories) {
        categories->UnregisterCategory(kClsidTextService, *cat, kClsidTextService);
    }
    categories->Release();
}

} // namespace

void DllAddRef() noexcept {
    InterlockedIncrement(&g_objects);
}

void DllRelease() noexcept {
    InterlockedDecrement(&g_objects);
}

LONG DllRefCount() noexcept {
    return g_objects + g_locks;
}

} // namespace aio

// ---- exports ----

using namespace aio;

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID) {
    switch (reason) {
    case DLL_PROCESS_ATTACH:
        g_module = module;
        DisableThreadLibraryCalls(module);
        break;
    default:
        break;
    }
    return TRUE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (!IsEqualCLSID(rclsid, kClsidTextService)) return CLASS_E_CLASSNOTAVAILABLE;
    return g_classFactory.QueryInterface(riid, ppv);
}

STDAPI DllCanUnloadNow() {
    return DllRefCount() == 0 ? S_OK : S_FALSE;
}

STDAPI DllRegisterServer() {
    return ComGuard([]() -> HRESULT {
        HRESULT hr = RegisterComServer();
        if (SUCCEEDED(hr)) hr = RegisterProfiles();
        if (SUCCEEDED(hr)) hr = RegisterCategories();
        if (FAILED(hr)) {
            DllUnregisterServer();
            return SELFREG_E_CLASS;
        }
        return S_OK;
    });
}

STDAPI DllUnregisterServer() {
    return ComGuard([]() -> HRESULT {
        UnregisterCategories();
        UnregisterProfiles();
        UnregisterComServer();
        return S_OK;
    });
}
