#include "TextService.h"

#include <algorithm>

#include "Document.h"
#include "EditSession.h"
#include "Globals.h"
#include "Keys.h"
#include "Log.h"
#include "ProcessInfo.h"

namespace aio {

namespace {

constexpr DWORD kKeyBudgetMs = 150; // §5.4
constexpr UINT_PTR kTimerAfterKey = 100;
constexpr UINT_PTR kTimerCaret = 101;
constexpr ULONGLONG kCaretMinIntervalMs = 16; // §6
// §5.4's cache serves a repeated OnTestKeyDown for the same pending key, which comes within one turn of the app's
// message loop. An auto-repeat (lParam bit 30) is a new key at least every ~33 ms, and a new press of a key comes after
// its key-up (which clears the cache): these bound how long a cached result may stand for "the same key".
constexpr ULONGLONG kCacheRepeatMs = 25;
constexpr ULONGLONG kCacheMs = 500;

template <class T>
void SafeRelease(T*& p) {
    if (p) {
        p->Release();
        p = nullptr;
    }
}

// A key's cache identity (§5.4).
LPARAM MaskOf(LPARAM lParam) {
    return lParam & 0x00FF0000;
}

bool IsNoLayout(HRESULT hr) {
    return hr == TF_E_NOLAYOUT || hr == TS_E_NOLAYOUT;
}

// Milliseconds since `start` (QueryPerformanceCounter), for the key timings in the log.
double MsSince(const LARGE_INTEGER& start) {
    static const LONGLONG frequency = [] {
        LARGE_INTEGER f;
        QueryPerformanceFrequency(&f);
        return f.QuadPart;
    }();
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return static_cast<double>(now.QuadPart - start.QuadPart) * 1000.0 / static_cast<double>(frequency);
}

} // namespace

Session::~Session() {
    composition.reset();
    if (context) {
        ITfSource* source = nullptr;
        if ((editCookie != TF_INVALID_COOKIE || layoutCookie != TF_INVALID_COOKIE) &&
            SUCCEEDED(context->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source))) && source) {
            if (editCookie != TF_INVALID_COOKIE) source->UnadviseSink(editCookie);
            if (layoutCookie != TF_INVALID_COOKIE) source->UnadviseSink(layoutCookie);
            source->Release();
        }
        context->Release();
    }
    if (docMgr) docMgr->Release();
}

TextService::TextService() {
    DllAddRef();
}

TextService::~TextService() {
    DllRelease();
}

// ---- IUnknown ----

STDMETHODIMP TextService::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfTextInputProcessor)) {
        *ppv = static_cast<ITfTextInputProcessor*>(this);
    } else if (IsEqualIID(riid, IID_ITfTextInputProcessorEx)) {
        *ppv = static_cast<ITfTextInputProcessorEx*>(this);
    } else if (IsEqualIID(riid, IID_ITfThreadMgrEventSink)) {
        *ppv = static_cast<ITfThreadMgrEventSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfKeyEventSink)) {
        *ppv = static_cast<ITfKeyEventSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfTextEditSink)) {
        *ppv = static_cast<ITfTextEditSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfTextLayoutSink)) {
        *ppv = static_cast<ITfTextLayoutSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfCompositionSink)) {
        *ppv = static_cast<ITfCompositionSink*>(this);
    } else if (IsEqualIID(riid, IID_ITfDisplayAttributeProvider)) {
        *ppv = static_cast<ITfDisplayAttributeProvider*>(this);
    } else {
        return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) TextService::AddRef() {
    return static_cast<ULONG>(InterlockedIncrement(&refs_));
}

STDMETHODIMP_(ULONG) TextService::Release() {
    const LONG n = InterlockedDecrement(&refs_);
    if (n == 0) delete this;
    return static_cast<ULONG>(n);
}

// ---- activation ----

STDMETHODIMP TextService::Activate(ITfThreadMgr* threadMgr, TfClientId clientId) {
    return ActivateEx(threadMgr, clientId, 0);
}

STDMETHODIMP TextService::ActivateEx(ITfThreadMgr* threadMgr, TfClientId clientId, DWORD flags) {
    if (!threadMgr) return E_INVALIDARG;
    return ComGuard([&]() -> HRESULT {
        Log("ActivateEx flags 0x%lx", flags);
        threadMgr_ = threadMgr;
        threadMgr_->AddRef();
        clientId_ = clientId;
        secureMode_ = (flags & TF_TMAE_SECUREMODE) != 0;

        ITfSource* source = nullptr;
        if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source))) && source) {
            source->AdviseSink(IID_ITfThreadMgrEventSink, static_cast<ITfThreadMgrEventSink*>(this),
                               &threadMgrCookie_);
            source->Release();
        }
        ITfKeystrokeMgr* keystroke = nullptr;
        if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keystroke))) &&
            keystroke) {
            keySinkAdvised_ =
                SUCCEEDED(keystroke->AdviseKeyEventSink(clientId_, static_cast<ITfKeyEventSink*>(this), TRUE));
            keystroke->Release();
        }
        Log("sinks: thread manager %s, keys %s", threadMgrCookie_ != TF_INVALID_COOKIE ? "advised" : "FAILED",
            keySinkAdvised_ ? "advised" : "FAILED");

        atoms_.Register();

        // §2.3: the connection opens asynchronously, so activation never blocks. On a secure desktop (§2.1) and where
        // MayConnect says no (§8), there is no connection at all and every key passes.
        if (secureMode_) {
            Log("passive: secure mode");
        } else {
            pipe_ = std::make_unique<PipeClient>(this);
            if (!pipe_->Start()) pipe_.reset();
        }

        // A document may already be focused.
        ITfDocumentMgr* focus = nullptr;
        if (SUCCEEDED(threadMgr_->GetFocus(&focus)) && focus) {
            OnSetFocus(focus, nullptr);
            focus->Release();
        }
        return S_OK;
    });
}

STDMETHODIMP TextService::Deactivate() {
    return ComGuard([&]() -> HRESULT {
        Log("Deactivate");
        BlurFocused();
        CloseAll();
        keyCache_ = {};
        pendingResults_.clear();
        pendingAfterKey_.clear();

        if (pipe_) {
            pipe_->Stop();
            pipe_.reset();
        }

        if (threadMgr_ && keySinkAdvised_) {
            ITfKeystrokeMgr* keystroke = nullptr;
            if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void**>(&keystroke))) &&
                keystroke) {
                keystroke->UnadviseKeyEventSink(clientId_);
                keystroke->Release();
            }
            keySinkAdvised_ = false;
        }
        if (threadMgr_ && threadMgrCookie_ != TF_INVALID_COOKIE) {
            ITfSource* source = nullptr;
            if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source))) && source) {
                source->UnadviseSink(threadMgrCookie_);
                source->Release();
            }
            threadMgrCookie_ = TF_INVALID_COOKIE;
        }
        SafeRelease(threadMgr_);
        clientId_ = TF_CLIENTID_NULL;
        return S_OK;
    });
}

// ---- sessions ----

Session* TextService::SessionFor(ITfContext* context, bool create) {
    if (!context) return nullptr;
    auto it = sessions_.find(context);
    if (it != sessions_.end()) return it->second.get();
    if (!create) return nullptr;

    auto session = std::make_unique<Session>();
    session->context = context;
    context->AddRef();
    ITfDocumentMgr* docMgr = nullptr;
    if (SUCCEEDED(context->GetDocumentMgr(&docMgr))) session->docMgr = docMgr; // owns the ref
    session->sid = NextSid();
    session->composition = std::make_unique<Composition>(context, clientId_, &atoms_,
                                                         static_cast<ITfCompositionSink*>(this));

    // The per-context sinks: edit (to cache ctx) and layout (for caret reports).
    ITfSource* source = nullptr;
    if (SUCCEEDED(context->QueryInterface(IID_ITfSource, reinterpret_cast<void**>(&source))) && source) {
        source->AdviseSink(IID_ITfTextEditSink, static_cast<ITfTextEditSink*>(this), &session->editCookie);
        source->AdviseSink(IID_ITfTextLayoutSink, static_cast<ITfTextLayoutSink*>(this), &session->layoutCookie);
        source->Release();
    }
    Session* raw = session.get();
    sessions_[context] = std::move(session);
    Log("session %u opened for a context", raw->sid);
    return raw;
}

Session* TextService::FindBySid(uint32_t sid) {
    for (auto& [context, session] : sessions_) {
        if (session->sid == sid) return session.get();
    }
    return nullptr;
}

void TextService::CloseSession(ITfContext* context) {
    auto it = sessions_.find(context);
    if (it == sessions_.end()) return;
    Session* s = it->second.get();
    if (focused_ == s) {
        focused_ = nullptr;
        if (pipe_) pipe_->SetFocused(false);
    }
    const uint32_t sid = s->sid;
    if (keyCache_.sid == sid) keyCache_ = {};
    if (s->opened && Ready()) {
        pipe_->Send([sid](uint32_t id) { return wire::Encode(wire::Close{id, sid}); });
    }
    sessions_.erase(it);
    Log("session %u closed", sid);
}

void TextService::CloseAll() {
    while (!sessions_.empty()) {
        CloseSession(sessions_.begin()->first);
    }
}

// ---- focus (§4) ----

STDMETHODIMP TextService::OnInitDocumentMgr(ITfDocumentMgr*) {
    return S_OK;
}

STDMETHODIMP TextService::OnUninitDocumentMgr(ITfDocumentMgr* docMgr) {
    return ComGuard([&]() -> HRESULT {
        // Close every session of this document manager's contexts (§4 close).
        std::vector<ITfContext*> toClose;
        for (auto& [context, session] : sessions_) {
            if (session->docMgr == docMgr) toClose.push_back(context);
        }
        for (ITfContext* context : toClose) CloseSession(context);
        return S_OK;
    });
}

STDMETHODIMP TextService::OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr* prevFocus) {
    (void)prevFocus;
    return ComGuard([&]() -> HRESULT {
        ITfContext* context = nullptr;
        const bool hasTop = focus && SUCCEEDED(focus->GetTop(&context)) && context;
        Log("OnSetFocus: %s", hasTop ? "a context" : "none");
        if (hasTop) {
            FocusContext(context);
            context->Release();
        } else {
            BlurFocused();
        }
        return S_OK;
    });
}

STDMETHODIMP TextService::OnPushContext(ITfContext*) {
    return S_OK;
}

STDMETHODIMP TextService::OnPopContext(ITfContext* context) {
    return ComGuard([&]() -> HRESULT {
        CloseSession(context);
        return S_OK;
    });
}

void TextService::BlurFocused() {
    if (!focused_) return;
    Session& s = *focused_;
    keyCache_ = {};
    if (pipe_) pipe_->SetFocused(false);
    if (!s.passive && s.opened && Ready()) {
        // §4: blur is a request; the DLL waits (within the budget) and applies the result to the old context. Pushes
        // that came while it was awaited still target the old focus, so they go first, as they would for a key.
        const uint32_t sid = s.sid;
        wire::EngineMessage response;
        const auto outcome = pipe_->Request([sid](uint32_t id) { return wire::Encode(wire::Blur{id, sid}); },
                                            kKeyBudgetMs, response);
        if (outcome == PipeClient::Outcome::response) {
            ApplyKeyResult(s, response.type == wire::EngineType::result ? response.result : wire::Result{}, false);
        }
        Log("session %u blurred", sid);
    }
    focused_ = nullptr;
    s.focused = false;
    s.panelShown = false;
}

void TextService::FocusContext(ITfContext* context) {
    // Passive (§2.1, §8: SYSTEM, a service, another desktop, secure mode): no sessions at all, every key passes.
    if (!pipe_) return;
    Session* existing = SessionFor(context, false);
    if (focused_ && focused_ == existing) return; // already focused
    BlurFocused();

    Session* s = SessionFor(context, true);
    if (!s) return;
    focused_ = s;
    s->focused = true;

    // Read the field (is it secure?) and the initial ctx under a read lock. If TSF can't grant one now, read it as soon
    // as it can; until then nothing is sent.
    const uint32_t sid = s->sid;
    HRESULT sessionResult = E_FAIL;
    HRESULT hr = EditSession::Run(context, clientId_, TF_ES_SYNC | TF_ES_READ,
                                  [this, sid](TfEditCookie ec) -> HRESULT {
                                      if (Session* session = FindBySid(sid)) ReadField(*session, ec);
                                      return S_OK;
                                  },
                                  &sessionResult);
    if (SUCCEEDED(hr) && sessionResult == TF_E_SYNCHRONOUS) {
        hr = EditSession::Run(context, clientId_, TF_ES_ASYNCDONTCARE | TF_ES_READ,
                              [this, sid](TfEditCookie ec) -> HRESULT {
                                  Session* session = FindBySid(sid);
                                  if (session && !session->fieldKnown) {
                                      ReadField(*session, ec);
                                      if (session->focused) FieldKnown(*session);
                                  }
                                  return S_OK;
                              });
        return;
    }
    if (s->fieldKnown) FieldKnown(*s);
}

void TextService::ReadField(Session& s, TfEditCookie ec) {
    s.field = ReadFieldInfo(s.context, ec);
    s.passive = s.field.secure || KeyboardDisabled(s.context);
    s.fieldKnown = true;
    if (!s.passive) RefreshContext(s, ec);
}

void TextService::FieldKnown(Session& s) {
    if (s.passive) {
        Log("session %u is a secure or disabled field: staying silent", s.sid);
        return;
    }
    if (pipe_) pipe_->SetFocused(true);
    if (!EnsureOpen(s)) return; // not connected yet: OnPipeConnected opens and focuses it
    SendFocus(s, true, false);
}

bool TextService::EnsureOpen(Session& s) {
    if (s.passive || !s.fieldKnown || !Ready()) return false;
    if (s.opened) return true;
    const uint32_t sid = s.sid;
    const wire::FieldInfo field = s.field;
    s.opened = pipe_->Send([sid, &field](uint32_t id) { return wire::Encode(wire::Open{id, sid, field}); });
    return s.opened;
}

void TextService::SendFocus(Session& s, bool newSerial, bool withField) {
    if (s.passive || !s.opened || !Ready()) return;
    if (newSerial || s.focusSerial == 0) ++s.focusSerial;
    const uint32_t sid = s.sid;
    const uint32_t serial = s.focusSerial;
    std::optional<wire::FieldInfo> field;
    if (withField) field = s.field;
    pipe_->Send([sid, serial, &field](uint32_t id) { return wire::Encode(wire::Focus{id, sid, serial, field}); });
}

bool TextService::CheckFieldChanged(Session& s, TfEditCookie ec) {
    if (!s.fieldKnown) {
        // The focus couldn't read it (no lock then): this is the first look.
        ReadField(s, ec);
        if (s.focused) FieldKnown(s);
        return !s.passive;
    }
    wire::FieldInfo field = ReadFieldInfo(s.context, ec);
    const bool passive = field.secure || KeyboardDisabled(s.context);
    if (field == s.field && passive == s.passive) return !s.passive;

    const bool wasPassive = s.passive;
    s.field = std::move(field);
    s.passive = passive;
    if (passive && !wasPassive) {
        // The field turned secure (§8): the engine gets a blur (its result is applied when it comes) and then nothing.
        Log("session %u turned secure or disabled", s.sid);
        if (s.opened && Ready()) RequestForSession(s, nullptr);
        s.panelShown = false;
        return false;
    }
    if (!passive && wasPassive) {
        if (EnsureOpen(s)) SendFocus(s, true, false);
        return true;
    }
    if (!passive) {
        // §4: re-sent while focused, with the new field, when the layout or input scope changes. It doesn't blur, and
        // it keeps the serial, so pushes the engine already sent for this focus still apply.
        if (s.opened) SendFocus(s, false, true);
        else if (EnsureOpen(s)) SendFocus(s, true, false);
    }
    return !passive;
}

// ---- keys (§5) ----

STDMETHODIMP TextService::OnSetFocus(BOOL foreground) {
    Log("key sink focus: %s", foreground ? "foreground" : "background");
    return S_OK;
}

bool TextService::SendsKeyUp(WPARAM wParam) const {
    if (IsModifierKey(wParam)) return true; // §5.2
    if (!Ready()) return false;
    const auto& caps = pipe_->welcome().capabilities;
    return std::find(caps.begin(), caps.end(), "keyUps") != caps.end();
}

bool TextService::CacheHit(bool down, WPARAM wParam, LPARAM lParam) const {
    if (!keyCache_.valid || keyCache_.down != down || keyCache_.wParam != wParam ||
        keyCache_.lParamMask != MaskOf(lParam)) {
        return false;
    }
    const bool repeat = down && ((lParam >> 30) & 1) != 0;
    return GetTickCount64() - keyCache_.at <= (repeat ? kCacheRepeatMs : kCacheMs);
}

bool TextService::HasEarlier(uint32_t sid) const {
    if (!pipe_) return false;
    return pipe_->AnyEarlier([this, sid](const wire::EngineMessage& m) {
        if (m.type == wire::EngineType::apply) return m.sid == sid;
        if (m.type == wire::EngineType::result && m.re) {
            auto it = pendingResults_.find(*m.re);
            return it != pendingResults_.end() && it->second == sid;
        }
        return false;
    });
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
    if (eaten) *eaten = FALSE;
    return ComGuard([&]() -> HRESULT {
        Session* s = SessionFor(context, false);
        if (!s || !s->focused || s->passive) return S_OK;

        if (!CacheHit(true, wParam, lParam)) {
            wire::Result result;
            const bool answered = HandleKey(*s, wParam, lParam, true, result);
            keyCache_ = {true, true, wParam, MaskOf(lParam), GetTickCount64(), s->sid, answered, std::move(result)};
        }
        // §5.4: eaten if the engine handles it or has outputs to apply first (and also if pushes are waiting to go in
        // before the key, §7): OnKeyDown then applies them and says whether the app still gets the key.
        const bool hasOutputs = keyCache_.answered && (keyCache_.result.handled || !keyCache_.result.outputs.empty());
        if (eaten) *eaten = hasOutputs || (keyCache_.answered && HasEarlier(s->sid));
        return S_OK;
    });
}

STDMETHODIMP TextService::OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
    if (eaten) *eaten = FALSE;
    return ComGuard([&]() -> HRESULT {
        Session* s = SessionFor(context, false);
        if (!s || !s->focused || s->passive) return S_OK;

        wire::Result result;
        bool answered = false;
        if (CacheHit(true, wParam, lParam) && keyCache_.sid == s->sid) {
            result = std::move(keyCache_.result);
            answered = keyCache_.answered;
        } else {
            answered = HandleKey(*s, wParam, lParam, true, result); // the app called KeyDown directly (§5.4)
        }
        keyCache_ = {};
        if (answered) {
            const bool handled = result.handled;
            ApplyKeyResult(*s, result, true);
            if (eaten) *eaten = handled;
        }
        return S_OK;
    });
}

STDMETHODIMP TextService::OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
    if (eaten) *eaten = FALSE;
    return ComGuard([&]() -> HRESULT {
        // A key-up ends its key-down: a later down of the same key is a new press, not a re-test.
        if (keyCache_.valid && keyCache_.down && keyCache_.wParam == wParam) keyCache_ = {};

        Session* s = SessionFor(context, false);
        if (!s || !s->focused || s->passive || !SendsKeyUp(wParam)) return S_OK;

        if (!CacheHit(false, wParam, lParam)) {
            wire::Result result;
            const bool answered = HandleKey(*s, wParam, lParam, false, result);
            keyCache_ = {true, false, wParam, MaskOf(lParam), GetTickCount64(), s->sid, answered, std::move(result)};
        }
        const bool hasOutputs = keyCache_.answered && (keyCache_.result.handled || !keyCache_.result.outputs.empty());
        if (eaten) *eaten = hasOutputs || (keyCache_.answered && HasEarlier(s->sid));
        return S_OK;
    });
}

STDMETHODIMP TextService::OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) {
    if (eaten) *eaten = FALSE;
    return ComGuard([&]() -> HRESULT {
        if (keyCache_.valid && keyCache_.down && keyCache_.wParam == wParam) keyCache_ = {};

        Session* s = SessionFor(context, false);
        if (!s || !s->focused || s->passive) return S_OK;

        wire::Result result;
        bool answered = false;
        if (CacheHit(false, wParam, lParam) && keyCache_.sid == s->sid) {
            result = std::move(keyCache_.result);
            answered = keyCache_.answered;
        } else {
            if (!SendsKeyUp(wParam)) return S_OK;
            answered = HandleKey(*s, wParam, lParam, false, result);
        }
        keyCache_ = {};
        if (answered) {
            const bool handled = result.handled;
            ApplyKeyResult(*s, result, true);
            if (eaten) *eaten = handled;
        }
        return S_OK;
    });
}

STDMETHODIMP TextService::OnPreservedKey(ITfContext*, REFGUID, BOOL* eaten) {
    if (eaten) *eaten = FALSE;
    return S_OK;
}

bool TextService::HandleKey(Session& s, WPARAM wParam, LPARAM lParam, bool down, wire::Result& result) {
    result = {};
    if (!Ready()) return false;
    LARGE_INTEGER started;
    QueryPerformanceCounter(&started);

    // A fresh read lock, so `sel`/`before`/`comp` are the document's now (the app may have inserted passed-through keys
    // since the last edit), and so a changed layout or input scope is seen before the key goes out (§4, §8). If TSF
    // can't grant it synchronously, the ctx cached in OnEndEdit stands.
    const uint32_t sid = s.sid;
    bool send = true;
    EditSession::Run(s.context, clientId_, TF_ES_SYNC | TF_ES_READ, [&, sid](TfEditCookie ec) -> HRESULT {
        Session* session = FindBySid(sid);
        if (!session) {
            send = false;
            return S_OK;
        }
        send = CheckFieldChanged(*session, ec);
        if (send) RefreshContext(*session, ec);
        return S_OK;
    });
    if (!send || s.passive || !EnsureOpen(s)) return false;

    wire::KeyEvent event;
    event.down = down;
    event.sid = s.sid;
    event.t = GetTickCount64();
    event.key = ReadKey(wParam, lParam, down);
    event.ctx = s.lastCtx;

    wire::EngineMessage response;
    LARGE_INTEGER sent;
    QueryPerformanceCounter(&sent);
    const auto outcome = pipe_->Request([&event](uint32_t id) {
        event.id = id;
        return wire::Encode(event);
    }, kKeyBudgetMs, response);
    // The key as the DLL sees it: the request's round trip (written to answer read), and the whole of it here (the ctx
    // read under a lock first). Times only, never the key.
    const double roundTrip = MsSince(sent);
    Log("key %s: round trip %.3f ms, in the DLL %.3f ms, %s", down ? "down" : "up", roundTrip, MsSince(started),
        outcome == PipeClient::Outcome::response ? "answered" :
        outcome == PipeClient::Outcome::timeout ? "timed out" : "failed");

    if (outcome == PipeClient::Outcome::response) {
        keyTimeouts_ = 0;
        // §3: an error on a key is handled:false with no outputs.
        if (response.type == wire::EngineType::result) result = std::move(response.result);
        return true;
    }
    if (outcome == PipeClient::Outcome::timeout) {
        // §5.4: pass the key through, discard the late result (OnPipeMessage drops it), resync without waiting, and
        // drop the connection after three in a row. Our composition ends first, keeping the text as typed (as §2.5
        // does for a lost engine): the app's key then lands after it, and the engine's reset leaves the document alone.
        ++keyTimeouts_;
        Log("a key timed out (%d in a row)", keyTimeouts_);
        if (s.composition->Active()) {
            EditSession::RunSyncOrAsync(s.context, clientId_, TF_ES_READWRITE, [this, sid](TfEditCookie ec) -> HRESULT {
                if (Session* found = FindBySid(sid)) {
                    found->composition->EndKeepingText(ec);
                    RefreshContext(*found, ec);
                }
                return S_OK;
            });
        }
        if (keyTimeouts_ >= 3) {
            keyTimeouts_ = 0;
            pipe_->Drop("three key timeouts");
        } else {
            RequestForSession(s, "timeout");
        }
        return false;
    }
    return false; // the connection failed: pass the key (OnEngineLost tidies up)
}

void TextService::RequestForSession(Session& s, const char* endReason) {
    if (!Ready()) return;
    const uint32_t sid = s.sid;
    const std::string reason = endReason ? endReason : "";
    const uint32_t id = pipe_->RequestAsync([sid, &reason](uint32_t id) {
        if (reason.empty()) return wire::Encode(wire::Blur{id, sid});
        return wire::Encode(wire::EndComposition{id, sid, reason});
    });
    if (id) pendingResults_[id] = sid;
}

void TextService::ApplyKeyResult(Session& s, const wire::Result& result, bool afterKeyAllowed) {
    // Split off any afterKey commits (§6): they go in a separate async session, after the app has had the key.
    std::vector<wire::Output> now;
    for (const auto& out : result.outputs) {
        const auto* commit = std::get_if<wire::CommitOutput>(&out);
        if (afterKeyAllowed && commit && commit->afterKey) {
            pendingAfterKey_.emplace_back(s.sid, out);
        } else {
            now.push_back(out);
        }
    }
    if (!pendingAfterKey_.empty() && pipe_) pipe_->StartTimer(kTimerAfterKey, USER_TIMER_MINIMUM);

    // §7: pushes for this session that arrived while the result was awaited go first, in the same edit session; so do
    // the results of its requests sent without waiting (endComposition{timeout}), which the engine answered first.
    std::vector<wire::EngineMessage> earlier;
    const uint32_t sid = s.sid;
    if (pipe_) {
        earlier = pipe_->TakeEarlier([this, sid](const wire::EngineMessage& m) {
            if (m.type == wire::EngineType::apply) return m.sid == sid;
            if (m.type == wire::EngineType::result && m.re) {
                auto it = pendingResults_.find(*m.re);
                return it != pendingResults_.end() && it->second == sid;
            }
            return false;
        });
        for (const auto& m : earlier) {
            if (m.type == wire::EngineType::result && m.re) pendingResults_.erase(*m.re);
        }
    }
    if (now.empty() && earlier.empty()) return;

    // The edit session may run now or later (TF_ES_ASYNCDONTCARE when TSF can't grant a synchronous lock), so it owns
    // copies and finds the session again by sid.
    EditSession::RunSyncOrAsync(
        s.context, clientId_, TF_ES_READWRITE,
        [this, sid, earlier = std::move(earlier), now = std::move(now)](TfEditCookie ec) -> HRESULT {
            Session* session = FindBySid(sid);
            if (!session) return S_OK;
            bool caretMoved = false;
            for (const auto& m : earlier) {
                if (m.type == wire::EngineType::apply) {
                    ApplyPushIn(*session, ec, m);
                } else {
                    ApplyOutputs(*session, ec, m.result.outputs, &caretMoved);
                }
            }
            ApplyOutputs(*session, ec, now, &caretMoved);
            RefreshContext(*session, ec);
            if (caretMoved || session->caretPending) ReportCaret(*session, false, ec);
            return S_OK;
        });
}

void TextService::ApplyOutputs(Session& s, TfEditCookie ec, const std::vector<wire::Output>& outputs,
                               bool* caretMoved) {
    for (const auto& out : outputs) {
        if (const auto* comp = std::get_if<wire::CompositionOutput>(&out)) {
            s.composition->SetComposition(ec, *comp);
            if (caretMoved) *caretMoved = true;
        } else if (const auto* commit = std::get_if<wire::CommitOutput>(&out)) {
            s.composition->Commit(ec, *commit);
            if (caretMoved) *caretMoved = true;
        } else if (const auto* p = std::get_if<wire::PanelOutput>(&out)) {
            const bool was = s.panelShown;
            s.panelShown = p->shown;
            if (p->shown && !was) {
                s.haveCaret = false; // §6: report when the panel becomes shown, changed or not
                if (caretMoved) *caretMoved = true;
            }
        } else if (std::holds_alternative<wire::AllowForegroundOutput>(out)) {
            if (Ready() && pipe_->welcome().enginePid) AllowSetForegroundWindow(pipe_->welcome().enginePid);
        }
    }
}

void TextService::RefreshContext(Session& s, TfEditCookie ec) {
    const int before = Ready() ? pipe_->welcome().limits.contextBefore : wire::Limits{}.contextBefore;
    const int selection = Ready() ? pipe_->welcome().limits.selection : wire::Limits{}.selection;
    s.lastCtx = ReadFieldContext(ec, s.context, *s.composition, before, selection);
}

// ---- async apply (§7) ----

const char* TextService::PushRefusal(const Session& s, const wire::EngineMessage& push) const {
    if (s.passive || !s.focused || focused_ != &s || push.focus != s.focusSerial) return "notFocused";
    if (s.field.readOnly) return "readOnly";
    return nullptr;
}

void TextService::ReplyApplied(uint32_t re, const char* refusal, const std::optional<wire::FieldContext>& ctx) {
    if (!Ready()) return;
    wire::Applied applied;
    applied.re = re;
    applied.ok = refusal == nullptr;
    if (refusal) applied.reason = refusal;
    applied.ctx = ctx;
    pipe_->Send([&applied](uint32_t id) {
        applied.id = id;
        return wire::Encode(applied);
    });
}

void TextService::ApplyPushIn(Session& s, TfEditCookie ec, const wire::EngineMessage& push) {
    if (const char* refusal = PushRefusal(s, push)) {
        ReplyApplied(push.id, refusal, std::nullopt);
        return;
    }
    bool caretMoved = false;
    ApplyOutputs(s, ec, push.result.outputs, &caretMoved);
    RefreshContext(s, ec);
    ReplyApplied(push.id, nullptr, s.lastCtx); // §7: after the session, with the new ctx
    if (caretMoved || s.caretPending) ReportCaret(s, false, ec);
}

void TextService::ApplyAsync(const wire::EngineMessage& message) {
    Session* s = FindBySid(message.sid);
    if (!s) {
        ReplyApplied(message.id, "gone", std::nullopt);
        return;
    }
    if (const char* refusal = PushRefusal(*s, message)) {
        ReplyApplied(message.id, refusal, std::nullopt);
        return;
    }
    // §7: TF_ES_ASYNCDONTCARE, so it may run now or later; it owns a copy and checks again when it runs.
    const uint32_t sid = message.sid;
    HRESULT sessionResult = E_FAIL;
    const HRESULT hr = EditSession::Run(
        s->context, clientId_, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
        [this, sid, message](TfEditCookie ec) -> HRESULT {
            if (Session* session = FindBySid(sid)) {
                ApplyPushIn(*session, ec, message);
            } else {
                ReplyApplied(message.id, "gone", std::nullopt);
            }
            return S_OK;
        },
        &sessionResult);
    if (FAILED(hr) || FAILED(sessionResult)) ReplyApplied(message.id, "denied", std::nullopt);
}

void TextService::ApplyResultLater(uint32_t sid, std::vector<wire::Output> outputs) {
    Session* s = FindBySid(sid);
    if (!s || outputs.empty()) return;
    EditSession::Run(s->context, clientId_, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
                     [this, sid, outputs = std::move(outputs)](TfEditCookie ec) -> HRESULT {
                         Session* session = FindBySid(sid);
                         if (!session) return S_OK;
                         bool caretMoved = false;
                         ApplyOutputs(*session, ec, outputs, &caretMoved);
                         RefreshContext(*session, ec);
                         if (caretMoved || session->caretPending) ReportCaret(*session, false, ec);
                         return S_OK;
                     });
}

// ---- edit and layout sinks ----

STDMETHODIMP TextService::OnEndEdit(ITfContext* context, TfEditCookie ec, ITfEditRecord* editRecord) {
    (void)editRecord;
    return ComGuard([&]() -> HRESULT {
        Session* s = SessionFor(context, false);
        if (s && s->fieldKnown && !s->passive) RefreshContext(*s, ec); // §5.1: cache ctx on every edit
        return S_OK;
    });
}

STDMETHODIMP TextService::OnLayoutChange(ITfContext* context, TfLayoutCode code, ITfContextView*) {
    (void)code;
    return ComGuard([&]() -> HRESULT {
        Session* s = SessionFor(context, false);
        if (s && !s->passive && s->panelShown) ReportCaret(*s, false);
        return S_OK;
    });
}

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie ec, ITfComposition* composition) {
    return ComGuard([&]() -> HRESULT {
        for (auto& [context, session] : sessions_) {
            Session& s = *session;
            if (!s.composition || s.composition->Raw() != composition) continue;
            s.composition->Terminated(); // TSF ended it; keep the range it covered
            Log("session %u: composition terminated", s.sid);
            if (!s.passive && s.opened && Ready()) {
                // §5.5: a request; its result's outputs go in with the write cookie TSF gave us here, and a commit
                // replaces the range the composition covered.
                const uint32_t sid = s.sid;
                wire::EngineMessage response;
                const auto outcome = pipe_->Request([sid](uint32_t id) {
                    return wire::Encode(wire::EndComposition{id, sid, "terminated"});
                }, kKeyBudgetMs, response);
                if (outcome == PipeClient::Outcome::response && response.type == wire::EngineType::result) {
                    ApplyOutputs(s, ec, response.result.outputs, nullptr);
                    RefreshContext(s, ec);
                }
            }
            s.composition->ForgetRange();
            break;
        }
        return S_OK;
    });
}

// ---- caret reports (§6) ----

void TextService::ReportCaret(Session& s, bool force, TfEditCookie ec) {
    if (s.passive || !Ready()) return;
    if (!s.panelShown) {
        // §6: the engine's UI anchors at the caret only while it shows its panel.
        s.caretPending = false;
        return;
    }
    const ULONGLONG now = GetTickCount64();
    if (!force && s.haveCaret && now - s.lastCaretAt < kCaretMinIntervalMs) {
        // §6: at most one report per 16 ms; the timer sends the last one.
        s.caretPending = true;
        pipe_->StartTimer(kTimerCaret, static_cast<UINT>(kCaretMinIntervalMs));
        return;
    }

    RECT rect = {};
    bool exact = true;
    bool known = false;
    HWND hwnd = nullptr;
    auto measure = [&](TfEditCookie cookie) -> HRESULT {
        ITfContextView* view = nullptr;
        if (FAILED(s.context->GetActiveView(&view)) || !view) return S_OK;
        view->GetWnd(&hwnd);
        // The composition's first character, or the empty selection when there is no composition.
        ITfRange* range = nullptr;
        if (s.composition->Active()) {
            ITfRange* full = nullptr;
            if (SUCCEEDED(s.composition->GetRange(&full)) && full) {
                if (SUCCEEDED(full->Clone(&range)) && range) {
                    range->Collapse(cookie, TF_ANCHOR_START);
                    LONG shifted = 0;
                    range->ShiftEnd(cookie, 1, &shifted, nullptr);
                }
                full->Release();
            }
        } else {
            TF_SELECTION sel = {};
            ULONG fetched = 0;
            if (SUCCEEDED(s.context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &sel, &fetched)) && fetched == 1) {
                range = sel.range;
                range->Collapse(cookie, TF_ANCHOR_START);
            }
        }
        if (range) {
            BOOL clipped = FALSE;
            const HRESULT hr = view->GetTextExt(cookie, range, &rect, &clipped);
            if (IsNoLayout(hr)) {
                s.caretPending = true; // §6: wait for OnLayoutChange
            } else if (FAILED(hr)) {
                exact = false;
                known = hwnd && GetWindowRect(hwnd, &rect); // §6: the window's box, marked inexact
            } else {
                known = true;
            }
            range->Release();
        }
        view->Release();
        return S_OK;
    };
    if (ec != TF_INVALID_COOKIE) {
        measure(ec);
    } else {
        EditSession::Run(s.context, clientId_, TF_ES_SYNC | TF_ES_READ, measure);
    }
    if (!known) return;

    // Physical screen pixels (§6): GetTextExt gives the app's coordinates; map them for windows that aren't per-monitor
    // aware (for those that are, the call changes nothing).
    POINT topLeft = {rect.left, rect.top};
    POINT bottomRight = {rect.right, rect.bottom};
    if (hwnd) {
        LogicalToPhysicalPointForPerMonitorDPI(hwnd, &topLeft);
        LogicalToPhysicalPointForPerMonitorDPI(hwnd, &bottomRight);
    }
    const RECT physical = {topLeft.x, topLeft.y, bottomRight.x, bottomRight.y};
    s.caretPending = false;
    if (!force && s.haveCaret && EqualRect(&physical, &s.lastCaret)) return; // §6: only if the rect changed
    s.haveCaret = true;
    s.lastCaret = physical;
    s.lastCaretAt = now;

    wire::Caret caret;
    caret.sid = s.sid;
    caret.rect[0] = physical.left;
    caret.rect[1] = physical.top;
    caret.rect[2] = physical.right - physical.left;
    caret.rect[3] = physical.bottom - physical.top;
    caret.exact = exact;
    caret.hwnd = reinterpret_cast<uintptr_t>(hwnd);
    pipe_->Send([&caret](uint32_t id) {
        caret.id = id;
        return wire::Encode(caret);
    });
}

// ---- display attribute provider ----

STDMETHODIMP TextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** enumInfo) {
    if (!enumInfo) return E_INVALIDARG;
    *enumInfo = nullptr;
    return ComGuard([&]() -> HRESULT {
        *enumInfo = new aio::EnumDisplayAttributeInfo();
        return S_OK;
    });
}

STDMETHODIMP TextService::GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** info) {
    if (!info) return E_INVALIDARG;
    *info = nullptr;
    wire::Style style;
    if (!StyleOfGuid(guid, style)) return E_INVALIDARG;
    return ComGuard([&]() -> HRESULT {
        *info = new aio::DisplayAttributeInfo(style);
        return S_OK;
    });
}

// ---- pipe events (§2.5, §7) ----

void TextService::OnPipeConnected(const wire::Welcome& welcome) {
    Log("engine connected (%zu-byte engine name, pid %lu)", welcome.engine.size(), welcome.enginePid);
    keyTimeouts_ = 0;
    pendingResults_.clear();
    // §2.5: re-send open for each live context and focus for the focused one.
    for (auto& [context, session] : sessions_) {
        session->opened = false;
        EnsureOpen(*session);
    }
    if (focused_ && focused_->opened) {
        SendFocus(*focused_, true, false);
        pipe_->SetFocused(true);
    }
}

void TextService::OnPipeDisconnected() {
    OnEngineLost();
}

void TextService::OnEngineLost() {
    Log("engine lost: ending compositions, passing keys through");
    keyCache_ = {};
    pendingResults_.clear();
    // §2.5: end every composition, keeping its text as typed, so nothing typed is lost.
    for (auto& [context, session] : sessions_) {
        Session& s = *session;
        s.opened = false;
        s.panelShown = false;
        s.caretPending = false;
        if (!s.composition || !s.composition->Active()) continue;
        const uint32_t sid = s.sid;
        EditSession::RunSyncOrAsync(s.context, clientId_, TF_ES_READWRITE, [this, sid](TfEditCookie ec) -> HRESULT {
            if (Session* found = FindBySid(sid)) {
                found->composition->EndKeepingText(ec);
                RefreshContext(*found, ec);
            }
            return S_OK;
        });
    }
}

void TextService::OnPipeMessage(const wire::EngineMessage& message) {
    switch (message.type) {
    case wire::EngineType::apply:
        ApplyAsync(message);
        break;
    case wire::EngineType::result:
    case wire::EngineType::error:
        if (message.re) {
            auto it = pendingResults_.find(*message.re);
            if (it != pendingResults_.end()) {
                const uint32_t sid = it->second;
                pendingResults_.erase(it);
                if (message.type == wire::EngineType::result) ApplyResultLater(sid, message.result.outputs);
            }
            // Otherwise a late key result whose waiter gave up: discarded (§5.4).
        }
        break;
    default:
        break; // §9: the DLL ignores what it doesn't know
    }
}

void TextService::OnPipeTimer(UINT_PTR id) {
    if (id == kTimerCaret) {
        if (focused_ && focused_->caretPending) ReportCaret(*focused_, false);
        return;
    }
    if (id != kTimerAfterKey) return;
    // §6 afterKey: a separate TF_ES_ASYNC session, after the app has had the key; one per session, in order.
    std::vector<std::pair<uint32_t, wire::Output>> pending = std::move(pendingAfterKey_);
    pendingAfterKey_.clear();
    while (!pending.empty()) {
        const uint32_t sid = pending.front().first;
        std::vector<wire::Output> outputs;
        for (auto it = pending.begin(); it != pending.end();) {
            if (it->first == sid) {
                outputs.push_back(std::move(it->second));
                it = pending.erase(it);
            } else {
                ++it;
            }
        }
        Session* s = FindBySid(sid);
        if (!s) continue;
        EditSession::Run(s->context, clientId_, TF_ES_ASYNC | TF_ES_READWRITE,
                         [this, sid, outputs = std::move(outputs)](TfEditCookie ec) -> HRESULT {
                             Session* session = FindBySid(sid);
                             if (!session) return S_OK;
                             bool caretMoved = false;
                             ApplyOutputs(*session, ec, outputs, &caretMoved);
                             RefreshContext(*session, ec);
                             if (caretMoved || session->caretPending) ReportCaret(*session, false, ec);
                             return S_OK;
                         });
    }
}

} // namespace aio
