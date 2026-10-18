#include "EditSession.h"

#include "Globals.h"

namespace aio {

EditSession::EditSession(Body body) : body_(std::move(body)) {
    DllAddRef();
}

EditSession::~EditSession() {
    DllRelease();
}

HRESULT EditSession::Run(ITfContext* context, TfClientId clientId, DWORD flags, Body body,
                         HRESULT* sessionResult) noexcept {
    if (sessionResult) *sessionResult = E_FAIL;
    if (!context) return E_INVALIDARG;
    return ComGuard([&]() -> HRESULT {
        auto* session = new EditSession(std::move(body));
        HRESULT hrSession = E_FAIL;
        const HRESULT hr = context->RequestEditSession(clientId, session, flags, &hrSession);
        session->Release();
        if (sessionResult) *sessionResult = hrSession;
        return hr;
    });
}

HRESULT EditSession::RunSyncOrAsync(ITfContext* context, TfClientId clientId, DWORD access, Body body,
                                    HRESULT* sessionResult) noexcept {
    HRESULT hrSession = E_FAIL;
    HRESULT hr = Run(context, clientId, TF_ES_SYNC | access, body, &hrSession);
    if (SUCCEEDED(hr) && hrSession == TF_E_SYNCHRONOUS) {
        hr = Run(context, clientId, TF_ES_ASYNCDONTCARE | access, std::move(body), &hrSession);
    }
    if (sessionResult) *sessionResult = hrSession;
    return hr;
}

STDMETHODIMP EditSession::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfEditSession)) {
        *ppv = static_cast<ITfEditSession*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) EditSession::AddRef() {
    return static_cast<ULONG>(InterlockedIncrement(&refs_));
}

STDMETHODIMP_(ULONG) EditSession::Release() {
    const LONG n = InterlockedDecrement(&refs_);
    if (n == 0) delete this;
    return static_cast<ULONG>(n);
}

STDMETHODIMP EditSession::DoEditSession(TfEditCookie ec) {
    return ComGuard([&] { return body_ ? body_(ec) : S_OK; });
}

} // namespace aio
