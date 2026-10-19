// One connection to the engine, per TSF thread (§2.3).
//
// A thread of its own connects (with backoff), runs the server check and the handshake, and reads. The TSF thread
// writes, and waits on an event for the response to a request. Everything else the reader gets (pushes, the results of
// requests nobody waits for, the connection coming and going) reaches the TSF thread through a message-only window
// created on it, in the order it arrived.

#pragma once

#include <windows.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "wire/Wire.h"

namespace aio {

// Called on the TSF thread only, from the message-only window.
class PipeEvents {
public:
    virtual void OnPipeConnected(const wire::Welcome& welcome) = 0;
    // The engine is lost (§2.5): `bye`, a broken pipe, a missing pong, or Drop().
    virtual void OnPipeDisconnected() = 0;
    // A push, or the result of a request nobody waited for (a late one, or one sent with RequestAsync).
    virtual void OnPipeMessage(const wire::EngineMessage& message) = 0;
    // A timer started with PipeClient::StartTimer.
    virtual void OnPipeTimer(UINT_PTR id) = 0;

protected:
    ~PipeEvents() = default;
};

class PipeClient {
public:
    // Builds a frame's body for the id it is given (ids are given out in the order frames are written).
    using Builder = std::function<std::string(uint32_t id)>;

    explicit PipeClient(PipeEvents* events) noexcept;
    ~PipeClient();
    PipeClient(const PipeClient&) = delete;
    PipeClient& operator=(const PipeClient&) = delete;

    // On the TSF thread. Starts connecting without waiting for it. False if this process or thread may not connect at
    // all (§2.1, §8), and then the DLL stays passive.
    bool Start();
    void Stop() noexcept;

    // The TSF thread has had OnPipeConnected for the current connection.
    bool Ready() const noexcept { return ready_; }
    const wire::Welcome& welcome() const noexcept { return welcome_; }

    // A notification. False if not connected or the write failed (which drops the connection).
    bool Send(const Builder& build) noexcept;

    enum class Outcome { response, timeout, failed };
    // A request: writes the frame and waits at most `budgetMs` for the one with `re` equal to its id.
    Outcome Request(const Builder& build, DWORD budgetMs, wire::EngineMessage& response,
                    uint32_t* id = nullptr) noexcept;
    // A request whose answer arrives later, through OnPipeMessage. Returns its id, or 0 if it wasn't sent.
    uint32_t RequestAsync(const Builder& build) noexcept;

    // The queued messages that arrived before the last Request's response and match `pick`, taken out of the queue in
    // order (§7: an apply that came while a key's result was awaited goes first, in the same edit session).
    std::vector<wire::EngineMessage> TakeEarlier(const std::function<bool(const wire::EngineMessage&)>& pick) noexcept;
    // Whether TakeEarlier would take anything, without taking it.
    bool AnyEarlier(const std::function<bool(const wire::EngineMessage&)>& pick) const noexcept;

    // Closes the connection; the connection thread reconnects with backoff.
    void Drop(const char* why) noexcept;

    // Whether a session is focused, for the keepalive (§2.5: pings only while focused).
    void SetFocused(bool focused) noexcept { focused_ = focused; }

    // One-shot timers on the TSF thread (ids from 100).
    void StartTimer(UINT_PTR id, UINT ms) noexcept;
    void StopTimer(UINT_PTR id) noexcept;

    struct Shared;

private:
    static LRESULT CALLBACK WindowProc(HWND, UINT, WPARAM, LPARAM);
    void Drain() noexcept;
    void Keepalive() noexcept;
    enum class WriteKind { notification, request, asyncRequest };
    bool Write(const Builder& build, DWORD timeoutMs, WriteKind kind, uint32_t* id) noexcept;

    PipeEvents* events_;
    std::shared_ptr<Shared> shared_;
    HWND wnd_ = nullptr;
    HANDLE thread_ = nullptr;
    bool ready_ = false;
    uint64_t generation_ = 0; // of the connection the TSF thread was told about
    wire::Welcome welcome_;
    uint64_t lastResponseSeq_ = 0;
    bool focused_ = false;
    uint32_t pingId_ = 0;
    ULONGLONG pingDeadline_ = 0;
};

} // namespace aio
