// An ITfEditSession that runs a function with the cookie TSF grants.

#pragma once

#include <windows.h>
#include <msctf.h>

#include <functional>

namespace aio {

class EditSession final : public ITfEditSession {
public:
    using Body = std::function<HRESULT(TfEditCookie)>;

    // Requests a session on `context` and runs `body` in it, now or later depending on `flags` and TSF. Returns the
    // HRESULT of RequestEditSession; `sessionResult` gets the body's (or TF_S_ASYNC when it runs later).
    static HRESULT Run(ITfContext* context, TfClientId clientId, DWORD flags, Body body,
                       HRESULT* sessionResult = nullptr) noexcept;

    // TF_ES_SYNC first, and TF_ES_ASYNCDONTCARE if TSF can't grant a synchronous lock now (§5.4).
    static HRESULT RunSyncOrAsync(ITfContext* context, TfClientId clientId, DWORD access, Body body,
                                  HRESULT* sessionResult = nullptr) noexcept;

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfEditSession
    STDMETHODIMP DoEditSession(TfEditCookie ec) override;

private:
    explicit EditSession(Body body);
    ~EditSession();

    LONG refs_ = 1;
    Body body_;
};

} // namespace aio
