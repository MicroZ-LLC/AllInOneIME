// The text input processor: one per TSF thread. It owns the thread's sinks, its one connection to the engine, and a
// session per ITfContext. It is where the spec's §4–§7 live.

#pragma once

#include <windows.h>
#include <msctf.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "Composition.h"
#include "DisplayAttributes.h"
#include "PipeClient.h"
#include "wire/Wire.h"

namespace aio {

class TextService;

// One ITfContext (§4). Created when a context first takes focus; closed on pop, uninit or deactivate.
struct Session {
    ITfContext* context = nullptr;
    ITfDocumentMgr* docMgr = nullptr;
    uint32_t sid = 0;
    uint32_t focusSerial = 0; // the serial of the last `focus` sent (0: none yet)
    DWORD editCookie = TF_INVALID_COOKIE;
    DWORD layoutCookie = TF_INVALID_COOKIE;
    std::unique_ptr<Composition> composition;
    wire::FieldInfo field;
    bool fieldKnown = false; // `field` was read under a lock (until then nothing is sent: it might be secure)
    bool passive = false;    // a secure field, or keyboard input disabled: nothing goes on the wire (§8)
    wire::FieldContext lastCtx;
    bool opened = false;     // `open` sent on the current connection
    bool focused = false;
    bool panelShown = false;
    bool caretPending = false; // a caret report waits for the throttle or for OnLayoutChange (§6)
    bool haveCaret = false;
    RECT lastCaret = {};
    ULONGLONG lastCaretAt = 0;

    ~Session();
};

class TextService final : public ITfTextInputProcessorEx,
                          public ITfThreadMgrEventSink,
                          public ITfKeyEventSink,
                          public ITfTextEditSink,
                          public ITfTextLayoutSink,
                          public ITfCompositionSink,
                          public ITfDisplayAttributeProvider,
                          public PipeEvents {
public:
    TextService();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor(Ex)
    STDMETHODIMP Activate(ITfThreadMgr* threadMgr, TfClientId clientId) override;
    STDMETHODIMP ActivateEx(ITfThreadMgr* threadMgr, TfClientId clientId, DWORD flags) override;
    STDMETHODIMP Deactivate() override;

    // ITfThreadMgrEventSink
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr* docMgr) override;
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr* docMgr) override;
    STDMETHODIMP OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr* prevFocus) override;
    STDMETHODIMP OnPushContext(ITfContext* context) override;
    STDMETHODIMP OnPopContext(ITfContext* context) override;

    // ITfKeyEventSink
    STDMETHODIMP OnSetFocus(BOOL foreground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext* context, REFGUID guid, BOOL* eaten) override;

    // ITfTextEditSink
    STDMETHODIMP OnEndEdit(ITfContext* context, TfEditCookie ec, ITfEditRecord* editRecord) override;

    // ITfTextLayoutSink
    STDMETHODIMP OnLayoutChange(ITfContext* context, TfLayoutCode code, ITfContextView* view) override;

    // ITfCompositionSink
    STDMETHODIMP OnCompositionTerminated(TfEditCookie ec, ITfComposition* composition) override;

    // ITfDisplayAttributeProvider
    STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** enumInfo) override;
    STDMETHODIMP GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** info) override;

    // PipeEvents (TSF thread)
    void OnPipeConnected(const wire::Welcome& welcome) override;
    void OnPipeDisconnected() override;
    void OnPipeMessage(const wire::EngineMessage& message) override;
    void OnPipeTimer(UINT_PTR id) override;

private:
    ~TextService();

    bool Ready() const noexcept { return pipe_ && pipe_->Ready(); }

    Session* SessionFor(ITfContext* context, bool create);
    Session* FindBySid(uint32_t sid);
    void CloseSession(ITfContext* context);
    void CloseAll();

    // §4.
    void FocusContext(ITfContext* context);
    void BlurFocused();
    void ReadField(Session& s, TfEditCookie ec);   // field, passive, ctx: under a lock
    void FieldKnown(Session& s);                    // once `field` is read: open + focus, unless passive
    bool CheckFieldChanged(Session& s, TfEditCookie ec); // §4: a new layout or input scope; false if now passive
    bool EnsureOpen(Session& s);
    void SendFocus(Session& s, bool newSerial, bool withField);

    // §5.4. A key through the engine; true if the engine answered (the result is then in `result`).
    bool HandleKey(Session& s, WPARAM wParam, LPARAM lParam, bool down, wire::Result& result);
    bool SendsKeyUp(WPARAM wParam) const;
    bool CacheHit(bool down, WPARAM wParam, LPARAM lParam) const;
    bool HasEarlier(uint32_t sid) const;
    // §5.3/§7: the result's outputs, after any pushes for the session that arrived while it was awaited, in one edit
    // session. `afterKeyAllowed`: commits marked afterKey go in a later session, after the app has had the key.
    void ApplyKeyResult(Session& s, const wire::Result& result, bool afterKeyAllowed);
    void ApplyOutputs(Session& s, TfEditCookie ec, const std::vector<wire::Output>& outputs, bool* caretMayHaveMoved);
    void ApplyPushIn(Session& s, TfEditCookie ec, const wire::EngineMessage& push); // §7, inside an edit session
    void ApplyAsync(const wire::EngineMessage& message);                             // §7, an `apply` push
    void ApplyResultLater(uint32_t sid, std::vector<wire::Output> outputs);       // an async request's result
    const char* PushRefusal(const Session& s, const wire::EngineMessage& push) const;
    void ReplyApplied(uint32_t re, const char* refusal, const std::optional<wire::FieldContext>& ctx);
    // A request whose result is applied to the session when it comes: `endComposition {reason}` (§5.4 timeout), or a
    // `blur` (reason null) for a field turning secure. Sent without waiting, so the TSF thread never waits past the
    // budget.
    void RequestForSession(Session& s, const char* endReason);

    void RefreshContext(Session& s, TfEditCookie ec);
    // §6. `ec`: a cookie of the edit session it is called in, or TF_INVALID_COOKIE to take a read lock of its own.
    void ReportCaret(Session& s, bool force, TfEditCookie ec = TF_INVALID_COOKIE);
    void OnEngineLost();

    uint32_t NextSid() { return nextSid_++; }

    LONG refs_ = 1;
    ITfThreadMgr* threadMgr_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    DWORD threadMgrCookie_ = TF_INVALID_COOKIE;
    bool keySinkAdvised_ = false;
    bool secureMode_ = false; // TF_TMAE_SECUREMODE: the logon or another secure desktop; never connect (§2.1)

    std::unique_ptr<PipeClient> pipe_;
    DisplayAttributeAtoms atoms_;
    std::map<ITfContext*, std::unique_ptr<Session>> sessions_;
    Session* focused_ = nullptr;
    uint32_t nextSid_ = 1;
    int keyTimeouts_ = 0; // §5.4: three in a row drops the connection

    // The cache of §5.4: a key's result by (wParam, lParam & 0x00FF0000), down or up.
    struct CachedKey {
        bool valid = false;
        bool down = true;
        WPARAM wParam = 0;
        LPARAM lParamMask = 0;
        ULONGLONG at = 0;
        uint32_t sid = 0;
        bool answered = false; // the engine answered (vs. a timeout or a lost engine: pass the key through)
        wire::Result result;
    };
    CachedKey keyCache_;

    // Requests sent without waiting whose results are applied to a session: request id → sid.
    std::map<uint32_t, uint32_t> pendingResults_;

    // §6 afterKey commits: applied on a timer, in a separate async session after the app has had the key.
    std::vector<std::pair<uint32_t, wire::Output>> pendingAfterKey_;
};

} // namespace aio
